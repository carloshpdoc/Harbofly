import SwiftUI
import AppKit
import ServiceManagement
import UserNotifications
import Sparkle

// MARK: - Config

/// Nome de exibição do app. Trocar aqui reflete na UI inteira.
enum AppInfo {
    static let name = "Harbofly"
    /// id da Window scene principal (usado também pra reconhecer a NSWindow).
    static let mainWindowID = "main"
    // Lê do próprio bundle (setado pelo make-app.sh). "dev" quando roda via `swift run`.
    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev" }
    static var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0" }
}

/// Apoio (tip jar).
enum Support {
    static let pixKey = "1570c17b-7e20-4258-8ad8-f83f15250502"
    static let webURL = "https://ko-fi.com/buildcomcarlos"
}

/// Chaves de preferência (UserDefaults / @AppStorage).
enum Prefs {
    static let deletePermanently = "deletePermanently"
    static let notifyEnabled = "notifyEnabled"
    static let notifyThreshold = "notifyThreshold"
    static let defaultThreshold = 0.10
    /// Projeto sem atividade (git/mtime) há mais que isso = "parado".
    static let staleThresholdDays = 90
    // Cadência da doação: quem já apoiou nunca mais é incomodado; quem adia
    // é adiado por intervalos crescentes.
    static let hasSupported = "hasSupported"
    static let donateSnoozeUntil = "donateSnoozeUntil"
    static let donateSnoozeCount = "donateSnoozeCount"
    /// Dias de snooze por vez que o usuário clica "agora não" (crescente).
    static let snoozeDays: [Double] = [7, 30, 90, 180]
    // Analytics opt-in (ver Analytics.swift).
    static let analyticsChoiceMade = "analyticsChoiceMade"
    static let analyticsEnabled = "analyticsEnabled"
    static let firstLaunchSent = "analyticsFirstLaunchSent"
    static let firstScanSent = "analyticsFirstScanSent"
    // Idioma da UI: "system" (default) ou um código suportado — "pt", "en",
    // "es", "fr", "de", "zh" (ver Localization.swift).
    static let language = "language"
    // Total acumulado (bytes) já limpo pelo app, na vida toda.
    static let totalFreedBytes = "totalFreedBytes"
}

// MARK: - Model

enum Tier: String {
    case safe = "Seguro (regenera sozinho)"
    case caution = "Cuidado (recria, mas custa)"
    case info = "Informativo (só leitura)"

    /// Tier informativo: mostrado só pra ciência, o app nunca apaga.
    var isReadOnly: Bool { self == .info }
}

struct CleanTarget: Identifiable {
    let id = UUID()
    let url: URL
    let label: String
    let detail: String
    let tier: Tier
    var bytes: Int64
    /// Dias desde a última atividade do projeto dono (só artifacts de dev;
    /// nil quando não se aplica ou não deu pra medir).
    var staleDays: Int? = nil
    /// Projeto parado com mudanças não commitadas ou commits não pushados —
    /// trabalho esquecido sem backup no remoto (só checado quando parado).
    var unsavedWork = false
    /// Alvo do Docker: a ação é `docker system prune` (irreversível), não Lixeira.
    var isDocker = false
}

func fmt(_ bytes: Int64) -> String {
    let f = ByteCountFormatter()
    f.countStyle = .file
    return f.string(fromByteCount: bytes)
}

// MARK: - Scanner

final class DiskScanner: ObservableObject {
    @Published var targets: [CleanTarget] = []
    @Published var scanning = false
    @Published var freeBytes: Int64 = 0
    @Published var totalBytes: Int64 = 0
    @Published var lastScan: Date?
    @Published var lastFreedBytes: Int64 = 0
    @Published var lastDeletePermanent = false
    @Published var justCleaned = false

    /// Evita disparar a notificação de disco baixo repetidamente: só notifica
    /// quando o espaço livre CRUZA pra baixo do limite.
    private var wasBelowThreshold = false

    private let home = FileManager.default.homeDirectoryForCurrentUser
    private let minBytes: Int64 = 10_000_000 // ignora ruído < 10 MB

