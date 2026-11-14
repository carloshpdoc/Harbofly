import Foundation

// MARK: - Inventário de um volume

/// Por que um item enumerado não entrou no índice. Existe como enum (e não como
/// `continue` solto) porque o descarte precisa ser contado: resultado vazio por
/// bug e resultado vazio por disco limpo são indistinguíveis sem isso.
enum SkipReason: String, CaseIterable {
    /// `._Foo`: o macOS cria esses em filesystem sem xattr (exFAT, FAT).
    /// Na prática o contador fica em zero quase sempre: o próprio macOS esconde
    /// os AppleDouble do `FileManager` (ele os interpreta como fork do arquivo
    /// hospedeiro em vez de listá-los). O ramo fica como defesa para quando a
    /// varredura vier de outra fonte — e porque custa uma comparação de prefixo.
    case appleDouble
    case junk            // .DS_Store, .localized
    case symlink
    case package         // bundle (.app, .photoslibrary): unidade, não arquivos
    case tooSmall
    /// Área de serviço do volume ($RECYCLE.BIN, .Spotlight-V100, .fseventsd…).
    /// Medida à parte e nunca candidata — o $RECYCLE.BIN de um disco meu tinha
    /// 4,24 GB de commits que não existiam em nenhum outro lugar.
    case volumeMetadata
}

enum IndexError: String {
    case stat            // lstat falhou (permissão, I/O)
    case enumerator      // o enumerador reportou erro naquele caminho
}

/// Linha de um corte do inventário (por extensão, por pasta, por faixa).
struct NamedStat: Identifiable, Hashable {
    var id: String { name }
    let name: String
    var files: Int
    var bytes: Int64
}

/// O que há num volume, com a conta fechando.
struct VolumeInventory {
    var root: URL
    /// Itens que a varredura visitou. Um diretório podado (bundle, área de
    /// serviço) conta como **um** item visitado, não como os N de dentro.
    var enumerated = 0
    var indexed = 0
    var skipped: [String: Int] = [:]
    var errors: [String: Int] = [:]
    /// Soma de `st_size`.
    var bytesLogical: Int64 = 0
    /// Soma de `st_blocks × 512` — o que o volume realmente gasta.
    var bytesAllocated: Int64 = 0
    var byExtension: [NamedStat] = []
    var byFolder: [NamedStat] = []
    var bySizeBucket: [NamedStat] = []
    /// Áreas de serviço do volume, com tamanho, para o usuário decidir sabendo.
    var metadata: [NamedStat] = []
    var durationMs = 0

    var skippedTotal: Int { skipped.values.reduce(0, +) }
    var errorsTotal: Int { errors.values.reduce(0, +) }

    /// A porta: todo item visitado terminou em exatamente um balde.
    var coverageOK: Bool { indexed + skippedTotal + errorsTotal == enumerated }

    /// Slack de cluster: em exFAT com muitos arquivos pequenos o alocado passa
    /// longe do lógico (medi 1,92 GB lógicos virarem 4,24 GB num disco meu).
    var slackBytes: Int64 { max(0, bytesAllocated - bytesLogical) }
    var slackIsRelevant: Bool {
        bytesLogical > 0 && Double(slackBytes) / Double(bytesLogical) > 0.05
    }
}

// MARK: - Indexador

final class VolumeIndexer: ObservableObject {
    @Published var indexing = false
    @Published var filesSoFar = 0
    @Published var bytesSoFar: Int64 = 0
    @Published var inventory: VolumeInventory?
    @Published var currentVolume: MountedVolume?

    /// Identifica a varredura corrente: resultado de scan antigo que chega
    /// atrasado é descartado em vez de sobrescrever o novo.
    private var generation = 0
    private var cancelled = false

    // Config — mesmos limiares do painel Duplicatas, para os dois modos
    // concordarem sobre o que é ruído.
    private let minSize: Int64 = 4 * 1024
    private let junkNames: Set<String> = [".DS_Store", ".localized"]
    /// Áreas de serviço de volume (Windows e macOS). Podadas e medidas à parte.
    static let metadataDirs: Set<String> = [
        "$RECYCLE.BIN", "$Recycle.Bin", "RECYCLER", "System Volume Information",
        ".Spotlight-V100", ".fseventsd", ".TemporaryItems", ".Trashes",
        ".DocumentRevisions-V100", "found.000", "lost+found",
    ]

    // MARK: API assíncrona (UI)

