import Foundation

/// Analytics anônimo e **opt-in** via GA4 Measurement Protocol.
///
/// Sem SDK: cada evento é um POST HTTPS pro Google Analytics feito pelo próprio
/// app (você lê exatamente o que sai, aqui no source). Sem conta, sem login,
/// sem IDFA. O identificador é um `client_id` aleatório gerado e guardado
/// localmente — não liga a nenhuma pessoa.
///
/// Filosofia Apple — o que NUNCA sai do app:
/// e-mail, IP, nome, hostname, caminhos, nem nomes de projeto.
/// Só nomes de evento, categorias genéricas de cache (DerivedData,
/// node_modules, Homebrew…) e métricas numéricas agregáveis.
///
/// Opt-in de verdade: sem consentimento, `start()` nunca roda e nenhum request
/// deixa a máquina. País (via IP, no ingest do GA4), versão e retenção o GA4
/// calcula do lado dele. Enquanto o `GA4Config` estiver com placeholder, tudo
/// fica inerte.
enum Analytics {
    private static var started = false

    // Identidade anônima e sessão (exigências do Measurement Protocol).
    private static let clientKey = "hf.analytics.clientID"
    private static var clientID: String = {
        let d = UserDefaults.standard
        if let existing = d.string(forKey: clientKey) { return existing }
        let id = UUID().uuidString
        d.set(id, forKey: clientKey)
        return id
    }()
    private static var sessionID = "0"

    /// Propriedades do usuário (device/locale) — coletadas 1x no start() e
    /// anexadas a cada evento. Só metadados NÃO-identificáveis do próprio device
    /// (idioma, país, versão do macOS, modelo, tema), no espírito do TelemetryDeck.
    /// Nunca IP nem geolocalização — o país vem do `Locale` que o user configurou.
    private static var userProps: [String: [String: String]] = [:]

    /// Só envia quando o GA4Config foi preenchido com valores reais.
    private static var configured: Bool {
        !GA4Config.measurementID.isEmpty && !GA4Config.measurementID.contains("XXXX")
            && !GA4Config.apiSecret.isEmpty && !GA4Config.apiSecret.contains("REPLACE")
    }
    private static var endpoint: URL? {
        guard configured else { return nil }
        return URL(string: "https://www.google-analytics.com/mp/collect?measurement_id=\(GA4Config.measurementID)&api_secret=\(GA4Config.apiSecret)")
    }

    // MARK: consentimento

    /// true depois que o usuário respondeu Sim/Não no first launch.
    static var choiceMade: Bool {
        UserDefaults.standard.bool(forKey: Prefs.analyticsChoiceMade)
    }
    /// true só se o usuário optou por compartilhar.
    static var enabled: Bool {
        UserDefaults.standard.bool(forKey: Prefs.analyticsEnabled)
    }

    /// Chamado no launch: se o usuário já consentiu, sobe o envio.
    static func bootstrapIfConsented() {
        guard enabled else { return }
        start()
    }

    /// Usuário aceitou (dialog do first launch ou toggle nas prefs).
    static func optIn() {
        let d = UserDefaults.standard
        d.set(true, forKey: Prefs.analyticsChoiceMade)
        d.set(true, forKey: Prefs.analyticsEnabled)
        start()
    }

    /// Usuário recusou (dialog) ou desligou o toggle. Nada é enviado.
    static func optOut() {
        let d = UserDefaults.standard
        d.set(true, forKey: Prefs.analyticsChoiceMade)
        d.set(false, forKey: Prefs.analyticsEnabled)
    }

    private static func start() {
        guard !started else { return }
        started = true
        sessionID = String(Int(Date().timeIntervalSince1970))
        guard configured else { return }
        _ = clientID   // materializa/persiste o id anônimo
        userProps = collectUserProperties()

        // Aquisição: primeiro launch de todos, uma vez na vida do app.
        if !UserDefaults.standard.bool(forKey: Prefs.firstLaunchSent) {
            UserDefaults.standard.set(true, forKey: Prefs.firstLaunchSent)
            signal("app_first_launch")
        }
        signal("app_launched")
    }

    // MARK: eventos
    //
    // Norte: cada sinal existe pra APRENDER e MELHORAR a ferramenta pro user.
    // Só nomes de evento, categorias genéricas de cache e métricas numéricas —
    // nunca caminho, nome de projeto ou qualquer coisa da máquina.

