import SwiftUI
import AppKit

// MARK: - Janela "Discos"

/// Modo de trabalho da janela: ver o que há num disco, ou comparar um disco
/// contra os outros montados.
enum VolumesMode: String, CaseIterable {
    case inventory, compare
}

/// Linha da tabela. Embrulha a linha do motor com os campos derivados que a
/// `Table` precisa ordenar (KeyPathComparator exige Comparable, e `URL` não é).
struct VolRow: Identifiable {
    let id: UUID
    let source: CrossVolumeRow
    let relPath: String
    let folder: String
    let ext: String
    var size: Int64 { source.size }
    var copies: Int { source.copies }
    var keeperVolume: String { source.keeperVolume }
    var modified: Date { source.modified }
    var atRisk: Bool { source.lastBackupOfMedia }
}

struct VolumesView: View {
    @ObservedObject var indexer: VolumeIndexer
    @ObservedObject var cross: CrossVolumeScanner

    @State private var volumes: [MountedVolume] = []
    @State private var selectedVolume: MountedVolume?
    @State private var mode: VolumesMode = .inventory
    @State private var selection = Set<UUID>()
    @State private var sortOrder = [KeyPathComparator(\VolRow.size, order: .reverse)]
    @State private var search = ""
    @State private var minSizeMB = 0.0
    @State private var folderFilter: String?
    @State private var extFilter: String?
    @State private var confirming = false
    @State private var showInternal = false
    @State private var barsOpen = true

    @AppStorage(Prefs.deletePermanently) private var deletePermanently = false
    @AppStorage(Prefs.language) private var language = "system"

    var body: some View {
        HStack(spacing: 0) {
            volumeList
                .frame(width: 250)
            Divider()
            detail
                .frame(minWidth: 620)
        }
        .frame(minWidth: 900, minHeight: 560)
        .onAppear(perform: reloadVolumes)
        .overlay { if confirming { confirmOverlay } }
    }

    // MARK: lista de volumes

