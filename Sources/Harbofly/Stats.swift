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

/// Snapshots do tamanho da paisagem (categoria -> bytes) ao longo do tempo.
/// Base da detecção de crescimento: diffar o agora contra um snapshot antigo
/// revela o que encheu o disco em silêncio (um `~/.git` novo, o `uv` crescendo).
enum SizeLog {
    struct Snap { let ts: Double; let cats: [String: Int64] }
    static let maxSnaps = 60
    /// No máx 1 snapshot a cada 6h — vários scans/dia não incham o defaults.
    static let minInterval = 21_600.0

    static func record(_ cats: [String: Int64], now: Double) {
        guard !cats.isEmpty else { return }
        let d = UserDefaults.standard
        var raw = d.array(forKey: Prefs.sizeHistory) as? [[String: Any]] ?? []
        if let lastTs = raw.first?["ts"] as? Double, now - lastTs < minInterval { return }
        raw.insert(["ts": now, "cats": cats.mapValues { Double($0) }], at: 0)
        d.set(Array(raw.prefix(maxSnaps)), forKey: Prefs.sizeHistory)
    }

    /// Mais novos primeiro.
    static func snaps() -> [Snap] {
        let raw = UserDefaults.standard.array(forKey: Prefs.sizeHistory) as? [[String: Any]] ?? []
        return raw.compactMap { e in
            guard let ts = e["ts"] as? Double else { return nil }
            let cats = (e["cats"] as? [String: Double] ?? [:]).mapValues { Int64($0) }
            return Snap(ts: ts, cats: cats)
        }
    }

    /// Snapshot mais antigo com pelo menos `minAgeDays` de idade (baseline do diff).
    static func baseline(now: Double, minAgeDays: Double) -> Snap? {
        snaps().filter { now - $0.ts >= minAgeDays * 86_400 }.last
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

    /// Valor equivalente em SSD da Apple que você deixou de comprar, na moeda da
    /// sua região (ver SSDPricing). Offline, atualizável por release.
    var savedMoney: Double { Double(totalBytes) * SSDPricing.perByte }

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

/// Preço de tabela da Apple por upgrade de SSD, por região, na moeda local.
/// OFFLINE e fonte única: sem scraping/rede — a Apple não expõe API de preço, e
/// um cleaner privacy-first não deve abrir conexão por um número aproximado. Se
/// mudar, sai no próximo release (o app já se auto-atualiza via Sparkle). Preços
/// = tier de 512 GB de upgrade no Apple Store de cada região (arredondados).
enum SSDPricing {
    /// (preço por 512 GB de upgrade, código da moeda).
    static let table: [String: (price: Double, currency: String)] = [
        "US": (200, "USD"),
        "BR": (1500, "BRL"),
        "GB": (200, "GBP"),
        "DE": (230, "EUR"), "FR": (230, "EUR"), "ES": (230, "EUR"),
        "IT": (230, "EUR"), "PT": (230, "EUR"), "NL": (230, "EUR"), "IE": (230, "EUR"),
        "CA": (250, "CAD"),
        "AU": (300, "AUD"),
        "JP": (30000, "JPY"),
        "CN": (1500, "CNY"),
        "IN": (20000, "INR"),
        "MX": (4000, "MXN"),
    ]
    static let fallback: (price: Double, currency: String) = (200, "USD")

    /// Preço/moeda da região atual do usuário (cai pro dólar quando não mapeado).
    static var current: (price: Double, currency: String) {
        let region = Locale.current.region?.identifier ?? "US"
        return table[region] ?? fallback
    }
    /// Valor por byte recuperado (preço de 512 GB ÷ 512 GB).
    static var perByte: Double { current.price / (512.0 * 1_000_000_000.0) }
}

/// "US$ 117" / "R$ 550" — na moeda da região atual (preço de SSD da Apple),
/// agrupamento pelo locale. Passe `code` pra forçar outra moeda.
func fmtMoney(_ value: Double, code: String = SSDPricing.current.currency) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = code
    f.maximumFractionDigits = 0
    return f.string(from: NSNumber(value: value)) ?? "\(code) \(Int(value))"
}
