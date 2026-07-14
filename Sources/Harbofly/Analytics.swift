import Foundation
import TelemetryDeck

/// Analytics anônimo e **opt-in** via TelemetryDeck.
///
/// Filosofia Apple — o que NUNCA sai do app:
/// e-mail, IP, nome, hostname, caminhos, nem nomes de projeto.
/// Só nomes de evento, categorias genéricas de cache (DerivedData,
/// node_modules, Homebrew…) e métricas numéricas agregáveis.
///
/// Opt-in de verdade: o SDK só é inicializado depois que o usuário aceita.
/// Sem consentimento, `TelemetryDeck.initialize` nunca roda e nenhum sinal
/// deixa a máquina. País, idioma e versão do macOS são preenchidos pelo
/// próprio SDK; retenção (1/7/30 dias) o TelemetryDeck calcula no servidor.
enum Analytics {
    /// App ID da conta em telemetrydeck.com.
    private static let appID = "3965E9D8-5C35-4F46-B693-1EEEAE69BE41"

    private static var started = false

    // MARK: consentimento

    /// true depois que o usuário respondeu Sim/Não no first launch.
    static var choiceMade: Bool {
        UserDefaults.standard.bool(forKey: Prefs.analyticsChoiceMade)
    }
    /// true só se o usuário optou por compartilhar.
    static var enabled: Bool {
        UserDefaults.standard.bool(forKey: Prefs.analyticsEnabled)
    }

    /// Chamado no launch: se o usuário já consentiu, sobe o SDK.
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

    /// Usuário recusou (dialog) ou desligou o toggle. O SDK fica inerte.
    static func optOut() {
        let d = UserDefaults.standard
        d.set(true, forKey: Prefs.analyticsChoiceMade)
        d.set(false, forKey: Prefs.analyticsEnabled)
    }

    private static func start() {
        guard !started else { return }
        let config = TelemetryDeck.Config(appID: appID)
        TelemetryDeck.initialize(config: config)
        started = true

        // Aquisição: primeiro launch de todos, uma vez na vida do app.
        if !UserDefaults.standard.bool(forKey: Prefs.firstLaunchSent) {
            UserDefaults.standard.set(true, forKey: Prefs.firstLaunchSent)
            signal("App.firstLaunch")
        }
        signal("App.launched")
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
        if !UserDefaults.standard.bool(forKey: Prefs.firstScanSent) {
            UserDefaults.standard.set(true, forKey: Prefs.firstScanSent)
            signal("Scan.first")
        }
        signal("Scan.finished",
               parameters: ["itemCount": String(itemCount), "durationMs": String(durationMs),
                            "freePct": String(Int((freeRatio * 100).rounded()))],
               floatValue: gb(recoverableBytes))
        // Composição: presença + peso de cada categoria genérica no scan.
        for (category, bytes) in byCategory {
            signal("Cache.present", parameters: ["category": category], floatValue: gb(bytes))
        }
    }

    // MARK: adoção de features (item 1) — 1x por sessão pra medir descoberta.
    private static var featuresSeen = Set<String>()
    static func featureUsed(_ name: String) {
        guard enabled, started, featuresSeen.insert(name).inserted else { return }
        signal("Feature.used", parameters: ["name": name])
    }

    /// Loop viral: compartilhou o card de conquista ou o recap do histórico.
    static func shared(_ kind: String) {
        guard enabled else { return }
        signal("Share.tapped", parameters: ["kind": kind])
    }

    static func feedbackOpened() {
        guard enabled else { return }
        signal("Feedback.opened")
    }
    static func feedbackSent(type: String) {
        guard enabled else { return }
        signal("Feedback.sent", parameters: ["type": type])
    }

    // MARK: auto-clean (item 2)
    /// Usuário mudou a config do auto-clean (ligar/desligar, gatilho, escopo).
    static func autoCleanConfigured(enabled on: Bool, trigger: String, scope: String) {
        guard enabled else { return }
        signal("AutoClean.configured",
               parameters: ["enabled": on ? "true" : "false", "trigger": trigger, "scope": scope])
    }
    /// O auto-clean disparou de verdade — quanto entregou e em que contexto.
    static func autoCleanRan(trigger: String, scope: String, freedBytes: Int64, itemCount: Int) {
        guard enabled else { return }
        signal("AutoClean.ran",
               parameters: ["trigger": trigger, "scope": scope, "itemCount": String(itemCount)],
               floatValue: gb(freedBytes))
    }

    // MARK: duplicatas (item 3)
    static func duplicatesScanned(groups: Int, reclaimableBytes: Int64, durationMs: Int) {
        guard enabled else { return }
        signal("Duplicates.scanned",
               parameters: ["groups": String(groups), "durationMs": String(durationMs)],
               floatValue: gb(reclaimableBytes))
    }
    static func duplicatesDeleted(mode: String, freedBytes: Int64, count: Int) {
        guard enabled else { return }
        signal("Duplicates.deleted",
               parameters: ["mode": mode, "count": String(count)],
               floatValue: gb(freedBytes))
    }

    /// Falhas (item 6): "delete" | "dockerPrune" | "feedback" | "duplicates".
    static func failure(_ category: String) {
        guard enabled else { return }
        signal("Failure", parameters: ["category": category])
    }

    /// Conversão: usuário abriu o diálogo de exclusão.
    static func deleteClicked(mode: String, itemCount: Int) {
        guard enabled else { return }
        signal("Delete.clicked",
               parameters: ["mode": mode, "itemCount": String(itemCount)])
    }

    /// Conversão: exclusão concluída. `byCategory` = bytes liberados por tipo
    /// genérico de cache (nunca o caminho/nome de projeto real).
    static func deleteConfirmed(mode: String, freedBytes: Int64, itemCount: Int, byCategory: [String: Int64]) {
        guard enabled else { return }
        signal("Delete.confirmed",
               parameters: ["mode": mode, "itemCount": String(itemCount)],
               floatValue: gb(freedBytes))
        for (category, bytes) in byCategory {
            signal("Cache.cleaned", parameters: ["category": category], floatValue: gb(bytes))
        }
    }

    // MARK: helpers

    private static func gb(_ bytes: Int64) -> Double { Double(bytes) / 1_073_741_824 }

    private static func signal(_ name: String, parameters: [String: String] = [:], floatValue: Double? = nil) {
        guard started else { return }
        TelemetryDeck.signal(name, parameters: parameters, floatValue: floatValue)
    }
}
