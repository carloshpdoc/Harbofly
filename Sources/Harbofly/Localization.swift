import Foundation

/// Idioma da UI. Segue o `Prefs.language`: "pt"/"en"/"es"/"fr"/"de"/"zh" forçam
/// o idioma; qualquer outro valor ("system"/nil) segue o Mac (cai pra inglês
/// quando o sistema está num idioma não suportado).
enum Lang {
    case pt, en, es, fr, de, zh

    static var current: Lang {
        switch UserDefaults.standard.string(forKey: Prefs.language) {
        case "pt": return .pt
        case "en": return .en
        case "es": return .es
        case "fr": return .fr
        case "de": return .de
        case "zh": return .zh
        default:
            switch Locale.current.language.languageCode?.identifier {
            case "pt": return .pt
            case "es": return .es
            case "fr": return .fr
            case "de": return .de
            case "zh": return .zh
            default: return .en
            }
        }
    }
}

/// Strings da UI, sempre no idioma corrente. É computado (não constante) pra
/// refletir a troca manual de idioma na hora: as Views que têm
/// `@AppStorage(Prefs.language)` re-renderizam e leem o valor novo daqui.
var L10n: L { L(lang: .current) }

/// Strings da UI — mesma ideia do content.ts do site: um ponto único com todas
/// as línguas, escolhido por `Lang.current`. PT e EN são obrigatórios; os demais
/// caem pro inglês quando faltarem. Números, bytes e datas já saem localizados
/// por ByteCountFormatter/Locale.
struct L {
    let lang: Lang
    private func s(_ pt: String, _ en: String,
                   es: String? = nil, fr: String? = nil, de: String? = nil, zh: String? = nil) -> String {
        switch lang {
        case .pt: return pt
        case .en: return en
        case .es: return es ?? en
        case .fr: return fr ?? en
        case .de: return de ?? en
        case .zh: return zh ?? en
        }
    }

    // MARK: comum
    var yes: String { s("Sim", "Yes", es: "Sí", fr: "Oui", de: "Ja", zh: "是") }
    var no: String { s("Não", "No", es: "No", fr: "Non", de: "Nein", zh: "否") }
    var cancel: String { s("Cancelar", "Cancel", es: "Cancelar", fr: "Annuler", de: "Abbrechen", zh: "取消") }
    var close: String { s("Fechar", "Close", es: "Cerrar", fr: "Fermer", de: "Schließen", zh: "关闭") }
    var quit: String { s("Sair", "Quit", es: "Salir", fr: "Quitter", de: "Beenden", zh: "退出") }
    var rescan: String { s("Rescan", "Rescan", es: "Reescanear", fr: "Réanalyser", de: "Neu scannen", zh: "重新扫描") }

