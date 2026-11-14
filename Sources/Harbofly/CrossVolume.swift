import Foundation

// MARK: - Comparação entre volumes

/// Uma linha do relatório: um arquivo do volume-alvo, com o que se sabe sobre
/// as outras cópias dele.
struct CrossVolumeRow: Identifiable {
    let id = UUID()
    let url: URL
    let size: Int64
    let modified: Date
    /// SHA-256 do conteúdo, verificado byte a byte contra o keeper.
    let hash: String
    /// Onde está a cópia que fica.
    let keeperURL: URL
    let keeperVolume: String
    /// Total de cópias desse conteúdo entre os volumes comparados.
    let copies: Int
    /// Apagar este arquivo deixaria o conteúdo com uma única cópia no mundo —
    /// e é mídia (foto/vídeo), que não se regenera.
    let lastBackupOfMedia: Bool
}

/// Pasta cujo conteúdo inteiro tem cópia em outro volume. É a unidade que
/// importa num disco de backup: a duplicata ali é a árvore, não o arquivo
/// (os 88,89 GB que liberei num disco meu eram 29 pastas `node_modules`).
struct IdenticalSubtree: Identifiable {
    let id = UUID()
    let url: URL
    let files: Int
    let bytes: Int64
}

struct CrossVolumeReport {
    var target: MountedVolume
    var others: [MountedVolume]

    /// Arquivos do alvo com cópia em OUTRO volume: liberar aqui mantém o
    /// conteúdo lá. É o balde que responde "o que posso apagar deste disco".
    var shared: [CrossVolumeRow] = []
    /// Arquivos duplicados DENTRO do próprio alvo (o keeper também está aqui).
    var internalDupes: [CrossVolumeRow] = []
    /// Pastas inteiramente duplicadas em outro volume.
    var subtrees: [IdenticalSubtree] = []

    /// O que existe só aqui — o que uma migração precisa levar, não apagar.
    var uniqueFiles = 0
    var uniqueBytes: Int64 = 0

    // Contabilidade: sem isso, "nada encontrado" por bug parece disco limpo.
    var indexedTarget = 0
    var indexedOthers = 0
    var hashErrors = 0
    var verifyMismatches = 0
    var coverageOK = true
    var durationMs = 0

    var sharedBytes: Int64 { shared.reduce(0) { $0 + $1.size } }
    var internalBytes: Int64 { internalDupes.reduce(0) { $0 + $1.size } }
    var subtreeBytes: Int64 { subtrees.reduce(0) { $0 + $1.bytes } }
    var mediaAtRisk: [CrossVolumeRow] { shared.filter { $0.lastBackupOfMedia } }
}

// MARK: - Scanner

/// Compara um volume contra os outros montados. Reusa o pipeline do painel
/// Duplicatas inteiro (4 fases, SHA-256 + verificação byte a byte): aqui os dois
/// lados estão montados, então a prova forte está disponível e é obrigatória.
final class CrossVolumeScanner: ObservableObject {
    @Published var scanning = false
    @Published var phase: DupPhase?
    @Published var walkedFiles = 0
    @Published var report: CrossVolumeReport?
    @Published var deleting = false
    @Published var deletingDone = 0
    @Published var deletingTotal = 0
    @Published var lastFreedBytes: Int64 = 0
    @Published var lastSkipped = 0
    @Published var justFinished = false

