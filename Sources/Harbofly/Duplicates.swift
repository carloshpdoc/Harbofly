import Foundation
import CryptoKit

// MARK: - Model

/// Um arquivo dentro de um grupo de duplicatas.
struct DuplicateFile: Identifiable {
    let id = UUID()
    let url: URL
    let size: Int64
    let modified: Date
    /// O "keeper": a cópia que fica. Os demais do grupo são candidatos a apagar.
    var isKeeper = false
}

/// Conjunto de arquivos com conteúdo byte-a-byte idêntico (sempre >= 2).
struct DuplicateGroup: Identifiable {
    let id = UUID()
    let size: Int64
    /// SHA-256 hex do conteúdo (compartilhado por todos do grupo).
    let hash: String
    /// keeper primeiro, depois os candidatos a apagar.
    var files: [DuplicateFile]

    /// Espaço recuperável = (n-1) × tamanho (apaga tudo menos o keeper).
    var reclaimable: Int64 { size * Int64(max(0, files.count - 1)) }
    var removable: [DuplicateFile] { files.filter { !$0.isKeeper } }
}

// MARK: - Scanner

/// Detector de arquivos duplicados por CONTEÚDO (não por nome). Pipeline em 4
/// fases, cada uma barata o suficiente pra só passar o candidato adiante:
///   1. agrupa por tamanho exato          (elimina ~tudo sem ler byte)
///   2. hash parcial (cabeça+cauda 16KB)  (divide grupos de mesmo tamanho)
///   3. SHA-256 completo (streaming, HW)  (colisão ~2^-256)
///   4. verificação byte-a-byte           (garantia absoluta antes de apagar)
/// Nunca apaga a última cópia de um grupo; ignora symlinks, hardlinks (mesmo
/// inode = mesma cópia física), bundles, e internos de VCS/deps.
final class DuplicateScanner: ObservableObject {
    @Published var groups: [DuplicateGroup] = []
    @Published var scanning = false
    @Published var statusLine = ""
    @Published var deleting = false
    @Published var deletingDone = 0
    @Published var deletingTotal = 0
    @Published var lastFreedBytes: Int64 = 0
    @Published var justFinished = false

    var totalReclaimable: Int64 { groups.reduce(0) { $0 + $1.reclaimable } }

    // Config
    private let minSize: Int64 = 4 * 1024            // ignora ruído < 4 KB
    private let partialChunk = 16 * 1024             // cabeça+cauda no hash parcial
    private let streamChunk = 1 * 1024 * 1024        // 1 MB no hash completo/verify
    private let junkNames: Set<String> = [".DS_Store", ".localized"]
    /// Diretórios que NÃO entram: apagar um objeto idêntico aqui corromperia
    /// um repo/dependência. Confiança > completude.
    private let skipDirs: Set<String> = [
        ".git", "node_modules", ".Trash", ".build", "DerivedData",
        "Pods", ".venv", "venv", "__pycache__",
    ]

    // MARK: API (assíncrona, pra UI)