    // MARK: descrições dos alvos (scanner)
    var devArtifact: String { s("Artifact de build, regenera no próximo build", "Build artifact, regenerates on the next build", es: "Artefacto de build, se regenera en el próximo build", fr: "Artefact de build, régénéré à la prochaine compilation", de: "Build-Artefakt, wird beim nächsten Build neu erzeugt", zh: "构建产物，下次构建时会自动重新生成") }
    var xcodeDerived: String { s("Intermediários de build do Xcode", "Xcode build intermediates", es: "Intermedios de build de Xcode", fr: "Fichiers intermédiaires de build Xcode", de: "Xcode-Build-Zwischendateien", zh: "Xcode 构建中间文件") }
    var iosDeviceSupport: String { s("Símbolos de devices, recria ao conectar o iPhone", "Device symbols, recreated when you connect an iPhone", es: "Símbolos de dispositivos, se recrean al conectar el iPhone", fr: "Symboles d'appareils, recréés à la connexion de l'iPhone", de: "Geräte-Symbole, werden beim Verbinden des iPhones neu erstellt", zh: "设备符号，连接 iPhone 时会重新生成") }
    var xcodeBuildMCP: String { s("Workspaces do XcodeBuildMCP", "XcodeBuildMCP workspaces", es: "Workspaces de XcodeBuildMCP", fr: "Espaces de travail XcodeBuildMCP", de: "XcodeBuildMCP-Workspaces", zh: "XcodeBuildMCP 工作区") }
    var swiftpmCache: String { s("Cache do Swift Package Manager", "Swift Package Manager cache", es: "Caché de Swift Package Manager", fr: "Cache de Swift Package Manager", de: "Swift-Package-Manager-Cache", zh: "Swift Package Manager 缓存") }
    var homebrewCache: String { s("Downloads do Homebrew", "Homebrew downloads", es: "Descargas de Homebrew", fr: "Téléchargements Homebrew", de: "Homebrew-Downloads", zh: "Homebrew 下载缓存") }
    var yarnCache: String { s("Cache do Yarn", "Yarn cache", es: "Caché de Yarn", fr: "Cache Yarn", de: "Yarn-Cache", zh: "Yarn 缓存") }
    var playwrightCache: String { s("Browsers baixados pelo Playwright", "Browsers downloaded by Playwright", es: "Navegadores descargados por Playwright", fr: "Navigateurs téléchargés par Playwright", de: "Von Playwright heruntergeladene Browser", zh: "Playwright 下载的浏览器") }
    var pipCache: String { s("Cache do pip", "pip cache", es: "Caché de pip", fr: "Cache pip", de: "pip-Cache", zh: "pip 缓存") }
    var googleCache: String { s("Cache do Google/Chrome", "Google/Chrome cache", es: "Caché de Google/Chrome", fr: "Cache Google/Chrome", de: "Google/Chrome-Cache", zh: "Google/Chrome 缓存") }
    var coreSimulatorDetail: String { s("Simuladores do Xcode: apague devices velhos pelo Xcode ou `xcrun simctl delete unavailable`", "Xcode simulators: delete old devices in Xcode or `xcrun simctl delete unavailable`", es: "Simuladores de Xcode: borra dispositivos viejos desde Xcode o con `xcrun simctl delete unavailable`", fr: "Simulateurs Xcode : supprimez les anciens appareils dans Xcode ou via `xcrun simctl delete unavailable`", de: "Xcode-Simulatoren: alte Geräte in Xcode löschen oder per `xcrun simctl delete unavailable`", zh: "Xcode 模拟器：在 Xcode 中删除旧设备，或运行 `xcrun simctl delete unavailable`") }
    var appSupportDetail: String { s("Dados de apps instalados: revise pelo Finder, não apague às cegas", "Installed app data: review in Finder, don't delete blindly", es: "Datos de apps instaladas: revísalos en el Finder, no borres a ciegas", fr: "Données des apps installées : vérifiez dans le Finder, ne supprimez pas à l'aveugle", de: "Daten installierter Apps: im Finder prüfen, nicht blind löschen", zh: "已装应用的数据：请在访达中检查，不要盲目删除") }
    var downloadsDetail: String { s("Sua pasta de downloads: revise e limpe manualmente pelo Finder", "Your downloads folder: review and clean manually in Finder", es: "Tu carpeta de descargas: revísala y límpiala manualmente en el Finder", fr: "Votre dossier Téléchargements : vérifiez et nettoyez manuellement dans le Finder", de: "Dein Downloads-Ordner: manuell im Finder prüfen und aufräumen", zh: "你的下载文件夹：请在访达中自行检查和清理") }
    var pkgCache: String { s("Cache de pacotes, baixa de novo quando precisar", "Package cache, re-downloaded on demand", es: "Caché de paquetes, se vuelve a descargar cuando haga falta", fr: "Cache de paquets, retéléchargé au besoin", de: "Paket-Cache, wird bei Bedarf neu geladen", zh: "包缓存，需要时会重新下载") }
    var depsCache: String { s("Dependências baixadas — o próximo build baixa tudo de novo", "Downloaded dependencies — the next build re-downloads everything", es: "Dependencias descargadas — el próximo build lo vuelve a descargar todo", fr: "Dépendances téléchargées — le prochain build retélécharge tout", de: "Heruntergeladene Abhängigkeiten — der nächste Build lädt alles neu", zh: "已下载的依赖——下次构建会重新下载") }
    var editorCache: String { s("Cache do editor, regenera ao abrir", "Editor cache, regenerates on launch", es: "Caché del editor, se regenera al abrirlo", fr: "Cache de l'éditeur, régénéré à l'ouverture", de: "Editor-Cache, wird beim Öffnen neu erzeugt", zh: "编辑器缓存，打开时会重新生成") }
    var jetbrainsCache: String { s("Índices e caches dos IDEs JetBrains, re-indexa ao abrir os projetos", "JetBrains IDE indexes and caches, re-indexed when you open projects", es: "Índices y cachés de los IDE de JetBrains, se reindexan al abrir los proyectos", fr: "Index et caches des IDE JetBrains, réindexés à l'ouverture des projets", de: "Indizes und Caches der JetBrains-IDEs, werden beim Öffnen der Projekte neu erstellt", zh: "JetBrains IDE 的索引和缓存，打开项目时会重新建立索引") }
    var aiModels: String { s("Modelos de IA baixados — apagar exige baixar de novo (podem ser dezenas de GB)", "Downloaded AI models — deleting means re-downloading (can be tens of GB)", es: "Modelos de IA descargados — borrarlos implica descargarlos de nuevo (pueden ser decenas de GB)", fr: "Modèles d'IA téléchargés — les supprimer oblige à les retélécharger (parfois des dizaines de Go)", de: "Heruntergeladene KI-Modelle — Löschen erfordert erneutes Herunterladen (können Dutzende GB sein)", zh: "已下载的 AI 模型——删除后需要重新下载（可能有几十 GB）") }
    var xcodeArchives: String { s("Builds arquivados com dSYMs — apagar perde a simbolização de versões já publicadas", "Archived builds with dSYMs — deleting loses symbolication for shipped versions", es: "Builds archivados con dSYMs — borrarlos pierde la simbolización de versiones ya publicadas", fr: "Builds archivés avec dSYMs — les supprimer fait perdre la symbolication des versions publiées", de: "Archivierte Builds mit dSYMs — Löschen verliert die Symbolication veröffentlichter Versionen", zh: "含 dSYM 的归档构建——删除后已发布的版本将无法进行符号化") }
    var dockerLabel: String { s("Docker (não usado)", "Docker (unused)", es: "Docker (sin uso)", fr: "Docker (inutilisé)", de: "Docker (ungenutzt)", zh: "Docker（未使用）") }
    var dockerDetail: String { s("Imagens, containers e build cache do Docker sem uso. Prune irreversível, não passa pela Lixeira.", "Unused Docker images, containers and build cache. Prune is irreversible, it does not go through the Trash.", es: "Imágenes, contenedores y caché de build de Docker sin uso. El prune es irreversible, no pasa por la Papelera.", fr: "Images, conteneurs et cache de build Docker inutilisés. Le prune est irréversible, il ne passe pas par la Corbeille.", de: "Ungenutzte Docker-Images, -Container und Build-Cache. Prune ist unumkehrbar und landet nicht im Papierkorb.", zh: "未使用的 Docker 镜像、容器和构建缓存。Prune 不可撤销，不会经过废纸篓。") }
    var dockerStoppedLabel: String { s("Docker (engine desligado)", "Docker (engine off)", es: "Docker (engine apagado)", fr: "Docker (moteur arrêté)", de: "Docker (Engine aus)", zh: "Docker（引擎未运行）") }
    var dockerStoppedDetail: String { s("Disk image do Docker. Ligue o engine pra ver e recuperar o espaço não usado.", "Docker disk image. Start the engine to see and reclaim unused space.", es: "Disk image de Docker. Enciende el engine para ver y recuperar el espacio sin uso.", fr: "Image disque Docker. Démarrez le moteur pour voir et récupérer l'espace inutilisé.", de: "Docker-Disk-Image. Engine starten, um ungenutzten Speicher zu sehen und freizugeben.", zh: "Docker 磁盘镜像。启动引擎即可查看并回收未使用的空间。") }
    var dockerPruneNote: String { s("O Docker é limpo via prune (irreversível), independente da opção acima.", "Docker is cleaned via prune (irreversible), regardless of the option above.", es: "Docker se limpia con prune (irreversible), sin importar la opción de arriba.", fr: "Docker est nettoyé via prune (irréversible), quelle que soit l'option ci-dessus.", de: "Docker wird per Prune bereinigt (unumkehrbar), unabhängig von der Option oben.", zh: "Docker 通过 prune 清理（不可撤销），与上面的选项无关。") }

