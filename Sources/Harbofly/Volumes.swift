import Foundation

// MARK: - Volumes montados

/// O que o app pode fazer com um volume. A lista crua do sistema é um pântano
/// (DMG de instalador, runtimes selados do CoreSimulator, /System/Volumes/*, o
/// mesmo disco físico montado duas vezes), então todo volume nasce classificado
/// e a UI nunca oferece ação em cima do que não deve ser tocado.
enum VolumeTier {
    /// Disco de dados gravável: indexa e pode apagar.
    case scannable
    /// DMG montado, runtime selado: indexa (informativo), nunca apaga.
    case readOnly
    /// Destino de Time Machine ou volume de rede: mede e mostra, não toca.
    case protected

    var canDelete: Bool { self == .scannable }
}

/// Um volume montado, já medido e classificado.
struct MountedVolume: Identifiable, Hashable {
    var id: String { url.path }
    let url: URL
    /// Nome de exibição (volumeNameKey), com fallback pro último componente.
    let name: String
    /// Tipo do filesystem vindo do statfs ("apfs", "exfat", "hfs", "smbfs"…).
    let fsType: String
    let total: Int64
    let free: Int64
    let isInternal: Bool
    let isRemovable: Bool
    let isEjectable: Bool
    let isReadOnly: Bool
    let isLocal: Bool
    /// É o volume de boot (`/`).
    let isRoot: Bool
    let isTimeMachine: Bool
    /// Identidade do volume — pega o mesmo disco físico montado em dois pontos
    /// (`/` e `/System/Volumes/Data` são o mesmo APFS container).
    let identifier: String
    /// `trashItem` funciona aqui? Em volume sem Lixeira a promessa "sempre
    /// recuperável" deixa de valer, e a UI precisa dizer isso em vez de cair
    /// em exclusão definitiva silenciosa.
    let trashSupported: Bool
    let tier: VolumeTier
    /// `true` quando isto não é um ponto de montagem, e sim uma pasta que o
    /// usuário pediu para tratar como escopo (`harbofly compare pastaA pastaB`).
    /// Tier, Lixeira e espaço vêm do volume real que a contém; o que muda é que
    /// a identidade do escopo passa a ser o caminho, não o `st_dev` — duas
    /// pastas do mesmo disco têm o mesmo dev e precisam ser distinguidas.
    var isSynthetic = false

    var used: Int64 { max(0, total - free) }
    var usedRatio: Double { total > 0 ? Double(used) / Double(total) : 0 }
    /// Externo = não é disco interno, ou é removível (pen drive, cartão, USB).
    var isExternal: Bool { !isInternal || isRemovable }
}

enum Volumes {

