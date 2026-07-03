import SwiftUI
import AppKit
import ServiceManagement
import UserNotifications

// MARK: - Config

/// Nome de exibição do app. Trocar aqui reflete na UI inteira.
enum AppInfo {
    static let name = "Harbofly"
}

/// Apoio (tip jar).
enum Support {
    static let pixKey = "1570c17b-7e20-4258-8ad8-f83f15250502"
    static let webURL = "https://ko-fi.com/carloshperc"
}

/// Chaves de preferência (UserDefaults / @AppStorage).
enum Prefs {
    static let deletePermanently = "deletePermanently"
    static let notifyEnabled = "notifyEnabled"
    static let notifyThreshold = "notifyThreshold"
    static let defaultThreshold = 0.10
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
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let (free, total) = self.diskSpace()
            var found = self.scanDevelopment() + self.scanLibrary() + self.scanInfo()
            found.sort { $0.bytes > $1.bytes }
            DispatchQueue.main.async {
                self.freeBytes = free
                self.totalBytes = total
                self.targets = found
                self.lastScan = Date()
                self.scanning = false
                self.checkLowSpaceNotification()
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
            for item in deletable {
                if permanently {
                    if (try? FileManager.default.removeItem(at: item.url)) != nil { freed += item.bytes }
                } else {
                    if (try? FileManager.default.trashItem(at: item.url, resultingItemURL: nil)) != nil { freed += item.bytes }
                }
            }
            DispatchQueue.main.async {
                self?.lastFreedBytes = freed
                self?.lastDeletePermanent = permanently
                self?.justCleaned = true
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
                        let project = item.deletingLastPathComponent().lastPathComponent
                        out.append(CleanTarget(
                            url: item,
                            label: "\(project)/\(item.lastPathComponent)",
                            detail: "Artifact de build — regenera no próximo build",
                            tier: .safe,
                            bytes: b
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

    /// Alvos conhecidos de ~/Library (dev caches).
    private func scanLibrary() -> [CleanTarget] {
        let lib = home.appendingPathComponent("Library")
        let specs: [(String, Tier, String)] = [
            ("Developer/Xcode/DerivedData", .safe, "Intermediários de build do Xcode"),
            ("Developer/Xcode/iOS DeviceSupport", .caution, "Símbolos de devices — recria ao conectar iPhone"),
            ("Developer/XcodeBuildMCP/workspaces", .safe, "Workspaces do XcodeBuildMCP"),
            ("Caches/org.swift.swiftpm", .safe, "Cache do Swift Package Manager"),
            ("Caches/Homebrew", .safe, "Downloads do Homebrew"),
            ("Caches/Yarn", .safe, "Cache do Yarn"),
            ("Caches/ms-playwright", .caution, "Browsers baixados pelo Playwright"),
            ("Caches/pip", .safe, "Cache do pip"),
            ("Caches/Google", .caution, "Cache do Google/Chrome"),
        ]
        var out: [CleanTarget] = []
        for (rel, tier, detail) in specs {
            let url = lib.appendingPathComponent(rel)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let b = size(of: url)
            if b > minBytes {
                out.append(CleanTarget(url: url, label: url.lastPathComponent, detail: detail, tier: tier, bytes: b))
            }
        }
        return out
    }

    /// Tier informativo (só leitura): pastas grandes que o app NÃO apaga, mas
    /// mostra pra você saber onde o espaço está e agir manualmente.
    private func scanInfo() -> [CleanTarget] {
        let specs: [(String, String, String)] = [
            ("Library/Developer/CoreSimulator", "CoreSimulator",
             "Simuladores do Xcode — apague devices velhos pelo Xcode ou `xcrun simctl delete unavailable`"),
            ("Library/Application Support", "Application Support",
             "Dados de apps instalados — revise pelo Finder, não apague às cegas"),
            ("Downloads", "Downloads",
             "Sua pasta de downloads — revise e limpe manualmente pelo Finder"),
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
        content.title = "\(AppInfo.name): disco quase cheio"
        content.body = "Só \(Int(ratio * 100))% livre (\(fmt(freeBytes))). Abra o \(AppInfo.name) pra liberar espaço."
        content.sound = .default
        let req = UNNotificationRequest(identifier: "harbofly.lowspace", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}

// MARK: - UI

struct ContentView: View {
    @ObservedObject var scanner: DiskScanner
    @Environment(\.openWindow) private var openWindow
    @State private var selection = Set<UUID>()
    @State private var confirming = false
    @State private var launchAtLogin = false
    @State private var showSupport = false
    @State private var pixCopied = false

    @AppStorage(Prefs.deletePermanently) private var deletePermanently = false
    @AppStorage(Prefs.notifyEnabled) private var notifyEnabled = true
    @AppStorage(Prefs.notifyThreshold) private var notifyThreshold = Prefs.defaultThreshold

    private let timer = Timer.publish(every: 1800, on: .main, in: .common).autoconnect()

    // Recuperável = só o que o app realmente apaga (exclui o tier informativo).
    private var reclaimable: Int64 { scanner.targets.filter { !$0.tier.isReadOnly }.reduce(0) { $0 + $1.bytes } }
    private var selectedTargets: [CleanTarget] { scanner.targets.filter { selection.contains($0.id) } }
    private var selectedBytes: Int64 { selectedTargets.reduce(0) { $0 + $1.bytes } }
    private var safeTargets: [CleanTarget] { scanner.targets.filter { $0.tier == .safe } }
    private var cautionTargets: [CleanTarget] { scanner.targets.filter { $0.tier == .caution } }
    private var infoTargets: [CleanTarget] { scanner.targets.filter { $0.tier == .info } }
    private var freeRatio: Double {
        scanner.totalBytes > 0 ? Double(scanner.freeBytes) / Double(scanner.totalBytes) : 1
    }

    private func relPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.replacingOccurrences(of: home, with: "~")
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
            .disabled(confirming || showSupport)

            if confirming { confirmOverlay }
            if showSupport { supportOverlay }
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
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
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

    private var confirmOverlay: some View {
        overlayCard {
            VStack(spacing: 14) {
                Text("Excluir \(selectedTargets.count) item(ns) — \(fmt(selectedBytes))?")
                    .font(.headline).multilineTextAlignment(.center)

                Picker("", selection: $deletePermanently) {
                    Text("Mover pra Lixeira").tag(false)
                    Text("Excluir de vez").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(deletePermanently
                     ? "Exclusão permanente: libera o espaço na hora, sem passar pela Lixeira. Não dá pra desfazer."
                     : "Vai pra Lixeira: dá pra recuperar, mas o espaço só é liberado ao esvaziar a Lixeira.")
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button(role: .destructive) {
                    let items = selectedTargets
                    let perm = deletePermanently
                    selection.removeAll()
                    confirming = false
                    scanner.delete(items, permanently: perm)
                } label: {
                    Text(deletePermanently ? "Excluir permanentemente" : "Mover pra Lixeira")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(deletePermanently ? .red : .accentColor)
                Button("Cancelar") { confirming = false }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var supportOverlay: some View {
        overlayCard {
            VStack(spacing: 14) {
                Text("☕").font(.system(size: 44))
                Text(scanner.lastFreedBytes > 0
                     ? (scanner.lastDeletePermanent
                        ? "Liberamos \(fmt(scanner.lastFreedBytes))!"
                        : "\(fmt(scanner.lastFreedBytes)) pra Lixeira!")
                     : "Obrigado! 💙")
                    .font(.title3.bold())
                Text("\(AppInfo.name) é grátis. Se te ajudou, me paga um café (R$2) pra apoiar o projeto 💙")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    copyPix()
                } label: {
                    Label(pixCopied ? "Chave PIX copiada!" : "Copiar chave PIX (R$2)",
                          systemImage: pixCopied ? "checkmark.circle.fill" : "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                if let url = URL(string: Support.webURL) {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label("Buy Me a Coffee", systemImage: "safari").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                Button("Talvez depois") { showSupport = false }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
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
                .help("Abrir em janela")
            }
            ProgressView(value: 1 - freeRatio)
                .tint(freeRatio < 0.1 ? .red : (freeRatio < 0.2 ? .orange : .accentColor))
            HStack {
                Text("\(fmt(scanner.freeBytes)) livre de \(fmt(scanner.totalBytes))")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("Recuperável: \(fmt(reclaimable))")
                    .font(.caption).bold()
                    .foregroundStyle(reclaimable > 0 ? .green : .secondary)
            }
        }
    }

    private var listSection: some View {
        Group {
            if scanner.targets.isEmpty {
                Text(scanner.scanning ? "Escaneando…" : "Nada relevante encontrado 🎉")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        if !safeTargets.isEmpty {
                            tierHeader("🟢 Seguro — regenera sozinho", safeTargets)
                            ForEach(safeTargets) { row($0) }
                        }
                        if !cautionTargets.isEmpty {
                            tierHeader("🟡 Cuidado — recria, mas custa", cautionTargets)
                            ForEach(cautionTargets) { row($0) }
                        }
                        if !infoTargets.isEmpty {
                            tierHeader("🔵 Informativo — só pra você saber (o app não apaga)", infoTargets)
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
                    Label("Revelar no Finder", systemImage: "magnifyingglass").font(.caption)
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
                Button("Selecionar seguros") {
                    selection = Set(scanner.targets.filter { $0.tier == .safe }.map { $0.id })
                }
                Button("Limpar seleção") { selection.removeAll() }
                    .disabled(selection.isEmpty)
                Spacer()
                Button {
                    confirming = true
                } label: {
                    Text(selection.isEmpty ? "Excluir" : "Excluir (\(fmt(selectedBytes)))")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(selection.isEmpty)
            }
            HStack {
                Button("Rescan") { scanner.scan() }.disabled(scanner.scanning)
                if let d = scanner.lastScan {
                    Text("Atualizado \(d.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Sair") { NSApp.terminate(nil) }
            }
            Divider()
            HStack(spacing: 6) {
                Toggle("Avisar quando o disco livre cair abaixo de", isOn: $notifyEnabled)
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
                Toggle("Abrir no login", isOn: $launchAtLogin)
                    .toggleStyle(.checkbox)
                    .onChange(of: launchAtLogin) { _, on in setLoginItem(on) }
                Spacer()
                Button {
                    scanner.lastFreedBytes = 0
                    pixCopied = false
                    showSupport = true
                } label: {
                    Label("Apoiar ☕", systemImage: "heart").font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.pink)
            }
        }
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // menu bar only, sem dock
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}

@main
struct HarboflyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var scanner = DiskScanner()

    var body: some Scene {
        MenuBarExtra {
            ContentView(scanner: scanner)
        } label: {
            Image(systemName: lowSpace ? "internaldrive.fill" : "internaldrive")
        }
        .menuBarExtraStyle(.window)

        Window(AppInfo.name, id: "main") {
            ContentView(scanner: scanner)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minHeight: 620)
        }
        .windowResizability(.contentSize)
    }

    private var lowSpace: Bool {
        scanner.totalBytes > 0 && Double(scanner.freeBytes) / Double(scanner.totalBytes) < 0.1
    }
}
