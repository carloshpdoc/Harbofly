import Foundation

/// Modo CLI do binário do app: `harbofly scan|clean|version`.
/// O cask do Homebrew cria o symlink `harbofly` pro executável dentro do
/// .app, então CLI e app são sempre a mesma versão, sem target separado.
/// Output em inglês (convenção de CLI); a UI continua nos 6 idiomas.
enum CLI {
    static func run(_ args: [String]) -> Int32 {
        switch args.first {
        case "scan":
            return scan(json: args.contains("--json"))
        case "clean":
            return clean(dryRun: args.contains("--dry-run"),
                         staleOnly: args.contains("--stale-only"))
        case "dups", "duplicates":
            let paths = args.dropFirst().filter { !$0.hasPrefix("-") }
            return dups(paths: Array(paths),
                        apply: args.contains("--apply"),
                        permanent: args.contains("--permanent"),
                        json: args.contains("--json"))
        case "volumes", "disks":
            return volumes(json: args.contains("--json"), all: args.contains("--all"))
        case "index":
            let paths = args.dropFirst().filter { !$0.hasPrefix("-") }
            return index(paths: Array(paths), json: args.contains("--json"))
        case "compare":
            let paths = args.dropFirst().filter { !$0.hasPrefix("-") }
            return compare(paths: Array(paths),
                           apply: args.contains("--apply"),
                           permanent: args.contains("--permanent"),
                           subtrees: args.contains("--subtrees"),
                           onlyUnique: args.contains("--only-unique"),
                           json: args.contains("--json"))
        case "version", "--version":
            print("\(AppInfo.name) \(AppInfo.version) (build \(AppInfo.build))")
            return 0
        case "help", "--help", "-h", nil:
            printHelp()
            return 0
        default:
            printHelp()
            return 64 // EX_USAGE
        }
    }

    private static func scan(json: Bool) -> Int32 {
        let scanner = DiskScanner(autoTriggers: false)
        if !json { FileHandle.standardError.write(Data("Scanning…\n".utf8)) }
        let targets = scanner.collectAll()
        let (free, total) = scanner.diskSpace()

        if json {
            let rows: [[String: Any]] = targets.map { t in
                var row: [String: Any] = [
                    "label": t.displayLabel,
                    "path": t.url.path,
                    "tier": tierName(t.tier),
                    "bytes": t.bytes,
                ]
                if let d = t.staleDays { row["staleDays"] = d }
                if t.unsavedWork { row["unsavedWork"] = true }
                if t.isDocker { row["docker"] = true }
                if t.isGitGC { row["gitgc"] = true }
                if t.isWorktree { row["worktree"] = true }
                if let p = t.worktreePending { row["pending"] = p }
                return row
            }
            let payload: [String: Any] = ["freeBytes": free, "totalBytes": total, "targets": rows]
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
                print(String(data: data, encoding: .utf8) ?? "{}")
            }
            return 0
        }

