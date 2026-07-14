import Foundation

/// Feedback in-app → Supabase (tabela `harbofly_feedback`).
///
/// A key abaixo é *publishable* (feita pra viver no client) e a tabela tem
/// RLS insert-only: com ela dá pra ENVIAR feedback, mas não pra ler, alterar
/// ou apagar nada. Junto do texto vão só versão do app/macOS e locale —
/// nunca nomes, caminhos ou qualquer coisa da máquina.
enum Feedback {
    private static let endpoint = URL(string: "https://svhwphsqvijwokorlvcd.supabase.co/rest/v1/harbofly_feedback")!
    private static let apiKey = "sb_publishable_01VsB0GhQn6jBTiWbPERXw_ALRVjbp-"

    /// POST do feedback. `type` é "bug" | "idea" | "other" pra segmentar os
    /// insights. Retorna true se o servidor aceitou (2xx).
    static func send(message: String, contact: String, type: String) async -> Bool {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }

        let os = ProcessInfo.processInfo.operatingSystemVersion
        var body: [String: String] = [
            "message": String(text.prefix(4000)),
            "type": type,
            "app_version": AppInfo.version,
            "build": AppInfo.build,
            "os_version": "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            "locale": Locale.current.identifier,
        ]
        let reply = contact.trimmingCharacters(in: .whitespacesAndNewlines)
        if !reply.isEmpty { body["contact"] = String(reply.prefix(200)) }

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "apikey")
        req.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        req.httpBody = try? JSONEncoder().encode(body)

        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else { return false }
        return true
    }
}