    // MARK: notificação de disco baixo
    var lowSpaceTitle: String { s("\(AppInfo.name): disco quase cheio", "\(AppInfo.name): disk almost full", es: "\(AppInfo.name): disco casi lleno", fr: "\(AppInfo.name) : disque presque plein", de: "\(AppInfo.name): Festplatte fast voll", zh: "\(AppInfo.name)：磁盘空间即将用完") }
    func lowSpaceBody(pct: Int, free: String) -> String {
        s("Só \(pct)% livre (\(free)). Abra o \(AppInfo.name) pra liberar espaço.",
          "Only \(pct)% free (\(free)). Open \(AppInfo.name) to free up space.",
          es: "Solo \(pct)% libre (\(free)). Abre \(AppInfo.name) para liberar espacio.",
          fr: "Seulement \(pct) % libres (\(free)). Ouvrez \(AppInfo.name) pour libérer de l'espace.",
          de: "Nur noch \(pct) % frei (\(free)). Öffne \(AppInfo.name), um Speicher freizugeben.",
          zh: "仅剩 \(pct)% 可用（\(free)）。打开 \(AppInfo.name) 释放空间。")
    }

    // MARK: opt-in de analytics
    var analyticsTitle: String { s("Ajude a melhorar o \(AppInfo.name)", "Help improve \(AppInfo.name)", es: "Ayuda a mejorar \(AppInfo.name)", fr: "Aidez à améliorer \(AppInfo.name)", de: "Hilf mit, \(AppInfo.name) zu verbessern", zh: "帮助改进 \(AppInfo.name)") }
    var analyticsSubtitle: String { s("Compartilhar dados de uso anônimos.", "Share anonymous usage data.", es: "Compartir datos de uso anónimos.", fr: "Partager des données d'utilisation anonymes.", de: "Anonyme Nutzungsdaten teilen.", zh: "分享匿名使用数据。") }
    var analyticsDetail: String { s("Só eventos e métricas agregadas. Nunca nomes, arquivos, caminhos ou IP.", "Only events and aggregate metrics. Never names, files, paths, or IP.", es: "Solo eventos y métricas agregadas. Nunca nombres, archivos, rutas ni IP.", fr: "Seulement des événements et des métriques agrégées. Jamais de noms, fichiers, chemins ni IP.", de: "Nur Ereignisse und aggregierte Metriken. Nie Namen, Dateien, Pfade oder IP.", zh: "只包含事件和汇总指标，绝不含名称、文件、路径或 IP。") }