    private var volumeList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "externaldrive.connected.to.line.below")
                Text(L10n.volumesTitle).font(.headline)
                Spacer()
                Button {
                    reloadVolumes()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain).help(L10n.volReload)
            }
            .padding(10)
            Divider()
            if volumes.isEmpty {
                Text(L10n.volNoVolumes)
                    .font(.callout).foregroundStyle(.secondary)
                    .padding(14)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(volumes) { volumeCard($0) }
                    }
                    .padding(8)
                }
            }
        }
        .background(Color.primary.opacity(0.03))
    }

    private func volumeCard(_ v: MountedVolume) -> some View {
        let picked = selectedVolume?.id == v.id
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: icon(v))
                    .foregroundStyle(picked ? Color.accentColor : .secondary)
                Text(v.name).font(.subheadline.bold()).lineLimit(1)
                Spacer()
                Text(v.fsType).font(.caption2.monospaced()).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    Capsule()
                        .fill(v.usedRatio > 0.9 ? Color.red
                              : (v.usedRatio > 0.8 ? Color.orange : Color.accentColor))
                        .frame(width: max(2, geo.size.width * v.usedRatio))
                }
            }
            .frame(height: 5)
            Text(L10n.volFreeOf(free: fmt(v.free), total: fmt(v.total)))
                .font(.caption2).foregroundStyle(.secondary)
            if !badges(v).isEmpty {
                HStack(spacing: 4) {
                    ForEach(badges(v), id: \.self) { b in
                        Text(b)
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                    }
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(picked ? Color.accentColor.opacity(0.14) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture { pick(v) }
    }

    private func icon(_ v: MountedVolume) -> String {
        if v.isTimeMachine { return "clock.arrow.circlepath" }
        if !v.isLocal { return "network" }
        if v.isRoot { return "internaldrive" }
        return v.isRemovable ? "externaldrive.badge.minus" : "externaldrive"
    }

    private func badges(_ v: MountedVolume) -> [String] {
        var out: [String] = []
        if v.isRoot { out.append(L10n.volBadgeBoot) }
        else if v.isExternal { out.append(L10n.volBadgeExternal) }
        if v.isTimeMachine { out.append(L10n.volBadgeTimeMachine) }
        if !v.isLocal { out.append(L10n.volBadgeNetwork) }
        if !v.trashSupported && v.tier.canDelete { out.append(L10n.volBadgeNoTrash) }
        if !v.tier.canDelete { out.append(L10n.volBadgeProtected) }
        return out
    }

    private func pick(_ v: MountedVolume) {
        selectedVolume = v
        selection.removeAll()
        clearFilters()
    }

    private func reloadVolumes() {
        volumes = Volumes.mounted()
        if let cur = selectedVolume, !volumes.contains(where: { $0.id == cur.id }) {
            selectedVolume = nil   // disco ejetado enquanto a janela estava aberta
        }
        if selectedVolume == nil { selectedVolume = volumes.first { $0.isExternal } ?? volumes.first }
    }

    // MARK: detalhe

    private var detail: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let v = selectedVolume {
                detailHeader(v)
                Divider()
                if indexer.indexing || cross.scanning { runningState }
                else if mode == .inventory { inventorySection }
                else { compareSection }
            } else {
                Spacer()
                Text(L10n.volPickOne)
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .padding(12)
    }

    private func detailHeader(_ v: MountedVolume) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(v.name).font(.title3.bold())
                Text(v.url.path).font(.caption.monospaced()).foregroundStyle(.secondary)
                Spacer()
            }
            HStack(spacing: 10) {
                Picker("", selection: $mode) {
                    Text(L10n.volModeInventory).tag(VolumesMode.inventory)
                    Text(L10n.volModeCompare).tag(VolumesMode.compare)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 320)

                Button(mode == .inventory ? L10n.volRunIndex : L10n.volRunCompare) {
                    run(on: v)
                }
                .buttonStyle(.borderedProminent)
                .disabled(indexer.indexing || cross.scanning || cross.deleting)

                if indexer.indexing || cross.scanning {
                    Button(L10n.cancel) {
                        indexer.cancel()
                        cross.cancel()
                    }
                }
                Spacer()
            }
            if !v.tier.canDelete {
                warning(L10n.volProtectedNote, color: .orange, icon: "lock")
            } else if !v.trashSupported {
                warning(L10n.volNoTrashNote(v.name), color: .orange, icon: "trash.slash")
            }
        }
    }

    private func run(on v: MountedVolume) {
        selection.removeAll()
        clearFilters()
        if mode == .inventory {
            indexer.index(volume: v)
        } else {
            let others = volumes.filter { $0.id != v.id && $0.isLocal }
            guard !others.isEmpty else { return }
            cross.scan(target: v, others: others)
        }
    }

    private var runningState: some View {
        VStack(spacing: 10) {
            if case let .hashing(done, total) = cross.phase, total > 0 {
                ProgressView(value: Double(done), total: Double(total)).frame(width: 260)
            } else {
                ProgressView()
            }
            Text(statusText).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusText: String {
        if indexer.indexing {
            return L10n.volWalking(files: indexer.filesSoFar, bytes: fmt(indexer.bytesSoFar))
        }
        if let p = cross.phase { return L10n.dupPhaseText(p) }
        if cross.scanning { return L10n.volWalking(files: cross.walkedFiles, bytes: "") }
        return L10n.scanning
    }

    // MARK: inventário

    private var inventorySection: some View {
        Group {
            if let inv = indexer.inventory {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        coverageBar(inv)
                        if inv.slackIsRelevant {
                            warning(L10n.volSlackNote(fmt(inv.slackBytes)), color: .blue, icon: "square.grid.3x3")
                        }
                        StatBars(title: L10n.volByFolder, rows: inv.byFolder, limit: 12,
                                 selected: nil, onTap: nil)
                        StatBars(title: L10n.volByExtension, rows: inv.byExtension, limit: 12,
                                 selected: nil, onTap: nil)
                        StatBars(title: L10n.volBySize, rows: inv.bySizeBucket, limit: 0,
                                 selected: nil, onTap: nil)
                        if !inv.metadata.isEmpty {
                            StatBars(title: L10n.volServiceAreas, rows: inv.metadata, limit: 0,
                                     selected: nil, onTap: nil)
                            Text(L10n.volServiceAreasNote)
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.trailing, 6)
                }
            } else {
                Text(L10n.volInventoryIntro)
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 40)
            }
        }
    }

    private func coverageBar(_ inv: VolumeInventory) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                proofCell(L10n.volCellFiles, "\(inv.indexed)")
                proofCell(L10n.volCellSpace, fmt(inv.bytesAllocated))
                proofCell(L10n.volCellSkipped, "\(inv.skippedTotal)")
                proofCell(L10n.volCellErrors, "\(inv.errorsTotal)",
                          tint: inv.errorsTotal > 0 ? .orange : nil)
                proofCell(L10n.volCellCoverage,
                          inv.coverageOK ? L10n.volCoverageOK : L10n.volCoverageFailed,
                          tint: inv.coverageOK ? .green : .red)
            }
            Text(L10n.volCoverageLine(indexed: inv.indexed, skipped: inv.skippedTotal,
                                      errors: inv.errorsTotal, visited: inv.enumerated))
                .font(.caption).foregroundStyle(.secondary)
            if !inv.skipped.isEmpty {
                Text(inv.skipped.sorted { $0.value > $1.value }
                        .map { "\(L10n.volSkipReason($0.key)) \($0.value)" }
                        .joined(separator: " · "))
                    .font(.caption2.monospaced()).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func proofCell(_ label: String, _ value: String, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.headline.monospacedDigit()).foregroundStyle(tint ?? .primary)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: comparação

    private var compareSection: some View {
        Group {
            if let r = cross.report {
                VStack(alignment: .leading, spacing: 10) {
                    compareSummary(r)
                    compareBars
                    filterRow
                    table
                    footer(r)
                }
            } else {
                Text(L10n.volCompareIntro)
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 40)
            }
        }
    }

    private func compareSummary(_ r: CrossVolumeReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                proofCell(L10n.volCellShared, fmt(r.sharedBytes))
                proofCell(L10n.volCellInternal, fmt(r.internalBytes))
                proofCell(L10n.volCellOnlyHere, fmt(r.uniqueBytes))
                proofCell(L10n.volCellErrors, "\(r.hashErrors)",
                          tint: r.hashErrors > 0 ? .orange : nil)
                proofCell(L10n.volCellCoverage,
                          r.coverageOK ? L10n.volCoverageOK : L10n.volCoverageFailed,
                          tint: r.coverageOK ? .green : .red)
            }
            Text(L10n.volVerifiedNote).font(.caption).foregroundStyle(.secondary)
            if !r.mediaAtRisk.isEmpty {
                warning(L10n.volMediaRiskNote(r.mediaAtRisk.count), color: .orange,
                        icon: "exclamationmark.triangle.fill")
            }
            if r.verifyMismatches > 0 {
                warning(L10n.volMismatchNote(r.verifyMismatches), color: .red, icon: "xmark.octagon")
            }
            if !r.subtrees.isEmpty {
                DisclosureGroup(L10n.volSubtrees(r.subtrees.count, fmt(r.subtreeBytes))) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(r.subtrees.prefix(30)) { s in
                            HStack {
                                Text(fmt(s.bytes)).font(.caption.monospacedDigit())
                                    .frame(width: 70, alignment: .trailing)
                                Text(relPath(s.url)).font(.caption.monospaced())
                                    .lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Button {
                                    NSWorkspace.shared.activateFileViewerSelecting([s.url])
                                } label: {
                                    Image(systemName: "magnifyingglass")
                                }
                                .buttonStyle(.plain).foregroundStyle(.blue)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.caption)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// Cortes por pasta e por extensão das linhas em exibição. Clicar numa
    /// barra filtra a tabela — é o que torna uma lista de dezenas de milhares
    /// de arquivos navegável, em vez de rolável.
    private var compareBars: some View {
        DisclosureGroup(isExpanded: $barsOpen) {
            HStack(alignment: .top, spacing: 18) {
                StatBars(title: L10n.volByFolder, rows: folderStats, limit: 6,
                         selected: folderFilter) { name in
                    folderFilter = (folderFilter == name) ? nil : name
                    selection.removeAll()
                }
                StatBars(title: L10n.volByExtension, rows: extStats, limit: 6,
                         selected: extFilter) { name in
                    extFilter = (extFilter == name) ? nil : name
                    selection.removeAll()
                }
            }
            .padding(.top, 6)
        } label: {
            Text(L10n.volBreakdown).font(.subheadline.bold())
        }
    }

    private var folderStats: [NamedStat] { aggregate(baseRows, by: { $0.folder }) }
    private var extStats: [NamedStat] {
        aggregate(baseRows, by: { $0.ext.isEmpty ? L10n.volNoExtension : $0.ext })
    }

    private func aggregate(_ rows: [VolRow], by key: (VolRow) -> String) -> [NamedStat] {
        var map: [String: NamedStat] = [:]
        for r in rows {
            let k = key(r)
            map[k, default: NamedStat(name: k, files: 0, bytes: 0)].add(r.size)
        }
        return map.values.sorted { $0.bytes > $1.bytes }
    }

    private var filterRow: some View {
        HStack(spacing: 8) {
            Toggle(L10n.volShowInternal, isOn: $showInternal)
                .toggleStyle(.checkbox).font(.caption)
            TextField(L10n.volSearch, text: $search)
                .textFieldStyle(.roundedBorder).frame(width: 200)
            Text(L10n.volMinSize(Int(minSizeMB))).font(.caption).foregroundStyle(.secondary)
            Slider(value: $minSizeMB, in: 0...200).frame(width: 110)
            if folderFilter != nil || extFilter != nil || !search.isEmpty || minSizeMB > 0 {
                Button(L10n.volClearFilters) { clearFilters() }.font(.caption)
            }
            Spacer()
            Button(L10n.volExportCSV) { exportCSV() }
                .disabled(rows.isEmpty)
        }
    }

    private var table: some View {
        Table(sortedRows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn(L10n.volColPath, value: \.relPath) { r in
                HStack(spacing: 4) {
                    if r.atRisk {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange).font(.caption2)
                            .help(L10n.volRowAtRisk)
                    }
                    Text(r.relPath).lineLimit(1).truncationMode(.middle)
                }
            }
            TableColumn(L10n.volColSize, value: \.size) { r in
                Text(fmt(r.size)).monospacedDigit()
            }
            .width(90)
            TableColumn(L10n.volColCopies, value: \.copies) { r in
                Text("\(r.copies)").monospacedDigit()
            }
            .width(60)
            TableColumn(L10n.volColKeeper, value: \.keeperVolume) { r in
                Text(r.keeperVolume).lineLimit(1)
            }
            .width(110)
            TableColumn(L10n.volColModified, value: \.modified) { r in
                Text(relativeAge(r.modified)).foregroundStyle(.secondary)
            }
            .width(120)
        }
        .frame(minHeight: 240)
        .contextMenu(forSelectionType: UUID.self) { ids in
            Button(L10n.revealInFinder) {
                let urls = rows.filter { ids.contains($0.id) }.map { $0.source.url }
                if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
            }
        }
    }

    private func footer(_ r: CrossVolumeReport) -> some View {
        HStack {
            Text(L10n.volRowCount(shown: sortedRows.count, total: baseRows.count))
                .font(.caption).foregroundStyle(.secondary)
            Button(L10n.dupSelectAll) { selection = Set(sortedRows.map { $0.id }) }
                .disabled(sortedRows.isEmpty)
            Button {
                selection.removeAll()
            } label: {
                Image(systemName: "xmark.circle")
            }
            .help(L10n.clearSelection).disabled(selection.isEmpty)
            Spacer()
            if cross.deleting {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(L10n.cleaningProgress(done: cross.deletingDone,
                                               total: cross.deletingTotal))
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Button {
                    confirming = true
                } label: {
                    Text(selection.isEmpty ? L10n.delete : L10n.deleteWithSize(fmt(selectedBytes)))
                }
                .buttonStyle(.borderedProminent).tint(.red)
                .disabled(selection.isEmpty || !(selectedVolume?.tier.canDelete ?? false))
            }
        }
    }

    // MARK: linhas e filtros

    /// Base: o que já existe em outro disco. As duplicatas internas entram só
    /// se o usuário pedir — ali o keeper também está neste volume, e misturar
    /// os dois casos na mesma lista confunde o que está sendo prometido.
    private var baseRows: [VolRow] {
        guard let r = cross.report, let v = selectedVolume else { return [] }
        let src = showInternal ? r.shared + r.internalDupes : r.shared
        let depth = v.url.standardizedFileURL.pathComponents.count
        return src.map { row in
            let comps = row.url.pathComponents
            let folder = comps.count > depth + 1 ? comps[depth] : "(raiz)"
            let rel = comps.count > depth
                ? comps[depth...].joined(separator: "/") : row.url.lastPathComponent
            return VolRow(id: row.id, source: row, relPath: rel, folder: folder,
                          ext: row.url.pathExtension.lowercased())
        }
    }

    private var rows: [VolRow] {
        let floor = Int64(minSizeMB) * 1024 * 1024
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        return baseRows.filter { r in
            if r.size < floor { return false }
            if let f = folderFilter, r.folder != f { return false }
            if let e = extFilter, r.ext != e { return false }
            if !needle.isEmpty, !r.relPath.lowercased().contains(needle) { return false }
            return true
        }
    }

    private var sortedRows: [VolRow] { rows.sorted(using: sortOrder) }

    private var selectedRows: [CrossVolumeRow] {
        rows.filter { selection.contains($0.id) }.map { $0.source }
    }
    private var selectedBytes: Int64 { selectedRows.reduce(0) { $0 + $1.size } }

    private func clearFilters() {
        folderFilter = nil
        extFilter = nil
        search = ""
        minSizeMB = 0
    }

    private func relPath(_ url: URL) -> String {
        guard let v = selectedVolume else { return url.path }
        let depth = v.url.standardizedFileURL.pathComponents.count
        let comps = url.pathComponents
        return comps.count > depth ? comps[depth...].joined(separator: "/") : url.lastPathComponent
    }

    // MARK: export

    /// Exporta o que está na tela (filtros aplicados), com o hash de cada linha
    /// — a lista serve de recibo do que foi provado idêntico.
    private func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(selectedVolume?.name ?? "volume").csv"
        panel.allowedContentTypes = []
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var csv = "path,bytes,sha256,copies,keeper,keeper_volume,media_single_copy\n"
        for r in sortedRows {
            csv += [quote(r.relPath), "\(r.size)", r.source.hash, "\(r.copies)",
                    quote(r.source.keeperURL.path), quote(r.keeperVolume),
                    r.atRisk ? "yes" : "no"].joined(separator: ",") + "\n"
        }
        try? csv.data(using: .utf8)?.write(to: url)
    }

    private func quote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: overlays

    private func warning(_ text: String, color: Color, icon: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(8)
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var confirmOverlay: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 14) {
                Text(L10n.volConfirmTitle(count: selectedRows.count, size: fmt(selectedBytes)))
                    .font(.headline).multilineTextAlignment(.center)

                let risky = selectedRows.filter { $0.lastBackupOfMedia }.count
                if risky > 0 {
                    warning(L10n.volConfirmRisk(risky), color: .orange,
                            icon: "exclamationmark.triangle.fill")
                }

                if selectedVolume?.trashSupported == true {
                    Picker("", selection: $deletePermanently) {
                        Text(L10n.moveToTrash).tag(false)
                        Text(L10n.deleteForever).tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    Text(deletePermanently ? L10n.permanentExplainer : L10n.trashExplainer)
                        .font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(L10n.volConfirmNoTrash(selectedVolume?.name ?? ""))
                        .font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(role: .destructive) {
                    let rows = selectedRows
                    // Sem Lixeira no volume, a remoção só pode ser definitiva.
                    let perm = (selectedVolume?.trashSupported == true) ? deletePermanently : true
                    selection.removeAll()
                    confirming = false
                    cross.delete(rows, permanently: perm)
                } label: {
                    Text(selectedVolume?.trashSupported == true && !deletePermanently
                         ? L10n.moveToTrash : L10n.deletePermanentlyBtn)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(selectedVolume?.trashSupported == true && !deletePermanently ? .accentColor : .red)

                Button(L10n.cancel) { confirming = false }
                    .buttonStyle(.bordered)
            }
            .padding(22)
            .frame(width: 360)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 24)
        }
    }
}

