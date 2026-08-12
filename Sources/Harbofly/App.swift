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
    // Via symlink (ex.: /opt/homebrew/bin/harbofly, criado pelo cask), o Bundle.main
    // aponta pro diretório do symlink e não acha o Info.plist — resolvemos o
    // executável real e derivamos o .app a partir dele.
    private static let bundle: Bundle = {
        if Bundle.main.infoDictionary?["CFBundleShortVersionString"] != nil { return Bundle.main }
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let appURL = exe.deletingLastPathComponent()   // MacOS
            .deletingLastPathComponent()               // Contents
            .deletingLastPathComponent()               // Harbofly.app
        return Bundle(url: appURL) ?? Bundle.main
    }()
    static var version: String { bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev" }
    static var build: String { bundle.infoDictionary?["CFBundleVersion"] as? String ?? "0" }
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
    // Auto-clean (opt-in): limpa 🟢 seguros sozinho, sempre pra Lixeira.
    static let autoCleanEnabled = "autoCleanEnabled"
    // "daily" (= fim do dia, default) | "startofday" | "xcode" | "weekly" | "lowdisk"
    static let autoCleanTrigger = "autoCleanTrigger"
    // Escopo do auto-clean, em escada de custo de rebuild:
    // "caches" = só caches de ferramentas (re-baixam sob demanda);
    // "all"    = + artifacts/DerivedData de projetos PARADOS (default);
    // "max"    = + DerivedData de projetos ativos (rebuild na próxima build).
    static let autoCleanScope = "autoCleanScope"
    static let autoCleanLastRun = "autoCleanLastRun"
    /// Piso: só auto-limpa quando houver pelo menos isso a recuperar.
    static let autoCleanMinBytes = "autoCleanMinBytes"
    static let autoCleanMinBytesDefault = 1_000_000_000
    /// Histórico (últimas 10) e resumo da última limpeza automática.
    static let autoCleanHistory = "autoCleanHistory"
    static let autoCleanLastCleanTs = "autoCleanLastCleanTs"
    static let autoCleanLastBytes = "autoCleanLastBytes"
    static let autoCleanLastCount = "autoCleanLastCount"
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
    /// Histórico detalhado de limpezas (ver CleanLog em Stats.swift).
    static let cleanHistory = "cleanHistory"
    /// Snapshots do tamanho da paisagem por categoria (ver SizeLog): base pra
    /// detecção de crescimento ("X apareceu / cresceu +Y desde…").
    static let sizeHistory = "sizeHistory"
    // Oferta proativa de auto-clean: depois de N limpezas manuais, convida a
    // automatizar (mesma cadência de snooze crescente da doação).
    static let manualCleanCount = "manualCleanCount"
    static let autoOfferSnoozeUntil = "autoOfferSnoozeUntil"
    static let autoOfferSnoozeCount = "autoOfferSnoozeCount"
    /// Limpezas manuais antes de oferecer a automação.
    static let autoOfferThreshold = 3
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
    /// Rótulo fixo (nomes de projeto/pasta). Rows 100% localizadas (Docker)
    /// usam labelKey no lugar.
    var label = ""
    /// Rótulo localizado, resolvido na render — troca junto com o idioma.
    var labelKey: KeyPath<L, String>? = nil
    /// Descrição como referência (não String): resolvida na render pra
    /// acompanhar a troca de idioma sem precisar de re-scan.
    let detailKey: KeyPath<L, String>
    let tier: Tier
    var bytes: Int64

    var displayLabel: String { labelKey.map { L10n[keyPath: $0] } ?? label }
    var detail: String { L10n[keyPath: detailKey] }
    /// Categoria genérica pra histórico e telemetria — NUNCA nome de projeto.
    /// DerivedData do Xcode é por-projeto (pasta "Projeto-hash"), então força
    /// "DerivedData"; o resto usa o nome (genérico) da pasta de cache.
    var category: String {
        if isDocker { return "Docker" }
        if url.path.contains("/Xcode/DerivedData/") { return "DerivedData" }
        return url.lastPathComponent
    }
    /// Dias desde a última atividade do projeto dono (só artifacts de dev;
    /// nil quando não se aplica ou não deu pra medir).
    var staleDays: Int? = nil
    /// Projeto parado com mudanças não commitadas ou commits não pushados —
    /// trabalho esquecido sem backup no remoto (só checado quando parado).
    var unsavedWork = false
    /// Alvo do Docker: a ação é `docker system prune` (irreversível), não Lixeira.
    var isDocker = false
    /// Linha do purgeable quando há snapshots locais do Time Machine: habilita o
    /// botão de thinning (recupera o espaço que o macOS só liberaria sob pressão).
    var canThinSnapshots = false
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
    @Published var deleting = false
    @Published var deletingDone = 0
    @Published var deletingTotal = 0
    /// Resultado da última tentativa de apagar simuladores indisponíveis:
    /// nil = não rodou; 0 = nenhum encontrado; N = quantos foram apagados.
    @Published var simDeleteDone: Int?
    /// Runtimes de simulador não usados apagados no último clique (nil = não rodou).
    @Published var runtimeDeleteDone: Int?
    /// Bytes liberados no último "esvaziar Lixeira" (nil = não rodou).
    @Published var trashEmptiedBytes: Int64?
    /// Nº de alertas de crescimento no último scan — badge do vigia no menu-bar.
    @Published var growthCount = 0

    /// Evita disparar a notificação de disco baixo repetidamente: só notifica
    /// quando o espaço livre CRUZA pra baixo do limite.
    private var wasBelowThreshold = false

    private let home = FileManager.default.homeDirectoryForCurrentUser
    private let minBytes: Int64 = 10_000_000 // ignora ruído < 10 MB

    /// Telemetria de "paisagem" (ecossistemas + caches não reconhecidos): 1x
    /// por execução do app, pra não repetir o sizing pesado a cada scan.
    private var landscapeReported = false

    /// true = ao final do scan corrente, roda a limpeza automática.
    private var pendingAutoClean = false
    private var autoCleanTimer: Timer?
    /// Refresh leve do espaço livre pro % do menu-bar (statfs, sem scan).
    private var diskTimer: Timer?

    /// `autoTriggers: false` = modo CLI: sem observers, timers ou notificações.
    init(autoTriggers: Bool = true) {
        guard autoTriggers else { return }
        // Os triggers do auto-clean vivem aqui (a UI do popover pode nem ter
        // sido criada ainda; o scanner existe desde o launch).
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == "com.apple.dt.Xcode" else { return }
            self?.autoCleanIfDue(fromXcodeQuit: true)
        }
        autoCleanTimer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
            self?.autoCleanIfDue(fromXcodeQuit: false)
        }
        // Checagem inicial (ex.: agendamento semanal vencido com o Mac desligado),
        // com folga pra não competir com o scan de abertura.
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) { [weak self] in
            self?.autoCleanIfDue(fromXcodeQuit: false)
        }
        // % do menu-bar vivo sem pagar scan: statfs a cada 3 min é barato.
        diskTimer = Timer.scheduledTimer(withTimeInterval: 180, repeats: true) { [weak self] _ in
            self?.refreshDiskSpace()
        }
        refreshDiskSpace()
    }

    /// Atualiza só free/total (statfs) sem escanear — barato, pro vigia do menu-bar.
    func refreshDiskSpace() {
        let (free, total) = diskSpace()
        freeBytes = free
        totalBytes = total
    }

    func scan() {
        // Não escanear no meio de uma limpeza: o rescan final do delete() reconcilia.
        guard !scanning, !deleting else { return }
        scanning = true
        let startedAt = Date()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let (free, total) = self.diskSpace()
            let found = self.collectAll()
            // Detecção de crescimento: diffa a paisagem atual contra o snapshot
            // e grava o novo. Fora do collectAll pra não pesar no modo CLI.
            let growth = self.growthAlerts(from: found)
            // Telemetria de "paisagem" (só com opt-in). Docker é por scan (barato,
            // já probado); ecossistemas + caches não reconhecidos rodam 1x por
            // execução do app pra não pagar o sizing de ~/Library/Caches todo scan.
            if Analytics.enabled {
                Analytics.dockerState(self.lastDockerState)
                if !self.landscapeReported {
                    self.landscapeReported = true
                    Analytics.ecosystems(self.detectedEcosystems())
                    let unrec = self.unrecognizedCaches()
                    Analytics.cacheUnrecognized(count: unrec.count, totalBytes: unrec.bytes)
                }
            }
            DispatchQueue.main.async {
                self.freeBytes = free
                self.totalBytes = total
                self.targets = growth + found
                self.growthCount = growth.count
                self.lastScan = Date()
                self.scanning = false
                self.checkLowSpaceNotification()
                let ms = Int(Date().timeIntervalSince(startedAt) * 1000)
                let cleanable = found.filter { !$0.tier.isReadOnly }
                let recoverable = cleanable.reduce(Int64(0)) { $0 + $1.bytes }
                // Composição só do que é recuperável (o tier informativo fica de
                // fora — inclui a linha "purgeable" cujo path é a home).
                var byCategory: [String: Int64] = [:]
                for t in cleanable { byCategory[t.category, default: 0] += t.bytes }
                let freeRatio = total > 0 ? Double(free) / Double(total) : 1
                Analytics.scanFinished(durationMs: ms, itemCount: found.count,
                                       recoverableBytes: recoverable,
                                       freeRatio: freeRatio, byCategory: byCategory)
                if self.pendingAutoClean {
                    self.pendingAutoClean = false
                    self.performAutoClean()
                }
            }
        }
    }

    /// Apaga os itens. `permanently == false` (default) move pra Lixeira
    /// (recuperável, mas o espaço só é liberado ao esvaziar a Lixeira);
    /// `true` remove de vez, liberando o espaço na hora.
    /// Itens read-only (tier informativo) são ignorados por segurança.
    func delete(_ items: [CleanTarget], permanently: Bool) {
        let deletable = items.filter { !$0.tier.isReadOnly }
        guard !deletable.isEmpty else { return }
        deleting = true
        deletingDone = 0
        deletingTotal = deletable.count
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var freed: Int64 = 0
            var count = 0
            var anyFailed = false
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
                    byCategory[item.category, default: 0] += item.bytes
                } else {
                    anyFailed = true
                }
                // Feedback imediato: some da lista assim que o item vai pra
                // Lixeira, sem esperar o rescan completo do final.
                DispatchQueue.main.async {
                    self?.deletingDone += 1
                    if ok { self?.targets.removeAll { $0.id == item.id } }
                }
            }
            let freedFinal = freed, countFinal = count, categories = byCategory, failed = anyFailed
            DispatchQueue.main.async {
                CleanLog.record(bytes: freedFinal, count: countFinal, byCategory: categories)
                self?.lastFreedBytes = freedFinal
                self?.lastDeletePermanent = permanently
                self?.justCleaned = true
                self?.deleting = false
                Analytics.deleteConfirmed(mode: permanently ? "permanent" : "trash",
                                          freedBytes: freedFinal, itemCount: countFinal, byCategory: categories)
                if failed { Analytics.failure("delete") }
                // Sem rescan completo: os itens já saíram da lista um a um, então
                // só atualizamos o disponível real (statfs) — reflete na hora o que
                // foi de fato liberado. Deleção permanente sobe o livre; Lixeira
                // não (o espaço só volta ao esvaziar). Rescan manual pelo botão.
                self?.refreshDiskSpace()
            }
        }
    }

    /// Varredura completa, síncrona — compartilhada entre o scan() assíncrono
    /// da UI e o modo CLI.
    func collectAll() -> [CleanTarget] {
        unsavedCache.removeAll()
        var found = scanDevelopment() + scanDerivedData() + scanLibrary()
            + scanInfo() + scanDocker() + scanCacheHome() + scanStrayGit()
            + scanDeviceSupportVersions() + scanOrphanedLeftovers() + scanGitBloat()
            + scanBigFiles() + scanTrash() + scanOrphanedAppData() + scanVMDisks()
        // Dedupe por path: scanners podem se sobrepor (ex.: órfão curado vs
        // generalizado no mesmo bundle-id). Mantém a primeira ocorrência.
        var seen = Set<String>()
        found = found.filter { seen.insert($0.url.path).inserted }
        found.sort { $0.bytes > $1.bytes }
        return found
    }

    // MARK: private

    func diskSpace() -> (Int64, Int64) {
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
        let names: Set<String> = ["build", ".build", "node_modules", "Pods", "DerivedData",
                                  ".venv", "venv", ".next", ".turbo", ".parcel-cache",
                                  "__pycache__", "Carthage", "target", "dist"]
        var out: [CleanTarget] = []

        // 'target' (Rust) e 'dist' (JS) são nomes genéricos: só contam como
        // artifact regenerável se o projeto tiver o marcador do ecossistema
        // (Cargo.toml / package.json), pra nunca apagar pasta de dados do usuário.
        func isBuildArtifact(_ url: URL) -> Bool {
            let name = url.lastPathComponent
            guard names.contains(name) else { return false }
            let fm = FileManager.default
            let projectDir = url.deletingLastPathComponent()
            switch name {
            case "target": return fm.fileExists(atPath: projectDir.appendingPathComponent("Cargo.toml").path)
            case "dist": return fm.fileExists(atPath: projectDir.appendingPathComponent("package.json").path)
            default: return true
            }
        }

        func recurse(_ dir: URL, depth: Int) {
            guard depth <= 3 else { return }
            guard let items = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: []
            ) else { return }
            for item in items {
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                guard isDir else { continue }
                if isBuildArtifact(item) {
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
                            detailKey: \.devArtifact,
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
                                   detailKey: \.xcodeDerived, tier: .safe, bytes: b,
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

    /// Diretório git real de `dir`. Normalmente é `dir/.git` (pasta), mas em
    /// git worktrees (e submódulos) `.git` é um ARQUIVO com `gitdir: <path>`
    /// apontando pro gitdir real — ex.: `<repo>/.git/worktrees/<nome>`, onde
    /// ficam o HEAD/index daquele worktree. Sem seguir esse ponteiro, a
    /// staleness de worktree cairia no mtime da pasta (impreciso).
    private func gitDir(at dir: URL) -> URL? {
        let fm = FileManager.default
        let dotGit = dir.appendingPathComponent(".git")
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: dotGit.path, isDirectory: &isDir) else { return nil }
        if isDir.boolValue { return dotGit }
        // `.git` é arquivo: primeira linha "gitdir: <path>" (relativo ou absoluto).
        guard let content = try? String(contentsOf: dotGit, encoding: .utf8) else { return nil }
        for line in content.split(whereSeparator: \.isNewline) {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("gitdir:") else { continue }
            let p = t.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
            guard !p.isEmpty else { return nil }
            return p.hasPrefix("/")
                ? URL(fileURLWithPath: p)
                : dir.appendingPathComponent(p).standardizedFileURL
        }
        return nil
    }

    /// Última atividade do projeto, 100% local: mtime do index/HEAD do git
    /// (commit/checkout/uso do git). Segue o ponteiro `gitdir:` em worktrees.
    /// Sobe até 3 níveis pra achar o .git de monorepos. Sem git, cai pro
    /// mtime da pasta do projeto.
    private func projectActivity(from dir: URL) -> Date? {
        let fm = FileManager.default
        func mtime(_ url: URL) -> Date? {
            (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        }
        var probe = dir
        for _ in 0..<4 {
            // A home (e acima) nunca é raiz de projeto — um ~/.git solto
            // (dotfiles) contaminaria a data de projetos sem git.
            guard probe.path != home.path, probe.path != "/" else { break }
            if let git = gitDir(at: probe) {
                let dates = [git.appendingPathComponent("index"),
                             git.appendingPathComponent("HEAD")].compactMap(mtime)
                if let latest = dates.max() { return latest }
            }
            probe = probe.deletingLastPathComponent()
        }
        return mtime(dir)
    }

    /// Alvos conhecidos de caches dev na home (~/Library e dotfiles).
    /// Cobre toolchains (Xcode, Gradle, npm…), editores e ferramentas de IA
    /// (pesos de modelo do Ollama/LM Studio/HuggingFace, que passam de
    /// dezenas de GB fácil).
    private func scanLibrary() -> [CleanTarget] {
        let specs: [(String, String, Tier, KeyPath<L, String>)] = [
            // Xcode & Apple (DerivedData e DeviceSupport têm scanner próprio)
            ("Library/Developer/Xcode/Archives", "Xcode Archives", .caution, \.xcodeArchives),
            ("Library/Developer/XcodeBuildMCP/workspaces", "workspaces", .safe, \.xcodeBuildMCP),
            ("Library/Developer/XCTestDevices", "XCTestDevices", .safe, \.xctestDevices),
            ("Library/Caches/org.swift.swiftpm", "org.swift.swiftpm", .safe, \.swiftpmCache),
            ("Library/Caches/CocoaPods", "CocoaPods", .safe, \.pkgCache),
            // Package managers / linguagens
            ("Library/Caches/Homebrew", "Homebrew", .safe, \.homebrewCache),
            ("Library/Caches/Yarn", "Yarn", .safe, \.yarnCache),
            ("Library/Caches/pnpm", "pnpm", .safe, \.pkgCache),
            (".npm", "npm", .safe, \.pkgCache),
            (".bun/install/cache", "Bun", .safe, \.pkgCache),
            ("Library/Caches/pip", "pip", .safe, \.pipCache),
            ("Library/Caches/uv", "uv", .safe, \.pkgCache),
            ("Library/Caches/go-build", "Go build", .safe, \.devArtifact),
            ("go/pkg/mod", "Go modules", .caution, \.depsCache),
            (".gradle/caches", "Gradle", .caution, \.depsCache),
            (".m2/repository", "Maven", .caution, \.depsCache),
            (".cargo/registry", "Cargo", .caution, \.depsCache),
            (".pub-cache", "Flutter pub", .caution, \.depsCache),
            // Android SDK / emulador
            ("Library/Android/sdk/system-images", "Android system images", .caution, \.androidSdkImages),
            (".android/avd", "Android AVDs", .caution, \.androidAvd),
            // Editores / IDEs
            ("Library/Application Support/Code/CachedData", "VS Code (CachedData)", .safe, \.editorCache),
            ("Library/Application Support/Code/Cache", "VS Code (Cache)", .safe, \.editorCache),
            ("Library/Application Support/Cursor/CachedData", "Cursor (CachedData)", .safe, \.editorCache),
            ("Library/Application Support/Cursor/Cache", "Cursor (Cache)", .safe, \.editorCache),
            ("Library/Caches/JetBrains", "JetBrains", .caution, \.jetbrainsCache),
            // Ferramentas de IA (pesos de modelo)
            (".ollama/models", "Ollama", .caution, \.aiModels),
            (".cache/huggingface", "Hugging Face", .caution, \.aiModels),
            (".lmstudio/models", "LM Studio", .caution, \.aiModels),
            (".cache/lm-studio", "LM Studio (legado)", .caution, \.aiModels),
            // Outros
            ("Library/Caches/ms-playwright", "ms-playwright", .caution, \.playwrightCache),
            ("Library/Caches/Google", "Google", .caution, \.googleCache),
        ]
        var out: [CleanTarget] = []
        for (rel, label, tier, detail) in specs {
            let url = home.appendingPathComponent(rel)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let b = size(of: url)
            if b > minBytes {
                out.append(CleanTarget(url: url, label: label, detailKey: detail, tier: tier, bytes: b))
            }
        }
        return out
    }

    /// Caches em ~/.cache (padrão XDG): uv, codex, puppeteer e afins vivem aqui,
    /// não em ~/Library/Caches — por isso o scanLibrary os perdia. Tudo em
    /// ~/.cache é, por definição, regenerável (tier seguro). Pula os que já têm
    /// scanner próprio com tier caution (modelos de IA) pra não duplicar/rebaixar.
    private func scanCacheHome() -> [CleanTarget] {
        let cache = home.appendingPathComponent(".cache")
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: cache, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return [] }
        // Já cobertos com tier próprio (caution) no scanLibrary: não duplicar.
        let handledElsewhere: Set<String> = ["huggingface", "lm-studio"]
        var out: [CleanTarget] = []
        for item in items {
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir, !handledElsewhere.contains(item.lastPathComponent) else { continue }
            let b = size(of: item)
            if b > minBytes {
                out.append(CleanTarget(url: item, label: item.lastPathComponent,
                                       detailKey: \.pkgCache, tier: .safe, bytes: b))
            }
        }
        return out
    }

    /// Repo Git acidental na Home. Um `git init/add` errado em ~ passa a rastrear
    /// a casa inteira e incha pra dezenas de GB. Quem versiona dotfiles usa repo
    /// bare fora da home, então um ~/.git normal é quase sempre engano — mas
    /// apagar repo às cegas é perigoso: tier .info (mostra, o app nunca apaga).
    private func scanStrayGit() -> [CleanTarget] {
        let dotgit = home.appendingPathComponent(".git")
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dotgit.path, isDirectory: &isDir),
              isDir.boolValue else { return [] }
        let b = size(of: dotgit)
        guard b > minBytes else { return [] }
        return [CleanTarget(url: dotgit, labelKey: \.strayGitLabel,
                            detailKey: \.strayGitDetail, tier: .info, bytes: b)]
    }

    /// iOS DeviceSupport quebrado por versão. Você acumula vários builds quase
    /// idênticos do mesmo iOS (23F77/81/84…): mantém o mais novo, oferece os
    /// antigos (recriam ao reconectar um device). Com 1 versão, vira bloco único.
    private func scanDeviceSupportVersions() -> [CleanTarget] {
        let root = home.appendingPathComponent("Library/Developer/Xcode/iOS DeviceSupport")
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]) else { return [] }
        let versions = items.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        guard !versions.isEmpty else { return [] }
        // Mais novo primeiro (por data de modificação).
        let sorted = versions.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a > b
        }
        // 1 versão: é a atual — bloco único (comportamento antigo). >1: descarta o topo.
        let old = sorted.count == 1 ? sorted : Array(sorted.dropFirst())
        var out: [CleanTarget] = []
        for v in old {
            let b = size(of: v)
            if b > minBytes {
                let detail: KeyPath<L, String> = sorted.count == 1 ? \.iosDeviceSupport : \.deviceSupportOld
                out.append(CleanTarget(url: v, label: "iOS DeviceSupport · \(v.lastPathComponent)",
                                       detailKey: detail, tier: .caution, bytes: b))
            }
        }
        return out
    }

    /// Sobras de apps que você não tem mais instalados (ex.: installer do Docker
    /// Desktop quando você usa OrbStack). Curado e conservador: só sinaliza se o
    /// app dono claramente não existe. Tier caution (é dado de app).
    private func scanOrphanedLeftovers() -> [CleanTarget] {
        // (pasta de sobra, apps que provariam que ainda está em uso, detalhe)
        let table: [(String, [String], KeyPath<L, String>)] = [
            ("Library/Application Support/com.docker.install", ["/Applications/Docker.app"], \.orphanLeftover),
        ]
        let fm = FileManager.default
        var out: [CleanTarget] = []
        for (rel, ownerApps, detail) in table {
            let url = home.appendingPathComponent(rel)
            guard fm.fileExists(atPath: url.path) else { continue }
            let stillUsed = ownerApps.contains { fm.fileExists(atPath: $0) }
            guard !stillUsed else { continue }
            let b = size(of: url)
            if b > minBytes {
                out.append(CleanTarget(url: url, label: url.lastPathComponent,
                                       detailKey: detail, tier: .caution, bytes: b))
            }
        }
        return out
    }

    /// Repos com .git inchado (pack gigante / binário no histórico) sob
    /// ~/Development. Advisory (info): apagar .git perde história — sugere git gc.
    private func scanGitBloat() -> [CleanTarget] {
        let dev = home.appendingPathComponent("Development")
        let threshold: Int64 = 1_000_000_000
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dev, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return [] }
        var out: [CleanTarget] = []
        for proj in items {
            let isDir = (try? proj.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir else { continue }
            let objects = proj.appendingPathComponent(".git/objects")
            guard FileManager.default.fileExists(atPath: objects.path) else { continue }
            let b = size(of: objects)
            if b >= threshold {
                out.append(CleanTarget(url: proj.appendingPathComponent(".git"),
                                       label: "\(proj.lastPathComponent)/.git",
                                       detailKey: \.gitBloat, tier: .info, bytes: b))
            }
        }
        return out
    }

    /// Maiores arquivos INDIVIDUAIS (não pastas) nas pastas de usuário — o culpado
    /// costuma ser UM arquivo (um .mp4, um .dmg), não a pasta. Tier info: o app não
    /// apaga arquivo pessoal, só revela no Finder.
    private func scanBigFiles() -> [CleanTarget] {
        let roots = ["Downloads", "Desktop", "Documents", "Movies"].map { home.appendingPathComponent($0) }
        let threshold: Int64 = 300_000_000
        let now = Date()
        // (url, bytes, parado): "parado" = não modificado há 180+ dias. Grande +
        // parado + insubstituível = candidato a mover pro SSD externo (a lente de
        // offload). O app NUNCA move — só sinaliza e revela no Finder.
        var files: [(URL, Int64, Bool)] = []
        for root in roots {
            guard let en = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]) else { continue }
            for case let f as URL in en {
                let v = try? f.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .contentModificationDateKey])
                guard v?.isRegularFile == true else { continue }
                let b = Int64(v?.totalFileAllocatedSize ?? 0)
                guard b >= threshold else { continue }
                let stale = (v?.contentModificationDate).map { now.timeIntervalSince($0) > 180 * 86_400 } ?? false
                files.append((f, b, stale))
            }
        }
        return files.sorted { $0.1 > $1.1 }.prefix(15).map {
            CleanTarget(url: $0.0, label: $0.0.lastPathComponent,
                        detailKey: $0.2 ? \.offloadDetail : \.bigFileDetail, tier: .info, bytes: $0.1)
        }
    }

    /// Bundle IDs dos apps instalados (lê CFBundleIdentifier dos .app). Base pra
    /// achar dados órfãos: pasta nomeada por bundle-id cujo app não existe mais.
    private func installedBundleIDs() -> Set<String> {
        let fm = FileManager.default
        let dirs = ["/Applications", "/Applications/Utilities", "/System/Applications",
                    home.appendingPathComponent("Applications").path]
        var ids = Set<String>()
        for dir in dirs {
            guard let apps = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for app in apps where app.hasSuffix(".app") {
                if let d = NSDictionary(contentsOfFile: "\(dir)/\(app)/Contents/Info.plist"),
                   let id = d["CFBundleIdentifier"] as? String {
                    ids.insert(id.lowercased())
                }
            }
        }
        return ids
    }

    /// Dados de apps que você não tem mais instalados: pastas em Containers e
    /// Application Support nomeadas por bundle-id (com.foo.bar) cujo app sumiu.
    /// Conservador — só nomes reverse-DNS, pula com.apple.*, tier caution (Lixeira).
    private func scanOrphanedAppData() -> [CleanTarget] {
        let installed = installedBundleIDs()
        let fm = FileManager.default
        var out: [CleanTarget] = []
        for rel in ["Library/Containers", "Library/Application Support"] {
            let root = home.appendingPathComponent(rel)
            guard let items = try? fm.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
            ) else { continue }
            for item in items {
                let name = item.lastPathComponent
                // Só nomes que parecem bundle-id (2+ pontos). Nomes simples como
                // "Google"/"Steam" não entram — evita falso-positivo de app vivo.
                guard name.filter({ $0 == "." }).count >= 2,
                      !name.lowercased().hasPrefix("com.apple."),
                      !installed.contains(name.lowercased()) else { continue }
                let b = size(of: item)
                if b > minBytes {
                    out.append(CleanTarget(url: item, label: name,
                                           detailKey: \.orphanAppData, tier: .caution, bytes: b))
                }
            }
        }
        return out
    }

    /// Discos de máquinas virtuais (Parallels/VMware/UTM) — 20–100 GB fáceis, e
    /// invisíveis pros cleaners comuns. Tier info: dado seu, revela no Finder.
    private func scanVMDisks() -> [CleanTarget] {
        let specs: [(String, String)] = [
            ("Parallels", "Parallels VMs"),
            ("Documents/Parallels", "Parallels VMs"),
            ("Virtual Machines.localized", "VMware VMs"),
            ("Library/Containers/com.utmapp.UTM/Data/Documents", "UTM VMs"),
        ]
        var out: [CleanTarget] = []
        for (rel, label) in specs {
            let url = home.appendingPathComponent(rel)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let b = size(of: url)
            if b > minBytes {
                out.append(CleanTarget(url: url, label: label, detailKey: \.vmDisk, tier: .info, bytes: b))
            }
        }
        return out
    }

    /// Lixeira: mover pra Lixeira não libera espaço até esvaziar. Surface com
    /// botão dedicado (o app até explica isso) — fecha o ciclo do delete-to-trash.
    private func scanTrash() -> [CleanTarget] {
        let trash = home.appendingPathComponent(".Trash")
        let b = size(of: trash)
        guard b > minBytes else { return [] }
        return [CleanTarget(url: trash, labelKey: \.trashLabel,
                            detailKey: \.trashDetail, tier: .info, bytes: b)]
    }

    /// 🥇 Detecção de crescimento: compara a paisagem atual (por categoria) com o
    /// snapshot mais antigo (≥1 dia) e avisa o que APARECEU grande ou CRESCEU — o
    /// que enche o disco em silêncio. Grava o snapshot novo a cada passada.
    private func growthAlerts(from found: [CleanTarget]) -> [CleanTarget] {
        let now = Date().timeIntervalSince1970
        var current: [String: Int64] = [:]
        var repURL: [String: URL] = [:]
        var repBytes: [String: Int64] = [:]
        for t in found {
            current[t.category, default: 0] += t.bytes
            if t.bytes > (repBytes[t.category] ?? 0) { repBytes[t.category] = t.bytes; repURL[t.category] = t.url }
        }
        defer { SizeLog.record(current, now: now) }
        guard let base = SizeLog.baseline(now: now, minAgeDays: 1) else { return [] }
        let days = max(1, Int((now - base.ts) / 86_400))
        let newBig: Int64 = 3_000_000_000, grew: Int64 = 3_000_000_000
        var out: [CleanTarget] = []
        for (cat, cur) in current where cur >= minBytes {
            let label: String?
            if base.cats[cat] == nil {
                label = cur >= newBig ? L10n.growthNew(name: cat, size: fmt(cur)) : nil
            } else if let p = base.cats[cat], cur - p >= grew {
                label = L10n.growthGrew(name: cat, size: fmt(cur - p), days: days)
            } else {
                label = nil
            }
            if let label = label {
                out.append(CleanTarget(url: repURL[cat] ?? home, label: label,
                                       detailKey: \.growthDetail, tier: .info,
                                       bytes: base.cats[cat].map { cur - $0 } ?? cur))
            }
        }
        return out.sorted { $0.bytes > $1.bytes }
    }

    /// Tier informativo (só leitura): pastas grandes que o app NÃO apaga, mas
    /// mostra pra você saber onde o espaço está e agir manualmente.
    private func scanInfo() -> [CleanTarget] {
        let specs: [(String, String, KeyPath<L, String>)] = [
            ("Library/Developer/CoreSimulator", "CoreSimulator", \.coreSimulatorDetail),
            ("Library/Application Support", "Application Support", \.appSupportDetail),
            ("Downloads", "Downloads", \.downloadsDetail),
            ("Documents", "Documents", \.documentsDetail),
            ("Desktop", "Desktop", \.desktopDetail),
        ]
        var out: [CleanTarget] = []
        for (rel, label, detail) in specs {
            let url = home.appendingPathComponent(rel)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let b = size(of: url)
            if b > minBytes {
                out.append(CleanTarget(url: url, label: label, detailKey: detail, tier: .info, bytes: b))
            }
        }

        // Espaço "purgeable" (snapshots do Time Machine, caches do sistema):
        // a diferença entre a capacidade que o macOS LIBERARIA sob demanda
        // (volumeAvailableCapacityForImportantUsage) e o livre real (statfs).
        // Explica o clássico "apaguei X GB e o Finder não mostra". URL fresca
        // a cada scan — resourceValues cacheia por instância de URL.
        let volume = URL(fileURLWithPath: NSHomeDirectory())
        if let important = (try? volume.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage {
            let (free, _) = diskSpace()
            let purgeable = important - free
            if purgeable > minBytes {
                out.append(CleanTarget(url: home, labelKey: \.purgeableLabel,
                                       detailKey: \.purgeableDetail, tier: .info, bytes: purgeable,
                                       canThinSnapshots: hasLocalSnapshots()))
            }
        }
        return out
    }

    /// Docker/OrbStack: mede o recuperável real via engine (não o disk image).
    /// Tier caution porque prune é irreversível e não passa pela Lixeira.
    /// Estado do engine no último scan (telemetria "off" = valor não recuperado).
    private(set) var lastDockerState = "absent"

    private func scanDocker() -> [CleanTarget] {
        switch DockerEngine.probe() {
        case .absent:
            lastDockerState = "absent"
            return []
        case .running(let reclaimable, let image):
            lastDockerState = "running"
            guard reclaimable > minBytes else { return [] }
            let url = image ?? DockerEngine.binary() ?? home
            return [CleanTarget(url: url, labelKey: \.dockerLabel, detailKey: \.dockerDetail,
                                tier: .caution, bytes: reclaimable, isDocker: true)]
        case .stopped(let bytes, let image):
            lastDockerState = "off"
            guard bytes > minBytes, let image = image else { return [] }
            return [CleanTarget(url: image, labelKey: \.dockerStoppedLabel,
                                detailKey: \.dockerStoppedDetail, tier: .info, bytes: bytes)]
        }
    }

    /// TIER 1 — toolchains que o user TEM (existência de marcadores, sem tamanho).
    /// Genérico, nunca caminho/projeto. Roda só com analytics ligado.
    private func detectedEcosystems() -> [String] {
        let fm = FileManager.default
        let markers: [(String, String)] = [
            ("Xcode", "Library/Developer/Xcode"), ("node", ".npm"), ("Bun", ".bun"),
            ("Cargo", ".cargo"), ("Go", "go/pkg"), ("Gradle", ".gradle"),
            ("Maven", ".m2"), ("CocoaPods", ".cocoapods"), ("Flutter", ".pub-cache"),
            ("Android", "Library/Android"), ("Ollama", ".ollama"),
            ("HuggingFace", ".cache/huggingface"), ("LMStudio", ".lmstudio"),
            ("JetBrains", "Library/Caches/JetBrains"), ("VSCode", "Library/Application Support/Code"),
            ("Homebrew", "Library/Caches/Homebrew"),
        ]
        var found = markers.filter { fm.fileExists(atPath: home.appendingPathComponent($1).path) }
            .map { $0.0 }
        if lastDockerState != "absent" { found.append("Docker") }
        return found
    }

    /// TIER 1 — caches grandes em ~/Library/Caches que não reconhecemos: só
    /// contagem + total (sem nomes, pra não vazar bundle-id de app próprio).
    private func unrecognizedCaches() -> (count: Int, bytes: Int64) {
        let caches = home.appendingPathComponent("Library/Caches")
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: caches, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return (0, 0) }
        let known: Set<String> = ["org.swift.swiftpm", "CocoaPods", "Homebrew", "Yarn", "pnpm",
                                   "pip", "uv", "go-build", "JetBrains", "ms-playwright", "Google"]
        var count = 0, total: Int64 = 0
        for item in items {
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir, !known.contains(item.lastPathComponent) else { continue }
            let b = size(of: item)
            if b >= 500_000_000 { count += 1; total += b }
        }
        return (count, total)
    }

    // MARK: auto-clean

    /// Dispara o ciclo se estiver habilitado e "vencido". Xcode-quit e disco
    /// baixo rodam no máx 1x/h; diário/semanal seguem o intervalo. Marca a
    /// tentativa mesmo abaixo do piso, pra não re-escanear em loop.
    func autoCleanIfDue(fromXcodeQuit: Bool) {
        let d = UserDefaults.standard
        guard d.bool(forKey: Prefs.autoCleanEnabled) else { return }
        let trigger = d.string(forKey: Prefs.autoCleanTrigger) ?? "daily"
        let elapsed = Date().timeIntervalSince1970 - d.double(forKey: Prefs.autoCleanLastRun)
        if fromXcodeQuit {
            guard trigger == "xcode", elapsed >= 3_600 else { return }
        } else {
            switch trigger {
            case "daily", "endofday":
                // "No fim do dia": preferido de noite (>=18h), mas nunca deixa
                // passar um dia inteiro se o Mac não esteve ligado à noite.
                guard elapsed >= 3_600 else { return }
                let hour = Calendar.current.component(.hour, from: Date())
                guard hour >= 18 || elapsed >= 86_400 else { return }
            case "startofday":
                // "No começo do dia": de manhã (6h–12h), mesmo fallback de 24h.
                guard elapsed >= 3_600 else { return }
                let hour = Calendar.current.component(.hour, from: Date())
                guard (hour >= 6 && hour < 12) || elapsed >= 86_400 else { return }
            case "weekly": guard elapsed >= 604_800 else { return }
            case "lowdisk":
                // statfs é barato; checa direto se cruzou o limite do aviso.
                guard elapsed >= 3_600 else { return }
                let (free, total) = diskSpace()
                guard total > 0, Double(free) / Double(total) < notifyThreshold else { return }
            default: return // "xcode" só dispara pelo observer
            }
        }
        pendingAutoClean = true
        scan()
    }

    /// Regras de confiança do auto-clean, mais duras que a limpeza manual:
    /// só 🟢 seguros; artifacts de ~/Development só no escopo "all" e ainda
    /// assim apenas de projetos parados 90+ dias (projeto ativo nunca);
    /// SEMPRE Lixeira (ignora o toggle permanente); e só acima do piso.
    private func performAutoClean() {
        let d = UserDefaults.standard
        let scope = d.string(forKey: Prefs.autoCleanScope) ?? "all"
        let floor = (d.object(forKey: Prefs.autoCleanMinBytes) as? Int) ?? Prefs.autoCleanMinBytesDefault
        let devRoot = home.appendingPathComponent("Development").path
        let eligible = targets.filter { t in
            guard t.tier == .safe, !t.isDocker else { return false }
            let isStaleProject = (t.staleDays ?? 0) >= Prefs.staleThresholdDays
            if t.url.path.hasPrefix(devRoot) {
                // Artifacts dentro do projeto (node_modules, .build…): só de
                // projetos parados, e nunca no escopo mais conservador.
                return scope != "caches" && isStaleProject
            }
            if t.url.path.contains("/Xcode/DerivedData/") {
                // DerivedData de projeto ativo custa rebuild: só no "max".
                return isStaleProject || scope == "max"
            }
            return true // caches de ferramentas: re-baixam sob demanda
        }
        let total = eligible.reduce(Int64(0)) { $0 + $1.bytes }
        d.set(Date().timeIntervalSince1970, forKey: Prefs.autoCleanLastRun)
        guard total >= Int64(floor) else { return }

        // Resumo + histórico (últimas 10) pra UI dar visibilidade do que
        // o app fez sozinho.
        d.set(Date().timeIntervalSince1970, forKey: Prefs.autoCleanLastCleanTs)
        d.set(Double(total), forKey: Prefs.autoCleanLastBytes)
        d.set(eligible.count, forKey: Prefs.autoCleanLastCount)
        var hist = d.array(forKey: Prefs.autoCleanHistory) as? [[String: Double]] ?? []
        hist.insert(["ts": Date().timeIntervalSince1970,
                     "bytes": Double(total),
                     "count": Double(eligible.count)], at: 0)
        d.set(Array(hist.prefix(10)), forKey: Prefs.autoCleanHistory)

        Analytics.autoCleanRan(trigger: d.string(forKey: Prefs.autoCleanTrigger) ?? "daily",
                               scope: scope, freedBytes: total, itemCount: eligible.count)
        notifyAutoClean(freed: total, count: eligible.count)
        delete(eligible, permanently: false)
    }

    private func notifyAutoClean(freed: Int64, count: Int) {
        let content = UNMutableNotificationContent()
        content.title = L10n.autoCleanNotifTitle
        content.body = L10n.autoCleanNotifBody(size: fmt(freed), count: count)
        let req = UNNotificationRequest(identifier: "harbofly.autoclean", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    // MARK: simuladores antigos

    /// Apaga simuladores de runtimes antigos (indisponíveis pro Xcode atual)
    /// via `xcrun simctl delete unavailable`. Irreversível (não passa pela
    /// Lixeira) — a UI pede confirmação em dois cliques. Re-escaneia ao fim.
    func deleteUnavailableSimulators() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Conta os indisponíveis PRIMEIRO: o comando só apaga simuladores de
            // runtimes sumidos (órfãos). Se não há nenhum, ele roda mas libera
            // zero — então damos feedback ("nenhum encontrado") em vez de parecer
            // quebrado. Os simuladores DISPONÍVEIS (o grosso do espaço) não são
            // tocados: isso se gerencia no Xcode, e por isso é tier informativo.
            let count = self?.unavailableSimulatorCount() ?? 0
            if count > 0 {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
                p.arguments = ["simctl", "delete", "unavailable"]
                p.standardOutput = Pipe()
                p.standardError = Pipe()
                try? p.run()
                p.waitUntilExit()
            }
            DispatchQueue.main.async {
                self?.simDeleteDone = count
                if count > 0 { self?.scan() }
            }
        }
    }

    /// Nº de simuladores de runtimes indisponíveis (o que o comando apagaria).
    private func unavailableSimulatorCount() -> Int {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        p.arguments = ["simctl", "list", "devices", "unavailable", "-j"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return 0 }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devices = json["devices"] as? [String: [[String: Any]]] else { return 0 }
        return devices.values.reduce(0) { $0 + $1.count }
    }

    /// Apaga runtimes de simulador (imagens de disco de iOS/etc) não usados há 30+
    /// dias via `simctl runtime delete --notUsedSinceDays 30`. Seguro: nunca toca
    /// no runtime em uso. Conta antes com `--dry-run` pra dar feedback honesto.
    func deleteUnusedRuntimes() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Conta com dry-run só pro feedback; o delete real roda sempre (é
            // seguro — só apaga runtime parado 30+ dias) pra um parse falho do
            // dry-run nunca bloquear a limpeza. O rescan reflete o que sobrou.
            let n = self?.unusedRuntimeCount() ?? 0
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            p.arguments = ["simctl", "runtime", "delete", "--notUsedSinceDays", "30"]
            p.standardOutput = Pipe()
            p.standardError = Pipe()
            try? p.run()
            p.waitUntilExit()
            DispatchQueue.main.async {
                self?.runtimeDeleteDone = n
                self?.scan()
            }
        }
    }

    /// Quantos runtimes o `--notUsedSinceDays 30` apagaria (via `--dry-run`).
    private func unusedRuntimeCount() -> Int {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        p.arguments = ["simctl", "runtime", "delete", "--notUsedSinceDays", "30", "--dry-run"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return 0 }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let text = String(data: data, encoding: .utf8) ?? ""
        // O dry-run lista uma imagem por linha; conta linhas com um UUID/identificador.
        return text.split(separator: "\n").filter { $0.contains("—") || $0.contains(" (") || $0.contains("iOS") || $0.contains("watchOS") || $0.contains("tvOS") }.count
    }

    /// Esvazia a Lixeira de verdade — mover pra Lixeira só libera espaço aqui.
    /// Best-effort: mede antes e remove o conteúdo (ignora itens travados/em uso).
    func emptyTrash() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let trash = self.home.appendingPathComponent(".Trash")
            let freed = self.size(of: trash)
            let fm = FileManager.default
            if let items = try? fm.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil, options: []) {
                for item in items { try? fm.removeItem(at: item) }
            }
            DispatchQueue.main.async {
                self.trashEmptiedBytes = freed
                self.scan()
            }
        }
    }

    /// Há snapshots locais do Time Machine? (o grosso do purgeable). Sem admin.
    private func hasLocalSnapshots() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        p.arguments = ["listlocalsnapshots", "/"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return false }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (String(data: data, encoding: .utf8) ?? "").contains("com.apple.TimeMachine")
    }

    /// Espaço purgeável agora (capacidade "importante" − livre real).
    private func purgeableBytes() -> Int64 {
        let volume = URL(fileURLWithPath: NSHomeDirectory())
        guard let important = (try? volume.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
        else { return 0 }
        let (free, _) = diskSpace()
        return max(0, Int64(important) - free)
    }

    /// Recupera o espaço preso pelos snapshots locais do TM, do mais antigo pro
    /// mais novo (`tmutil thinlocalsnapshots`, urgência 4). Precisa de admin — o
    /// osascript mostra o prompt nativo do macOS (o app não é sandboxed). O
    /// backup no HD externo do TM NÃO é tocado; só some o histórico local.
    func thinLocalSnapshots() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let bytes = max(self?.purgeableBytes() ?? 0, 1_000_000_000)
            let script = "do shell script \"/usr/bin/tmutil thinlocalsnapshots / \(bytes) 4\" with administrator privileges"
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", script]
            p.standardOutput = Pipe()
            p.standardError = Pipe()
            try? p.run()
            p.waitUntilExit()
            DispatchQueue.main.async { self?.scan() }
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

/// Painel ativo do popover/janela: limpeza de disco, duplicatas ou histórico.
enum Pane { case cleaner, duplicates, uninstall, stats }

struct ContentView: View {
    @ObservedObject var scanner: DiskScanner
    @ObservedObject var updater: Updater
    @ObservedObject var duplicates: DuplicateScanner
    @ObservedObject var uninstaller: AppUninstaller
    @Environment(\.openWindow) private var openWindow
    @State private var pane: Pane = .cleaner
    @State private var selection = Set<UUID>()
    @State private var confirming = false
    @State private var confirmingSimDelete = false
    @State private var confirmingRuntimeDelete = false
    @State private var confirmingEmptyTrash = false
    @State private var confirmingThinSnapshots = false
    @State private var launchAtLogin = false
    @State private var showSupport = false
    @State private var pixCopied = false
    @State private var showFeedback = false
    @State private var feedbackText = ""
    @State private var feedbackContact = ""
    /// Categoria do feedback: "bug" | "idea" | "other" (segmenta os insights).
    @State private var feedbackType = "idea"
    @State private var feedbackSending = false
    @State private var feedbackSent = false
    @State private var feedbackFailed = false
    /// Força a seção de doação mesmo pra quem já apoiou (quando o próprio usuário
    /// clica em "Apoiar" no rodapé).
    @State private var manualSupport = false
    /// Oferta proativa de auto-clean após algumas limpezas manuais.
    @State private var showAutoOffer = false

    @AppStorage(Prefs.deletePermanently) private var deletePermanently = false
    @AppStorage(Prefs.notifyEnabled) private var notifyEnabled = true
    @AppStorage(Prefs.notifyThreshold) private var notifyThreshold = Prefs.defaultThreshold
    @AppStorage(Prefs.hasSupported) private var hasSupported = false
    @AppStorage(Prefs.donateSnoozeUntil) private var donateSnoozeUntil = 0.0
    @AppStorage(Prefs.donateSnoozeCount) private var donateSnoozeCount = 0
    @AppStorage(Prefs.totalFreedBytes) private var totalFreedBytes = 0
    @AppStorage(Prefs.autoCleanEnabled) private var autoCleanEnabled = false
    @AppStorage(Prefs.autoCleanTrigger) private var autoCleanTrigger = "daily"
    @AppStorage(Prefs.autoCleanScope) private var autoCleanScope = "all"
    @AppStorage(Prefs.autoCleanMinBytes) private var autoCleanMinBytes = Prefs.autoCleanMinBytesDefault
    @AppStorage(Prefs.autoCleanLastCleanTs) private var autoCleanLastCleanTs = 0.0
    @AppStorage(Prefs.autoCleanLastBytes) private var autoCleanLastBytes = 0.0
    @AppStorage(Prefs.autoCleanLastCount) private var autoCleanLastCount = 0
    @AppStorage(Prefs.analyticsChoiceMade) private var analyticsChoiceMade = false
    @AppStorage(Prefs.analyticsEnabled) private var analyticsEnabled = false
    @AppStorage(Prefs.manualCleanCount) private var manualCleanCount = 0
    @AppStorage(Prefs.autoOfferSnoozeUntil) private var autoOfferSnoozeUntil = 0.0
    @AppStorage(Prefs.autoOfferSnoozeCount) private var autoOfferSnoozeCount = 0
    // Observa a troca manual de idioma: ao mudar, a View re-renderiza e o L10n
    // (computado) já devolve as strings no idioma novo.
    @AppStorage(Prefs.language) private var language = "system"

    /// Só pede doação se a pessoa nunca apoiou e o snooze já venceu.
    private var shouldAskDonate: Bool {
        !hasSupported && Date().timeIntervalSince1970 > donateSnoozeUntil
    }

    /// Oferece automatizar quando a pessoa já limpou manualmente algumas vezes,
    /// ainda não ligou o auto-clean e o snooze da oferta já venceu.
    private var shouldOfferAutoClean: Bool {
        !autoCleanEnabled
            && manualCleanCount >= Prefs.autoOfferThreshold
            && Date().timeIntervalSince1970 > autoOfferSnoozeUntil
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
                Picker("", selection: $pane) {
                    Text(L10n.paneCleaner).tag(Pane.cleaner)
                    Text(L10n.paneDuplicates).tag(Pane.duplicates)
                    Text(L10n.paneUninstall).tag(Pane.uninstall)
                    Text(L10n.paneStats).tag(Pane.stats)
                }
                .pickerStyle(.segmented).labelsHidden()

                if pane == .cleaner {
                    header
                    Divider()
                    listSection
                    Divider()
                    footer
                } else if pane == .duplicates {
                    DuplicatesView(scanner: duplicates)
                } else if pane == .uninstall {
                    UninstallView(scanner: uninstaller)
                } else {
                    StatsView()
                }
            }
            .padding(12)
            .disabled(confirming || showSupport || showFeedback || showAutoOffer || !analyticsChoiceMade)

            if !analyticsChoiceMade { analyticsOptInOverlay }
            else if confirming { confirmOverlay }
            if showAutoOffer { autoCleanOfferOverlay }
            if showSupport { supportOverlay }
            if showFeedback { feedbackOverlay }
        }
        .frame(width: 470)
        .onAppear {
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
            Analytics.paneSwitched(to: "cleaner")
            if scanner.targets.isEmpty { scanner.scan() }
        }
        .onReceive(timer) { _ in scanner.scan() }
        .onChange(of: pane) { _, p in
            let name = p == .cleaner ? "cleaner" : (p == .duplicates ? "duplicates" : "history")
            Analytics.paneSwitched(to: name)     // tempo em cada aba
            if p == .duplicates { Analytics.featureUsed("duplicates") }
            else if p == .stats { Analytics.featureUsed("history") }
        }
        .onChange(of: autoCleanEnabled) { _, _ in reportAutoCleanConfig() }
        .onChange(of: autoCleanTrigger) { _, _ in reportAutoCleanConfig() }
        .onChange(of: autoCleanScope) { _, _ in reportAutoCleanConfig() }
        .onChange(of: scanner.justCleaned) { _, cleaned in
            guard cleaned else { return }
            scanner.justCleaned = false
            guard scanner.lastFreedBytes > 0 else { return }
            // No pico de valor (acabou de limpar), ou oferece automatizar (se
            // ainda faz na mão), ou cai no card de conquista/apoio de sempre.
            if shouldOfferAutoClean {
                Analytics.offer("shown")
                showAutoOffer = true
            } else {
                pixCopied = false
                showSupport = true
            }
        }
    }

    // Abre a janela de app (dock + foco), fora da barra de menu.
    func openMainWindow() {
        presentMainWindow(using: openWindow)
    }

    private func reportAutoCleanConfig() {
        Analytics.autoCleanConfigured(enabled: autoCleanEnabled, trigger: autoCleanTrigger, scope: autoCleanScope)
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

    /// Liga o auto-clean no preset mais seguro (fim do dia, só caches),
    /// direto da oferta proativa. A UI de config no rodapé fica disponível
    /// pra ajustar depois.
    private func acceptAutoOffer() {
        Analytics.offer("accepted")
        autoCleanEnabled = true
        autoCleanTrigger = "daily"   // = "No fim do dia"
        autoCleanScope = "caches"
        showAutoOffer = false
    }

    /// "Agora não" na oferta: adia por intervalo crescente (mesma escada da doação).
    private func snoozeAutoOffer() {
        Analytics.offer("snoozed")
        let days = Prefs.snoozeDays[min(autoOfferSnoozeCount, Prefs.snoozeDays.count - 1)]
        autoOfferSnoozeUntil = Date().timeIntervalSince1970 + days * 86_400
        autoOfferSnoozeCount += 1
        showAutoOffer = false
        // Não perde o card de conquista/apoio dessa limpeza.
        pixCopied = false
        showSupport = true
    }

    /// Oferta proativa: "você já limpou N vezes, quer automatizar?".
    private var autoCleanOfferOverlay: some View {
        overlayCard {
            VStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 40)).foregroundStyle(.tint)
                Text(L10n.autoOfferTitle(count: manualCleanCount))
                    .font(.headline).multilineTextAlignment(.center)
                Text(L10n.autoOfferBody)
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    acceptAutoOffer()
                } label: {
                    Text(L10n.autoOfferYes).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    snoozeAutoOffer()
                } label: {
                    Text(L10n.notNow).frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: Compartilhar conquista

    /// Card 1200x675 (proporção OG/Twitter) com o quanto foi recuperado.
    private func makeShareImage(freed: Int64) -> NSImage {
        ShareCard.render { draw in
            draw(L10n.shareCardVerb, .systemFont(ofSize: 60, weight: .semibold), ShareCard.muted, 470)
            draw(fmt(freed), .systemFont(ofSize: 150, weight: .heavy), ShareCard.teal, 350)
            draw(L10n.shareCardTail, .systemFont(ofSize: 44, weight: .medium), ShareCard.ink, 190)
            draw("harbofly.app", .monospacedSystemFont(ofSize: 34, weight: .regular), ShareCard.muted, 95)
        }
    }

    private func shareAchievement() {
        Analytics.shared("achievement")
        let image = makeShareImage(freed: scanner.lastFreedBytes)
        let text = L10n.shareText(fmt(scanner.lastFreedBytes))
        showSharePicker([image, text])
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
                    manualCleanCount += 1 // alimenta a oferta proativa de auto-clean
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

                // O total em dinheiro (preço de SSD da Apple): pico de
                // gratidão é o melhor momento pro pedido de café logo abaixo.
                if Double(totalFreedBytes) * SSDPricing.perByte >= 1 {
                    Text(L10n.recapMoneyShort(fmtMoney(Double(totalFreedBytes) * SSDPricing.perByte)))
                        .font(.caption.bold()).foregroundStyle(.orange)
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

                    Picker("", selection: $feedbackType) {
                        Text(L10n.feedbackTypeBug).tag("bug")
                        Text(L10n.feedbackTypeIdea).tag("idea")
                        Text(L10n.feedbackTypeOther).tag("other")
                    }
                    .pickerStyle(.segmented).labelsHidden()

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
        let message = feedbackText, contact = feedbackContact, type = feedbackType
        Task { @MainActor in
            let ok = await Feedback.send(message: message, contact: contact, type: type)
            feedbackSending = false
            if ok {
                Analytics.feedbackSent(type: type)
                feedbackSent = true
                feedbackText = ""
                feedbackContact = ""
                feedbackType = "idea"
            } else {
                Analytics.failure("feedback")
                feedbackFailed = true
            }
        }
    }

    private func closeFeedback() {
        showFeedback = false
        feedbackSent = false
        feedbackFailed = false
    }

    /// Configuração do auto-clean (só aparece com o toggle ligado):
    /// quando, o quê, piso mínimo e a última limpeza (histórico no tooltip).
    private var autoCleanConfig: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(L10n.autoCleanWhenLabel).font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $autoCleanTrigger) {
                    Text(L10n.autoCleanEndOfDay).tag("daily")
                    Text(L10n.autoCleanStartOfDay).tag("startofday")
                    Text(L10n.autoCleanXcode).tag("xcode")
                    Text(L10n.autoCleanWeekly).tag("weekly")
                    Text(L10n.autoCleanLowDisk).tag("lowdisk")
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()

                Text(L10n.autoCleanMinLabel).font(.caption).foregroundStyle(.secondary)
                    .padding(.leading, 6)
                Picker("", selection: $autoCleanMinBytes) {
                    Text("500 MB").tag(500_000_000)
                    Text("1 GB").tag(1_000_000_000)
                    Text("5 GB").tag(5_000_000_000)
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
                Spacer()
            }
            HStack(spacing: 6) {
                Text(L10n.autoCleanScopeLabel).font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $autoCleanScope) {
                    Text(L10n.autoCleanScopeCaches).tag("caches")
                    Text(L10n.autoCleanScopeAll).tag("all")
                    Text(L10n.autoCleanScopeMax).tag("max")
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
                Spacer()
            }
            Text(L10n.autoCleanNote)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if autoCleanLastCleanTs > 0 {
                Text(L10n.autoCleanLast(
                    date: Date(timeIntervalSince1970: autoCleanLastCleanTs)
                        .formatted(date: .abbreviated, time: .shortened),
                    size: fmt(Int64(autoCleanLastBytes)),
                    count: autoCleanLastCount))
                    .font(.caption).foregroundStyle(.secondary)
                    .help(autoCleanHistoryHelp)
            } else {
                Text(L10n.autoCleanNever)
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.leading, 20)
    }

    /// Tooltip com as últimas limpezas automáticas.
    private var autoCleanHistoryHelp: String {
        let hist = UserDefaults.standard.array(forKey: Prefs.autoCleanHistory) as? [[String: Double]] ?? []
        return hist.map { e in
            let when = Date(timeIntervalSince1970: e["ts"] ?? 0)
                .formatted(date: .abbreviated, time: .shortened)
            return "\(when) — \(fmt(Int64(e["bytes"] ?? 0)))"
        }.joined(separator: "\n")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "internaldrive")
                Text(AppInfo.name).font(.headline)
                Spacer()
                if scanner.scanning || scanner.deleting { ProgressView().controlSize(.small) }
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
                    Text(t.displayLabel).font(.headline).lineLimit(1)
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
                    Text(t.displayLabel).font(.headline).lineLimit(1)
                    Spacer()
                    Text(fmt(t.bytes)).font(.headline.monospacedDigit())
                }
                Text(relPath(t.url))
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Text(t.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: 12) {
                    // A linha de purgeable aponta pro volume (home): revelar
                    // no Finder não diz nada — esconde o botão nesse caso.
                    if t.url != FileManager.default.homeDirectoryForCurrentUser {
                        Button {
                            Analytics.infoAction("revealInFinder")
                            NSWorkspace.shared.activateFileViewerSelecting([t.url])
                        } label: {
                            Label(L10n.revealInFinder, systemImage: "magnifyingglass").font(.caption)
                        }
                        .buttonStyle(.plain).foregroundStyle(.blue)
                    }

                    // Ação especial do CoreSimulator: 1 clique arma, 2º executa
                    // (simctl delete unavailable é irreversível).
                    if t.url.path.hasSuffix("Developer/CoreSimulator") {
                        Button {
                            if confirmingSimDelete {
                                confirmingSimDelete = false
                                Analytics.infoAction("deleteOldSims")
                                scanner.deleteUnavailableSimulators()
                            } else {
                                scanner.simDeleteDone = nil   // limpa feedback antigo
                                confirmingSimDelete = true
                            }
                        } label: {
                            Label(confirmingSimDelete ? L10n.deleteOldSimsConfirm : L10n.deleteOldSims,
                                  systemImage: confirmingSimDelete ? "exclamationmark.triangle.fill" : "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(confirmingSimDelete ? .red : .blue)
                    }

                    // Runtimes de simulador não usados (imagens de iOS) — 2 cliques.
                    if t.url.path.hasSuffix("Developer/CoreSimulator") {
                        Button {
                            if confirmingRuntimeDelete {
                                confirmingRuntimeDelete = false
                                Analytics.infoAction("deleteUnusedRuntimes")
                                scanner.deleteUnusedRuntimes()
                            } else {
                                scanner.runtimeDeleteDone = nil
                                confirmingRuntimeDelete = true
                            }
                        } label: {
                            Label(confirmingRuntimeDelete ? L10n.deleteRuntimesConfirm : L10n.deleteRuntimes,
                                  systemImage: confirmingRuntimeDelete ? "exclamationmark.triangle.fill" : "cpu")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(confirmingRuntimeDelete ? .red : .blue)
                    }

                    // Recuperar espaço preso por snapshots locais do TM — 2 cliques.
                    if t.canThinSnapshots {
                        Button {
                            if confirmingThinSnapshots {
                                confirmingThinSnapshots = false
                                Analytics.infoAction("thinSnapshots")
                                scanner.thinLocalSnapshots()
                            } else {
                                confirmingThinSnapshots = true
                            }
                        } label: {
                            Label(confirmingThinSnapshots ? L10n.thinSnapshotsConfirm : L10n.thinSnapshots,
                                  systemImage: confirmingThinSnapshots ? "exclamationmark.triangle.fill" : "clock.arrow.circlepath")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(confirmingThinSnapshots ? .red : .blue)
                    }

                    // Esvaziar a Lixeira de verdade — 2 cliques (irreversível).
                    if t.url.lastPathComponent == ".Trash" {
                        Button {
                            if confirmingEmptyTrash {
                                confirmingEmptyTrash = false
                                Analytics.infoAction("emptyTrash")
                                scanner.emptyTrash()
                            } else {
                                scanner.trashEmptiedBytes = nil
                                confirmingEmptyTrash = true
                            }
                        } label: {
                            Label(confirmingEmptyTrash ? L10n.emptyTrashConfirm : L10n.emptyTrash,
                                  systemImage: confirmingEmptyTrash ? "exclamationmark.triangle.fill" : "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(confirmingEmptyTrash ? .red : .blue)
                    }
                }
                .padding(.top, 2)
                // Feedback do simctl: sem isso, quando não há indisponível o
                // clique não muda nada e parece quebrado.
                if t.url.path.hasSuffix("Developer/CoreSimulator"), let n = scanner.simDeleteDone {
                    Text(n > 0 ? L10n.simDeleted(n) : L10n.simNoneToDelete)
                        .font(.caption)
                        .foregroundStyle(n > 0 ? .green : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if t.url.path.hasSuffix("Developer/CoreSimulator"), let n = scanner.runtimeDeleteDone {
                    Text(n > 0 ? L10n.runtimesDeleted(n) : L10n.runtimesNoneToDelete)
                        .font(.caption)
                        .foregroundStyle(n > 0 ? .green : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if t.url.lastPathComponent == ".Trash", let freed = scanner.trashEmptiedBytes {
                    Text(L10n.trashEmptied(fmt(freed)))
                        .font(.caption)
                        .foregroundStyle(freed > 0 ? .green : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(10)
        .background(Color.blue.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var footer: some View {
        VStack(spacing: 8) {
            HStack {
                Text(L10n.selectLabel)
                    .font(.caption).foregroundStyle(.secondary)
                Button(L10n.selectSafe) {
                    selection = Set(scanner.targets.filter { $0.tier == .safe }.map { $0.id })
                }
                .help(L10n.selectSafeHelp)
                if !staleTargets.isEmpty {
                    Button(L10n.selectStale) {
                        selection = Set(staleTargets.map { $0.id })
                    }
                    .help(L10n.selectStaleHelp)
                }
                Button {
                    selection.removeAll()
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .help(L10n.clearSelection)
                .disabled(selection.isEmpty)
                Spacer()
                if scanner.deleting {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(L10n.cleaningProgress(done: scanner.deletingDone,
                                                   total: scanner.deletingTotal))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Button {
                        Analytics.deleteClicked(mode: deletePermanently ? "permanent" : "trash",
                                                itemCount: selection.count)
                        let cats = Dictionary(grouping: selectedTargets, by: { $0.category })
                            .mapValues { $0.reduce(Int64(0)) { $0 + $1.bytes } }
                        Analytics.deleteSelected(byCategory: cats)
                        confirming = true
                    } label: {
                        Text(selection.isEmpty ? L10n.delete : L10n.deleteWithSize(fmt(selectedBytes)))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(selection.isEmpty)
                }
            }
            HStack {
                Button(L10n.rescan) { scanner.scan() }.disabled(scanner.scanning || scanner.deleting)
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
                Toggle(L10n.autoCleanToggle, isOn: $autoCleanEnabled)
                    .toggleStyle(.checkbox)
                Spacer()
            }
            if autoCleanEnabled { autoCleanConfig }
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
                    Analytics.feedbackOpened()
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
        HStack(spacing: 3) {
            Image(systemName: warn ? "internaldrive.fill" : "internaldrive")
            if let pct = freePct { Text("\(pct)%").monospacedDigit() }
        }
        .onAppear { openIfPending(); scanner.refreshDiskSpace() }
        .onChange(of: requester.pending) { _, _ in openIfPending() }
    }

    /// % de espaço livre pro label (nil antes da 1ª medição).
    private var freePct: Int? {
        guard scanner.totalBytes > 0 else { return nil }
        return Int((Double(scanner.freeBytes) / Double(scanner.totalBytes) * 100).rounded())
    }

    /// Vigia em alerta: disco baixo OU há crescimento suspeito detectado.
    private var warn: Bool {
        (scanner.totalBytes > 0 && Double(scanner.freeBytes) / Double(scanner.totalBytes) < 0.1)
            || scanner.growthCount > 0
    }

    private func openIfPending() {
        guard requester.pending else { return }
        requester.pending = false
        presentMainWindow(using: openWindow)
    }
}

@main
enum Main {
    static func main() {
        // Modo CLI: `harbofly scan|clean|version` (symlink do Homebrew ou o
        // binário dentro do .app chamado direto). Args desconhecidos (flags
        // do Finder/Xcode etc.) seguem pro app normal.
        let args = Array(CommandLine.arguments.dropFirst())
        if let cmd = args.first,
           ["scan", "clean", "dups", "duplicates", "help", "--help", "-h", "version", "--version"].contains(cmd) {
            exit(CLI.run(args))
        }
        HarboflyApp.main()
    }
}

struct HarboflyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var scanner = DiskScanner()
    @StateObject private var updater = Updater()
    // Compartilhado entre as duas cenas: preserva o resultado do scan de
    // duplicatas ao alternar barra de menu ↔ janela.
    @StateObject private var duplicates = DuplicateScanner()
    @StateObject private var uninstaller = AppUninstaller()

    var body: some Scene {
        MenuBarExtra {
            ContentView(scanner: scanner, updater: updater, duplicates: duplicates, uninstaller: uninstaller)
        } label: {
            MenuBarLabel(scanner: scanner)
        }
        .menuBarExtraStyle(.window)

        Window(AppInfo.name, id: AppInfo.mainWindowID) {
            ContentView(scanner: scanner, updater: updater, duplicates: duplicates, uninstaller: uninstaller)
                .fixedSize()
        }
        .windowResizability(.contentSize)
    }
}