    // MARK: confirmação de exclusão
    func confirmTitle(count: Int, size: String) -> String {
        let items = count == 1
            ? s("1 item", "1 item", es: "1 elemento", fr: "1 élément", de: "1 Element", zh: "1 个项目")
            : s("\(count) itens", "\(count) items", es: "\(count) elementos", fr: "\(count) éléments", de: "\(count) Elemente", zh: "\(count) 个项目")
        return s("Excluir \(items) (\(size))?", "Delete \(items) (\(size))?",
                 es: "¿Eliminar \(items) (\(size))?", fr: "Supprimer \(items) (\(size)) ?",
                 de: "\(items) (\(size)) löschen?", zh: "删除 \(items)（\(size)）？")
    }
    var moveToTrash: String { s("Mover pra Lixeira", "Move to Trash", es: "Mover a la Papelera", fr: "Placer dans la Corbeille", de: "In den Papierkorb", zh: "移到废纸篓") }
    var deleteForever: String { s("Excluir de vez", "Delete permanently", es: "Eliminar definitivamente", fr: "Supprimer définitivement", de: "Endgültig löschen", zh: "彻底删除") }
    var permanentExplainer: String { s("Exclusão permanente: libera o espaço na hora, sem passar pela Lixeira. Não dá pra desfazer.", "Permanent delete: frees the space right away, skipping the Trash. Can't be undone.", es: "Eliminación permanente: libera el espacio al instante, sin pasar por la Papelera. No se puede deshacer.", fr: "Suppression définitive : libère l'espace immédiatement, sans passer par la Corbeille. Irréversible.", de: "Endgültiges Löschen: gibt den Speicher sofort frei, ohne Papierkorb. Kann nicht rückgängig gemacht werden.", zh: "彻底删除：立即释放空间，不经过废纸篓。无法撤销。") }
    var trashExplainer: String { s("Vai pra Lixeira: dá pra recuperar, mas o espaço só é liberado ao esvaziar a Lixeira.", "Goes to the Trash: recoverable, but the space is only freed when you empty the Trash.", es: "Va a la Papelera: recuperable, pero el espacio solo se libera al vaciarla.", fr: "Va dans la Corbeille : récupérable, mais l'espace n'est libéré qu'en vidant la Corbeille.", de: "Wandert in den Papierkorb: wiederherstellbar, aber der Speicher wird erst beim Leeren frei.", zh: "移到废纸篓：可恢复，但只有清空废纸篓后才会释放空间。") }
    var deletePermanentlyBtn: String { s("Excluir permanentemente", "Delete permanently", es: "Eliminar permanentemente", fr: "Supprimer définitivement", de: "Endgültig löschen", zh: "永久删除") }

