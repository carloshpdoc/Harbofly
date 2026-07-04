import Foundation

/// Idioma da UI. Segue o `Prefs.language`: "pt"/"en" forçam o idioma; qualquer
/// outro valor ("system"/nil) segue o Mac (PT quando o sistema é português,
/// inglês caso contrário).
enum Lang {
    case pt, en
    static var current: Lang {
        switch UserDefaults.standard.string(forKey: Prefs.language) {
        case "pt": return .pt
        case "en": return .en
        default: return Locale.current.language.languageCode?.identifier == "pt" ? .pt : .en
        }
    }
}

/// Strings da UI, sempre no idioma corrente. É computado (não constante) pra
/// refletir a troca manual de idioma na hora: as Views que têm
/// `@AppStorage(Prefs.language)` re-renderizam e leem o valor novo daqui.
var L10n: L { L(lang: .current) }

/// Strings da UI em PT/EN — mesma ideia do content.ts do site: um ponto único
/// com as duas línguas, escolhido por `Lang.current`. Números, bytes e datas já
/// saem localizados por ByteCountFormatter/Locale.
struct L {
    let lang: Lang
    private func s(_ pt: String, _ en: String) -> String { lang == .pt ? pt : en }

    // MARK: comum
    var yes: String { s("Sim", "Yes") }
    var no: String { s("Não", "No") }
    var cancel: String { s("Cancelar", "Cancel") }
    var close: String { s("Fechar", "Close") }
    var quit: String { s("Sair", "Quit") }
    var rescan: String { s("Rescan", "Rescan") }

    // MARK: descrições dos alvos (scanner)
    var devArtifact: String { s("Artifact de build, regenera no próximo build", "Build artifact, regenerates on the next build") }
    var xcodeDerived: String { s("Intermediários de build do Xcode", "Xcode build intermediates") }
    var iosDeviceSupport: String { s("Símbolos de devices, recria ao conectar o iPhone", "Device symbols, recreated when you connect an iPhone") }
    var xcodeBuildMCP: String { s("Workspaces do XcodeBuildMCP", "XcodeBuildMCP workspaces") }
    var swiftpmCache: String { s("Cache do Swift Package Manager", "Swift Package Manager cache") }
    var homebrewCache: String { s("Downloads do Homebrew", "Homebrew downloads") }
    var yarnCache: String { s("Cache do Yarn", "Yarn cache") }
    var playwrightCache: String { s("Browsers baixados pelo Playwright", "Browsers downloaded by Playwright") }
    var pipCache: String { s("Cache do pip", "pip cache") }
    var googleCache: String { s("Cache do Google/Chrome", "Google/Chrome cache") }
    var coreSimulatorDetail: String { s("Simuladores do Xcode: apague devices velhos pelo Xcode ou `xcrun simctl delete unavailable`", "Xcode simulators: delete old devices in Xcode or `xcrun simctl delete unavailable`") }
    var appSupportDetail: String { s("Dados de apps instalados: revise pelo Finder, não apague às cegas", "Installed app data: review in Finder, don't delete blindly") }
    var downloadsDetail: String { s("Sua pasta de downloads: revise e limpe manualmente pelo Finder", "Your downloads folder: review and clean manually in Finder") }

    // MARK: notificação de disco baixo
    var lowSpaceTitle: String { s("\(AppInfo.name): disco quase cheio", "\(AppInfo.name): disk almost full") }
    func lowSpaceBody(pct: Int, free: String) -> String {
        s("Só \(pct)% livre (\(free)). Abra o \(AppInfo.name) pra liberar espaço.",
          "Only \(pct)% free (\(free)). Open \(AppInfo.name) to free up space.")
    }

    // MARK: opt-in de analytics
    var analyticsTitle: String { s("Ajude a melhorar o \(AppInfo.name)", "Help improve \(AppInfo.name)") }
    var analyticsSubtitle: String { s("Compartilhar dados de uso anônimos.", "Share anonymous usage data.") }
    var analyticsDetail: String { s("Só eventos e métricas agregadas. Nunca nomes, arquivos, caminhos ou IP.", "Only events and aggregate metrics. Never names, files, paths, or IP.") }

