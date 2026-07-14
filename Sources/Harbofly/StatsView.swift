import SwiftUI
import AppKit

// MARK: - Card de compartilhamento (estilo compartilhado)

/// Cards 1200×675 (proporção OG/Twitter) com o visual do site. Usado pelo
/// card pós-limpeza e pelo recap do histórico.
enum ShareCard {
    static let size = NSSize(width: 1200, height: 675)
    static let teal = NSColor(srgbRed: 0.31, green: 0.82, blue: 0.77, alpha: 1)
    static let ink = NSColor(srgbRed: 0.918, green: 0.949, blue: 1.0, alpha: 1)
    static let muted = NSColor(srgbRed: 0.56, green: 0.63, blue: 0.71, alpha: 1)
    static let gold = NSColor(srgbRed: 1.0, green: 0.80, blue: 0.35, alpha: 1)

    /// Renderiza o fundo em degradê e entrega um `draw(texto, fonte, cor, y)`
    /// centralizado horizontalmente pro chamador compor as linhas.
    static func render(_ body: (_ draw: (String, NSFont, NSColor, CGFloat) -> Void) -> Void) -> NSImage {
        let img = NSImage(size: size)
        img.lockFocus()
        NSGradient(colors: [
            NSColor(srgbRed: 0.031, green: 0.063, blue: 0.110, alpha: 1),
            NSColor(srgbRed: 0.051, green: 0.106, blue: 0.165, alpha: 1),
        ])?.draw(in: NSRect(origin: .zero, size: size), angle: 120)
        body { s, font, color, y in
            let p = NSMutableParagraphStyle(); p.alignment = .center
            let attr: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: p]
            let str = s as NSString
            let h = str.size(withAttributes: attr).height
            str.draw(in: NSRect(x: 0, y: y - h / 2, width: size.width, height: h), withAttributes: attr)
        }
        img.unlockFocus()
        return img
    }
}

/// Abre o share sheet nativo ancorado na janela ativa. Nonisolated (chamado de
/// métodos de View nonisolated); o AppKit roda dentro de `assumeIsolated` pra
/// satisfazer o strict-concurrency sem forçar os chamadores a virar @MainActor
/// (evita erro de isolamento no toolchain do CI).
func showSharePicker(_ items: [Any]) {
    MainActor.assumeIsolated {
        let picker = NSSharingServicePicker(items: items)
        if let view = NSApp.keyWindow?.contentView {
            picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
        }
    }
}

// MARK: - Painel "Histórico"

/// Estatísticas de tudo que o app já limpou, com o número que importa —
/// quanto isso custaria em SSD da Apple — e um recap compartilhável.
struct StatsView: View {
    // Re-renderiza quando uma limpeza atualiza o total ou quando o idioma muda.
    @AppStorage(Prefs.totalFreedBytes) private var totalFreedBytes = 0
    @AppStorage(Prefs.language) private var language = "system"

    var body: some View {
        let stats = CleanStats.compute()
        return Group {
            if stats.totalBytes <= 0 {
                VStack(spacing: 10) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 36)).foregroundStyle(.secondary)
                    Text(L10n.statsEmpty)
                        .font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                content(stats)
            }
        }
    }

    private func content(_ stats: CleanStats) -> some View {
        VStack(spacing: 12) {
            // Hero: o total da vida toda.
            VStack(spacing: 2) {
                Text(fmt(stats.totalBytes))
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [.teal, .green],
                                                    startPoint: .leading, endPoint: .trailing))
                Text(stats.firstTs.map { L10n.statsRecoveredSince(shortDate($0)) }
                     ?? L10n.statsRecoveredSoFar)
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 6)

            // O "uau": o total traduzido no preço de SSD da Apple.
            if stats.savedUSD >= 1 {
                VStack(spacing: 3) {
                    Text(L10n.moneyLine(fmtUSD(stats.savedUSD)))
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L10n.moneyFootnote)
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(10)
                .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }

            // Equivalência concreta (a melhor unidade pro tamanho).
            if stats.totalBytes >= 1_000_000_000 {
                let movies = Int(stats.totalBytes / 15_000_000_000)
                Text(movies >= 1
                     ? L10n.eqMovies(movies)
                     : L10n.eqPhotos(grouped(stats.totalBytes / 4_000_000)))
                    .font(.callout).foregroundStyle(.secondary)
            }

            if stats.cleanCount > 0 {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    tile(L10n.statsCleans, "\(stats.cleanCount)")
                    tile(L10n.statsBiggest, fmt(stats.biggestBytes))
                    tile(L10n.statsLast30d, fmt(stats.last30dBytes))
                    tile(L10n.statsTopVillain,
                         stats.topVillain.map { "\($0.name) · \(fmt($0.bytes))" } ?? "—")
                }
            }

            if let maxWeek = stats.weekly.max(), maxWeek > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.statsChartTitle).font(.caption).foregroundStyle(.secondary)
                    HStack(alignment: .bottom, spacing: 4) {
                        ForEach(0..<12, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(i == 11 ? Color.teal : Color.teal.opacity(0.45))
                                .frame(height: barHeight(stats.weekly[i], max: maxWeek))
                                .frame(maxWidth: .infinity)
                                .help(fmt(stats.weekly[i]))
                        }
                    }
                    .frame(height: 56, alignment: .bottom)
                }
                .padding(10)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            }

            Button {
                shareRecap(stats)
            } label: {
                Label(L10n.shareRecap, systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func tile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline.monospacedDigit()).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    private func barHeight(_ v: Int64, max maxV: Int64) -> CGFloat {
        v <= 0 ? 3 : 8 + 48 * CGFloat(v) / CGFloat(maxV)
    }

    private func shortDate(_ ts: Double) -> String {
        Date(timeIntervalSince1970: ts).formatted(date: .abbreviated, time: .omitted)
    }

    private func grouped(_ n: Int64) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    // MARK: recap compartilhável

    private func shareRecap(_ stats: CleanStats) {
        Analytics.shared("recap")
        let image = ShareCard.render { draw in
            draw("Harbofly Recap", .monospacedSystemFont(ofSize: 30, weight: .regular), ShareCard.muted, 605)
            draw(L10n.shareCardVerb, .systemFont(ofSize: 46, weight: .medium), ShareCard.muted, 505)
            draw(fmt(stats.totalBytes), .systemFont(ofSize: 145, weight: .heavy), ShareCard.teal, 390)
            if stats.savedUSD >= 1 {
                draw(L10n.recapMoneyShort(fmtUSD(stats.savedUSD)),
                     .systemFont(ofSize: 52, weight: .semibold), ShareCard.gold, 250)
            }
            if stats.cleanCount > 0 {
                draw(L10n.recapCardFooter(count: stats.cleanCount,
                                          villain: stats.topVillain?.name ?? ""),
                     .systemFont(ofSize: 30, weight: .medium), ShareCard.ink, 160)
            }
            draw("harbofly.app", .monospacedSystemFont(ofSize: 34, weight: .regular), ShareCard.muted, 80)
        }
        let text = stats.savedUSD >= 1
            ? L10n.recapShareText(size: fmt(stats.totalBytes), usd: fmtUSD(stats.savedUSD))
            : L10n.shareText(fmt(stats.totalBytes))
        showSharePicker([image, text])
    }
}