    func index(volume: MountedVolume) {
        guard !indexing else { return }
        generation += 1
        let gen = generation
        cancelled = false
        indexing = true
        filesSoFar = 0
        bytesSoFar = 0
        inventory = nil
        currentVolume = volume
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let (inv, _) = self.walk(root: volume.url) { files, bytes in
                DispatchQueue.main.async {
                    guard self.generation == gen else { return }
                    self.filesSoFar = files
                    self.bytesSoFar = bytes
                }
            }
            DispatchQueue.main.async {
                guard self.generation == gen else { return }   // scan velho: descarta
                self.inventory = inv
                self.indexing = false
                Analytics.volumeIndexed(files: inv.indexed, bytes: inv.bytesAllocated,
                                        fsType: volume.fsType, durationMs: inv.durationMs)
            }
        }
    }

    /// Interrompe a varredura corrente. Um volume de 4 TB pode levar minutos —
    /// cancelar é responsabilidade do usuário, não de um watchdog com prazo fixo
    /// que mataria um scan legítimo no meio.
    func cancel() { cancelled = true }

    // MARK: Núcleo síncrono (compartilhado UI + CLI)

    /// Varre `root` contando **todo** item visitado. Devolve o inventário e as
    /// entradas aproveitáveis pelo pipeline de duplicatas.
    func walk(root: URL, progress: (Int, Int64) -> Void = { _, _ in })
        -> (VolumeInventory, [FileEntry]) {
        let started = Date()
        // Canônica desde a raiz: todo caminho que sai daqui é comparável com o
        // escopo sem outro syscall.
        let root = Volumes.canonical(root)
        let rootDepth = root.pathComponents.count
        var inv = VolumeInventory(root: root)
        var ents: [FileEntry] = []
        var byExt: [String: NamedStat] = [:]
        var byFolder: [String: NamedStat] = [:]
        var buckets = SizeBucket.empty()
        var meta: [String: NamedStat] = [:]

        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey,
                                         .isPackageKey, .isDirectoryKey]
        // O errorHandler é o ÚNICO lugar onde falha de diretório aparece (pasta
        // sem permissão, I/O no meio da árvore). Devolver `true` sem registrar
        // faz a subárvore inteira desaparecer calada — e aí a porta de cobertura
        // fecha por omissão, que é pior do que não ter porta.
        let walkErrors = ErrorTally()
        guard let en = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: Array(keys), options: [],
            errorHandler: { _, _ in walkErrors.count += 1; return true }
        ) else {
            inv.durationMs = Int(Date().timeIntervalSince(started) * 1000)
            return (inv, ents)
        }

        for case let url as URL in en {
            if cancelled { break }
            inv.enumerated += 1

            guard let rv = try? url.resourceValues(forKeys: keys) else {
                inv.errors[IndexError.enumerator.rawValue, default: 0] += 1
                continue
            }

            if rv.isDirectory == true {
                let name = url.lastPathComponent
                if Self.metadataDirs.contains(name) {
                    // Mede e poda: aparece no relatório com tamanho, nunca como
                    // candidata. Agrega por nome — num disco real a mesma área
                    // aparece em vários níveis (um .Spotlight-V100 por pasta).
                    let bytes = allocatedSize(of: url)
                    // Aqui `files` conta ocorrências da área no disco, não arquivos.
                    meta[name, default: NamedStat(name: name, files: 0, bytes: 0)].add(bytes)
                    inv.skipped[SkipReason.volumeMetadata.rawValue, default: 0] += 1
                    en.skipDescendants()
                    continue
                }
                if rv.isPackage == true {
                    inv.skipped[SkipReason.package.rawValue, default: 0] += 1
                    en.skipDescendants()
                    continue
                }
                // Diretório comum não é item contável: desconta a visita.
                inv.enumerated -= 1
                continue
            }

            if rv.isSymbolicLink == true {
                inv.skipped[SkipReason.symlink.rawValue, default: 0] += 1
                continue
            }
            if rv.isRegularFile != true {
                inv.skipped[SkipReason.junk.rawValue, default: 0] += 1
                continue
            }
            let base = url.lastPathComponent
            if base.hasPrefix("._") {
                inv.skipped[SkipReason.appleDouble.rawValue, default: 0] += 1
                continue
            }
            if junkNames.contains(base) {
                inv.skipped[SkipReason.junk.rawValue, default: 0] += 1
                continue
            }
            guard let st = lstatOf(url.path) else {
                inv.errors[IndexError.stat.rawValue, default: 0] += 1
                continue
            }
            if st.size < minSize {
                inv.skipped[SkipReason.tooSmall.rawValue, default: 0] += 1
                // Ainda conta no espaço: 23 mil arquivos de menos de 1 MB somavam
                // 1,35 GB num disco meu, e ignorá-los faria o total mentir.
                inv.bytesLogical += st.size
                inv.bytesAllocated += st.allocated
                continue
            }

            inv.indexed += 1
            inv.bytesLogical += st.size
            inv.bytesAllocated += st.allocated
            let ext = url.pathExtension.isEmpty ? "(sem extensão)" : url.pathExtension.lowercased()
            byExt[ext, default: NamedStat(name: ext, files: 0, bytes: 0)].add(st.allocated)
            let folder = topFolder(of: url, belowRootComponents: rootDepth)
            byFolder[folder, default: NamedStat(name: folder, files: 0, bytes: 0)].add(st.allocated)
            buckets.add(size: st.size, bytes: st.allocated)

            ents.append(FileEntry(url: url, size: st.size, mtime: st.mtime,
                                  inode: InodeKey(dev: st.dev, ino: st.ino)))

            if inv.indexed % 2000 == 0 { progress(inv.indexed, inv.bytesAllocated) }
        }

        // Cada diretório que falhou conta como um item visitado que terminou no
        // balde de erro: a conta fecha e a falha fica visível.
        if walkErrors.count > 0 {
            inv.errors[IndexError.enumerator.rawValue, default: 0] += walkErrors.count
            inv.enumerated += walkErrors.count
        }
        inv.byExtension = byExt.values.sorted { $0.bytes > $1.bytes }
        inv.byFolder = byFolder.values.sorted { $0.bytes > $1.bytes }
        inv.bySizeBucket = buckets.rows()
        inv.metadata = meta.values.sorted { $0.bytes > $1.bytes }
        inv.durationMs = Int(Date().timeIntervalSince(started) * 1000)
        progress(inv.indexed, inv.bytesAllocated)
        return (inv, ents)
    }

    // MARK: private

    /// Primeiro componente abaixo da raiz varrida. Arquivo solto na raiz vira
    /// uma linha própria em vez de se diluir no total.
    ///
    /// Conta componentes em vez de cortar prefixo de string: o prefixo erra
    /// quando o caminho volta com outra grafia de maiúsculas (filesystem
    /// case-insensitive) ou com barra sobrando, e aí a pasta reportada era
    /// "Users".
    private func topFolder(of url: URL, belowRootComponents rootDepth: Int) -> String {
        let comps = url.pathComponents
        guard comps.count > rootDepth + 1 else { return "(raiz)" }
        return comps[rootDepth]
    }

    private func lstatOf(_ path: String)
        -> (dev: Int32, ino: UInt64, size: Int64, allocated: Int64, mtime: Date)? {
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }
        let mtime = Date(timeIntervalSince1970:
            Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1e9)
        // st_blocks é sempre em unidades de 512 B (não é o bsize do filesystem).
        return (st.st_dev, st.st_ino, Int64(st.st_size), Int64(st.st_blocks) * 512, mtime)
    }

    /// Tamanho alocado de uma subárvore (usado só nas áreas de serviço podadas).
    private func allocatedSize(of url: URL) -> Int64 {
        guard let en = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
            options: [], errorHandler: { _, _ in true }
        ) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in en {
            if let v = try? f.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]) {
                total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
            }
        }
        return total
    }
}