        print("\(AppInfo.name) — \(fmt(free)) free of \(fmt(total))\n")
        for t in targets {
            var extras: [String] = []
            if let d = t.staleDays, d >= Prefs.staleThresholdDays { extras.append("idle \(d)d") }
            if t.unsavedWork { extras.append("unpushed work!") }
            let suffix = extras.isEmpty ? "" : "  [\(extras.joined(separator: ", "))]"
            print("\(tierEmoji(t.tier))  \(pad(fmt(t.bytes)))  \(t.displayLabel) — \(relPath(t.url))\(suffix)")
        }
        let reclaimable = targets.filter { !$0.tier.isReadOnly }.reduce(Int64(0)) { $0 + $1.bytes }
        print("\nreclaimable: \(fmt(reclaimable)) (🟢+🟡; 🔵 is read-only)")
        return 0
    }

    private static func clean(dryRun: Bool, staleOnly: Bool) -> Int32 {
        let scanner = DiskScanner(autoTriggers: false)
        FileHandle.standardError.write(Data("Scanning…\n".utf8))
        let targets = scanner.collectAll()
        // Mesma semântica do "Selecionar seguros" do app: só tier 🟢.
        // Docker fica de fora (prune é irreversível — use o app ou o docker).
        // git gc também fica de fora (a ação é recompactar o repo, não Lixeira —
        // mandar um repo pra Lixeira seria catastrófico; use o app ou `git gc`).
        var eligible = targets.filter { $0.tier == .safe && !$0.isDocker && !$0.isGitGC && !$0.isWorktree }
        if staleOnly {
            eligible = eligible.filter { ($0.staleDays ?? 0) >= Prefs.staleThresholdDays }
        }
        guard !eligible.isEmpty else {
            print("Nothing to clean.")
            return 0
        }
        var freed: Int64 = 0
        var cleaned = 0
        var byCategory: [String: Int64] = [:]
        for t in eligible {
            if dryRun {
                print("would trash:  \(pad(fmt(t.bytes)))  \(t.displayLabel)")
                freed += t.bytes
            } else if (try? FileManager.default.trashItem(at: t.url, resultingItemURL: nil)) != nil {
                print("trashed:  \(pad(fmt(t.bytes)))  \(t.displayLabel)")
                freed += t.bytes
                cleaned += 1
                byCategory[t.url.lastPathComponent, default: 0] += t.bytes
            } else {
                print("FAILED:   \(t.displayLabel) — \(t.url.path)")
            }
        }
        // Mesmo histórico/total da UI (mesmo domínio de defaults do .app).
        if !dryRun { CleanLog.record(bytes: freed, count: cleaned, byCategory: byCategory) }
        print(dryRun ? "\nWould move \(fmt(freed)) to the Trash."
                     : "\nMoved \(fmt(freed)) to the Trash (recoverable until you empty it).")
        if targets.contains(where: { $0.isDocker }) {
            print("note: Docker space is skipped in the CLI — use the app or `docker system prune`.")
        }
        if targets.contains(where: { $0.isGitGC }) {
            print("note: bloated git repos are skipped in the CLI — use the app or run `git gc` in the repo.")
        }
        return 0
    }

    /// Duplicatas por conteúdo. Sem pastas = presets pessoais. Dry-run por
    /// padrão; `--apply` manda os não-keepers pra Lixeira (o keeper sempre fica).
    private static func dups(paths: [String], apply: Bool, permanent: Bool, json: Bool) -> Int32 {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots: [URL] = paths.isEmpty
            ? ["Downloads", "Documents", "Desktop", "Pictures"].map { home.appendingPathComponent($0) }
            : paths.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        let existing = roots.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else {
            FileHandle.standardError.write(Data("No folders to scan.\n".utf8))
            return 64
        }

        let scanner = DuplicateScanner()
        let groups = scanner.findDuplicates(roots: existing) { phase in
            if !json { dupProgress(phase) }
        }
        let reclaimable = groups.reduce(Int64(0)) { $0 + $1.reclaimable }

        if json {
            let rows: [[String: Any]] = groups.map { g in
                ["hash": g.hash, "size": g.size, "reclaimable": g.reclaimable,
                 "keeper": g.files.first(where: { $0.isKeeper })?.url.path ?? "",
                 "duplicates": g.removable.map { $0.url.path }]
            }
            let payload: [String: Any] = ["groups": rows, "reclaimableBytes": reclaimable]
            if let data = try? JSONSerialization.data(withJSONObject: payload,
                                                      options: [.prettyPrinted, .sortedKeys]) {
                print(String(data: data, encoding: .utf8) ?? "{}")
            }
            return 0
        }

        if groups.isEmpty { print("No duplicates found."); return 0 }
        for g in groups {
            print("\n\(pad(fmt(g.size))) × \(g.files.count)  reclaim \(fmt(g.reclaimable))  sha256:\(g.hash.prefix(12))")
            for f in g.files {
                let mark = f.isKeeper ? "keep " : (apply ? "TRASH" : "dup  ")
                print("  \(mark) \(relPath(f.url))")
            }
        }
        print("\n\(groups.count) group(s) — reclaimable: \(fmt(reclaimable))")

        guard apply else {
            print("(dry-run — pass --apply to move duplicates to the Trash; the keeper stays.)")
            return 0
        }
        var freed: Int64 = 0, n = 0
        for g in groups {
            for f in g.removable {
                let ok = permanent
                    ? (try? FileManager.default.removeItem(at: f.url)) != nil
                    : (try? FileManager.default.trashItem(at: f.url, resultingItemURL: nil)) != nil
                if ok { freed += f.size; n += 1 }
            }
        }
        CleanLog.record(bytes: freed, count: n, byCategory: ["duplicates": freed])
        print(permanent
              ? "Deleted \(n) file(s), freed \(fmt(freed))."
              : "Moved \(n) file(s) to the Trash, freed \(fmt(freed)) (recoverable).")
        return 0
    }

    // MARK: discos conectados

    /// Volumes montados que valem mostrar. É o mesmo filtro da UI: o que o
    /// Finder esconde (nobrowse, /System/Volumes/*, DMG de instalador) fica fora.
    private static func volumes(json: Bool, all: Bool) -> Int32 {
        let list = Volumes.mounted(includingReadOnly: all)
        if json {
            let rows: [[String: Any]] = list.map { v in
                ["name": v.name, "path": v.url.path, "fs": v.fsType,
                 "totalBytes": v.total, "freeBytes": v.free,
                 "tier": tierName(v.tier), "internal": v.isInternal,
                 "removable": v.isRemovable, "readOnly": v.isReadOnly,
                 "timeMachine": v.isTimeMachine, "trash": v.trashSupported]
            }
            return emitJSON(["volumes": rows])
        }
        guard !list.isEmpty else { print("No volumes."); return 0 }
        print("\(AppInfo.name) \(AppInfo.version) — mounted volumes\n")
        for v in list {
            print("\(pad(fmt(v.total)))  \(pad(fmt(v.free))) free  \(padR(v.fsType, 6))  \(v.name)")
            print("           \(v.url.path)  [\(flags(v).joined(separator: ", "))]")
        }
        return 0
    }

    private static func flags(_ v: MountedVolume) -> [String] {
        var f: [String] = []
        f.append(v.isRoot ? "boot" : (v.isInternal ? "internal" : "external"))
        if v.isRemovable { f.append("removable") }
        if v.isReadOnly { f.append("read-only") }
        if v.isTimeMachine { f.append("Time Machine") }
        if !v.isLocal { f.append("network") }
        f.append(v.trashSupported ? "trash" : "NO TRASH")
        if !v.tier.canDelete { f.append("protected") }
        return f
    }

    /// Inventário de um volume: cobertura, espaço, e os cortes por pasta,
    /// extensão e faixa de tamanho.
    private static func index(paths: [String], json: Bool) -> Int32 {
        guard let root = resolveOne(paths) else { return 64 }
        let indexer = VolumeIndexer()
        if !json { FileHandle.standardError.write(Data("Walking \(root.path)…\n".utf8)) }
        let (inv, _) = indexer.walk(root: root) { n, bytes in
            guard !json, n % 20_000 == 0 else { return }
            FileHandle.standardError.write(Data("\r\(n) files, \(fmt(bytes))   ".utf8))
        }
        if !json { FileHandle.standardError.write(Data("\n".utf8)) }

        if json {
            return emitJSON([
                "root": root.path,
                "enumerated": inv.enumerated, "indexed": inv.indexed,
                "skipped": inv.skipped, "errors": inv.errors,
                "coverageOK": inv.coverageOK,
                "bytesLogical": inv.bytesLogical, "bytesAllocated": inv.bytesAllocated,
                "durationMs": inv.durationMs,
                "byFolder": inv.byFolder.map { ["name": $0.name, "files": $0.files, "bytes": $0.bytes] },
                "byExtension": inv.byExtension.map { ["name": $0.name, "files": $0.files, "bytes": $0.bytes] },
                "bySize": inv.bySizeBucket.map { ["name": $0.name, "files": $0.files, "bytes": $0.bytes] },
                "metadata": inv.metadata.map { ["name": $0.name, "bytes": $0.bytes] },
            ])
        }

        let fs = Volumes.fsType(at: root.path)
        print("\(AppInfo.name) \(AppInfo.version) — index of \(root.path) (\(fs))\n")
        printCoverage(inv)
        print("")
        printStats("by folder", inv.byFolder, limit: 12)
        printStats("by extension", inv.byExtension, limit: 12)
        printStats("by size", inv.bySizeBucket, limit: 0)
        if !inv.metadata.isEmpty {
            print("volume service areas (never deletion candidates):")
            for m in inv.metadata { print("  \(pad(fmt(m.bytes)))  \(m.name)") }
            print("")
        }
        return inv.coverageOK ? 0 : 65   // EX_DATAERR: a conta não fechou
    }

    /// Compara um volume contra os outros montados: o que já existe em outro
    /// disco, o que está duplicado aqui dentro, e o que só existe aqui.
    private static func compare(paths: [String], apply: Bool, permanent: Bool,
                                subtrees: Bool, onlyUnique: Bool, json: Bool) -> Int32 {
        let all = Volumes.mounted()
        guard let targetPath = paths.first else {
            FileHandle.standardError.write(Data("Usage: harbofly compare <volume> [other…]\n".utf8))
            return 64
        }
        guard let target = volume(at: targetPath, in: all) else {
            FileHandle.standardError.write(Data("Not a volume or folder: \(targetPath)\n".utf8))
            return 64
        }
        let others: [MountedVolume]
        if paths.count > 1 {
            others = paths.dropFirst().compactMap { volume(at: $0, in: all) }
        } else if target.isSynthetic {
            // Alvo é uma pasta: comparar contra "todos os volumes" significaria
            // varrer o disco de boot inteiro por causa de um argumento que
            // parecia modesto. Quem compara pasta diz contra o quê.
            let msg = """
            \(targetPath) is a folder, not a volume — name the other side too:
              harbofly compare \(targetPath) <other-folder-or-volume>

            """
            FileHandle.standardError.write(Data(msg.utf8))
            return 64
        } else {
            // Alvo é um volume: comparar contra os outros montados é o ponto.
            others = all.filter { $0.id != target.id && $0.isLocal }
        }
        guard !others.isEmpty else {
            FileHandle.standardError.write(Data("No other volume to compare against.\n".utf8))
            return 64
        }

        let scanner = CrossVolumeScanner()
        let r = scanner.compare(target: target, others: others,
                                phase: { if !json { dupProgress($0) } },
                                walked: { n in
            guard !json, n % 20_000 == 0 else { return }
            FileHandle.standardError.write(Data("\rWalking… \(n) files   ".utf8))
        })

        if json {
            return emitJSON([
                "target": target.url.path,
                "others": others.map { $0.url.path },
                "indexedTarget": r.indexedTarget, "indexedOthers": r.indexedOthers,
                "coverageOK": r.coverageOK, "hashErrors": r.hashErrors,
                "verifyMismatches": r.verifyMismatches, "durationMs": r.durationMs,
                "sharedFiles": r.shared.count, "sharedBytes": r.sharedBytes,
                "internalFiles": r.internalDupes.count, "internalBytes": r.internalBytes,
                "uniqueFiles": r.uniqueFiles, "uniqueBytes": r.uniqueBytes,
                "mediaAtRisk": r.mediaAtRisk.count,
                "subtrees": r.subtrees.map { ["path": $0.url.path, "files": $0.files, "bytes": $0.bytes] },
                "shared": r.shared.prefix(5000).map {
                    ["path": $0.url.path, "bytes": $0.size, "sha256": $0.hash,
                     "keeper": $0.keeperURL.path, "keeperVolume": $0.keeperVolume,
                     "copies": $0.copies, "lastBackupOfMedia": $0.lastBackupOfMedia]
                },
            ])
        }

        print("\n\(AppInfo.name) \(AppInfo.version) — \(target.name) vs \(others.map { $0.name }.joined(separator: ", "))\n")
        print("indexed:  \(r.indexedTarget) here, \(r.indexedOthers) elsewhere")
        print("coverage: \(r.coverageOK ? "OK" : "FAILED — some files were not accounted for")"
              + "  hash errors: \(r.hashErrors)"
              + (r.verifyMismatches > 0 ? "  VERIFY MISMATCHES: \(r.verifyMismatches)" : ""))
        print("")
        // Rótulos de largura fixa: o nome do alvo no meio da coluna desalinhava
        // a tabela, e `compare` também aceita pasta, onde "volume" seria errado.
        print("  already elsewhere  : \(pad(fmt(r.sharedBytes)))  \(r.shared.count) file(s)")
        print("  duplicated inside  : \(pad(fmt(r.internalBytes)))  \(r.internalDupes.count) file(s)")
        print("  only here          : \(pad(fmt(r.uniqueBytes)))  \(r.uniqueFiles) file(s)")
        if !r.mediaAtRisk.isEmpty {
            print("\n  ⚠︎  \(r.mediaAtRisk.count) media file(s) would be left with a single copy.")
        }
        if !target.trashSupported {
            print("  ⚠︎  \(target.name) has no Trash — deleting there is permanent.")
        }

        if subtrees && !r.subtrees.isEmpty {
            print("\nfolders fully duplicated elsewhere:")
            for s in r.subtrees.prefix(40) {
                print("  \(pad(fmt(s.bytes)))  \(s.files) file(s)  \(s.url.path)")
            }
        }
        if onlyUnique {
            print("\n(only-here listing is a count here; use the Disks window or --json for the list.)")
        }

        guard apply else {
            print("\n(dry-run — pass --apply to remove what already exists on another volume.)")
            return 0
        }
        guard target.tier.canDelete else {
            FileHandle.standardError.write(Data("\(target.name) is protected (read-only, network or Time Machine).\n".utf8))
            return 77 // EX_NOPERM
        }
        var freed: Int64 = 0, n = 0, skipped = 0
        for row in r.shared {
            guard stillMatches(row) else { skipped += 1; continue }
            let ok = permanent
                ? (try? FileManager.default.removeItem(at: row.url)) != nil
                : (try? FileManager.default.trashItem(at: row.url, resultingItemURL: nil)) != nil
            if ok { freed += row.size; n += 1 } else { skipped += 1 }
        }
        CleanLog.record(bytes: freed, count: n, byCategory: ["crossvolume": freed])
        print(permanent
              ? "\nDeleted \(n) file(s), freed \(fmt(freed))."
              : "\nMoved \(n) file(s) to the Trash, freed \(fmt(freed)) (recoverable).")
        if skipped > 0 { print("skipped \(skipped) file(s) that changed since the scan or could not be removed.") }
        let (free, total) = Volumes.space(at: target.url.path)
        print("\(target.name): \(fmt(free)) free of \(fmt(total)).")
        return 0
    }

    /// O arquivo ainda é o que foi provado idêntico? Entre a varredura e a
    /// remoção ele pode ter mudado — aí não é mais o mesmo arquivo.
    private static func stillMatches(_ r: CrossVolumeRow) -> Bool {
        var st = stat()
        guard lstat(r.url.path, &st) == 0, Int64(st.st_size) == r.size else { return false }
        let mtime = Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1e9
        return abs(mtime - r.modified.timeIntervalSince1970) < 1
    }

    private static func printCoverage(_ inv: VolumeInventory) {
        let skips = inv.skipped.sorted { $0.value > $1.value }
            .map { "\($0.key) \($0.value)" }.joined(separator: ", ")
        let errs = inv.errors.sorted { $0.value > $1.value }
            .map { "\($0.key) \($0.value)" }.joined(separator: ", ")
        print("coverage: \(inv.indexed) indexed + \(inv.skippedTotal) skipped + \(inv.errorsTotal) errors"
              + " = \(inv.enumerated) visited  \(inv.coverageOK ? "OK" : "FAILED")")
        if !skips.isEmpty { print("  skipped:  \(skips)") }
        if !errs.isEmpty { print("  errors:   \(errs)") }
        var line = "bytes:    \(fmt(inv.bytesLogical)) logical / \(fmt(inv.bytesAllocated)) allocated"
        if inv.slackIsRelevant { line += "  (cluster slack \(fmt(inv.slackBytes)))" }
        print(line)
        print("time:     \(inv.durationMs) ms")
    }

    private static func printStats(_ title: String, _ rows: [NamedStat], limit: Int) {
        guard !rows.isEmpty else { return }
        print("\(title):")
        let shown = limit > 0 ? Array(rows.prefix(limit)) : rows
        for r in shown { print("  \(pad(fmt(r.bytes)))  \(pad("\(r.files)")) file(s)  \(r.name)") }
        if limit > 0 && rows.count > limit { print("  … \(rows.count - limit) more") }
        print("")
    }

    private static func resolveOne(_ paths: [String]) -> URL? {
        guard let first = paths.first else {
            FileHandle.standardError.write(Data("Usage: harbofly index <path>\n".utf8))
            return nil
        }
        let url = URL(fileURLWithPath: (first as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            FileHandle.standardError.write(Data("No such path: \(url.path)\n".utf8))
            return nil
        }
        return url
    }

    /// Resolve o argumento num escopo de comparação: ponto de montagem, nome de
    /// volume ("T7 Shield"), ou uma pasta qualquer — comparar duas pastas é
    /// legítimo e é o mesmo motor, só com o escopo definido por caminho.
    private static func volume(at path: String, in list: [MountedVolume]) -> MountedVolume? {
        let p = (path as NSString).expandingTildeInPath
        if let exact = list.first(where: { $0.url.path == p }) { return exact }
        if let byName = list.first(where: { $0.name == path }) { return byName }
        return Volumes.scope(forFolder: URL(fileURLWithPath: p), in: list)
    }

    private static func emitJSON(_ payload: [String: Any]) -> Int32 {
        guard let data = try? JSONSerialization.data(withJSONObject: payload,
                                                     options: [.prettyPrinted, .sortedKeys]) else {
            FileHandle.standardError.write(Data("Could not serialize output.\n".utf8))
            return 70 // EX_SOFTWARE
        }
        print(String(data: data, encoding: .utf8) ?? "{}")
        return 0
    }

    private static func printHelp() {
        print("""
        \(AppInfo.name) \(AppInfo.version) — dev disk cleaner (CLI mode)

        USAGE
          harbofly scan [--json]           list caches/artifacts with size and risk tier
          harbofly clean [--dry-run]       move all 🟢 safe items to the Trash
                        [--stale-only]     …only from projects idle for 90+ days
          harbofly dups [folders...]       find duplicate files by content (SHA-256
                        [--apply]          + byte-verify); --apply trashes non-keepers
                        [--permanent]      delete instead of Trash
                        [--json]           no folders = Downloads/Documents/Desktop/Pictures
          harbofly volumes [--json]        list mounted volumes (size, free, fs, flags)
                        [--all]            include read-only ones (mounted .dmg)
          harbofly index <path> [--json]   inventory: coverage, space, by folder/ext/size
          harbofly compare <vol> [other…]  what on <vol> already exists on another
                        [--subtrees]       volume, what repeats inside it, what is
                        [--only-unique]    only there. No other volume given = all
                        [--apply]          mounted ones. --apply removes only what
                        [--permanent]      was proven to exist elsewhere.
                        [--json]
          harbofly version                 print version

        Everything goes to the Trash (recoverable). 🟡 caution and 🔵 info tiers
        are never touched by the CLI — use the app for those. `compare` refuses
        read-only, network and Time Machine volumes, and says so when a volume
        has no Trash.
        """)
    }

    // MARK: helpers

    /// Fase do scan de duplicatas em inglês (convenção do CLI).
    private static func phaseText(_ p: DupPhase) -> String {
        switch p {
        case .listing: return "Listing files…"
        case .comparing(let n): return "Comparing ends of \(n) candidates…"
        case .hashing(let done, let total): return "Full-hashing \(done)/\(total) files…"
        case .verifying: return "Verifying byte for byte…"
        }
    }

    /// Escreve a fase no stderr. A fase de hashing sobrescreve a mesma linha
    /// com `\r` (contagem determinística), fechando com `\n` ao terminar.
    private static func dupProgress(_ p: DupPhase) {
        let err = FileHandle.standardError
        switch p {
        case .hashing(let done, let total):
            err.write(Data("\r\(phaseText(p))   ".utf8))
            if done == total { err.write(Data("\n".utf8)) }
        default:
            err.write(Data("\(phaseText(p))\n".utf8))
        }
    }

    private static func tierEmoji(_ t: Tier) -> String {
        switch t { case .safe: return "🟢"; case .caution: return "🟡"; case .info: return "🔵" }
    }
    private static func tierName(_ t: Tier) -> String {
        switch t { case .safe: return "safe"; case .caution: return "caution"; case .info: return "info" }
    }
    private static func relPath(_ url: URL) -> String {
        url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
    private static func pad(_ s: String) -> String {
        s.count >= 9 ? s : String(repeating: " ", count: 9 - s.count) + s
    }
    /// Preenche à direita (colunas de texto, ao contrário dos tamanhos).
    private static func padR(_ s: String, _ width: Int) -> String {
        s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
    }
    private static func tierName(_ t: VolumeTier) -> String {
        switch t {
        case .scannable: return "scannable"
        case .readOnly: return "readOnly"
        case .protected: return "protected"
        }
    }
}
