import SwiftUI
import AppKit

// MARK: - UI do uninstaller

/// Modo "Apps": lista os apps instalados com a pegada total (bundle + rastros),
/// você seleciona e manda pra Lixeira. Reusa o padrão de confirmação do cleaner.
enum AppSort: CaseIterable { case size, lastUsed, vendor, category }

struct UninstallView: View {
    @ObservedObject var scanner: AppUninstaller

    @State private var selection = Set<UUID>()
    @State private var confirming = false
    @State private var sort: AppSort = .size
    @State private var query = ""
    @AppStorage(Prefs.language) private var language = "system"

    private var selectedApps: [InstalledApp] { scanner.apps.filter { selection.contains($0.id) } }
    private var selectedBytes: Int64 { selectedApps.reduce(0) { $0 + $1.totalBytes } }

    /// Apps ordenados pelo critério escolhido. lastUsed nil (sem dado do
    /// Spotlight) vai pro fim quando ordena por uso.
    private var sortedApps: [InstalledApp] {
        switch sort {
        case .size: return scanner.apps.sorted { $0.totalBytes > $1.totalBytes }
        case .lastUsed: return scanner.apps.sorted {
            ($0.lastUsed ?? .distantFuture) < ($1.lastUsed ?? .distantFuture) }
        case .vendor: return scanner.apps.sorted {
            $0.vendor == $1.vendor ? $0.totalBytes > $1.totalBytes : $0.vendor < $1.vendor }
        case .category: return scanner.apps.sorted {
            $0.category == $1.category ? $0.totalBytes > $1.totalBytes : $0.category < $1.category }
        }
    }

    /// Aplica a busca por texto (nome/fabricante/bundle-id) sobre a lista ordenada.
    private var visibleApps: [InstalledApp] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return sortedApps }
        return sortedApps.filter {
            $0.name.lowercased().contains(q)
                || $0.vendor.lowercased().contains(q)
                || $0.bundleID.lowercased().contains(q)
        }
    }

    private func sortLabel(_ s: AppSort) -> String {
        switch s {
        case .size: return L10n.sortSize
        case .lastUsed: return L10n.sortLastUsed
        case .vendor: return L10n.sortVendor
        case .category: return L10n.sortCategory
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.uninstallIntro).font(.caption).foregroundStyle(.secondary)

            if scanner.scanning {
                VStack(spacing: 10) {
                    Spacer()
                    ProgressView()
                    Text(L10n.scanning).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 440)
            } else if !scanner.scannedOnce {
                VStack(spacing: 12) {
                    Spacer()
                    Button(L10n.uninstallScan) { scanner.scan() }
                        .buttonStyle(.borderedProminent)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 440)
            } else if scanner.apps.isEmpty {
                Text(L10n.nothingFound).frame(maxWidth: .infinity, minHeight: 440)
            } else {
                HStack(spacing: 6) {
                    Text(L10n.sortBy).font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $sort) {
                        ForEach(AppSort.allCases, id: \.self) { Text(sortLabel($0)).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(.secondary)
                        TextField(L10n.searchApps, text: $query).textFieldStyle(.plain).frame(width: 130)
                        if !query.isEmpty {
                            Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.gray.opacity(0.12))
                    .clipShape(Capsule())
                }
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(visibleApps) { row($0) }
                    }
                    .padding(.trailing, 4)
                }
                .frame(height: 440)
                Divider()
                HStack {
                    Button(L10n.clearSelection) { selection.removeAll() }
                        .disabled(selection.isEmpty)
                    Button(L10n.rescan) { scanner.scan() }
                        .disabled(scanner.scanning || scanner.deleting)
                    Spacer()
                    if scanner.justFinished && scanner.lastFreedBytes > 0 {
                        Text(L10n.trashed(fmt(scanner.lastFreedBytes)))
                            .font(.caption).foregroundStyle(.green)
                    }
                    Button {
                        confirming = true
                    } label: {
                        Text(L10n.uninstallSelected(fmt(selectedBytes)))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedApps.isEmpty || scanner.deleting)
                }
            }
        }
        .confirmationDialog(
            L10n.uninstallConfirm(count: selectedApps.count, size: fmt(selectedBytes)),
            isPresented: $confirming, titleVisibility: .visible
        ) {
            Button(L10n.moveToTrash) {
                scanner.uninstall(selectedApps)
                selection.removeAll()
            }
            Button(L10n.cancel, role: .cancel) {}
        } message: {
            Text(L10n.uninstallConfirmNote)
        }
        .onAppear {
            if !scanner.scannedOnce && !scanner.scanning { scanner.scan() }
        }
    }

    /// "Fabricante · Categoria · N rastros" (só as partes que existem).
    private func subtitle(_ app: InstalledApp) -> String {
        var parts: [String] = [app.vendor]
        if app.category != "—" { parts.append(app.category) }
        if !app.leftovers.isEmpty { parts.append("\(app.leftovers.count) \(L10n.uninstallLeftovers)") }
        return parts.joined(separator: " · ")
    }

    /// App sem uso há 6+ meses = candidato claro a remover (padrão dos cleaners).
    private func isUnusedLong(_ date: Date) -> Bool {
        Date().timeIntervalSince(date) >= 180 * 86_400
    }

    private func row(_ app: InstalledApp) -> some View {
        let isOn = selection.contains(app.id)
        return HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.appURL.path))
                .resizable().frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).font(.body)
                Text(subtitle(app))
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                // Última vez aberto — o sinal de "app abandonado". Sem dado do
                // Spotlight = "nunca aberto" (discreto); usado há muito = laranja.
                if let used = app.lastUsed {
                    Label(L10n.lastUsedAgo(relativeAge(used)), systemImage: "clock")
                        .font(.caption2)
                        .foregroundStyle(isUnusedLong(used) ? .orange : .secondary)
                } else {
                    Label(L10n.neverOpened, systemImage: "clock")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .help(app.bundleID)
            Spacer()
            Text(fmt(app.totalBytes)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            Toggle("", isOn: Binding(
                get: { isOn },
                set: { on in if on { selection.insert(app.id) } else { selection.remove(app.id) } }
            )).labelsHidden()
        }
        .padding(8)
        .background(isOn ? Color.accentColor.opacity(0.12) : Color.gray.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture { if isOn { selection.remove(app.id) } else { selection.insert(app.id) } }
    }
}
