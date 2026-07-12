import SwiftUI
import AppKit
import QuickLookThumbnailing

// MARK: - UI de duplicatas

/// Modo "Duplicatas" do popover/janela. Vê grupos de arquivos idênticos por
/// conteúdo, com o original destacado e as cópias pré-selecionadas. Reusa o
/// mesmo padrão de confirmação e o `delete(permanently:)` do cleaner.
struct DuplicatesView: View {
    @ObservedObject var scanner: DuplicateScanner

    /// Pastas a escanear. Começa nos presets pessoais que existem; o usuário
    /// adiciona/remove via chips + NSOpenPanel.
    @State private var roots: [URL] = DuplicatesView.defaultRoots()
    @State private var selection = Set<UUID>()
    @State private var confirming = false
    @State private var hasScanned = false

    @AppStorage(Prefs.deletePermanently) private var deletePermanently = false
    @AppStorage(Prefs.language) private var language = "system"

    private static func defaultRoots() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ["Downloads", "Documents", "Desktop", "Pictures"]
            .map { home.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    // Derivados
    private var allCopies: [DuplicateFile] { scanner.groups.flatMap { $0.removable } }
    private var selectedFiles: [DuplicateFile] { allCopies.filter { selection.contains($0.id) } }
    private var selectedBytes: Int64 { selectedFiles.reduce(0) { $0 + $1.size } }

    private func relPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.replacingOccurrences(of: home, with: "~")
    }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 8) {
                dupHeader
                foldersRow
                Divider()
                listSection
                Divider()
                footer
            }
            .disabled(confirming)

            if confirming { confirmOverlay }
        }
        .onChange(of: scanner.scanning) { _, now in
            if !now { preselect() }         // scan terminou: marca as cópias
        }
        .onChange(of: scanner.justFinished) { _, done in
            if done { scanner.justFinished = false; preselect() }
        }
        .onAppear { if !scanner.groups.isEmpty { hasScanned = true; preselect() } }
    }

    /// Pré-seleciona todas as cópias (nunca os originais).
    private func preselect() {
        selection = Set(allCopies.map { $0.id })
    }

    // MARK: header

    private var dupHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "doc.on.doc")
                Text(L10n.dupTitle).font(.headline)
                Spacer()
                if scanner.scanning || scanner.deleting { ProgressView().controlSize(.small) }
            }
            HStack {
                Text(L10n.dupVerifiedNote)
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if scanner.totalReclaimable > 0 {
                    Text(L10n.reclaimable(fmt(scanner.totalReclaimable)))
                        .font(.caption).bold().foregroundStyle(.green)
                }
            }
        }
    }

    private var foldersRow: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(roots, id: \.self) { chip($0) }
                }
            }
            Button {
                addFolder()
            } label: {
                Image(systemName: "folder.badge.plus")
            }
            .buttonStyle(.plain).foregroundStyle(.blue)
            .help(L10n.dupAddFolder)

            Button(hasScanned ? L10n.rescan : L10n.dupFind) { runScan() }
                .buttonStyle(.borderedProminent)
                .disabled(roots.isEmpty || scanner.scanning || scanner.deleting)
        }
    }

    private func chip(_ url: URL) -> some View {
        HStack(spacing: 4) {
            Text(url.lastPathComponent).font(.caption).lineLimit(1)
            Button {
                roots.removeAll { $0 == url }
            } label: {
                Image(systemName: "xmark.circle.fill").font(.caption2)
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .help(L10n.dupRemoveFolder)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(Color.primary.opacity(0.08)))
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = L10n.dupAddFolder
        guard panel.runModal() == .OK else { return }
        for u in panel.urls where !roots.contains(u) { roots.append(u) }
    }

    private func runScan() {
        hasScanned = true
        selection.removeAll()
        scanner.scan(roots: roots)
    }

    // MARK: lista

    private var listSection: some View {
        Group {
            if scanner.scanning {
                VStack(spacing: 8) {
                    // Fase 3 (hashing) tem contagem → barra determinística;
                    // as demais fases seguem com spinner indeterminado.
                    if case let .hashing(done, total) = scanner.phase, total > 0 {
                        ProgressView(value: Double(done), total: Double(total))
                            .frame(width: 220)
                    } else {
                        ProgressView()
                    }
                    Text(scanner.phase.map { L10n.dupPhaseText($0) } ?? L10n.scanning)
                        .font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 320)
            } else if scanner.groups.isEmpty {
                Text(hasScanned ? L10n.dupEmpty : L10n.dupIntro)
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 320)
                    .padding(.horizontal, 20)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(scanner.groups) { groupCard($0) }
                    }
                    .padding(.trailing, 4)
                }
                .frame(height: 360)
            }
        }
    }

    private func groupCard(_ g: DuplicateGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(L10n.dupGroupHeader(size: fmt(g.size), count: g.files.count))
                    .font(.subheadline.bold())
                Spacer()
                Text(L10n.dupReclaim(fmt(g.reclaimable)))
                    .font(.caption.monospacedDigit()).foregroundStyle(.green)
            }
            ForEach(g.files) { fileRow($0) }
        }
        .padding(10)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func fileRow(_ f: DuplicateFile) -> some View {
        let picked = selection.contains(f.id)
        return HStack(spacing: 10) {
            if f.isKeeper {
                Image(systemName: "star.fill").foregroundStyle(.green).frame(width: 22)
            } else {
                Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(picked ? Color.accentColor : .secondary)
                    .frame(width: 22)
            }
            FileThumb(url: f.url, side: 44)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(f.url.lastPathComponent).font(.headline).lineLimit(1)
                    if f.isKeeper {
                        Text(L10n.dupKeep)
                            .font(.caption2.bold()).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(.green))
                            .help(L10n.dupKeepWhy)
                    }
                    Spacer()
                }
                Text(relPath(f.url))
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([f.url])
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.plain).foregroundStyle(.blue)
            .help(L10n.revealInFinder)
        }
        .padding(6)
        .background(f.isKeeper ? Color.green.opacity(0.08)
                    : (picked ? Color.accentColor.opacity(0.12) : Color.clear))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture {
            guard !f.isKeeper else { return }   // guard: original nunca entra na seleção
            if picked { selection.remove(f.id) } else { selection.insert(f.id) }
        }
    }

    // MARK: footer

    private var footer: some View {
        HStack {
            Text(L10n.selectLabel).font(.caption).foregroundStyle(.secondary)
            Button(L10n.dupSelectAll) { preselect() }
                .help(L10n.dupSelectAllHelp)
                .disabled(allCopies.isEmpty)
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
                    confirming = true
                } label: {
                    Text(selection.isEmpty ? L10n.delete : L10n.deleteWithSize(fmt(selectedBytes)))
                }
                .buttonStyle(.borderedProminent).tint(.red)
                .disabled(selection.isEmpty)
            }
        }
    }

    // MARK: overlay de confirmação

    private var confirmOverlay: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 14) {
                Text(L10n.dupConfirmTitle(count: selectedFiles.count, size: fmt(selectedBytes)))
                    .font(.headline).multilineTextAlignment(.center)

                Picker("", selection: $deletePermanently) {
                    Text(L10n.moveToTrash).tag(false)
                    Text(L10n.deleteForever).tag(true)
                }
                .pickerStyle(.segmented).labelsHidden()

                Text(deletePermanently ? L10n.permanentExplainer : L10n.trashExplainer)
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button(role: .destructive) {
                    let files = selectedFiles
                    let perm = deletePermanently
                    selection.removeAll()
                    confirming = false
                    scanner.delete(files, permanently: perm)
                } label: {
                    Text(deletePermanently ? L10n.deletePermanentlyBtn : L10n.moveToTrash)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(deletePermanently ? .red : .accentColor)

                Button(L10n.cancel) { confirming = false }
                    .buttonStyle(.bordered)
            }
            .padding(22)
            .frame(width: 320)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 24)
        }
    }
}

// MARK: - Miniatura

/// Thumbnail de arquivo via QuickLook (o mesmo preview do Finder), com cache em
/// memória e fallback pro ícone de tipo enquanto carrega/quando não há preview.
struct FileThumb: View {
    let url: URL
    let side: CGFloat
    @State private var image: NSImage?

    private static let cache = NSCache<NSURL, NSImage>()

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06))
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable().aspectRatio(contentMode: .fit).padding(6)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: url) { image = await Self.thumbnail(for: url, side: side) }
    }

    private static func thumbnail(for url: URL, side: CGFloat) async -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let req = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: side, height: side),
            scale: scale, representationTypes: .thumbnail)
        return await withCheckedContinuation { cont in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { rep, _ in
                if let ns = rep?.nsImage {
                    cache.setObject(ns, forKey: url as NSURL)
                    cont.resume(returning: ns)
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }
}
