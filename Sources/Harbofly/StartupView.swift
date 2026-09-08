import SwiftUI
import AppKit

// MARK: - UI dos itens de inicialização

/// Aba "Início": lista o que sobe sozinho no login/background. Os agentes do
/// usuário têm toggle (desativar = tira do próximo login, reversível); os do
/// sistema são só-leitura (revelar no Finder).
struct StartupView: View {
    @ObservedObject var scanner: StartupManager

    @State private var query = ""
    @AppStorage(Prefs.language) private var language = "system"

    private var userItems: [StartupItem] { scanner.items.filter { $0.scope == .userAgent }.filter(match) }
    private var systemItems: [StartupItem] { scanner.items.filter { $0.scope != .userAgent }.filter(match) }

    private func match(_ i: StartupItem) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return true }
        return i.name.lowercased().contains(q) || i.program.lowercased().contains(q)
            || i.label.lowercased().contains(q)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.startupIntro).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if scanner.scanning {
                VStack(spacing: 10) { Spacer(); ProgressView()
                    Text(L10n.scanning).font(.caption).foregroundStyle(.secondary); Spacer() }
                    .frame(maxWidth: .infinity, minHeight: 440)
            } else if !scanner.scannedOnce {
                VStack(spacing: 12) { Spacer()
                    Button(L10n.startupScan) { scanner.scan() }.buttonStyle(.borderedProminent)
                    Spacer() }.frame(maxWidth: .infinity, minHeight: 440)
            } else if scanner.items.isEmpty {
                Text(L10n.nothingFound).frame(maxWidth: .infinity, minHeight: 440)
            } else {
                HStack {
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(.secondary)
                        TextField(L10n.searchApps, text: $query).textFieldStyle(.plain).frame(width: 150)
                        if !query.isEmpty {
                            Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.gray.opacity(0.12)).clipShape(Capsule()).fixedSize()
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        if !userItems.isEmpty {
                            groupHeader(L10n.startupUserGroup, userItems.count)
                            ForEach(userItems) { userRow($0) }
                        }
                        if !systemItems.isEmpty {
                            groupHeader(L10n.startupSystemGroup, systemItems.count)
                            ForEach(systemItems) { systemRow($0) }
                        }
                    }
                    .padding(.trailing, 4)
                }
                .frame(height: 440)
                Divider()
                HStack {
                    Button(L10n.rescan) { scanner.scan() }.disabled(scanner.scanning)
                    Spacer()
                }
            }
        }
        .onAppear { if !scanner.scannedOnce && !scanner.scanning { scanner.scan() } }
    }

    private func groupHeader(_ title: String, _ count: Int) -> some View {
        Text("\(title) · \(count)").font(.caption.bold()).foregroundStyle(.secondary)
            .padding(.top, 6)
    }

    private func userRow(_ item: StartupItem) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(item.name).font(.body)
                    if !item.enabled {
                        Text(L10n.startupDisabled).font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                Text(item.program).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            .help(item.label)
            Spacer()
            Toggle("", isOn: Binding(
                get: { item.enabled },
                set: { scanner.setEnabled(item, $0) }
            )).labelsHidden()
        }
        .padding(8)
        .background(item.enabled ? Color.gray.opacity(0.06) : Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func systemRow(_ item: StartupItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.body)
                Text(item.program).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            .help(item.label)
            Spacer()
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.plistURL])
            } label: {
                Label(L10n.revealInFinder, systemImage: "magnifyingglass").font(.caption)
            }
            .buttonStyle(.plain).foregroundStyle(.blue)
        }
        .padding(8)
        .background(Color.gray.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
