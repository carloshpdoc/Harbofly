import SwiftUI
import AppKit
import ServiceManagement

// MARK: - Config

/// Nome de exibição do app. Trocar aqui reflete na UI inteira.
enum AppInfo {
    static let name = "Harbofly"
}

/// Apoio (tip jar) — troque pelos seus dados.
enum Support {
    static let pixKey = "SUA_CHAVE_PIX@email.com"          // TODO: sua chave PIX
    static let webURL = "https://buymeacoffee.com/SEU_USER" // TODO: opcional (Buy Me a Coffee / Ko-fi)
}

// MARK: - Model

enum Tier: String {
    case safe = "Seguro (regenera sozinho)"
    case caution = "Cuidado (recria, mas custa)"
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
    @Published var justCleaned = false

    private let home = FileManager.default.homeDirectoryForCurrentUser
    private let minBytes: Int64 = 10_000_000 // ignora ruído < 10 MB

    func scan() {
        guard !scanning else { return }
        scanning = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let (free, total) = self.diskSpace()
            var found = self.scanDevelopment() + self.scanLibrary()
            found.sort { $0.bytes > $1.bytes }
            DispatchQueue.main.async {
                self.freeBytes = free
                self.totalBytes = total
                self.targets = found
                self.lastScan = Date()
                self.scanning = false
            }
        }
    }

    func delete(_ items: [CleanTarget]) {
        let toFree = items.reduce(Int64(0)) { $0 + $1.bytes }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            for item in items {
                try? FileManager.default.removeItem(at: item.url)
            }
            DispatchQueue.main.async {
                self?.lastFreedBytes = toFree
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

    private let timer = Timer.publish(every: 1800, on: .main, in: .common).autoconnect()

    private var reclaimable: Int64 { scanner.targets.reduce(0) { $0 + $1.bytes } }
    private var selectedTargets: [CleanTarget] { scanner.targets.filter { selection.contains($0.id) } }
    private var selectedBytes: Int64 { selectedTargets.reduce(0) { $0 + $1.bytes } }
    private var safeTargets: [CleanTarget] { scanner.targets.filter { $0.tier == .safe } }
    private var cautionTargets: [CleanTarget] { scanner.targets.filter { $0.tier == .caution } }
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
                Text("A exclusão é permanente (não vai pra Lixeira, pra liberar espaço na hora).")
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button(role: .destructive) {
                    let items = selectedTargets
                    selection.removeAll()
                    confirming = false
                    scanner.delete(items)
                } label: {
                    Text("Excluir permanentemente").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.red)
                Button("Cancelar") { confirming = false }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var supportOverlay: some View {
        overlayCard {
            VStack(spacing: 14) {
                Text("☕").font(.system(size: 44))
                Text(scanner.lastFreedBytes > 0 ? "Liberamos \(fmt(scanner.lastFreedBytes))!" : "Obrigado! 💙")
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