// MARK: - Barras de um corte do inventário

/// Gráfico de barras de um corte (pasta, extensão, faixa). Clicar numa barra
/// filtra — foi o que tornou uma lista de 32 mil arquivos navegável.
struct StatBars: View {
    let title: String
    let rows: [NamedStat]
    /// 0 = sem limite.
    let limit: Int
    let selected: String?
    let onTap: ((String) -> Void)?

    private var shown: [NamedStat] { limit > 0 ? Array(rows.prefix(limit)) : rows }
    private var maxBytes: Int64 { max(1, shown.map { $0.bytes }.max() ?? 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline.bold())
                Spacer()
                if limit > 0 && rows.count > limit {
                    Text(L10n.volMoreRows(rows.count - limit))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            ForEach(shown) { r in
                HStack(spacing: 8) {
                    Text(r.name)
                        .font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                        .frame(width: 170, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule()
                                .fill(selected == r.name ? Color.accentColor : Color.accentColor.opacity(0.55))
                                .frame(width: max(2, geo.size.width * Double(r.bytes) / Double(maxBytes)))
                        }
                    }
                    .frame(height: 12)
                    Text(fmt(r.bytes)).font(.caption.monospacedDigit())
                        .frame(width: 74, alignment: .trailing)
                    Text(L10n.volFilesCount(r.files)).font(.caption2).foregroundStyle(.secondary)
                        .frame(width: 84, alignment: .trailing)
                }
                .contentShape(Rectangle())
                .onTapGesture { onTap?(r.name) }
            }
        }
    }
}
