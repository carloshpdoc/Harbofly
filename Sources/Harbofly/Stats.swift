import Foundation

/// Registro persistente de cada limpeza (manual, automática, duplicatas e CLI).
/// Fonte única do painel de histórico: quem limpa chama `record(...)`, que
/// também mantém o total acumulado (`Prefs.totalFreedBytes`).
enum CleanLog {
    struct Entry {
        let ts: Double
        let bytes: Int64
        let count: Int
        /// Bytes por categoria genérica (só as top 5 de cada limpeza).
        let cats: [String: Int64]
    }

    /// Teto generoso: ~1 KB por entrada, anos de uso sem pesar no defaults.
    static let maxEntries = 1000

    static func record(bytes: Int64, count: Int, byCategory: [String: Int64]) {
        guard bytes > 0 else { return }
        let d = UserDefaults.standard
        d.set(Int(d.integer(forKey: Prefs.totalFreedBytes)) + Int(bytes),
              forKey: Prefs.totalFreedBytes)
        var cats: [String: Double] = [:]
        for (k, v) in byCategory.sorted(by: { $0.value > $1.value }).prefix(5) {
            cats[k] = Double(v)
        }
        var hist = d.array(forKey: Prefs.cleanHistory) as? [[String: Any]] ?? []
        hist.insert(["ts": Date().timeIntervalSince1970,
                     "bytes": Double(bytes),
                     "count": count,
                     "cats": cats], at: 0)
        d.set(Array(hist.prefix(maxEntries)), forKey: Prefs.cleanHistory)
    }

    /// Entradas mais novas primeiro.
    static func entries() -> [Entry] {
        let hist = UserDefaults.standard.array(forKey: Prefs.cleanHistory) as? [[String: Any]] ?? []
        return hist.compactMap { e in
            guard let ts = e["ts"] as? Double, let bytes = e["bytes"] as? Double else { return nil }
            let cats = (e["cats"] as? [String: Double] ?? [:]).mapValues { Int64($0) }
            return Entry(ts: ts, bytes: Int64(bytes),
                         count: (e["count"] as? Int) ?? Int(e["count"] as? Double ?? 0),
                         cats: cats)
        }
    }
}

/// Agregados do histórico pro painel "Histórico" e pro card de recap.
struct CleanStats {
    /// Vida toda — inclui limpezas anteriores ao histórico detalhado.
    let totalBytes: Int64
    let cleanCount: Int
    let biggestBytes: Int64
    let last30dBytes: Int64
    let topVillain: (name: String, bytes: Int64)?
    let firstTs: Double?
    /// Últimas 12 semanas, da mais antiga pra atual.
    let weekly: [Int64]

    /// Preço público da Apple por upgrade de SSD: US$ 200 por 512 GB.
    static let usdPerByte = 200.0 / (512.0 * 1_000_000_000.0)
    var savedUSD: Double { Double(totalBytes) * Self.usdPerByte }

    static func compute() -> CleanStats {
        let entries = CleanLog.entries()
        let total = Int64(UserDefaults.standard.integer(forKey: Prefs.totalFreedBytes))
        let now = Date().timeIntervalSince1970
        var villains: [String: Int64] = [:]
        var weekly = [Int64](repeating: 0, count: 12)
        for e in entries {
            for (k, v) in e.cats { villains[k, default: 0] += v }
            let weeksAgo = Int((now - e.ts) / 604_800)
            if weeksAgo >= 0 && weeksAgo < 12 { weekly[11 - weeksAgo] += e.bytes }
        }
        return CleanStats(
            totalBytes: max(total, entries.reduce(0) { $0 + $1.bytes }),
            cleanCount: entries.count,
            biggestBytes: entries.map(\.bytes).max() ?? 0,
            last30dBytes: entries.filter { now - $0.ts < 2_592_000 }.reduce(0) { $0 + $1.bytes },
            topVillain: villains.max(by: { $0.value < $1.value }).map { ($0.key, $0.value) },
            firstTs: entries.last?.ts,
            weekly: weekly)
    }
}

/// "US$ 117" / "$117" — moeda em dólar (preço da Apple), agrupamento no locale.
func fmtUSD(_ value: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = "USD"
    f.maximumFractionDigits = 0
    return f.string(from: NSNumber(value: value)) ?? "US$\(Int(value))"
}