    func scan(roots: [URL]) {
        guard !scanning, !deleting else { return }
        scanning = true
        groups = []
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let found = self.findDuplicates(roots: roots) { line in
                DispatchQueue.main.async { self.statusLine = line }
            }
            DispatchQueue.main.async {
                self.groups = found
                self.scanning = false
                self.statusLine = ""
            }
        }
    }

    /// Move os arquivos (nunca keepers) pra Lixeira (ou apaga de vez). Dissolve
    /// grupos que ficarem com < 2 arquivos.
    func delete(_ files: [DuplicateFile], permanently: Bool) {
        let removable = files.filter { !$0.isKeeper }   // guard: keeper nunca sai
        guard !removable.isEmpty else { return }
        deleting = true
        deletingDone = 0
        deletingTotal = removable.count
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var freed: Int64 = 0
            var deleted = Set<UUID>()
            for f in removable {
                let ok = permanently
                    ? (try? FileManager.default.removeItem(at: f.url)) != nil
                    : (try? FileManager.default.trashItem(at: f.url, resultingItemURL: nil)) != nil
                if ok { freed += f.size; deleted.insert(f.id) }
                DispatchQueue.main.async { self.deletingDone += 1 }
            }
            let freedFinal = freed
            DispatchQueue.main.async {
                self.groups = self.groups.compactMap { g in
                    var g = g
                    g.files.removeAll { deleted.contains($0.id) }
                    return g.files.count >= 2 ? g : nil
                }
                self.lastFreedBytes = freedFinal
                self.deleting = false
                self.justFinished = true
            }
        }
    }

    // MARK: Núcleo síncrono (compartilhado UI + CLI)

    func findDuplicates(roots: [URL], progress: (String) -> Void = { _ in }) -> [DuplicateGroup] {
        // Fase 0 — enumerar, deduplicando hardlinks por (dev, inode).
        progress("Listando arquivos…")
        var bySize: [Int64: [Entry]] = [:]
        var seenInodes = Set<InodeKey>()
        for root in roots {
            enumerate(root) { e in
                if seenInodes.contains(e.inode) { return }  // hardlink: cópia física única
                seenInodes.insert(e.inode)
                bySize[e.size, default: []].append(e)
            }
        }

        // Fase 1 — só tamanhos com colisão.
        let sizeGroups = bySize.values.filter { $0.count >= 2 }
        guard !sizeGroups.isEmpty else { return [] }

        // Fase 2 — hash parcial (cabeça+cauda).
        progress("Comparando pontas (\(sizeGroups.reduce(0) { $0 + $1.count }) candidatos)…")
        var byPartial: [String: [Entry]] = [:]
        for group in sizeGroups {
            for e in group {
                let key = "\(e.size):\(partialHash(e.url, size: e.size))"
                byPartial[key, default: []].append(e)
            }
        }
        let partialFlat = byPartial.values.filter { $0.count >= 2 }.flatMap { $0 }
        guard !partialFlat.isEmpty else { return [] }

        // Fase 3 — SHA-256 completo (streaming, concorrente).
        progress("Hash completo de \(partialFlat.count) arquivos…")
        var byFull: [String: [Entry]] = [:]
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: partialFlat.count) { i in
            let e = partialFlat[i]
            guard let h = self.fullHash(e.url) else { return }
            lock.lock(); byFull[h, default: []].append(e); lock.unlock()
        }
        let fullGroups = byFull.filter { $0.value.count >= 2 }

        // Fase 4 — verificação byte-a-byte contra o keeper (garantia absoluta).
        progress("Verificando byte-a-byte…")
        var result: [DuplicateGroup] = []
        for (hash, entries) in fullGroups {
            let ranked = entries.sorted { keeperRank($0) < keeperRank($1) }
            let keeper = ranked[0]
            var confirmed = [keeper]
            for e in ranked.dropFirst() where bytesEqual(keeper.url, e.url) {
                confirmed.append(e)
            }
            guard confirmed.count >= 2 else { continue }
            var files = confirmed.map {
                DuplicateFile(url: $0.url, size: $0.size, modified: $0.mtime)
            }
            files[0].isKeeper = true
            result.append(DuplicateGroup(size: keeper.size, hash: hash, files: files))
        }
        result.sort { $0.reclaimable > $1.reclaimable }
        return result
    }

    // MARK: private

    private struct InodeKey: Hashable { let dev: Int32; let ino: UInt64 }
    private struct Entry { let url: URL; let size: Int64; let mtime: Date; let inode: InodeKey }

    private func enumerate(_ root: URL, _ emit: (Entry) -> Void) {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey,
                                         .isPackageKey, .isDirectoryKey]
        guard let en = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: Array(keys),
            options: [], errorHandler: { _, _ in true }
        ) else { return }
        for case let url as URL in en {
            guard let rv = try? url.resourceValues(forKeys: keys) else { continue }
            if rv.isDirectory == true {
                if rv.isPackage == true || skipDirs.contains(url.lastPathComponent) {
                    en.skipDescendants()
                }
                continue
            }
            if rv.isSymbolicLink == true || rv.isRegularFile != true { continue }
            let name = url.lastPathComponent
            if name.hasPrefix("._") || junkNames.contains(name) { continue }
            guard let s = statOf(url.path), s.size >= minSize else { continue }
            emit(Entry(url: url, size: s.size, mtime: s.mtime,
                       inode: InodeKey(dev: s.dev, ino: s.ino)))
        }
    }

    private func statOf(_ path: String) -> (dev: Int32, ino: UInt64, size: Int64, mtime: Date)? {
        var st = stat()
        guard stat(path, &st) == 0 else { return nil }
        let mtime = Date(timeIntervalSince1970:
            Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1e9)
        return (st.st_dev, st.st_ino, Int64(st.st_size), mtime)
    }

    /// Ordem do keeper (menor = fica): pasta mais canônica, evita Lixeira e
    /// nomes de cópia, depois mais antigo, depois caminho mais curto.
    private func keeperRank(_ e: Entry) -> (Int, TimeInterval, Int) {
        let p = e.url.path
        var rank: Int
        if p.contains("/Documents/") { rank = 0 }
        else if p.contains("/Pictures/") { rank = 1 }
        else if p.contains("/Desktop/") { rank = 3 }
        else if p.contains("/Downloads/") { rank = 4 }
        else { rank = 2 }
        if p.contains("/.Trash/") { rank += 100 }
        let n = e.url.lastPathComponent.lowercased()
        if n.contains(" copy") || n.contains("(1)") || n.contains("cópia") { rank += 10 }
        return (rank, e.mtime.timeIntervalSince1970, p.count)
    }

    private func partialHash(_ url: URL, size: Int64) -> String {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return "?" }
        defer { try? fh.close() }
        var hasher = SHA256()
        let head = (try? fh.read(upToCount: partialChunk)) ?? Data()
        hasher.update(data: head)
        if size > Int64(partialChunk) * 2 {
            try? fh.seek(toOffset: UInt64(size - Int64(partialChunk)))
            let tail = (try? fh.read(upToCount: partialChunk)) ?? Data()
            hasher.update(data: tail)
        }
        return hex(hasher.finalize())
    }

    private func fullHash(_ url: URL) -> String? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        var hasher = SHA256()
        while true {
            let chunk = autoreleasepool { (try? fh.read(upToCount: streamChunk)) ?? Data() }
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hex(hasher.finalize())
    }

    private func bytesEqual(_ a: URL, _ b: URL) -> Bool {
        guard let fa = try? FileHandle(forReadingFrom: a),
              let fb = try? FileHandle(forReadingFrom: b) else { return false }
        defer { try? fa.close(); try? fb.close() }
        while true {
            let da = autoreleasepool { (try? fa.read(upToCount: streamChunk)) ?? Data() }
            let db = autoreleasepool { (try? fb.read(upToCount: streamChunk)) ?? Data() }
            if da != db { return false }
            if da.isEmpty { return true }
        }
    }

    private func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