    // MARK: overlay de apoio / conquista
    func recovered(_ size: String) -> String { s("Você recuperou \(size)!", "You recovered \(size)!", es: "¡Recuperaste \(size)!", fr: "Vous avez récupéré \(size) !", de: "Du hast \(size) freigegeben!", zh: "你释放了 \(size)！") }
    func trashed(_ size: String) -> String { s("\(size) mandados pra Lixeira!", "\(size) moved to the Trash!", es: "¡\(size) enviados a la Papelera!", fr: "\(size) placés dans la Corbeille !", de: "\(size) in den Papierkorb verschoben!", zh: "已将 \(size) 移到废纸篓！") }
    var thanks: String { s("Obrigado! 💙", "Thank you! 💙", es: "¡Gracias! 💙", fr: "Merci ! 💙", de: "Danke! 💙", zh: "谢谢！💙") }
    var share: String { s("Compartilhar", "Share", es: "Compartir", fr: "Partager", de: "Teilen", zh: "分享") }
    var donateAsk: String { s("\(AppInfo.name) é grátis. Se te ajudou, me paga um café (R$2) pra apoiar o projeto 💙", "\(AppInfo.name) is free. If it helped, buy me a coffee (R$2) to support the project 💙", es: "\(AppInfo.name) es gratis. Si te ayudó, invítame a un café para apoyar el proyecto 💙", fr: "\(AppInfo.name) est gratuit. S'il vous a aidé, offrez-moi un café pour soutenir le projet 💙", de: "\(AppInfo.name) ist kostenlos. Wenn es dir geholfen hat, spendier mir einen Kaffee, um das Projekt zu unterstützen 💙", zh: "\(AppInfo.name) 是免费的。如果它帮到了你，请我喝杯咖啡来支持这个项目吧 💙") }
    var pixCopied: String { s("Chave PIX copiada!", "PIX key copied!", es: "¡Clave PIX copiada!", fr: "Clé PIX copiée !", de: "PIX-Schlüssel kopiert!", zh: "PIX 密钥已复制！") }
    var copyPix: String { s("Copiar chave PIX (R$2)", "Copy PIX key (R$2)", es: "Copiar clave PIX", fr: "Copier la clé PIX", de: "PIX-Schlüssel kopieren", zh: "复制 PIX 密钥") }
    var alreadySupported: String { s("Já apoiei ❤️", "Already supported ❤️", es: "Ya aporté ❤️", fr: "J'ai déjà soutenu ❤️", de: "Schon unterstützt ❤️", zh: "已支持 ❤️") }
    var notNow: String { s("Agora não", "Not now", es: "Ahora no", fr: "Pas maintenant", de: "Jetzt nicht", zh: "暂时不用") }

    // MARK: header
    var openInWindow: String { s("Abrir em janela", "Open in a window", es: "Abrir en ventana", fr: "Ouvrir dans une fenêtre", de: "In Fenster öffnen", zh: "在窗口中打开") }
    func freeOfTotal(free: String, total: String) -> String { s("\(free) livre de \(total)", "\(free) free of \(total)", es: "\(free) libres de \(total)", fr: "\(free) libres sur \(total)", de: "\(free) von \(total) frei", zh: "可用 \(free) / 共 \(total)") }
    func reclaimable(_ size: String) -> String { s("Recuperável: \(size)", "Recoverable: \(size)", es: "Recuperable: \(size)", fr: "Récupérable : \(size)", de: "Freigebbar: \(size)", zh: "可回收：\(size)") }

