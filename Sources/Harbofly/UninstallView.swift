import SwiftUI
import AppKit

// MARK: - UI do uninstaller

/// Modo "Apps": lista os apps instalados com a pegada total (bundle + rastros),
/// você seleciona e manda pra Lixeira. Reusa o padrão de confirmação do cleaner.
struct UninstallView: View {
    @ObservedObject var scanner: AppUninstaller

    @State private var selection = Set<UUID>()
    @State private var confirming = false
    @AppStorage(Prefs.language) private var language = "system"

    private var selectedApps: [InstalledApp] { scanner.apps.filter { selection.contains($0.id) } }
    private var selectedBytes: Int64 { selectedApps.reduce(0) { $0 + $1.totalBytes } }

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
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(scanner.apps) { row($0) }
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

    private func row(_ app: InstalledApp) -> some View {
        let isOn = selection.contains(app.id)
        return HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.appURL.path))
                .resizable().frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).font(.body)
                Text(app.leftovers.isEmpty
                     ? app.bundleID
                     : "\(app.bundleID) · \(app.leftovers.count) \(L10n.uninstallLeftovers)")
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
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