    /// Ativação: scan concluído. `recoverableBytes` = só o que o app apaga;
    /// `byCategory` = composição por tipo genérico (pra saber quais caches são
    /// mais comuns/pesados na base e priorizar o roadmap); `freeRatio` = pressão
    /// de disco (quanta dor a base sente).
    static func scanFinished(durationMs: Int, itemCount: Int, recoverableBytes: Int64,
                             freeRatio: Double, byCategory: [String: Int64]) {
        guard enabled else { return }
        if configured, !UserDefaults.standard.bool(forKey: Prefs.firstScanSent) {
            UserDefaults.standard.set(true, forKey: Prefs.firstScanSent)
            signal("scan_first")
        }
        signal("scan_finished",
               metrics: ["item_count": Double(itemCount), "duration_ms": Double(durationMs),
                         "free_pct": (freeRatio * 100).rounded()],
               floatValue: gb(recoverableBytes))
        // Composição: presença + peso de cada categoria genérica no scan.
        for (category, bytes) in byCategory {
            signal("cache_present", parameters: ["category": category], floatValue: gb(bytes))
        }
    }

    // MARK: adoção de features (item 1) — 1x por sessão pra medir descoberta.
    private static var featuresSeen = Set<String>()
    static func featureUsed(_ name: String) {
        guard enabled, started, featuresSeen.insert(name).inserted else { return }
        signal("feature_used", parameters: ["name": name])
    }

    /// Loop viral: compartilhou o card de conquista ou o recap do histórico.
    static func shared(_ kind: String) {
        guard enabled else { return }
        signal("share_tapped", parameters: ["kind": kind])
    }

    static func feedbackOpened() {
        guard enabled else { return }
        signal("feedback_opened")
    }
    static func feedbackSent(type: String) {
        guard enabled else { return }
        signal("feedback_sent", parameters: ["type": type])
    }

    // MARK: auto-clean (item 2)
    /// Usuário mudou a config do auto-clean (ligar/desligar, gatilho, escopo).
    static func autoCleanConfigured(enabled on: Bool, trigger: String, scope: String) {
        guard enabled else { return }
        signal("autoclean_configured",
               parameters: ["enabled": on ? "true" : "false", "trigger": trigger, "scope": scope])
    }
    /// O auto-clean disparou de verdade — quanto entregou e em que contexto.
    static func autoCleanRan(trigger: String, scope: String, freedBytes: Int64, itemCount: Int) {
        guard enabled else { return }
        signal("autoclean_ran",
               parameters: ["trigger": trigger, "scope": scope],
               metrics: ["item_count": Double(itemCount)],
               floatValue: gb(freedBytes))
    }

    // MARK: duplicatas (item 3)
    static func duplicatesScanned(groups: Int, reclaimableBytes: Int64, durationMs: Int) {
        guard enabled else { return }
        signal("duplicates_scanned",
               metrics: ["groups": Double(groups), "duration_ms": Double(durationMs)],
               floatValue: gb(reclaimableBytes))
    }
    static func duplicatesDeleted(mode: String, freedBytes: Int64, count: Int) {
        guard enabled else { return }
        signal("duplicates_deleted",
               parameters: ["mode": mode],
               metrics: ["count": Double(count)],
               floatValue: gb(freedBytes))
    }

    /// Falhas (item 6): "delete" | "dockerPrune" | "feedback" | "duplicates".
    /// `reason` (opcional): rótulo genérico do motivo — ex.: "notFound" |
    /// "permission" | "busy" | "other" — nunca caminho/nome, só pra diagnosticar
    /// em campo mantendo a privacidade.
    static func failure(_ category: String, reason: String? = nil) {
        guard enabled else { return }
        var parameters = ["category": category]
        if let reason { parameters["reason"] = reason }
        signal("failure", parameters: parameters)
    }

    // MARK: TIER 1 — descoberta de features

    /// Composição do público: toolchains que o user TEM (mesmo sem limpar),
    /// pra saber se a base é iOS/web/Android/AI e priorizar o roadmap. 1x/sessão.
    private static var ecosystemsSent = false
    static func ecosystems(_ list: [String]) {
        guard enabled, started, !ecosystemsSent, !list.isEmpty else { return }
        ecosystemsSent = true
        signal("app_ecosystems", parameters: ["list": list.sorted().joined(separator: ",")])
    }

    /// Caches grandes que o app NÃO reconhece — só contagem + total, SEM nomes,
    /// pra nunca vazar o bundle-id de um app próprio do dev. Sinaliza que há
    /// alvo novo a ganhar; a versão nomeada exigiria uma allowlist curada.
    static func cacheUnrecognized(count: Int, totalBytes: Int64) {
        guard enabled, count > 0 else { return }
        signal("cache_unrecognized", metrics: ["count": Double(count)], floatValue: gb(totalBytes))
    }

    /// Funil de decisão: categorias que o user SELECIONOU ao abrir o diálogo
    /// (cruzado com delete_confirmed dá o abandono por categoria).
    static func deleteSelected(byCategory: [String: Int64]) {
        guard enabled else { return }
        for (category, bytes) in byCategory {
            signal("delete_selected", parameters: ["category": category], floatValue: gb(bytes))
        }
    }

    // MARK: TIER 2 — valor e retenção

    /// Funil da oferta proativa: "shown" | "accepted" | "snoozed".
    static func offer(_ action: String) {
        guard enabled else { return }
        signal("offer_\(action)")
    }