    func scan() {
        guard !scanning else { return }
        scanning = true
        let startedAt = Date()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            self.unsavedCache.removeAll()
            let (free, total) = self.diskSpace()
            var found = self.scanDevelopment() + self.scanDerivedData() + self.scanLibrary()
                + self.scanInfo() + self.scanDocker()
            found.sort { $0.bytes > $1.bytes }
            DispatchQueue.main.async {
                self.freeBytes = free
                self.totalBytes = total
                self.targets = found
                self.lastScan = Date()
                self.scanning = false
                self.checkLowSpaceNotification()
                let ms = Int(Date().timeIntervalSince(startedAt) * 1000)
                let recoverable = found.filter { !$0.tier.isReadOnly }.reduce(Int64(0)) { $0 + $1.bytes }
                Analytics.scanFinished(durationMs: ms, itemCount: found.count, recoverableBytes: recoverable)
            }
        }
    }

    /// Apaga os itens. `permanently == false` (default) move pra Lixeira
    /// (recuperável, mas o espaço só é liberado ao esvaziar a Lixeira);
    /// `true` remove de vez, liberando o espaço na hora.
    /// Itens read-only (tier informativo) são ignorados por segurança.
    func delete(_ items: [CleanTarget], permanently: Bool) {
        let deletable = items.filter { !$0.tier.isReadOnly }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var freed: Int64 = 0
            var count = 0
            // Bytes liberados por tipo genérico de cache (nunca o caminho/nome real).
            var byCategory: [String: Int64] = [:]
            for item in deletable {
                let ok: Bool
                if item.isDocker {
                    // Docker não vai pra Lixeira: sempre prune (irreversível),
                    // independente do toggle permanente/Lixeira.
                    ok = DockerEngine.prune()
                } else if permanently {
                    ok = (try? FileManager.default.removeItem(at: item.url)) != nil
                } else {
                    ok = (try? FileManager.default.trashItem(at: item.url, resultingItemURL: nil)) != nil
                }
                if ok {
                    freed += item.bytes
                    count += 1
                    let key = item.isDocker ? "docker" : item.url.lastPathComponent
                    byCategory[key, default: 0] += item.bytes
                }
            }
            let freedFinal = freed, countFinal = count, categories = byCategory
            DispatchQueue.main.async {
                let d = UserDefaults.standard
                d.set(Int(d.integer(forKey: Prefs.totalFreedBytes)) + Int(freedFinal),
                      forKey: Prefs.totalFreedBytes)
                self?.lastFreedBytes = freedFinal
                self?.lastDeletePermanent = permanently
                self?.justCleaned = true
                Analytics.deleteConfirmed(mode: permanently ? "permanent" : "trash",
                                          freedBytes: freedFinal, itemCount: countFinal, byCategory: categories)
                self?.scan()
            }
        }
    }

    // MARK: private

    private func diskSpace() -> (Int64, Int64) {
        // statfs = leitura direta do filesystem, sem o cache de resourceValues
        // (volumeAvailableCapacityForImportantUsage fica preso à instância da URL
        // e não refletia a deleção na hora).
        var st = statfs()
        if statfs(NSHomeDirectory(), &st) == 0 {
            let bsize = Int64(st.f_bsize)
            let free = Int64(st.f_bavail) * bsize
            let total = Int64(st.f_blocks) * bsize
            return (free, total)
        }
        return (0, 0)
    }

    private func size(of url: URL) -> Int64 {
        guard let en = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
            options: []
        ) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in en {
            if let v = try? f.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]) {
                total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
            }
        }
        return total
    }

    /// Descobre sozinho build artifacts sob ~/Development (sem config de path).
    private func scanDevelopment() -> [CleanTarget] {
        let dev = home.appendingPathComponent("Development")
        let names: Set<String> = ["build", ".build", "node_modules", "Pods", "DerivedData"]
        var out: [CleanTarget] = []

        func recurse(_ dir: URL, depth: Int) {
            guard depth <= 3 else { return }
            guard let items = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: []
            ) else { return }
            for item in items {
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                guard isDir else { continue }
                if names.contains(item.lastPathComponent) {
                    let b = size(of: item)
                    if b > minBytes {
                        let projectDir = item.deletingLastPathComponent()
                        var stale: Int? = nil
                        if let last = projectActivity(from: projectDir) {
                            stale = max(0, Int(Date().timeIntervalSince(last) / 86_400))
                        }
                        let isStale = (stale ?? 0) >= Prefs.staleThresholdDays
                        out.append(CleanTarget(
                            url: item,
                            label: "\(projectDir.lastPathComponent)/\(item.lastPathComponent)",
                            detail: L10n.devArtifact,
                            tier: .safe,
                            bytes: b,
                            staleDays: stale,
                            unsavedWork: isStale && hasUnsavedWork(projectDir)
                        ))
                    }
                    // não desce dentro do artifact
                } else {
                    recurse(item, depth: depth + 1)
                }
            }
        }

        recurse(dev, depth: 0)
        return out
    }

    /// DerivedData quebrado por projeto (em vez de um blob único): cada
    /// subpasta vira uma linha. O projeto dono vem do info.plist
    /// (WorkspacePath) — quando existe, a linha ganha o nome da pasta do
    /// projeto e herda a detecção de staleness. Pastas de sistema
    /// (ModuleCache.noindex…) aparecem com o nome cru, sem staleness.
    private func scanDerivedData() -> [CleanTarget] {
        let dd = home.appendingPathComponent("Library/Developer/Xcode/DerivedData")
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dd, includingPropertiesForKeys: [.isDirectoryKey], options: []
        ) else { return [] }
        var out: [CleanTarget] = []
        for item in items {
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir else { continue }
            let b = size(of: item)
            guard b > minBytes else { continue }

            let raw = item.lastPathComponent
            // "Projeto-hash" -> "Projeto"; nomes sem hash (ModuleCache.noindex) ficam como estão.
            var project = raw.contains("-")
                ? raw.components(separatedBy: "-").dropLast().joined(separator: "-")
                : raw
            var stale: Int? = nil
            var unsaved = false
            if let ws = workspacePath(of: item) {
                let projDir = ws.deletingLastPathComponent()
                project = projDir.lastPathComponent // desambigua clones/worktrees do mesmo app
                if let last = projectActivity(from: projDir) {
                    stale = max(0, Int(Date().timeIntervalSince(last) / 86_400))
                }
                if (stale ?? 0) >= Prefs.staleThresholdDays {
                    unsaved = hasUnsavedWork(projDir)
                }
            }
            out.append(CleanTarget(url: item, label: "DerivedData/\(project)",
                                   detail: L10n.xcodeDerived, tier: .safe, bytes: b,
                                   staleDays: stale, unsavedWork: unsaved))
        }
        return out
    }

    /// Workspace/projeto que gerou a pasta de DerivedData (info.plist do Xcode).
    private func workspacePath(of derived: URL) -> URL? {
        let plist = derived.appendingPathComponent("info.plist")
        guard let data = try? Data(contentsOf: plist),
              let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                  as? [String: Any],
              let path = dict["WorkspacePath"] as? String else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Cache por scan: projeto -> tem trabalho não salvo (evita repetir o
    /// `git status` quando vários artifacts pertencem ao mesmo projeto).
    private var unsavedCache: [String: Bool] = [:]

    /// true se o repo tem mudanças não commitadas ou commits não pushados.
    /// Só é chamado pra projetos PARADOS (é onde o aviso importa: trabalho
    /// esquecido sem backup no remoto). Local, via /usr/bin/git — sem rede.
    private func hasUnsavedWork(_ dir: URL) -> Bool {
        if let cached = unsavedCache[dir.path] { return cached }
        let result = checkUnsavedWork(dir)
        unsavedCache[dir.path] = result
        return result
    }

    private func checkUnsavedWork(_ dir: URL) -> Bool {
        let gitPath = "/usr/bin/git"
        guard FileManager.default.isExecutableFile(atPath: gitPath) else { return false }
        func git(_ args: [String]) -> String? {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: gitPath)
            p.arguments = ["-C", dir.path] + args
            let out = Pipe()
            p.standardOutput = out
            p.standardError = Pipe()
            do { try p.run() } catch { return nil }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // mudanças não commitadas (ignora untracked: menos ruído, mais rápido)
        if let status = git(["status", "--porcelain", "--untracked-files=no"]), !status.isEmpty {
            return true
        }
        // commits locais que não existem em nenhum remote
        if let ahead = git(["log", "--branches", "--not", "--remotes", "--oneline", "-1"]), !ahead.isEmpty {
            return true
        }
        return false
    }

    /// Última atividade do projeto, 100% local: mtime do .git/index ou
    /// .git/HEAD (commit/checkout/uso do git). Sobe até 3 níveis pra achar o
    /// .git de monorepos. Sem git, cai pro mtime da pasta do projeto.
    private func projectActivity(from dir: URL) -> Date? {
        let fm = FileManager.default
        func mtime(_ url: URL) -> Date? {
            (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        }
        var probe = dir
        for _ in 0..<4 {
            let git = probe.appendingPathComponent(".git")
            if fm.fileExists(atPath: git.path) {
                let dates = [git.appendingPathComponent("index"),
                             git.appendingPathComponent("HEAD")].compactMap(mtime)
                if let latest = dates.max() { return latest }
            }
            let parent = probe.deletingLastPathComponent()
            guard parent.path != probe.path, probe.path != home.path else { break }
            probe = parent
        }
        return mtime(dir)
    }

    /// Alvos conhecidos de caches dev na home (~/Library e dotfiles).
    /// Cobre toolchains (Xcode, Gradle, npm…), editores e ferramentas de IA
    /// (pesos de modelo do Ollama/LM Studio/HuggingFace, que passam de
    /// dezenas de GB fácil).
    private func scanLibrary() -> [CleanTarget] {
        let specs: [(String, String, Tier, String)] = [
            // Xcode & Apple (DerivedData tem scanner próprio, por projeto)
            ("Library/Developer/Xcode/iOS DeviceSupport", "iOS DeviceSupport", .caution, L10n.iosDeviceSupport),
            ("Library/Developer/Xcode/Archives", "Xcode Archives", .caution, L10n.xcodeArchives),
            ("Library/Developer/XcodeBuildMCP/workspaces", "workspaces", .safe, L10n.xcodeBuildMCP),
            ("Library/Caches/org.swift.swiftpm", "org.swift.swiftpm", .safe, L10n.swiftpmCache),
            ("Library/Caches/CocoaPods", "CocoaPods", .safe, L10n.pkgCache),
            // Package managers / linguagens
            ("Library/Caches/Homebrew", "Homebrew", .safe, L10n.homebrewCache),
            ("Library/Caches/Yarn", "Yarn", .safe, L10n.yarnCache),
            ("Library/Caches/pnpm", "pnpm", .safe, L10n.pkgCache),
            (".npm", "npm", .safe, L10n.pkgCache),
            (".bun/install/cache", "Bun", .safe, L10n.pkgCache),
            ("Library/Caches/pip", "pip", .safe, L10n.pipCache),
            ("Library/Caches/uv", "uv", .safe, L10n.pkgCache),
            ("Library/Caches/go-build", "Go build", .safe, L10n.devArtifact),
            ("go/pkg/mod", "Go modules", .caution, L10n.depsCache),
            (".gradle/caches", "Gradle", .caution, L10n.depsCache),
            (".m2/repository", "Maven", .caution, L10n.depsCache),
            (".cargo/registry", "Cargo", .caution, L10n.depsCache),
            (".pub-cache", "Flutter pub", .caution, L10n.depsCache),
            // Editores / IDEs
            ("Library/Application Support/Code/CachedData", "VS Code (CachedData)", .safe, L10n.editorCache),
            ("Library/Application Support/Code/Cache", "VS Code (Cache)", .safe, L10n.editorCache),
            ("Library/Application Support/Cursor/CachedData", "Cursor (CachedData)", .safe, L10n.editorCache),
            ("Library/Application Support/Cursor/Cache", "Cursor (Cache)", .safe, L10n.editorCache),
            ("Library/Caches/JetBrains", "JetBrains", .caution, L10n.jetbrainsCache),
            // Ferramentas de IA (pesos de modelo)
            (".ollama/models", "Ollama", .caution, L10n.aiModels),
            (".cache/huggingface", "Hugging Face", .caution, L10n.aiModels),
            (".lmstudio/models", "LM Studio", .caution, L10n.aiModels),
            (".cache/lm-studio", "LM Studio (legado)", .caution, L10n.aiModels),
            // Outros
            ("Library/Caches/ms-playwright", "ms-playwright", .caution, L10n.playwrightCache),
            ("Library/Caches/Google", "Google", .caution, L10n.googleCache),
        ]
        var out: [CleanTarget] = []
        for (rel, label, tier, detail) in specs {
            let url = home.appendingPathComponent(rel)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let b = size(of: url)
            if b > minBytes {
                out.append(CleanTarget(url: url, label: label, detail: detail, tier: tier, bytes: b))
            }
        }
        return out
    }

    /// Tier informativo (só leitura): pastas grandes que o app NÃO apaga, mas
    /// mostra pra você saber onde o espaço está e agir manualmente.
    private func scanInfo() -> [CleanTarget] {
        let specs: [(String, String, String)] = [
            ("Library/Developer/CoreSimulator", "CoreSimulator", L10n.coreSimulatorDetail),
            ("Library/Application Support", "Application Support", L10n.appSupportDetail),
            ("Downloads", "Downloads", L10n.downloadsDetail),
            ("Documents", "Documents", L10n.documentsDetail),
            ("Desktop", "Desktop", L10n.desktopDetail),
        ]
        var out: [CleanTarget] = []
        for (rel, label, detail) in specs {
            let url = home.appendingPathComponent(rel)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let b = size(of: url)
            if b > minBytes {
                out.append(CleanTarget(url: url, label: label, detail: detail, tier: .info, bytes: b))
            }
        }
        return out
    }

    /// Docker/OrbStack: mede o recuperável real via engine (não o disk image).
    /// Tier caution porque prune é irreversível e não passa pela Lixeira.
    private func scanDocker() -> [CleanTarget] {
        switch DockerEngine.probe() {
        case .absent:
            return []
        case .running(let reclaimable, let image):
            guard reclaimable > minBytes else { return [] }
            let url = image ?? DockerEngine.binary() ?? home
            return [CleanTarget(url: url, label: L10n.dockerLabel, detail: L10n.dockerDetail,
                                tier: .caution, bytes: reclaimable, isDocker: true)]
        case .stopped(let bytes, let image):
            guard bytes > minBytes, let image = image else { return [] }
            return [CleanTarget(url: image, label: L10n.dockerStoppedLabel,
                                detail: L10n.dockerStoppedDetail, tier: .info, bytes: bytes)]
        }
    }

    // MARK: notificação de disco baixo

    private var notifyEnabled: Bool {
        (UserDefaults.standard.object(forKey: Prefs.notifyEnabled) as? Bool) ?? true
    }
    private var notifyThreshold: Double {
        (UserDefaults.standard.object(forKey: Prefs.notifyThreshold) as? Double) ?? Prefs.defaultThreshold
    }

    private func checkLowSpaceNotification() {
        guard totalBytes > 0 else { return }
        let ratio = Double(freeBytes) / Double(totalBytes)
        let below = ratio < notifyThreshold
        defer { wasBelowThreshold = below }
        guard notifyEnabled, below, !wasBelowThreshold else { return }

        let content = UNMutableNotificationContent()
        content.title = L10n.lowSpaceTitle
        content.body = L10n.lowSpaceBody(pct: Int(ratio * 100), free: fmt(freeBytes))
        content.sound = .default
        let req = UNNotificationRequest(identifier: "harbofly.lowspace", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}

// MARK: - UI

struct ContentView: View {
    @ObservedObject var scanner: DiskScanner
    @ObservedObject var updater: Updater
    @Environment(\.openWindow) private var openWindow
    @State private var selection = Set<UUID>()
    @State private var confirming = false
    @State private var launchAtLogin = false
    @State private var showSupport = false
    @State private var pixCopied = false
    @State private var showFeedback = false
    @State private var feedbackText = ""
    @State private var feedbackContact = ""
    @State private var feedbackSending = false
    @State private var feedbackSent = false
    @State private var feedbackFailed = false
    /// Força a seção de doação mesmo pra quem já apoiou (quando o próprio usuário
    /// clica em "Apoiar" no rodapé).
    @State private var manualSupport = false

    @AppStorage(Prefs.deletePermanently) private var deletePermanently = false
    @AppStorage(Prefs.notifyEnabled) private var notifyEnabled = true
    @AppStorage(Prefs.notifyThreshold) private var notifyThreshold = Prefs.defaultThreshold
    @AppStorage(Prefs.hasSupported) private var hasSupported = false
    @AppStorage(Prefs.donateSnoozeUntil) private var donateSnoozeUntil = 0.0
    @AppStorage(Prefs.donateSnoozeCount) private var donateSnoozeCount = 0
    @AppStorage(Prefs.totalFreedBytes) private var totalFreedBytes = 0
    @AppStorage(Prefs.analyticsChoiceMade) private var analyticsChoiceMade = false
    @AppStorage(Prefs.analyticsEnabled) private var analyticsEnabled = false
    // Observa a troca manual de idioma: ao mudar, a View re-renderiza e o L10n
    // (computado) já devolve as strings no idioma novo.
    @AppStorage(Prefs.language) private var language = "system"

    /// Só pede doação se a pessoa nunca apoiou e o snooze já venceu.
    private var shouldAskDonate: Bool {
        !hasSupported && Date().timeIntervalSince1970 > donateSnoozeUntil
    }

    private let timer = Timer.publish(every: 1800, on: .main, in: .common).autoconnect()

    // Recuperável = só o que o app realmente apaga (exclui o tier informativo).
    private var reclaimable: Int64 { scanner.targets.filter { !$0.tier.isReadOnly }.reduce(0) { $0 + $1.bytes } }
    private var selectedTargets: [CleanTarget] { scanner.targets.filter { selection.contains($0.id) } }
    private var selectedBytes: Int64 { selectedTargets.reduce(0) { $0 + $1.bytes } }
    private var safeTargets: [CleanTarget] { scanner.targets.filter { $0.tier == .safe } }
    private var staleTargets: [CleanTarget] {
        scanner.targets.filter { !$0.tier.isReadOnly && ($0.staleDays ?? 0) >= Prefs.staleThresholdDays }
    }
    private var cautionTargets: [CleanTarget] { scanner.targets.filter { $0.tier == .caution } }
    private var infoTargets: [CleanTarget] { scanner.targets.filter { $0.tier == .info } }
    private var freeRatio: Double {
        scanner.totalBytes > 0 ? Double(scanner.freeBytes) / Double(scanner.totalBytes) : 1
    }

    private func relPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.replacingOccurrences(of: home, with: "~")
    }

    // Guard de segurança: limpar caches do Xcode com ele aberto pode
    // atrapalhar um build em andamento — avisa antes de confirmar.
    private var xcodeIsRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.apple.dt.Xcode" }
    }
    private var selectionTouchesXcode: Bool {
        selectedTargets.contains { $0.url.path.contains("/Library/Developer/Xcode/") }
    }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 10) {
                header
                Divider()
                listSection
                Divider()
                footer
            }
            .padding(12)
            .disabled(confirming || showSupport || showFeedback || !analyticsChoiceMade)

            if !analyticsChoiceMade { analyticsOptInOverlay }
            else if confirming { confirmOverlay }
            if showSupport { supportOverlay }
            if showFeedback { feedbackOverlay }
        }
        .frame(width: 470)
        .onAppear {
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
            if scanner.targets.isEmpty { scanner.scan() }
        }
        .onReceive(timer) { _ in scanner.scan() }
        .onChange(of: scanner.justCleaned) { _, cleaned in
            if cleaned {
                scanner.justCleaned = false
                if scanner.lastFreedBytes > 0 { pixCopied = false; showSupport = true }
            }
        }
    }

    // Abre a janela de app (dock + foco), fora da barra de menu.
    func openMainWindow() {
        presentMainWindow(using: openWindow)
    }

    private func setLoginItem(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            // reverte o toggle pro estado real se falhar
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
        }
    }

    private func copyPix() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(Support.pixKey, forType: .string)
        pixCopied = true
        hasSupported = true // quem copiou o PIX não é mais incomodado
    }

    /// "Agora não": adia a próxima pergunta por um intervalo crescente.
    private func snoozeDonate() {
        let days = Prefs.snoozeDays[min(donateSnoozeCount, Prefs.snoozeDays.count - 1)]
        donateSnoozeUntil = Date().timeIntervalSince1970 + days * 86_400
        donateSnoozeCount += 1
        showSupport = false
        manualSupport = false
    }

    // MARK: Compartilhar conquista

    /// Card 1200x675 (proporção OG/Twitter) com o quanto foi recuperado.
    private func makeShareImage(freed: Int64) -> NSImage {
        let size = NSSize(width: 1200, height: 675)
        let img = NSImage(size: size)
        img.lockFocus()

        let rect = NSRect(origin: .zero, size: size)
        NSGradient(colors: [
            NSColor(srgbRed: 0.031, green: 0.063, blue: 0.110, alpha: 1),
            NSColor(srgbRed: 0.051, green: 0.106, blue: 0.165, alpha: 1),
        ])?.draw(in: rect, angle: 120)

        let teal = NSColor(srgbRed: 0.31, green: 0.82, blue: 0.77, alpha: 1)
        let ink = NSColor(srgbRed: 0.918, green: 0.949, blue: 1.0, alpha: 1)
        let muted = NSColor(srgbRed: 0.56, green: 0.63, blue: 0.71, alpha: 1)

        func draw(_ s: String, font: NSFont, color: NSColor, y: CGFloat) {
            let p = NSMutableParagraphStyle(); p.alignment = .center
            let attr: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: p]
            let str = s as NSString
            let h = str.size(withAttributes: attr).height
            str.draw(in: NSRect(x: 0, y: y - h / 2, width: size.width, height: h), withAttributes: attr)
        }

        draw(L10n.shareCardVerb, font: .systemFont(ofSize: 60, weight: .semibold), color: muted, y: 470)
        draw(fmt(freed), font: .systemFont(ofSize: 150, weight: .heavy), color: teal, y: 350)
        draw(L10n.shareCardTail, font: .systemFont(ofSize: 44, weight: .medium), color: ink, y: 190)
        draw("harbofly.app", font: .monospacedSystemFont(ofSize: 34, weight: .regular), color: muted, y: 95)

        img.unlockFocus()
        return img
    }

    private func shareAchievement() {
        let image = makeShareImage(freed: scanner.lastFreedBytes)
        let text = L10n.shareText(fmt(scanner.lastFreedBytes))
        let picker = NSSharingServicePicker(items: [image, text])
        if let view = NSApp.keyWindow?.contentView {
            picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
        }
    }

    // MARK: Overlays (inline — não fecham o popover da barra de menu)

    private func overlayCard<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            content()
                .padding(22)
                .frame(width: 320)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .shadow(radius: 24)
        }
    }

    /// First launch: pergunta de consentimento no estilo Apple.
    private var analyticsOptInOverlay: some View {
        overlayCard {
            VStack(spacing: 14) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 40)).foregroundStyle(.tint)
                Text(L10n.analyticsTitle)
                    .font(.headline).multilineTextAlignment(.center)
                Text(L10n.analyticsSubtitle)
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text(L10n.analyticsDetail)
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    Analytics.optIn()
                    analyticsEnabled = true
                    analyticsChoiceMade = true
                } label: {
                    Text(L10n.yes).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    Analytics.optOut()
                    analyticsEnabled = false
                    analyticsChoiceMade = true
                } label: {
                    Text(L10n.no).frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var confirmOverlay: some View {
        overlayCard {
            VStack(spacing: 14) {
                Text(L10n.confirmTitle(count: selectedTargets.count, size: fmt(selectedBytes)))
                    .font(.headline).multilineTextAlignment(.center)

                Picker("", selection: $deletePermanently) {
                    Text(L10n.moveToTrash).tag(false)
                    Text(L10n.deleteForever).tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(deletePermanently ? L10n.permanentExplainer : L10n.trashExplainer)
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if selectedTargets.contains(where: { $0.isDocker }) {
                    Text(L10n.dockerPruneNote)
                        .font(.callout).foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if selectionTouchesXcode && xcodeIsRunning {
                    Text(L10n.xcodeRunningNote)
                        .font(.callout).foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(role: .destructive) {
                    let items = selectedTargets
                    let perm = deletePermanently
                    selection.removeAll()
                    confirming = false
                    scanner.delete(items, permanently: perm)
                } label: {
                    Text(deletePermanently ? L10n.deletePermanentlyBtn : L10n.moveToTrash)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(deletePermanently ? .red : .accentColor)
                Button(L10n.cancel) { confirming = false }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var supportOverlay: some View {
        let freed = scanner.lastFreedBytes
        let askDonate = manualSupport || shouldAskDonate
        return overlayCard {
            VStack(spacing: 14) {
                Text(freed > 0 ? "🎉" : "☕").font(.system(size: 44))
                Text(freed > 0
                     ? (scanner.lastDeletePermanent
                        ? L10n.recovered(fmt(freed))
                        : L10n.trashed(fmt(freed)))
                     : L10n.thanks)
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)

                // Histórico: quanto o app já liberou na vida toda.
                if totalFreedBytes > 0 && Int64(totalFreedBytes) != freed {
                    Text(L10n.totalFreed(fmt(Int64(totalFreedBytes))))
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                // Momento de valor: compartilhar a conquista (só após uma limpeza real).
                if freed > 0 {
                    Button {
                        shareAchievement()
                    } label: {
                        Label(L10n.share, systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                if askDonate {
                    Text(L10n.donateAsk)
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        copyPix()
                    } label: {
                        Label(pixCopied ? L10n.pixCopied : L10n.copyPix,
                              systemImage: pixCopied ? "checkmark.circle.fill" : "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    if let url = URL(string: Support.webURL) {
                        Button {
                            NSWorkspace.shared.open(url)
                            hasSupported = true
                        } label: {
                            Label("Buy Me a Coffee", systemImage: "safari").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    HStack {
                        Button(L10n.alreadySupported) { hasSupported = true; showSupport = false; manualSupport = false }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                        Spacer()
                        Button(L10n.notNow) { snoozeDonate() }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                } else {
                    Button(L10n.close) { showSupport = false }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var feedbackOverlay: some View {
        overlayCard {
            VStack(spacing: 14) {
                if feedbackSent {
                    Text("💙").font(.system(size: 44))
                    Text(L10n.feedbackThanks)
                        .font(.title3.bold()).multilineTextAlignment(.center)
                    Button {
                        closeFeedback()
                    } label: {
                        Text(L10n.close).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .font(.system(size: 40)).foregroundStyle(.tint)
                    Text(L10n.feedbackTitle).font(.headline)
                    Text(L10n.feedbackSubtitle)
                        .font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    TextEditor(text: $feedbackText)
                        .font(.body)
                        .frame(height: 90)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

                    TextField(L10n.feedbackContactPlaceholder, text: $feedbackContact)
                        .textFieldStyle(.roundedBorder)

                    Text(L10n.feedbackPrivacyNote)
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    if feedbackFailed {
                        Text(L10n.feedbackError)
                            .font(.caption).foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        sendFeedback()
                    } label: {
                        Text(feedbackSending ? L10n.feedbackSending : L10n.feedbackSend)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(feedbackSending
                              || feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button(L10n.cancel) { closeFeedback() }
                        .buttonStyle(.bordered)
                        .disabled(feedbackSending)
                }
            }
        }
    }

    private func sendFeedback() {
        feedbackFailed = false
        feedbackSending = true
        let message = feedbackText, contact = feedbackContact
        Task { @MainActor in
            let ok = await Feedback.send(message: message, contact: contact)
            feedbackSending = false
            if ok {
                feedbackSent = true
                feedbackText = ""
                feedbackContact = ""
            } else {
                feedbackFailed = true
            }
        }
    }

    private func closeFeedback() {
        showFeedback = false
        feedbackSent = false
        feedbackFailed = false
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "internaldrive")
                Text(AppInfo.name).font(.headline)
                Spacer()
                if scanner.scanning { ProgressView().controlSize(.small) }
                Button { openMainWindow() } label: {
                    Image(systemName: "macwindow")
                }
                .buttonStyle(.plain)
                .help(L10n.openInWindow)
            }
            ProgressView(value: 1 - freeRatio)
                .tint(freeRatio < 0.1 ? .red : (freeRatio < 0.2 ? .orange : .accentColor))
            HStack {
                Text(L10n.freeOfTotal(free: fmt(scanner.freeBytes), total: fmt(scanner.totalBytes)))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(L10n.reclaimable(fmt(reclaimable)))
                    .font(.caption).bold()
                    .foregroundStyle(reclaimable > 0 ? .green : .secondary)
            }
        }
    }

    private var listSection: some View {
        Group {
            if scanner.targets.isEmpty {
                Text(scanner.scanning ? L10n.scanning : L10n.nothingFound)
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        if !safeTargets.isEmpty {
                            tierHeader(L10n.tierSafe, safeTargets)
                            ForEach(safeTargets) { row($0) }
                        }
                        if !cautionTargets.isEmpty {
                            tierHeader(L10n.tierCaution, cautionTargets)
                            ForEach(cautionTargets) { row($0) }
                        }
                        if !infoTargets.isEmpty {
                            tierHeader(L10n.tierInfo, infoTargets)
                            ForEach(infoTargets) { infoRow($0) }
                        }
                    }
                    .padding(.trailing, 4)
                }
                .frame(height: 440)
            }
        }
    }

    private func tierHeader(_ title: String, _ items: [CleanTarget]) -> some View {
        let total = items.reduce(Int64(0)) { $0 + $1.bytes }
        return HStack {
            Text(title).font(.subheadline.bold()).foregroundStyle(.secondary)
            Spacer()
            Text(fmt(total)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.top, 6)
    }

    private func row(_ t: CleanTarget) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: selection.contains(t.id) ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(selection.contains(t.id) ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(t.label).font(.headline).lineLimit(1)
                    if t.tier == .caution {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    Spacer()
                    Text(fmt(t.bytes)).font(.headline.monospacedDigit())
                }
                Text(relPath(t.url))
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Text(t.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                if let days = t.staleDays, days >= Prefs.staleThresholdDays {
                    Label(L10n.staleProject(days: days), systemImage: "moon.zzz.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
                if t.unsavedWork {
                    Label(L10n.unsavedWorkNote, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.red)
                }
            }
        }
        .padding(10)
        .background(selection.contains(t.id) ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture {
            if selection.contains(t.id) { selection.remove(t.id) } else { selection.insert(t.id) }
        }
    }

    // Linha read-only do tier informativo: sem seleção/exclusão, só revela no Finder.
    private func infoRow(_ t: CleanTarget) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .font(.title3).foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(t.label).font(.headline).lineLimit(1)
                    Spacer()
                    Text(fmt(t.bytes)).font(.headline.monospacedDigit())
                }
                Text(relPath(t.url))
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Text(t.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([t.url])
                } label: {
                    Label(L10n.revealInFinder, systemImage: "magnifyingglass").font(.caption)
                }
                .buttonStyle(.plain).foregroundStyle(.blue).padding(.top, 2)
            }
        }
        .padding(10)
        .background(Color.blue.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var footer: some View {
        VStack(spacing: 8) {
            HStack {
                Button(L10n.selectSafe) {
                    selection = Set(scanner.targets.filter { $0.tier == .safe }.map { $0.id })
                }
                if !staleTargets.isEmpty {
                    Button(L10n.selectStale) {
                        selection = Set(staleTargets.map { $0.id })
                    }
                    .help(L10n.selectStaleHelp)
                }
                Button(L10n.clearSelection) { selection.removeAll() }
                    .disabled(selection.isEmpty)
                Spacer()
                Button {
                    Analytics.deleteClicked(mode: deletePermanently ? "permanent" : "trash",
                                            itemCount: selection.count)
                    confirming = true
                } label: {
                    Text(selection.isEmpty ? L10n.delete : L10n.deleteWithSize(fmt(selectedBytes)))
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(selection.isEmpty)
            }
            HStack {
                Button(L10n.rescan) { scanner.scan() }.disabled(scanner.scanning)
                if let d = scanner.lastScan {
                    Text(L10n.updatedAt(d.formatted(date: .omitted, time: .shortened)))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Text("v\(AppInfo.version) (\(AppInfo.build))")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .help("Build \(AppInfo.build)")
                Button(L10n.quit) { NSApp.terminate(nil) }
            }
            Divider()
            HStack(spacing: 6) {
                Toggle(L10n.notifyBelow, isOn: $notifyEnabled)
                    .toggleStyle(.checkbox)
                Picker("", selection: $notifyThreshold) {
                    Text("5%").tag(0.05)
                    Text("10%").tag(0.10)
                    Text("15%").tag(0.15)
                    Text("20%").tag(0.20)
                }
                .labelsHidden()
                .frame(width: 66)
                .disabled(!notifyEnabled)
                Spacer()
            }
            HStack {
                Toggle(L10n.shareAnonToggle, isOn: Binding(
                    get: { analyticsEnabled },
                    set: { on in
                        if on { Analytics.optIn() } else { Analytics.optOut() }
                        analyticsEnabled = on
                    }
                ))
                .toggleStyle(.checkbox)
                Spacer()
            }
            HStack {
                Text(L10n.languageLabel)
                Picker("", selection: $language) {
                    Text(L10n.langSystem).tag("system")
                    Text("Português").tag("pt")
                    Text("English").tag("en")
                    Text("Español").tag("es")
                    Text("Français").tag("fr")
                    Text("Deutsch").tag("de")
                    Text("简体中文").tag("zh")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                Spacer()
            }
            if updater.isAvailable {
                HStack {
                    Toggle(L10n.autoUpdateToggle,
                           isOn: Binding(get: { updater.autoCheck }, set: { updater.setAuto($0) }))
                        .toggleStyle(.checkbox)
                    Spacer()
                    Button(L10n.checkNow) { updater.check() }
                        .buttonStyle(.plain).foregroundStyle(.blue)
                }
            }
            HStack {
                Toggle(L10n.openAtLogin, isOn: $launchAtLogin)
                    .toggleStyle(.checkbox)
                    .onChange(of: launchAtLogin) { _, on in setLoginItem(on) }
                Spacer()
                Button {
                    showFeedback = true
                } label: {
                    Label(L10n.feedbackCta, systemImage: "bubble.left").font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
                Button {
                    scanner.lastFreedBytes = 0
                    pixCopied = false
                    manualSupport = true
                    showSupport = true
                } label: {
                    Label(L10n.supportCta, systemImage: "heart").font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.pink)
            }
        }
    }
}

// MARK: - Updater (Sparkle)

/// Wrapper do Sparkle. Só ativa quando rodando como app empacotado — o make-app.sh
/// injeta `SUFeedURL`/`SUPublicEDKey` no Info.plist. Em `swift run` (dev) fica inerte,
/// então o fluxo de desenvolvimento não depende de chave nenhuma.
final class Updater: ObservableObject {
    @Published private(set) var isAvailable = false
    @Published var autoCheck = false
    private let controller: SPUStandardUpdaterController?

    init() {
        if Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil {
            let c = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            controller = c
            isAvailable = true
            autoCheck = c.updater.automaticallyChecksForUpdates
        } else {
            controller = nil
        }
    }

    func check() { controller?.checkForUpdates(nil) }

    func setAuto(_ on: Bool) {
        controller?.updater.automaticallyChecksForUpdates = on
        autoCheck = on
    }
}

// MARK: - App

/// Ponte AppDelegate → SwiftUI: o delegate não tem acesso ao `openWindow` do
/// environment, então ele marca o pedido aqui e a `MenuBarLabel` (view
/// sempre-viva do status item) abre a janela.
final class MainWindowRequester: ObservableObject {
    static let shared = MainWindowRequester()
    @Published var pending = false
}

/// Mostra a janela principal no desktop (com ícone no Dock e foco).
@MainActor
func presentMainWindow(using openWindow: OpenWindowAction) {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    openWindow(id: AppInfo.mainWindowID)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // menu bar only, sem dock
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        Analytics.bootstrapIfConsented()

        // Launch manual (Finder/Launchpad/Spotlight): abre a janela no desktop,
        // porque o ícone na barra de menu pode estar escondido/lotado.
        // Login automático continua discreto (só barra de menu).
        if !launchedAsLoginItem {
            MainWindowRequester.shared.pending = true
        }

        // Quando a janela principal fecha, volta a ser só menu bar (sem Dock).
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification, object: nil)
    }

    /// Usuário "abriu" o app de novo com ele já rodando: mostra a janela.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        MainWindowRequester.shared.pending = true
        return false
    }

    @objc private func windowWillClose(_ note: Notification) {
        guard let w = note.object as? NSWindow,
              w.identifier?.rawValue.hasPrefix(AppInfo.mainWindowID) == true else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    /// true quando o launch veio do login item (SMAppService), não do usuário.
    private var launchedAsLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == AEEventID(kAEOpenApplication)
            && event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
                == OSType(keyAELaunchedAsLogInItem)
    }
}

/// Ícone da barra de menu. Por ser a única view viva desde o launch, também é
/// quem executa os pedidos de abrir a janela principal (ver MainWindowRequester).
struct MenuBarLabel: View {
    @ObservedObject var scanner: DiskScanner
    @ObservedObject private var requester = MainWindowRequester.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: lowSpace ? "internaldrive.fill" : "internaldrive")
            .onAppear { openIfPending() }
            .onChange(of: requester.pending) { _, _ in openIfPending() }
    }

    private var lowSpace: Bool {
        scanner.totalBytes > 0 && Double(scanner.freeBytes) / Double(scanner.totalBytes) < 0.1
    }

    private func openIfPending() {
        guard requester.pending else { return }
        requester.pending = false
        presentMainWindow(using: openWindow)
    }
}

@main
struct HarboflyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var scanner = DiskScanner()
    @StateObject private var updater = Updater()

    var body: some Scene {
        MenuBarExtra {
            ContentView(scanner: scanner, updater: updater)
        } label: {
            MenuBarLabel(scanner: scanner)
        }
        .menuBarExtraStyle(.window)

        Window(AppInfo.name, id: AppInfo.mainWindowID) {
            ContentView(scanner: scanner, updater: updater)
                .fixedSize()
        }
        .windowResizability(.contentSize)
    }
}