/// Contador compartilhado com o `errorHandler` do enumerador (que é um closure
/// de escape e não pode capturar um `var` local do walk).
private final class ErrorTally {
    var count = 0
}

// MARK: - Faixas de tamanho

/// Distribuição por tamanho. As faixas são as que se provaram úteis na prática:
/// separam "milhares de arquivinhos que somam pouco" de "poucos arquivos que são
/// o disco inteiro" (380 `.mp4` somavam 50 GB contra 23.661 arquivos somando 1,35 GB).
struct SizeBucket {
    private static let limits: [(String, Int64)] = [
        ("< 1 KB", 1024),
        ("1 KB – 1 MB", 1 << 20),
        ("1 – 10 MB", 10 << 20),
        ("10 – 100 MB", 100 << 20),
        ("100 MB – 1 GB", 1 << 30),
        ("> 1 GB", Int64.max),
    ]
    private var counts = [Int](repeating: 0, count: limits.count)
    private var bytes = [Int64](repeating: 0, count: limits.count)

    static func empty() -> SizeBucket { SizeBucket() }

    mutating func add(size: Int64, bytes b: Int64) {
        for (i, limit) in Self.limits.enumerated() where size < limit.1 {
            counts[i] += 1
            bytes[i] += b
            return
        }
    }

    func rows() -> [NamedStat] {
        Self.limits.enumerated().compactMap { i, l in
            counts[i] == 0 ? nil : NamedStat(name: l.0, files: counts[i], bytes: bytes[i])
        }
    }
}

extension NamedStat {
    mutating func add(_ b: Int64) {
        self = NamedStat(name: name, files: files + 1, bytes: bytes + b)
    }
}