    // MARK: lista
    var scanning: String { s("Escaneando…", "Scanning…", es: "Escaneando…", fr: "Analyse…", de: "Scanne…", zh: "扫描中…") }
    var nothingFound: String { s("Nada relevante encontrado 🎉", "Nothing relevant found 🎉", es: "No se encontró nada relevante 🎉", fr: "Rien de pertinent trouvé 🎉", de: "Nichts Relevantes gefunden 🎉", zh: "没有发现可清理的内容 🎉") }
    var tierSafe: String { s("🟢 Seguro: regenera sozinho", "🟢 Safe: regenerates itself", es: "🟢 Seguro: se regenera solo", fr: "🟢 Sûr : se régénère tout seul", de: "🟢 Sicher: regeneriert sich selbst", zh: "🟢 安全：会自动重新生成") }
    var tierCaution: String { s("🟡 Cuidado: recria, mas custa", "🟡 Caution: rebuilds, but costs", es: "🟡 Cuidado: se recrea, pero cuesta", fr: "🟡 Attention : se recrée, mais ça coûte", de: "🟡 Vorsicht: wird neu erstellt, kostet aber", zh: "🟡 谨慎：可重建，但有代价") }
    var tierInfo: String { s("🔵 Informativo: só pra você saber (o app não apaga)", "🔵 Info: just so you know (the app doesn't delete)", es: "🔵 Informativo: solo para que lo sepas (la app no borra)", fr: "🔵 Info : juste pour information (l'app ne supprime pas)", de: "🔵 Info: nur zur Kenntnis (die App löscht nichts)", zh: "🔵 信息：仅供参考（应用不会删除）") }
    var revealInFinder: String { s("Revelar no Finder", "Reveal in Finder", es: "Mostrar en el Finder", fr: "Afficher dans le Finder", de: "Im Finder zeigen", zh: "在访达中显示") }

    // MARK: footer
    var selectSafe: String { s("Selecionar seguros", "Select safe", es: "Seleccionar seguros", fr: "Sélectionner les sûrs", de: "Sichere auswählen", zh: "选择安全项") }
    var clearSelection: String { s("Limpar seleção", "Clear selection", es: "Limpiar selección", fr: "Effacer la sélection", de: "Auswahl aufheben", zh: "清除选择") }
    var delete: String { s("Excluir", "Delete", es: "Eliminar", fr: "Supprimer", de: "Löschen", zh: "删除") }
    func deleteWithSize(_ size: String) -> String { s("Excluir (\(size))", "Delete (\(size))", es: "Eliminar (\(size))", fr: "Supprimer (\(size))", de: "Löschen (\(size))", zh: "删除（\(size)）") }
    func updatedAt(_ time: String) -> String { s("Atualizado \(time)", "Updated \(time)", es: "Actualizado \(time)", fr: "Mis à jour à \(time)", de: "Aktualisiert \(time)", zh: "更新于 \(time)") }
    var notifyBelow: String { s("Avisar quando o disco livre cair abaixo de", "Warn when free disk drops below", es: "Avisar cuando el espacio libre baje de", fr: "Prévenir si l'espace libre passe sous", de: "Warnen bei freiem Speicher unter", zh: "当可用空间低于此值时提醒") }
    var shareAnonToggle: String { s("Compartilhar dados de uso anônimos", "Share anonymous usage data", es: "Compartir datos de uso anónimos", fr: "Partager des données d'utilisation anonymes", de: "Anonyme Nutzungsdaten teilen", zh: "分享匿名使用数据") }
    var autoUpdateToggle: String { s("Buscar atualizações automaticamente", "Check for updates automatically", es: "Buscar actualizaciones automáticamente", fr: "Rechercher les mises à jour automatiquement", de: "Automatisch nach Updates suchen", zh: "自动检查更新") }
    var checkNow: String { s("Buscar agora", "Check now", es: "Buscar ahora", fr: "Vérifier maintenant", de: "Jetzt suchen", zh: "立即检查") }
    var openAtLogin: String { s("Abrir no login", "Open at login", es: "Abrir al iniciar sesión", fr: "Ouvrir à la connexion", de: "Beim Anmelden öffnen", zh: "登录时打开") }
    var supportCta: String { s("Apoiar ☕", "Support ☕", es: "Apoyar ☕", fr: "Soutenir ☕", de: "Unterstützen ☕", zh: "支持 ☕") }
    var languageLabel: String { s("Idioma", "Language", es: "Idioma", fr: "Langue", de: "Sprache", zh: "语言") }
    var langSystem: String { s("Sistema", "System", es: "Sistema", fr: "Système", de: "System", zh: "跟随系统") }

