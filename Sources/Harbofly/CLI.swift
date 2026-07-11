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
        var eligible = targets.filter { $0.tier == .safe && !$0.isDocker }
        if staleOnly {
            eligible = eligible.filter { ($0.staleDays ?? 0) >= Prefs.staleThresholdDays }
        }
        guard !eligible.isEmpty else {
            print("Nothing to clean.")
            return 0
        }
        var freed: Int64 = 0
        for t in eligible {
            if dryRun {
                print("would trash:  \(pad(fmt(t.bytes)))  \(t.displayLabel)")
                freed += t.bytes
            } else if (try? FileManager.default.trashItem(at: t.url, resultingItemURL: nil)) != nil {
                print("trashed:  \(pad(fmt(t.bytes)))  \(t.displayLabel)")
                freed += t.bytes
            } else {
                print("FAILED:   \(t.displayLabel) — \(t.url.path)")
            }
        }
        print(dryRun ? "\nWould move \(fmt(freed)) to the Trash."
                     : "\nMoved \(fmt(freed)) to the Trash (recoverable until you empty it).")
        if targets.contains(where: { $0.isDocker }) {
            print("note: Docker space is skipped in the CLI — use the app or `docker system prune`.")
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
        let groups = scanner.findDuplicates(roots: existing) { line in
            if !json { FileHandle.standardError.write(Data("\(line)\n".utf8)) }
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
        print(permanent
              ? "Deleted \(n) file(s), freed \(fmt(freed))."
              : "Moved \(n) file(s) to the Trash, freed \(fmt(freed)) (recoverable).")
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
          harbofly version                 print version

        Everything goes to the Trash (recoverable). 🟡 caution and 🔵 info tiers
        are never touched by the CLI — use the app for those.
        """)
    }

    // MARK: helpers

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
}
