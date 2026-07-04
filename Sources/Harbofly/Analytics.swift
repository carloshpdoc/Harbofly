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

    /// Ativação: scan concluído. `recoverableBytes` = só o que o app apaga.
    static func scanFinished(durationMs: Int, itemCount: Int, recoverableBytes: Int64) {
        guard enabled else { return }
        if !UserDefaults.standard.bool(forKey: Prefs.firstScanSent) {
            UserDefaults.standard.set(true, forKey: Prefs.firstScanSent)
            signal("Scan.first")
        }
        signal("Scan.finished",
               parameters: ["itemCount": String(itemCount), "durationMs": String(durationMs)],
               floatValue: gb(recoverableBytes))
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