    // MARK: feedback
    var feedbackCta: String { s("Feedback", "Feedback", es: "Comentarios", fr: "Votre avis", de: "Feedback", zh: "反馈") }
    var feedbackTitle: String { s("Enviar feedback", "Send feedback", es: "Enviar comentarios", fr: "Donner votre avis", de: "Feedback senden", zh: "发送反馈") }
    var feedbackSubtitle: String { s("Bug, ideia ou sugestão — vai direto pro criador do app.", "Bug, idea or suggestion — goes straight to the app's creator.", es: "Bug, idea o sugerencia — va directo al creador de la app.", fr: "Bug, idée ou suggestion — envoyé directement au créateur de l'app.", de: "Bug, Idee oder Vorschlag — geht direkt an den Entwickler der App.", zh: "Bug、想法或建议——直接发送给应用的开发者。") }
    var feedbackContactPlaceholder: String { s("Email pra resposta (opcional)", "Email for a reply (optional)", es: "Email para respuesta (opcional)", fr: "E-mail pour une réponse (facultatif)", de: "E-Mail für Antwort (optional)", zh: "回复邮箱（选填）") }
    var feedbackSend: String { s("Enviar", "Send", es: "Enviar", fr: "Envoyer", de: "Senden", zh: "发送") }
    var feedbackSending: String { s("Enviando…", "Sending…", es: "Enviando…", fr: "Envoi…", de: "Wird gesendet…", zh: "发送中…") }
    var feedbackThanks: String { s("Recebido! Obrigado 💙", "Received! Thank you 💙", es: "¡Recibido! Gracias 💙", fr: "Bien reçu ! Merci 💙", de: "Angekommen! Danke 💙", zh: "已收到！谢谢 💙") }
    var feedbackError: String { s("Não deu pra enviar. Confere a internet e tenta de novo?", "Couldn't send. Check your connection and try again?", es: "No se pudo enviar. Revisa tu conexión e inténtalo de nuevo.", fr: "Échec de l'envoi. Vérifiez votre connexion et réessayez.", de: "Senden fehlgeschlagen. Verbindung prüfen und erneut versuchen?", zh: "发送失败。请检查网络后重试。") }
    var feedbackPrivacyNote: String { s("Enviado junto: versão do app e do macOS. Nada mais.", "Sent along: app and macOS version. Nothing else.", es: "Se envía junto: versión de la app y de macOS. Nada más.", fr: "Envoyé avec : version de l'app et de macOS. Rien d'autre.", de: "Mitgesendet: App- und macOS-Version. Sonst nichts.", zh: "随同发送：应用和 macOS 版本，仅此而已。") }

    // MARK: card de compartilhamento
    var shareCardVerb: String { s("Recuperei", "Recovered", es: "Recuperé", fr: "J'ai récupéré", de: "Ich habe", zh: "我释放了") }
    var shareCardTail: String { s("de espaço no meu Mac com o Harbofly 🗑️", "of space on my Mac with Harbofly 🗑️", es: "de espacio en mi Mac con Harbofly 🗑️", fr: "d'espace sur mon Mac avec Harbofly 🗑️", de: "auf meinem Mac freigegeben — mit Harbofly 🗑️", zh: "的 Mac 磁盘空间 — 用 Harbofly 🗑️") }
    func shareText(_ size: String) -> String {
        s("Recuperei \(size) de espaço no meu Mac com o Harbofly 🗑️ https://harbofly.app",
          "Recovered \(size) of space on my Mac with Harbofly 🗑️ https://harbofly.app",
          es: "Recuperé \(size) de espacio en mi Mac con Harbofly 🗑️ https://harbofly.app",
          fr: "J'ai récupéré \(size) d'espace sur mon Mac avec Harbofly 🗑️ https://harbofly.app",
          de: "Ich habe mit Harbofly \(size) Speicherplatz auf meinem Mac freigegeben 🗑️ https://harbofly.app",
          zh: "我用 Harbofly 释放了 \(size) 的 Mac 磁盘空间 🗑️ https://harbofly.app")
    }
}