    /// Extensões que não se regeneram: o guard de cópia única só grita nelas.
    static let mediaExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "gif", "bmp", "webp",
        "raw", "cr2", "cr3", "nef", "arw", "dng", "orf", "rw2",
        "mp4", "mov", "m4v", "avi", "mkv", "3gp", "mts", "m2ts", "wmv", "mpg", "mpeg",
        "wav", "aiff", "flac", "m4a", "mp3",
    ]

    private var generation = 0
    private var cancelled = false

    func cancel() { cancelled = true }

    // MARK: API assíncrona (UI)

    func scan(target: MountedVolume, others: [MountedVolume]) {
        guard !scanning, !deleting else { return }
        generation += 1
        let gen = generation
        cancelled = false
        scanning = true
        walkedFiles = 0
        report = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let r = self.compare(target: target, others: others, phase: { p in
                DispatchQueue.main.async {
                    guard self.generation == gen else { return }
                    self.phase = p
                }
            }, walked: { n in
                DispatchQueue.main.async {
                    guard self.generation == gen else { return }
                    self.walkedFiles = n
                }
            })
            DispatchQueue.main.async {
                guard self.generation == gen else { return }   // scan velho: descarta
                self.report = r
                self.scanning = false
                self.phase = nil
                Analytics.crossVolumeScanned(groups: r.shared.count + r.internalDupes.count,
                                             reclaimableBytes: r.sharedBytes,
                                             durationMs: r.durationMs)
            }
        }
    }

    // MARK: Núcleo síncrono (compartilhado UI + CLI)

    func compare(target: MountedVolume, others: [MountedVolume],
                 phase: (DupPhase) -> Void = { _ in },
                 walked: (Int) -> Void = { _ in }) -> CrossVolumeReport {
        let started = Date()
        var out = CrossVolumeReport(target: target, others: others)
        let indexer = VolumeIndexer()

        // Fase 0 — um passeio por volume, com contabilidade. Nada de varrer
        // duas vezes: o pipeline recebe as entradas já enumeradas.
        phase(.listing)
        var all: [FileEntry] = []
        let (invTarget, entriesTarget) = indexer.walk(root: target.url) { n, _ in walked(n) }
        out.indexedTarget = invTarget.indexed
        out.coverageOK = invTarget.coverageOK
        all += entriesTarget
        for other in others {
            guard !cancelled else { break }
            let (inv, ents) = indexer.walk(root: other.url) { n, _ in walked(out.indexedTarget + n) }
            out.indexedOthers += inv.indexed
            out.coverageOK = out.coverageOK && inv.coverageOK
            all += ents
        }
        guard !cancelled else {
            out.durationMs = Int(Date().timeIntervalSince(started) * 1000)
            return out
        }

        // Fases 1-4 — motor de duplicatas, com o keeper fora do alvo.
        //
        // "Ser do alvo" é pertencer ao conjunto que a varredura do alvo
        // devolveu. Comparar prefixo de caminho não serve: o enumerador do
        // FileManager devolve `/private/tmp/x` para a raiz `/tmp/x`, enquanto
        // `resolvingSymlinksInPath()` normaliza ao contrário (`/private/tmp` →
        // `/tmp`). Os dois lados deixavam de se reconhecer e o escopo ficava
        // vazio sem erro nenhum — nada aparecia, como se o disco não tivesse
        // duplicata. Pertencimento a conjunto não tem esse furo.
        let targetPaths = Set(entriesTarget.map { $0.url.path })
        let targetDev = KeeperPolicy.devOf(target.url) ?? 0
        let scanner = DuplicateScanner()
        let run = scanner.run(entries: all, policy: .avoidPaths(targetPaths), progress: phase)
        out.hashErrors = run.hashErrors
        out.verifyMismatches = run.verifyMismatches

        // Mapa dev → nome do volume, para a linha dizer onde a cópia fica.
        var volumeNames: [Int32: String] = [:]
        for v in [target] + others {
            if let dev = KeeperPolicy.devOf(v.url) { volumeNames[dev] = v.name }
        }

        // Caminhos do alvo que têm gêmeo em outro volume — base da detecção de
        // subárvore e do balde "só aqui".
        var twinned = Set<String>()

        for g in run.groups {
            guard let keeper = g.files.first(where: { $0.isKeeper }) else { continue }
            let keeperInTarget = targetPaths.contains(keeper.url.path)
            let keeperDev = KeeperPolicy.devOf(keeper.url) ?? targetDev
            let ext = keeper.url.pathExtension.lowercased()
            let isMedia = Self.mediaExtensions.contains(ext)

            for f in g.removable {
                guard targetPaths.contains(f.url.path) else { continue }
                let row = CrossVolumeRow(
                    url: f.url, size: f.size, modified: f.modified, hash: g.hash,
                    keeperURL: keeper.url,
                    keeperVolume: volumeNames[keeperDev] ?? target.name,
                    copies: g.files.count,
                    // Depois de apagar este, sobra 1? Então aqui morre o backup.
                    lastBackupOfMedia: isMedia && g.copiesAfterRemoving(1) == 1
                )
                // O keeper está fora do alvo? Então apagar aqui mantém o
                // conteúdo lá. Se o keeper também está aqui, é repetição
                // interna — outra promessa, outro balde.
                if !keeperInTarget {
                    out.shared.append(row)
                    twinned.insert(f.url.path)
                } else {
                    out.internalDupes.append(row)
                }
            }
        }
        out.shared.sort { $0.size > $1.size }
        out.internalDupes.sort { $0.size > $1.size }

        // Só aqui = indexado no alvo e sem gêmeo fora.
        for e in entriesTarget where !twinned.contains(e.url.path) {
            out.uniqueFiles += 1
            out.uniqueBytes += e.size
        }

        out.subtrees = identicalSubtrees(entries: entriesTarget, twinned: twinned,
                                         root: target.url)
        out.durationMs = Int(Date().timeIntervalSince(started) * 1000)
        return out
    }

    /// Pastas onde **todo** arquivo indexado tem gêmeo em outro volume. Só a
    /// pasta mais alta que satisfaz isso é reportada (a mãe ganha da filha), e
    /// pastas de 1 arquivo ficam de fora — ali a linha de arquivo já basta.
    private func identicalSubtrees(entries: [FileEntry], twinned: Set<String>,
                                   root: URL) -> [IdenticalSubtree] {
        guard !twinned.isEmpty else { return [] }
        let rootPath = root.path
        var total: [String: (files: Int, bytes: Int64)] = [:]
        var dup: [String: (files: Int, bytes: Int64)] = [:]

        for e in entries {
            let isTwin = twinned.contains(e.url.path)
            var dir = e.url.deletingLastPathComponent().path
            while dir.count >= rootPath.count {
                total[dir, default: (0, 0)].files += 1
                total[dir]!.bytes += e.size
                if isTwin {
                    dup[dir, default: (0, 0)].files += 1
                    dup[dir]!.bytes += e.size
                }
                if dir == rootPath { break }
                let parent = (dir as NSString).deletingLastPathComponent
                if parent == dir { break }
                dir = parent
            }
        }

        // Candidata = todo arquivo de dentro tem gêmeo, com pelo menos 2 arquivos.
        var candidates = Set(total.keys.filter { dir in
            guard let t = total[dir], t.files >= 2 else { return false }
            return dup[dir]?.files == t.files
        })
        // Mantém só a mais alta de cada linhagem.
        for dir in candidates {
            let parent = (dir as NSString).deletingLastPathComponent
            if candidates.contains(parent) { candidates.remove(dir) }
        }
        return candidates.compactMap { dir in
            guard let t = total[dir] else { return nil }
            return IdenticalSubtree(url: URL(fileURLWithPath: dir), files: t.files, bytes: t.bytes)
        }
        .sorted { $0.bytes > $1.bytes }
    }

    // MARK: Deleção

    /// Apaga as linhas escolhidas. Nunca o keeper (por construção o keeper está
    /// fora do alvo), e **re-confere tamanho e mtime antes de cada remoção**:
    /// entre a varredura e o clique o arquivo pode ter mudado, e aí ele não é
    /// mais o que foi provado idêntico.
    func delete(_ rows: [CrossVolumeRow], permanently: Bool) {
        guard !rows.isEmpty, !deleting else { return }
        deleting = true
        deletingDone = 0
        deletingTotal = rows.count
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var freed: Int64 = 0
            var removed = 0
            var skipped = 0
            var gone = Set<UUID>()
            for r in rows {
                defer { DispatchQueue.main.async { self.deletingDone += 1 } }
                guard Self.stillMatches(r) else { skipped += 1; continue }
                let ok = permanently
                    ? (try? FileManager.default.removeItem(at: r.url)) != nil
                    : (try? FileManager.default.trashItem(at: r.url, resultingItemURL: nil)) != nil
                if ok { freed += r.size; removed += 1; gone.insert(r.id) }
                else { skipped += 1 }
            }
            let freedFinal = freed, removedFinal = removed, skippedFinal = skipped
            DispatchQueue.main.async {
                if var rep = self.report {
                    rep.shared.removeAll { gone.contains($0.id) }
                    rep.internalDupes.removeAll { gone.contains($0.id) }
                    self.report = rep
                }
                CleanLog.record(bytes: freedFinal, count: removedFinal,
                                byCategory: ["crossvolume": freedFinal])
                Analytics.duplicatesDeleted(mode: permanently ? "permanent" : "trash",
                                            freedBytes: freedFinal, count: removedFinal)
                self.lastFreedBytes = freedFinal
                self.lastSkipped = skippedFinal
                self.deleting = false
                self.justFinished = true
            }
        }
    }

    /// O arquivo em disco ainda é o que foi provado idêntico?
    private static func stillMatches(_ r: CrossVolumeRow) -> Bool {
        var st = stat()
        guard lstat(r.url.path, &st) == 0 else { return false }
        guard Int64(st.st_size) == r.size else { return false }
        let mtime = Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1e9
        return abs(mtime - r.modified.timeIntervalSince1970) < 1
    }
}