    // MARK: confirmação de exclusão
    func confirmTitle(count: Int, size: String) -> String {
        let items = count == 1 ? s("1 item", "1 item") : s("\(count) itens", "\(count) items")
        return s("Excluir \(items) (\(size))?", "Delete \(items) (\(size))?")
    }
    var moveToTrash: String { s("Mover pra Lixeira", "Move to Trash") }
    var deleteForever: String { s("Excluir de vez", "Delete permanently") }
    var permanentExplainer: String { s("Exclusão permanente: libera o espaço na hora, sem passar pela Lixeira. Não dá pra desfazer.", "Permanent delete: frees the space right away, skipping the Trash. Can't be undone.") }
    var trashExplainer: String { s("Vai pra Lixeira: dá pra recuperar, mas o espaço só é liberado ao esvaziar a Lixeira.", "Goes to the Trash: recoverable, but the space is only freed when you empty the Trash.") }
    var deletePermanentlyBtn: String { s("Excluir permanentemente", "Delete permanently") }

    // MARK: overlay de apoio / conquista
    func recovered(_ size: String) -> String { s("Você recuperou \(size)!", "You recovered \(size)!") }
    func trashed(_ size: String) -> String { s("\(size) mandados pra Lixeira!", "\(size) moved to the Trash!") }
    var thanks: String { s("Obrigado! 💙", "Thank you! 💙") }
    var share: String { s("Compartilhar", "Share") }
    var donateAsk: String { s("\(AppInfo.name) é grátis. Se te ajudou, me paga um café (R$2) pra apoiar o projeto 💙", "\(AppInfo.name) is free. If it helped, buy me a coffee (R$2) to support the project 💙") }
    var pixCopied: String { s("Chave PIX copiada!", "PIX key copied!") }
    var copyPix: String { s("Copiar chave PIX (R$2)", "Copy PIX key (R$2)") }
    var alreadySupported: String { s("Já apoiei ❤️", "Already supported ❤️") }
    var notNow: String { s("Agora não", "Not now") }

    // MARK: header
    var openInWindow: String { s("Abrir em janela", "Open in a window") }
    func freeOfTotal(free: String, total: String) -> String { s("\(free) livre de \(total)", "\(free) free of \(total)") }
    func reclaimable(_ size: String) -> String { s("Recuperável: \(size)", "Recoverable: \(size)") }

    // MARK: lista
    var scanning: String { s("Escaneando…", "Scanning…") }
    var nothingFound: String { s("Nada relevante encontrado 🎉", "Nothing relevant found 🎉") }
    var tierSafe: String { s("🟢 Seguro: regenera sozinho", "🟢 Safe: regenerates itself") }
    var tierCaution: String { s("🟡 Cuidado: recria, mas custa", "🟡 Caution: rebuilds, but costs") }
    var tierInfo: String { s("🔵 Informativo: só pra você saber (o app não apaga)", "🔵 Info: just so you know (the app doesn't delete)") }
    var revealInFinder: String { s("Revelar no Finder", "Reveal in Finder") }

    // MARK: footer
    var selectSafe: String { s("Selecionar seguros", "Select safe") }
    var clearSelection: String { s("Limpar seleção", "Clear selection") }
    var delete: String { s("Excluir", "Delete") }
    func deleteWithSize(_ size: String) -> String { s("Excluir (\(size))", "Delete (\(size))") }
    func updatedAt(_ time: String) -> String { s("Atualizado \(time)", "Updated \(time)") }
    var notifyBelow: String { s("Avisar quando o disco livre cair abaixo de", "Warn when free disk drops below") }
    var shareAnonToggle: String { s("Compartilhar dados de uso anônimos", "Share anonymous usage data") }
    var autoUpdateToggle: String { s("Buscar atualizações automaticamente", "Check for updates automatically") }
    var checkNow: String { s("Buscar agora", "Check now") }
    var openAtLogin: String { s("Abrir no login", "Open at login") }
    var supportCta: String { s("Apoiar ☕", "Support ☕") }
    var languageLabel: String { s("Idioma", "Language") }
    var langSystem: String { s("Sistema", "System") }

    // MARK: card de compartilhamento
    var shareCardVerb: String { s("Recuperei", "Recovered") }
    var shareCardTail: String { s("de espaço no meu Mac com o Harbofly 🗑️", "of space on my Mac with Harbofly 🗑️") }
    func shareText(_ size: String) -> String {
        s("Recuperei \(size) de espaço no meu Mac com o Harbofly 🗑️ https://harbofly.app",
          "Recovered \(size) of space on my Mac with Harbofly 🗑️ https://harbofly.app")
    }
}