    /// Volumes que valem mostrar, do boot pros externos. Filtra tudo que o
    /// Finder também esconde, e nunca devolve o mesmo disco duas vezes.
    ///
    /// Por padrão deixa de fora os somente-leitura: um DMG de instalador
    /// montado (`/Volumes/Claude`, `/Volumes/Bambu Studio`) não é disco que se
    /// administre, e aparecer na lista é só ruído. `includingReadOnly` traz
    /// tudo, para quem quiser ver o que o app está ignorando.
    static func mounted(includingReadOnly: Bool = false) -> [MountedVolume] {
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeIsBrowsableKey, .volumeIsInternalKey,
            .volumeIsRemovableKey, .volumeIsEjectableKey, .volumeIsReadOnlyKey,
            .volumeIsLocalKey, .volumeIsRootFileSystemKey, .volumeIdentifierKey,
        ]
        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]
        ) else { return [] }

        let tmMounts = timeMachineMounts()
        var out: [MountedVolume] = []
        var seen = Set<String>()
        for url in urls {
            // /System/Volumes/* são partições de sistema (VM, Preboot, Update,
            // Data…): o espaço delas já está contado no volume de boot.
            if url.path.hasPrefix("/System/Volumes/") { continue }
            guard let v = describe(url, keys: keys, tmMounts: tmMounts) else { continue }
            guard v.total > 0 else { continue }                  // volume fantasma
            if v.isReadOnly && !includingReadOnly { continue }
            if !v.identifier.isEmpty, !seen.insert(v.identifier).inserted { continue }
            out.append(v)
        }
        // Boot primeiro (é o alvo de comparação natural), depois os maiores.
        out.sort { a, b in
            if a.isRoot != b.isRoot { return a.isRoot }
            return a.total > b.total
        }
        return out
    }

    /// Caminho canônico de uma raiz: symlinks resolvidos e `.`/`..` removidos.
    ///
    /// Tudo aqui compara caminho por prefixo, e prefixo mente quando há symlink
    /// no meio: o enumerador do FileManager devolve `/private/tmp/x` para uma
    /// raiz dada como `/tmp/x`, e aí nenhum arquivo "pertence" ao escopo. A raiz
    /// é canonizada UMA vez (resolver por arquivo seria um syscall a mais em
    /// cada um dos quase um milhão de itens de um disco grande).
    static func canonical(_ url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
    }

    /// Espaço do volume que contém `path`. `statfs` direto, igual ao
    /// `DiskScanner.diskSpace()` — e pelo mesmo motivo: `resourceValues` fica
    /// preso ao cache da URL e não reflete a deleção na hora.
    static func space(at path: String) -> (free: Int64, total: Int64) {
        var st = statfs()
        guard statfs(path, &st) == 0 else { return (0, 0) }
        let bsize = Int64(st.f_bsize)
        return (Int64(st.f_bavail) * bsize, Int64(st.f_blocks) * bsize)
    }

    /// Tipo do filesystem no ponto de montagem ("apfs", "exfat"…).
    static func fsType(at path: String) -> String {
        var st = statfs()
        guard statfs(path, &st) == 0 else { return "" }
        return withUnsafeBytes(of: &st.f_fstypename) { raw in
            String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
        }
    }

    /// Trata uma pasta qualquer como escopo de comparação, herdando do volume
    /// real que a contém tudo que diz respeito a segurança (só-leitura, rede,
    /// Time Machine, Lixeira).
    static func scope(forFolder url: URL, in list: [MountedVolume]) -> MountedVolume? {
        let dir = canonical(url)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir),
              isDir.boolValue else { return nil }
        guard let host = owner(of: dir, in: list) else { return nil }
        return MountedVolume(
            url: dir, name: dir.lastPathComponent, fsType: host.fsType,
            total: host.total, free: host.free,
            isInternal: host.isInternal, isRemovable: host.isRemovable,
            isEjectable: host.isEjectable, isReadOnly: host.isReadOnly,
            isLocal: host.isLocal, isRoot: false, isTimeMachine: host.isTimeMachine,
            identifier: host.identifier, trashSupported: host.trashSupported,
            tier: host.tier, isSynthetic: true
        )
    }

    /// Volume que contém este caminho, se estiver entre os montados visíveis.
    static func owner(of url: URL, in list: [MountedVolume]) -> MountedVolume? {
        let path = canonical(url).path
        // Caminho mais longo primeiro: /Volumes/X ganha de / para /Volumes/X/a.
        return list.sorted { $0.url.path.count > $1.url.path.count }
            .first { path == $0.url.path || path.hasPrefix($0.url.path == "/" ? "/" : $0.url.path + "/") }
    }

    // MARK: private

    private static func describe(_ url: URL, keys: [URLResourceKey],
                                 tmMounts: Set<String>) -> MountedVolume? {
        guard let rv = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
        guard rv.volumeIsBrowsable != false else { return nil }

        let (free, total) = space(at: url.path)
        let isRoot = rv.volumeIsRootFileSystem ?? (url.path == "/")
        let isReadOnly = rv.volumeIsReadOnly ?? false
        let isLocal = rv.volumeIsLocal ?? true
        let isTM = tmMounts.contains(url.path) || hasBackupMarker(url)

        let tier: VolumeTier
        if isTM || !isLocal { tier = .protected }
        else if isReadOnly { tier = .readOnly }
        else { tier = .scannable }

        return MountedVolume(
            url: url,
            name: rv.volumeName ?? (url.path == "/" ? "Macintosh HD" : url.lastPathComponent),
            fsType: fsType(at: url.path),
            total: total,
            free: free,
            isInternal: rv.volumeIsInternal ?? isRoot,
            isRemovable: rv.volumeIsRemovable ?? false,
            isEjectable: rv.volumeIsEjectable ?? false,
            isReadOnly: isReadOnly,
            isLocal: isLocal,
            isRoot: isRoot,
            isTimeMachine: isTM,
            identifier: (rv.volumeIdentifier as? NSObject)?.description ?? "",
            trashSupported: trashWorks(url, isRoot: isRoot, readOnly: isReadOnly, tier: tier),
            tier: tier
        )
    }

    /// Destinos de Time Machine configurados (`tmutil destinationinfo`). Apagar
    /// de dentro de um backup corrompe o backup — então o volume só aparece.
    private static func timeMachineMounts() -> Set<String> {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        p.arguments = ["destinationinfo"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return [] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        var mounts = Set<String>()
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespaces) == "Mount Point" else { continue }
            let path = parts[1].trimmingCharacters(in: .whitespaces)
            if !path.isEmpty { mounts.insert(path) }
        }
        return mounts
    }

    /// Marcador de backup na raiz do volume, pros destinos que o tmutil não
    /// lista (disco de backup de outra máquina, por exemplo).
    private static func hasBackupMarker(_ url: URL) -> Bool {
        let fm = FileManager.default
        for marker in ["Backups.backupdb", ".Backups.backupdb"] {
            if fm.fileExists(atPath: url.appendingPathComponent(marker).path) { return true }
        }
        // .backupbundle/.sparsebundle de TM ficam soltos na raiz.
        guard let items = try? fm.contentsOfDirectory(atPath: url.path) else { return false }
        return items.contains { $0.hasSuffix(".backupbundle") }
    }

    /// Heurística de Lixeira: o volume de boot sempre tem (~/.Trash); nos outros
    /// o macOS cria `.Trashes/<uid>` na primeira vez, então "a raiz é gravável"
    /// é o melhor sinal barato. Read-only e protegido nunca têm.
    private static func trashWorks(_ url: URL, isRoot: Bool,
                                   readOnly: Bool, tier: VolumeTier) -> Bool {
        guard !readOnly, tier == .scannable else { return false }
        if isRoot { return true }
        let fm = FileManager.default
        let trashes = url.appendingPathComponent(".Trashes")
        if fm.fileExists(atPath: trashes.path) { return fm.isWritableFile(atPath: trashes.path) }
        return fm.isWritableFile(atPath: url.path)
    }
}
