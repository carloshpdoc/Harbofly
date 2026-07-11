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
    var documentsDetail: String { s("Seus documentos: revise e limpe manualmente pelo Finder", "Your documents: review and clean manually in Finder", es: "Tus documentos: revísalos y límpialos manualmente en el Finder", fr: "Vos documents : vérifiez et nettoyez manuellement dans le Finder", de: "Deine Dokumente: manuell im Finder prüfen und aufräumen", zh: "你的文稿文件夹：请在访达中自行检查和清理") }
    var desktopDetail: String { s("Sua Mesa: revise e limpe manualmente pelo Finder", "Your Desktop: review and clean manually in Finder", es: "Tu escritorio: revísalo y límpialo manualmente en el Finder", fr: "Votre bureau : vérifiez et nettoyez manuellement dans le Finder", de: "Dein Schreibtisch: manuell im Finder prüfen und aufräumen", zh: "你的桌面：请在访达中自行检查和清理") }
    var pkgCache: String { s("Cache de pacotes, baixa de novo quando precisar", "Package cache, re-downloaded on demand", es: "Caché de paquetes, se vuelve a descargar cuando haga falta", fr: "Cache de paquets, retéléchargé au besoin", de: "Paket-Cache, wird bei Bedarf neu geladen", zh: "包缓存，需要时会重新下载") }
    var depsCache: String { s("Dependências baixadas — o próximo build baixa tudo de novo", "Downloaded dependencies — the next build re-downloads everything", es: "Dependencias descargadas — el próximo build lo vuelve a descargar todo", fr: "Dépendances téléchargées — le prochain build retélécharge tout", de: "Heruntergeladene Abhängigkeiten — der nächste Build lädt alles neu", zh: "已下载的依赖——下次构建会重新下载") }
    var editorCache: String { s("Cache do editor, regenera ao abrir", "Editor cache, regenerates on launch", es: "Caché del editor, se regenera al abrirlo", fr: "Cache de l'éditeur, régénéré à l'ouverture", de: "Editor-Cache, wird beim Öffnen neu erzeugt", zh: "编辑器缓存，打开时会重新生成") }
    var jetbrainsCache: String { s("Índices e caches dos IDEs JetBrains, re-indexa ao abrir os projetos", "JetBrains IDE indexes and caches, re-indexed when you open projects", es: "Índices y cachés de los IDE de JetBrains, se reindexan al abrir los proyectos", fr: "Index et caches des IDE JetBrains, réindexés à l'ouverture des projets", de: "Indizes und Caches der JetBrains-IDEs, werden beim Öffnen der Projekte neu erstellt", zh: "JetBrains IDE 的索引和缓存，打开项目时会重新建立索引") }
    var aiModels: String { s("Modelos de IA baixados — apagar exige baixar de novo (podem ser dezenas de GB)", "Downloaded AI models — deleting means re-downloading (can be tens of GB)", es: "Modelos de IA descargados — borrarlos implica descargarlos de nuevo (pueden ser decenas de GB)", fr: "Modèles d'IA téléchargés — les supprimer oblige à les retélécharger (parfois des dizaines de Go)", de: "Heruntergeladene KI-Modelle — Löschen erfordert erneutes Herunterladen (können Dutzende GB sein)", zh: "已下载的 AI 模型——删除后需要重新下载（可能有几十 GB）") }
    var xcodeArchives: String { s("Builds arquivados com dSYMs — apagar perde a simbolização de versões já publicadas", "Archived builds with dSYMs — deleting loses symbolication for shipped versions", es: "Builds archivados con dSYMs — borrarlos pierde la simbolización de versiones ya publicadas", fr: "Builds archivés avec dSYMs — les supprimer fait perdre la symbolication des versions publiées", de: "Archivierte Builds mit dSYMs — Löschen verliert die Symbolication veröffentlichter Versionen", zh: "含 dSYM 的归档构建——删除后已发布的版本将无法进行符号化") }
    var purgeableLabel: String { s("Espaço purgeável do macOS", "macOS purgeable space", es: "Espacio purgable de macOS", fr: "Espace purgeable de macOS", de: "Bereinigbarer macOS-Speicher", zh: "macOS 可清除空间") }
    var purgeableDetail: String { s("Snapshots do Time Machine e caches do sistema que o macOS libera sozinho quando falta espaço. É por isso que o livre do Finder difere daqui — não precisa apagar na mão.", "Time Machine snapshots and system caches macOS frees on its own when space runs low. That's why Finder's free space differs from here — no need to delete anything manually.", es: "Snapshots de Time Machine y cachés del sistema que macOS libera solo cuando falta espacio. Por eso el espacio libre del Finder difiere de este — no hace falta borrar nada a mano.", fr: "Snapshots Time Machine et caches système que macOS libère tout seul quand l'espace manque. C'est pourquoi l'espace libre du Finder diffère d'ici — rien à supprimer à la main.", de: "Time-Machine-Snapshots und System-Caches, die macOS bei Platzmangel selbst freigibt. Deshalb weicht der freie Speicher im Finder hiervon ab — manuelles Löschen ist unnötig.", zh: "Time Machine 快照和系统缓存，macOS 会在空间不足时自动释放。这就是访达显示的可用空间与此处不同的原因——无需手动删除。") }
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
    var xcodeRunningNote: String { s("O Xcode está aberto — feche antes de limpar caches dele pra não atrapalhar um build em andamento.", "Xcode is running — quit it before cleaning its caches so you don't disrupt an ongoing build.", es: "Xcode está abierto — ciérralo antes de limpiar sus cachés para no interrumpir un build en curso.", fr: "Xcode est ouvert — quittez-le avant de nettoyer ses caches pour ne pas perturber un build en cours.", de: "Xcode läuft — beende es vor dem Bereinigen seiner Caches, um keinen laufenden Build zu stören.", zh: "Xcode 正在运行——清理其缓存前请先退出，以免影响正在进行的构建。") }

    // MARK: overlay de apoio / conquista
    func recovered(_ size: String) -> String { s("Você recuperou \(size)!", "You recovered \(size)!", es: "¡Recuperaste \(size)!", fr: "Vous avez récupéré \(size) !", de: "Du hast \(size) freigegeben!", zh: "你释放了 \(size)！") }
    func trashed(_ size: String) -> String { s("\(size) mandados pra Lixeira!", "\(size) moved to the Trash!", es: "¡\(size) enviados a la Papelera!", fr: "\(size) placés dans la Corbeille !", de: "\(size) in den Papierkorb verschoben!", zh: "已将 \(size) 移到废纸篓！") }
    var thanks: String { s("Obrigado! 💙", "Thank you! 💙", es: "¡Gracias! 💙", fr: "Merci ! 💙", de: "Danke! 💙", zh: "谢谢！💙") }
    var share: String { s("Compartilhar", "Share", es: "Compartir", fr: "Partager", de: "Teilen", zh: "分享") }
    var donateAsk: String { s("\(AppInfo.name) é grátis. Se te ajudou, me paga um café (R$2) pra apoiar o projeto 💙", "\(AppInfo.name) is free. If it helped, buy me a coffee (R$2) to support the project 💙", es: "\(AppInfo.name) es gratis. Si te ayudó, invítame a un café para apoyar el proyecto 💙", fr: "\(AppInfo.name) est gratuit. S'il vous a aidé, offrez-moi un café pour soutenir le projet 💙", de: "\(AppInfo.name) ist kostenlos. Wenn es dir geholfen hat, spendier mir einen Kaffee, um das Projekt zu unterstützen 💙", zh: "\(AppInfo.name) 是免费的。如果它帮到了你，请我喝杯咖啡来支持这个项目吧 💙") }
    var pixCopied: String { s("Chave PIX copiada!", "PIX key copied!", es: "¡Clave PIX copiada!", fr: "Clé PIX copiée !", de: "PIX-Schlüssel kopiert!", zh: "PIX 密钥已复制！") }
    var copyPix: String { s("Copiar chave PIX (R$2)", "Copy PIX key (R$2)", es: "Copiar clave PIX", fr: "Copier la clé PIX", de: "PIX-Schlüssel kopieren", zh: "复制 PIX 密钥") }
    var alreadySupported: String { s("Já apoiei ❤️", "Already supported ❤️", es: "Ya aporté ❤️", fr: "J'ai déjà soutenu ❤️", de: "Schon unterstützt ❤️", zh: "已支持 ❤️") }
    func totalFreed(_ size: String) -> String { s("No total, o \(AppInfo.name) já liberou \(size) pra você", "In total, \(AppInfo.name) has freed \(size) for you", es: "En total, \(AppInfo.name) ya liberó \(size) para ti", fr: "Au total, \(AppInfo.name) a déjà libéré \(size) pour vous", de: "Insgesamt hat \(AppInfo.name) schon \(size) für dich freigegeben", zh: "\(AppInfo.name) 总共已为你释放了 \(size)") }
    var notNow: String { s("Agora não", "Not now", es: "Ahora no", fr: "Pas maintenant", de: "Jetzt nicht", zh: "暂时不用") }

    // MARK: header
    var openInWindow: String { s("Abrir em janela", "Open in a window", es: "Abrir en ventana", fr: "Ouvrir dans une fenêtre", de: "In Fenster öffnen", zh: "在窗口中打开") }
    func freeOfTotal(free: String, total: String) -> String { s("\(free) livre de \(total)", "\(free) free of \(total)", es: "\(free) libres de \(total)", fr: "\(free) libres sur \(total)", de: "\(free) von \(total) frei", zh: "可用 \(free) / 共 \(total)") }
    func reclaimable(_ size: String) -> String { s("Recuperável: \(size)", "Recoverable: \(size)", es: "Recuperable: \(size)", fr: "Récupérable : \(size)", de: "Freigebbar: \(size)", zh: "可回收：\(size)") }

    // MARK: lista
    var scanning: String { s("Escaneando…", "Scanning…", es: "Escaneando…", fr: "Analyse…", de: "Scanne…", zh: "扫描中…") }
    func cleaningProgress(done: Int, total: Int) -> String {
        s("Limpando… \(done)/\(total)", "Cleaning… \(done)/\(total)",
          es: "Limpiando… \(done)/\(total)", fr: "Nettoyage… \(done)/\(total)",
          de: "Aufräumen… \(done)/\(total)", zh: "清理中… \(done)/\(total)")
    }
    var nothingFound: String { s("Nada relevante encontrado 🎉", "Nothing relevant found 🎉", es: "No se encontró nada relevante 🎉", fr: "Rien de pertinent trouvé 🎉", de: "Nichts Relevantes gefunden 🎉", zh: "没有发现可清理的内容 🎉") }
    var tierSafe: String { s("🟢 Seguro: regenera sozinho", "🟢 Safe: regenerates itself", es: "🟢 Seguro: se regenera solo", fr: "🟢 Sûr : se régénère tout seul", de: "🟢 Sicher: regeneriert sich selbst", zh: "🟢 安全：会自动重新生成") }
    var tierCaution: String { s("🟡 Cuidado: recria, mas custa", "🟡 Caution: rebuilds, but costs", es: "🟡 Cuidado: se recrea, pero cuesta", fr: "🟡 Attention : se recrée, mais ça coûte", de: "🟡 Vorsicht: wird neu erstellt, kostet aber", zh: "🟡 谨慎：可重建，但有代价") }
    var tierInfo: String { s("🔵 Informativo: só pra você saber (o app não apaga)", "🔵 Info: just so you know (the app doesn't delete)", es: "🔵 Informativo: solo para que lo sepas (la app no borra)", fr: "🔵 Info : juste pour information (l'app ne supprime pas)", de: "🔵 Info: nur zur Kenntnis (die App löscht nichts)", zh: "🔵 信息：仅供参考（应用不会删除）") }
    var revealInFinder: String { s("Revelar no Finder", "Reveal in Finder", es: "Mostrar en el Finder", fr: "Afficher dans le Finder", de: "Im Finder zeigen", zh: "在访达中显示") }
    var deleteOldSims: String { s("Apagar simuladores antigos", "Delete old simulators", es: "Borrar simuladores antiguos", fr: "Supprimer les anciens simulateurs", de: "Alte Simulatoren löschen", zh: "删除旧模拟器") }
    var deleteOldSimsConfirm: String { s("Tem certeza? Remove de vez (simctl delete unavailable)", "Are you sure? Removes permanently (simctl delete unavailable)", es: "¿Seguro? Se eliminan de forma permanente (simctl delete unavailable)", fr: "Sûr ? Suppression définitive (simctl delete unavailable)", de: "Sicher? Endgültiges Löschen (simctl delete unavailable)", zh: "确定吗？将永久删除（simctl delete unavailable）") }

    // MARK: projetos parados (staleness)
    func staleProject(days: Int) -> String {
        let months = days / 30
        if months >= 2 {
            return s("Projeto parado há \(months) meses", "Project idle for \(months) months",
                     es: "Proyecto inactivo desde hace \(months) meses", fr: "Projet inactif depuis \(months) mois",
                     de: "Projekt seit \(months) Monaten inaktiv", zh: "项目已闲置 \(months) 个月")
        }
        return s("Projeto parado há \(days) dias", "Project idle for \(days) days",
                 es: "Proyecto inactivo desde hace \(days) días", fr: "Projet inactif depuis \(days) jours",
                 de: "Projekt seit \(days) Tagen inaktiv", zh: "项目已闲置 \(days) 天")
    }
    var selectStale: String { s("Parados", "Stale", es: "Inactivos", fr: "Inactifs", de: "Inaktive", zh: "闲置项") }
    var selectStaleHelp: String { s("Artifacts de projetos sem atividade (git/arquivos) há 90+ dias", "Artifacts from projects with no activity (git/files) in 90+ days", es: "Artefactos de proyectos sin actividad (git/archivos) desde hace 90+ días", fr: "Artefacts de projets sans activité (git/fichiers) depuis 90+ jours", de: "Artefakte von Projekten ohne Aktivität (Git/Dateien) seit 90+ Tagen", zh: "来自 90 天以上无活动（git/文件）项目的产物") }
    var unsavedWorkNote: String { s("Tem mudanças não commitadas ou não enviadas ao remoto", "Has uncommitted or unpushed changes", es: "Tiene cambios sin commit o sin push", fr: "Contient des modifications non commitées ou non poussées", de: "Hat nicht committete oder nicht gepushte Änderungen", zh: "有未提交或未推送的更改") }

    // MARK: footer
    var selectLabel: String { s("Selecionar:", "Select:", es: "Seleccionar:", fr: "Sélectionner :", de: "Auswählen:", zh: "选择：") }
    var selectSafe: String { s("Seguros", "Safe", es: "Seguros", fr: "Sûrs", de: "Sichere", zh: "安全项") }
    var selectSafeHelp: String { s("Seleciona tudo do tier 🟢 seguro (regenera sozinho)", "Selects everything in the 🟢 safe tier (regenerates itself)", es: "Selecciona todo el nivel 🟢 seguro (se regenera solo)", fr: "Sélectionne tout le niveau 🟢 sûr (se régénère tout seul)", de: "Wählt alles der Stufe 🟢 sicher aus (regeneriert sich selbst)", zh: "选择所有 🟢 安全项（会自动重新生成）") }
    var clearSelection: String { s("Limpar seleção", "Clear selection", es: "Limpiar selección", fr: "Effacer la sélection", de: "Auswahl aufheben", zh: "清除选择") }
    var delete: String { s("Excluir", "Delete", es: "Eliminar", fr: "Supprimer", de: "Löschen", zh: "删除") }
    func deleteWithSize(_ size: String) -> String { s("Excluir (\(size))", "Delete (\(size))", es: "Eliminar (\(size))", fr: "Supprimer (\(size))", de: "Löschen (\(size))", zh: "删除（\(size)）") }
    func updatedAt(_ time: String) -> String { s("Atualizado \(time)", "Updated \(time)", es: "Actualizado \(time)", fr: "Mis à jour à \(time)", de: "Aktualisiert \(time)", zh: "更新于 \(time)") }
    var notifyBelow: String { s("Avisar quando o disco livre cair abaixo de", "Warn when free disk drops below", es: "Avisar cuando el espacio libre baje de", fr: "Prévenir si l'espace libre passe sous", de: "Warnen bei freiem Speicher unter", zh: "当可用空间低于此值时提醒") }
    var shareAnonToggle: String { s("Compartilhar dados de uso anônimos", "Share anonymous usage data", es: "Compartir datos de uso anónimos", fr: "Partager des données d'utilisation anonymes", de: "Anonyme Nutzungsdaten teilen", zh: "分享匿名使用数据") }
    var autoUpdateToggle: String { s("Buscar atualizações automaticamente", "Check for updates automatically", es: "Buscar actualizaciones automáticamente", fr: "Rechercher les mises à jour automatiquement", de: "Automatisch nach Updates suchen", zh: "自动检查更新") }

    // MARK: auto-clean
    var autoCleanToggle: String { s("Limpar seguros automaticamente", "Auto-clean safe items", es: "Limpiar seguros automáticamente", fr: "Nettoyage auto des éléments sûrs", de: "Sichere automatisch bereinigen", zh: "自动清理安全项") }
    var autoCleanXcode: String { s("Ao fechar o Xcode", "When Xcode quits", es: "Al cerrar Xcode", fr: "À la fermeture de Xcode", de: "Beim Beenden von Xcode", zh: "退出 Xcode 时") }
    var autoCleanDaily: String { s("Diariamente", "Daily", es: "A diario", fr: "Chaque jour", de: "Täglich", zh: "每天") }
    var autoCleanWeekly: String { s("Semanalmente", "Weekly", es: "Semanalmente", fr: "Chaque semaine", de: "Wöchentlich", zh: "每周") }
    var autoCleanNote: String { s("Só itens 🟢 seguros, sempre pra Lixeira. Seu código-fonte nunca é tocado.", "Only 🟢 safe items, always to the Trash. Your source code is never touched.", es: "Solo elementos 🟢 seguros, siempre a la Papelera. Tu código fuente nunca se toca.", fr: "Uniquement les éléments 🟢 sûrs, toujours vers la Corbeille. Votre code source n'est jamais touché.", de: "Nur 🟢 sichere Elemente, immer in den Papierkorb. Dein Quellcode wird nie angetastet.", zh: "只清理 🟢 安全项，始终移到废纸篓。绝不触碰你的源代码。") }
    var autoCleanWhenLabel: String { s("Quando:", "When:", es: "Cuándo:", fr: "Quand :", de: "Wann:", zh: "时机：") }
    var autoCleanScopeLabel: String { s("O quê:", "What:", es: "Qué:", fr: "Quoi :", de: "Was:", zh: "范围：") }
    var autoCleanMinLabel: String { s("Mínimo:", "Minimum:", es: "Mínimo:", fr: "Minimum :", de: "Minimum:", zh: "下限：") }
    var autoCleanLowDisk: String { s("Quando o disco ficar baixo", "When disk runs low", es: "Cuando quede poco disco", fr: "Quand le disque est presque plein", de: "Wenn der Speicher knapp wird", zh: "磁盘空间不足时") }
    var autoCleanScopeCaches: String { s("Só caches de ferramentas", "Tool caches only", es: "Solo cachés de herramientas", fr: "Caches d'outils seulement", de: "Nur Tool-Caches", zh: "仅工具缓存") }
    var autoCleanScopeAll: String { s("Caches + projetos parados", "Caches + idle projects", es: "Cachés + proyectos inactivos", fr: "Caches + projets inactifs", de: "Caches + inaktive Projekte", zh: "缓存 + 闲置项目") }
    var autoCleanScopeMax: String { s("Tudo 🟢 (com DerivedData ativo)", "Everything 🟢 (incl. active DerivedData)", es: "Todo 🟢 (con DerivedData activo)", fr: "Tout 🟢 (avec DerivedData actif)", de: "Alles 🟢 (inkl. aktivem DerivedData)", zh: "全部 🟢（含活跃项目的 DerivedData）") }
    func autoCleanLast(date: String, size: String, count: Int) -> String {
        s("Última: \(date) — \(size) (\(count) itens)", "Last: \(date) — \(size) (\(count) items)",
          es: "Última: \(date) — \(size) (\(count) elementos)", fr: "Dernier : \(date) — \(size) (\(count) éléments)",
          de: "Zuletzt: \(date) — \(size) (\(count) Elemente)", zh: "上次：\(date) — \(size)（\(count) 个项目）")
    }
    var autoCleanNever: String { s("Ainda não limpou nada sozinho", "Hasn't cleaned anything on its own yet", es: "Aún no limpió nada por su cuenta", fr: "N'a encore rien nettoyé tout seul", de: "Hat noch nichts von selbst bereinigt", zh: "还没有自动清理过任何内容") }
    var autoCleanNotifTitle: String { s("\(AppInfo.name): limpeza automática", "\(AppInfo.name): auto-clean", es: "\(AppInfo.name): limpieza automática", fr: "\(AppInfo.name) : nettoyage automatique", de: "\(AppInfo.name): automatische Bereinigung", zh: "\(AppInfo.name)：自动清理") }
    func autoCleanNotifBody(size: String, count: Int) -> String {
        s("\(count) itens (\(size)) foram pra Lixeira.", "\(count) items (\(size)) went to the Trash.",
          es: "\(count) elementos (\(size)) fueron a la Papelera.", fr: "\(count) éléments (\(size)) placés dans la Corbeille.",
          de: "\(count) Elemente (\(size)) wurden in den Papierkorb verschoben.", zh: "已将 \(count) 个项目（\(size)）移到废纸篓。")
    }
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

    // MARK: duplicatas
    var paneCleaner: String { s("Limpeza", "Cleanup", es: "Limpieza", fr: "Nettoyage", de: "Aufräumen", zh: "清理") }
    var paneDuplicates: String { s("Duplicatas", "Duplicates", es: "Duplicados", fr: "Doublons", de: "Duplikate", zh: "重复文件") }
    var dupTitle: String { s("Arquivos duplicados", "Duplicate files", es: "Archivos duplicados", fr: "Fichiers en double", de: "Doppelte Dateien", zh: "重复文件") }
    var dupIntro: String { s("Escolha pastas e procure cópias idênticas — mesmo conteúdo, verificado byte a byte. Nada é apagado sem você confirmar.", "Pick folders and find identical copies — same content, verified byte for byte. Nothing is deleted without your confirmation.", es: "Elige carpetas y busca copias idénticas — mismo contenido, verificado byte a byte. Nada se borra sin tu confirmación.", fr: "Choisissez des dossiers et trouvez les copies identiques — même contenu, vérifié octet par octet. Rien n'est supprimé sans votre confirmation.", de: "Wähle Ordner und finde identische Kopien — gleicher Inhalt, Byte für Byte geprüft. Nichts wird ohne deine Bestätigung gelöscht.", zh: "选择文件夹并查找完全相同的副本——内容一致，逐字节校验。未经你确认不会删除任何内容。") }
    var dupEmpty: String { s("Nenhuma duplicata encontrada 🎉", "No duplicates found 🎉", es: "No se encontraron duplicados 🎉", fr: "Aucun doublon trouvé 🎉", de: "Keine Duplikate gefunden 🎉", zh: "未发现重复文件 🎉") }
    var dupFind: String { s("Procurar duplicatas", "Find duplicates", es: "Buscar duplicados", fr: "Chercher les doublons", de: "Duplikate suchen", zh: "查找重复文件") }
    var dupAddFolder: String { s("Adicionar pasta", "Add folder", es: "Añadir carpeta", fr: "Ajouter un dossier", de: "Ordner hinzufügen", zh: "添加文件夹") }
    var dupRemoveFolder: String { s("Remover pasta", "Remove folder", es: "Quitar carpeta", fr: "Retirer le dossier", de: "Ordner entfernen", zh: "移除文件夹") }
    var dupKeep: String { s("Original", "Original", es: "Original", fr: "Original", de: "Original", zh: "原件") }
    var dupKeepWhy: String { s("Cópia que fica — nunca é apagada.", "The copy that stays — never deleted.", es: "La copia que se queda — nunca se borra.", fr: "La copie conservée — jamais supprimée.", de: "Die Kopie, die bleibt — wird nie gelöscht.", zh: "保留的副本——永不删除。") }
    var dupSelectAll: String { s("Todas as cópias", "All copies", es: "Todas las copias", fr: "Toutes les copies", de: "Alle Kopien", zh: "所有副本") }
    var dupSelectAllHelp: String { s("Seleciona todas as cópias (o original de cada grupo fica de fora)", "Selects every copy (the original of each group is left out)", es: "Selecciona todas las copias (el original de cada grupo queda fuera)", fr: "Sélectionne toutes les copies (l'original de chaque groupe est exclu)", de: "Wählt alle Kopien aus (das Original jeder Gruppe bleibt außen vor)", zh: "选择所有副本（每组的原件除外）") }
    func dupGroupHeader(size: String, count: Int) -> String {
        s("\(size) × \(count) cópias", "\(size) × \(count) copies",
          es: "\(size) × \(count) copias", fr: "\(size) × \(count) copies",
          de: "\(size) × \(count) Kopien", zh: "\(size) × \(count) 份")
    }
    func dupReclaim(_ size: String) -> String { s("recupera \(size)", "reclaims \(size)", es: "recupera \(size)", fr: "récupère \(size)", de: "gibt \(size) frei", zh: "可回收 \(size)") }
    func dupConfirmTitle(count: Int, size: String) -> String {
        let copies = count == 1
            ? s("1 cópia", "1 copy", es: "1 copia", fr: "1 copie", de: "1 Kopie", zh: "1 份副本")
            : s("\(count) cópias", "\(count) copies", es: "\(count) copias", fr: "\(count) copies", de: "\(count) Kopien", zh: "\(count) 份副本")
        return s("Excluir \(copies) (\(size))? O original de cada grupo é mantido.",
                 "Delete \(copies) (\(size))? The original of each group is kept.",
                 es: "¿Eliminar \(copies) (\(size))? El original de cada grupo se mantiene.",
                 fr: "Supprimer \(copies) (\(size)) ? L'original de chaque groupe est conservé.",
                 de: "\(copies) (\(size)) löschen? Das Original jeder Gruppe bleibt erhalten.",
                 zh: "删除 \(copies)（\(size)）？每组的原件将保留。")
    }
    var dupVerifiedNote: String { s("Comparação por conteúdo (SHA-256 + byte a byte), não por nome. O original de cada grupo nunca é apagado.", "Compared by content (SHA-256 + byte for byte), not by name. The original of each group is never deleted.", es: "Comparación por contenido (SHA-256 + byte a byte), no por nombre. El original de cada grupo nunca se borra.", fr: "Comparaison par contenu (SHA-256 + octet par octet), pas par nom. L'original de chaque groupe n'est jamais supprimé.", de: "Vergleich nach Inhalt (SHA-256 + Byte für Byte), nicht nach Name. Das Original jeder Gruppe wird nie gelöscht.", zh: "按内容比对（SHA-256 + 逐字节），而非按文件名。每组的原件永不删除。") }
    func dupPhaseText(_ phase: DupPhase) -> String {
        let body: String
        switch phase {
        case .listing:
            body = s("listando arquivos", "listing files", es: "listando archivos", fr: "liste des fichiers", de: "Dateien werden aufgelistet", zh: "正在列出文件")
        case .comparing(let n):
            body = s("comparando as pontas de \(n) candidatos", "comparing the ends of \(n) candidates", es: "comparando los extremos de \(n) candidatos", fr: "comparaison des extrémités de \(n) candidats", de: "vergleiche die Enden von \(n) Kandidaten", zh: "正在比较 \(n) 个候选文件的首尾")
        case .hashing(let n):
            body = s("verificando \(n) arquivos por completo", "full-hashing \(n) files", es: "verificando \(n) archivos por completo", fr: "hachage complet de \(n) fichiers", de: "vollständiges Hashen von \(n) Dateien", zh: "正在完整校验 \(n) 个文件")
        case .verifying:
            body = s("conferindo byte a byte", "verifying byte for byte", es: "comprobando byte a byte", fr: "vérification octet par octet", de: "Byte-für-Byte-Prüfung", zh: "正在逐字节核对")
        }
        return s("Etapa \(phase.step)/\(DupPhase.total) · \(body)…",
                 "Step \(phase.step)/\(DupPhase.total) · \(body)…",
                 es: "Paso \(phase.step)/\(DupPhase.total) · \(body)…",
                 fr: "Étape \(phase.step)/\(DupPhase.total) · \(body)…",
                 de: "Schritt \(phase.step)/\(DupPhase.total) · \(body)…",
                 zh: "第 \(phase.step)/\(DupPhase.total) 步 · \(body)…")
    }
}
