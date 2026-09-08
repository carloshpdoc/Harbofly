import Foundation

// MARK: - Itens de inicialização (Login Items / Launch Agents)

/// Um item que sobe sozinho no login/background. v0: só os LaunchAgents do
/// usuário (~/Library/LaunchAgents) são ativáveis/desativáveis (sem admin);
/// os globais/daemons são só-leitura (mexer neles pede root — fora do escopo).
struct StartupItem: Identifiable {
    let id = UUID()
    let label: String        // Label do launchd
    let name: String         // nome amigável
    let program: String      // o que ele executa (path/1º arg)
    let plistURL: URL        // localização atual do .plist
    let scope: Scope
    var enabled: Bool        // true = em LaunchAgents; false = na pasta de desativados
    enum Scope { case userAgent, globalAgent, daemon }
    /// Só os agentes do usuário podem ser ligados/desligados sem admin.
    var canToggle: Bool { scope == .userAgent }
}

/// Lista os itens de inicialização e liga/desliga os do usuário movendo o .plist
/// pra uma pasta gerenciada (reversível — nunca apaga). Efeito pleno no próximo
/// login; `launchctl` é chamado best-effort pra parar/subir já.
final class StartupManager: ObservableObject {
    @Published var items: [StartupItem] = []
    @Published var scanning = false
    @Published var scannedOnce = false

    private let home = FileManager.default.homeDirectoryForCurrentUser
    private var userAgents: URL { home.appendingPathComponent("Library/LaunchAgents") }
    /// Onde os desativados ficam guardados (fora de LaunchAgents, então não sobem).
    private var disabledDir: URL {
        home.appendingPathComponent("Library/Application Support/Harbofly/DisabledAgents")
    }

    func scan() {
        guard !scanning else { return }
        scanning = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let found = self?.collect() ?? []
            DispatchQueue.main.async {
                self?.items = found
                self?.scannedOnce = true
                self?.scanning = false
            }
        }
    }

    /// Liga/desliga um agente do usuário movendo o .plist. Reversível.
    func setEnabled(_ item: StartupItem, _ on: Bool) {
        guard item.canToggle, item.enabled != on else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: disabledDir, withIntermediateDirectories: true)
        let name = item.plistURL.lastPathComponent
        let dest = (on ? userAgents : disabledDir).appendingPathComponent(name)
        do {
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.moveItem(at: item.plistURL, to: dest)
        } catch { return }
        // best-effort: aplica já nesta sessão (efeito pleno mesmo é no próximo login)
        launchctl(on ? "bootstrap" : "bootout", plist: dest)
        scan()
    }

    // MARK: private

    private func launchctl(_ verb: String, plist: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = [verb, "gui/\(getuid())", plist.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }

    private func collect() -> [StartupItem] {
        var out: [StartupItem] = []
        // 1) agentes do usuário — ativos
        out += plists(in: userAgents).map { parse($0, scope: .userAgent, enabled: true) }
        // 2) agentes do usuário — desativados por nós
        out += plists(in: disabledDir).map { parse($0, scope: .userAgent, enabled: false) }
        // 3) globais e daemons — só leitura
        out += plists(in: URL(fileURLWithPath: "/Library/LaunchAgents"))
            .map { parse($0, scope: .globalAgent, enabled: true) }
        out += plists(in: URL(fileURLWithPath: "/Library/LaunchDaemons"))
            .map { parse($0, scope: .daemon, enabled: true) }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func plists(in dir: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]))?
            .filter { $0.pathExtension == "plist" } ?? []
    }

    private func parse(_ url: URL, scope: StartupItem.Scope, enabled: Bool) -> StartupItem {
        let d = NSDictionary(contentsOf: url)
        let label = (d?["Label"] as? String) ?? url.deletingPathExtension().lastPathComponent
        let program = (d?["Program"] as? String)
            ?? (d?["ProgramArguments"] as? [String])?.first
            ?? "—"
        return StartupItem(label: label, name: friendlyName(label: label, program: program),
                           program: program, plistURL: url, scope: scope, enabled: enabled)
    }

    /// Nome amigável: se o programa aponta pra um .app, usa o nome do app;
    /// senão, o último segmento do label reverse-DNS.
    private func friendlyName(label: String, program: String) -> String {
        if let r = program.range(of: ".app", options: .backwards) {
            let appPath = String(program[..<r.upperBound])
            return (appPath as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
        }
        let seg = label.split(separator: ".").last.map(String.init) ?? label
        return seg.prefix(1).uppercased() + seg.dropFirst()
    }
}
