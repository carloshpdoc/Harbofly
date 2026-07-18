import Foundation
import AppKit

// MARK: - App uninstaller

/// Um app instalado com sua "pegada" completa: o bundle + todos os rastros
/// espalhados (Application Support, Containers, Caches, Preferences, saved
/// state, launch agents…) — o que o macOS deixa pra trás ao arrastar pro lixo.
struct InstalledApp: Identifiable {
    let id = UUID()
    let name: String
    let bundleID: String
    let appURL: URL
    let appBytes: Int64
    /// Rastros que existem no disco (fora o bundle).
    let leftovers: [URL]
    let leftoverBytes: Int64
    var totalBytes: Int64 { appBytes + leftoverBytes }
    /// Tudo que vai pra Lixeira ao desinstalar: bundle + rastros.
    var allPaths: [URL] { [appURL] + leftovers }
}

/// Lista os apps instalados e mede a pegada de cada um. Desinstalar manda o
/// bundle + rastros pra Lixeira (sempre reversível — nunca exclusão permanente).
final class AppUninstaller: ObservableObject {
    @Published var apps: [InstalledApp] = []
    @Published var scanning = false
    @Published var deleting = false
    @Published var lastFreedBytes: Int64 = 0
    @Published var justFinished = false
    /// Já escaneou ao menos 1x nesta sessão. Vive no objeto (não na View) porque
    /// o MenuBarExtra recria a View ao re-renderizar e zeraria um @State.
    @Published var scannedOnce = false

    private let home = FileManager.default.homeDirectoryForCurrentUser

    func scan() {
        guard !scanning, !deleting else { return }
        scanning = true
        justFinished = false
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let found = self?.collect() ?? []
            DispatchQueue.main.async {
                self?.apps = found
                self?.scannedOnce = true
                self?.scanning = false
            }
        }
    }

    /// Manda pra Lixeira o app + todos os rastros. Reversível (dá pra restaurar
    /// da Lixeira) — coerente com a promessa do app.
    func uninstall(_ selected: [InstalledApp]) {
        guard !selected.isEmpty, !deleting else { return }
        deleting = true
        let urls = selected.flatMap { $0.allPaths }
        let freed = selected.reduce(Int64(0)) { $0 + $1.totalBytes }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            for url in urls {
                try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
            }
            DispatchQueue.main.async {
                self?.lastFreedBytes = freed
                self?.justFinished = true
                self?.deleting = false
                self?.scan()
            }
        }
    }

    // MARK: private

    private func collect() -> [InstalledApp] {
        let dirs = ["/Applications", "/Applications/Utilities",
                    home.appendingPathComponent("Applications").path]
        let fm = FileManager.default
        var out: [InstalledApp] = []
        for dir in dirs {
            guard let apps = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for app in apps where app.hasSuffix(".app") {
                let appURL = URL(fileURLWithPath: "\(dir)/\(app)")
                guard let d = NSDictionary(contentsOfFile: "\(dir)/\(app)/Contents/Info.plist"),
                      let bundleID = d["CFBundleIdentifier"] as? String else { continue }
                let name = (app as NSString).deletingPathExtension
                let leftovers = leftoverPaths(bundleID: bundleID, name: name)
                let appBytes = size(of: appURL)
                let leftoverBytes = leftovers.reduce(Int64(0)) { $0 + size(of: $1) }
                out.append(InstalledApp(name: name, bundleID: bundleID, appURL: appURL,
                                        appBytes: appBytes, leftovers: leftovers,
                                        leftoverBytes: leftoverBytes))
            }
        }
        return out.sorted { $0.totalBytes > $1.totalBytes }
    }

    /// Rastros conhecidos de um app (padrão AppCleaner): por bundle-id e por nome,
    /// nos ~12 lugares onde o macOS espalha dados de app. Só retorna o que existe.
    private func leftoverPaths(bundleID: String, name: String) -> [URL] {
        let fm = FileManager.default
        let rels = [
            "Library/Application Support/\(bundleID)",
            "Library/Application Support/\(name)",
            "Library/Containers/\(bundleID)",
            "Library/Caches/\(bundleID)",
            "Library/Caches/\(name)",
            "Library/Preferences/\(bundleID).plist",
            "Library/Saved Application State/\(bundleID).savedState",
            "Library/HTTPStorages/\(bundleID)",
            "Library/WebKit/\(bundleID)",
            "Library/Logs/\(name)",
            "Library/Cookies/\(bundleID).binarycookies",
            "Library/Application Scripts/\(bundleID)",
            "Library/LaunchAgents/\(bundleID).plist",
        ]
        var out: [URL] = []
        for rel in rels {
            let url = home.appendingPathComponent(rel)
            if fm.fileExists(atPath: url.path) { out.append(url) }
        }
        // Group Containers: pastas TEAMID.<bundle-id> — casa por conter o bundle-id.
        let groups = home.appendingPathComponent("Library/Group Containers")
        if let items = try? fm.contentsOfDirectory(
            at: groups, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for g in items where g.lastPathComponent.contains(bundleID) { out.append(g) }
        }
        return out
    }

    /// Tamanho de um arquivo solto (plist/cookies) OU de uma pasta (recursivo).
    private func size(of url: URL) -> Int64 {
        let rv = try? url.resourceValues(forKeys: [.isDirectoryKey, .totalFileAllocatedSizeKey])
        if rv?.isDirectory != true {
            return Int64(rv?.totalFileAllocatedSize ?? 0)
        }
        guard let en = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
            options: []) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in en {
            if let v = try? f.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]) {
                total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
            }
        }
        return total
    }
}