    /// Estado do Docker no scan: "running" | "off" (engine desligado, valor
    /// perdido) | "absent". Alimenta um possível nudge "ligue o Docker".
    static func dockerState(_ state: String) {
        guard enabled else { return }
        signal("docker_state", parameters: ["state": state])
    }

    // MARK: TIER 3 — fricção e ações do tier informativo

    /// Ações no tier 🔵 informativo: "revealInFinder" | "deleteOldSims".
    static func infoAction(_ name: String) {
        guard enabled else { return }
        signal("info_action", parameters: ["action": name])
    }

    // MARK: capacidade — tempo em cada aba (cronometrado localmente)

    private static var currentPane: String?
    private static var paneStart: Date?
    /// Fecha a duração da aba anterior e abre a da nova. Emite `pane_duration`
    /// com o nome da aba que foi deixada e quantos segundos ficou nela.
    @MainActor
    static func paneSwitched(to name: String) {
        guard enabled, started else { return }
        let now = Date()
        if let prev = currentPane, let opened = paneStart {
            let seconds = Int(now.timeIntervalSince(opened).rounded())
            signal("pane_duration", parameters: ["name": prev], metrics: ["seconds": Double(seconds)])
        }
        currentPane = name
        paneStart = now
    }

    /// Conversão: usuário abriu o diálogo de exclusão.
    static func deleteClicked(mode: String, itemCount: Int) {
        guard enabled else { return }
        signal("delete_clicked",
               parameters: ["mode": mode],
               metrics: ["item_count": Double(itemCount)])
    }

    /// Conversão: exclusão concluída. `byCategory` = bytes liberados por tipo
    /// genérico de cache (nunca o caminho/nome de projeto real).
    static func deleteConfirmed(mode: String, freedBytes: Int64, itemCount: Int, byCategory: [String: Int64]) {
        guard enabled else { return }
        signal("delete_confirmed",
               parameters: ["mode": mode],
               metrics: ["item_count": Double(itemCount)],
               floatValue: gb(freedBytes))
        for (category, bytes) in byCategory {
            signal("cache_cleaned", parameters: ["category": category], floatValue: gb(bytes))
        }
    }

    // MARK: helpers

    /// Metadados de device/locale como user_properties do GA4 — coletados só do
    /// próprio Mac (Locale, ProcessInfo, sysctl), nunca IP ou geolocalização.
    private static func collectUserProperties() -> [String: [String: String]] {
        func p(_ v: String) -> [String: String] { ["value": v] }
        let appLang: String
        switch Lang.current {
        case .pt: appLang = "pt"
        case .en: appLang = "en"
        case .es: appLang = "es"
        case .fr: appLang = "fr"
        case .de: appLang = "de"
        case .zh: appLang = "zh"
        }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        // Dark mode sem AppKit: no macOS o modo escuro seta esse default global.
        let dark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        var props: [String: [String: String]] = [
            "lang": p(Locale.current.language.languageCode?.identifier ?? "und"),
            "app_lang": p(appLang),
            "region": p(Locale.current.region?.identifier ?? "ZZ"),
            "os_version": p("\(os.majorVersion).\(os.minorVersion)"),
            "appearance": p(dark ? "dark" : "light"),
            "app_version": p(AppInfo.version),
        ]
        if let model = macModel() { props["model"] = p(model) }
        return props
    }

    /// Modelo do Mac (ex.: "Mac15,3") via sysctl — só o identificador de hardware,
    /// nunca serial nem nada que ligue a uma pessoa.
    private static func macModel() -> String? {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }

    private static func gb(_ bytes: Int64) -> Double { Double(bytes) / 1_073_741_824 }

    /// Ponto único de saída: monta o payload do Measurement Protocol e faz um
    /// POST fire-and-forget (não bloqueia, falha em silêncio se estiver offline).
    /// `session_id` + `engagement_time_msec` são exigidos pelo GA4 pra o evento
    /// contar como engajamento e aparecer nos relatórios. `floatValue` (GB) vai
    /// como o param numérico `gb`.
    private static func signal(_ name: String, parameters: [String: String] = [:],
                               metrics: [String: Double] = [:], floatValue: Double? = nil) {
        guard started, configured, let url = endpoint else { return }
        var params: [String: Any] = parameters
        // Metrics vão como número (GA4 só agrega custom metric com valor numérico).
        for (key, value) in metrics { params[key] = value }
        params["session_id"] = sessionID
        params["engagement_time_msec"] = 100
        if let floatValue { params["gb"] = floatValue }

        var body: [String: Any] = [
            "client_id": clientID,
            "non_personalized_ads": true,
            "events": [["name": name, "params": params]],
        ]
        if !userProps.isEmpty { body["user_properties"] = userProps }
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        URLSession.shared.dataTask(with: req).resume()
    }
}
