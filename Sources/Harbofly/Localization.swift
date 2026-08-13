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
    var xctestDevices: String { s("Simuladores efêmeros de testes (xcodebuild/MCP); regeneram no próximo run", "Ephemeral test simulators (xcodebuild/MCP); regenerated on the next run", es: "Simuladores de prueba efímeros (xcodebuild/MCP); se regeneran en la próxima ejecución", fr: "Simulateurs de test éphémères (xcodebuild/MCP) ; régénérés à la prochaine exécution", de: "Kurzlebige Test-Simulatoren (xcodebuild/MCP); werden beim nächsten Lauf neu erzeugt", zh: "临时测试模拟器（xcodebuild/MCP）；下次运行时会重新生成") }
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

    var androidSdkImages: String { s("Imagens de sistema do emulador Android — rebaixáveis pelo SDK Manager", "Android emulator system images — re-downloadable from the SDK Manager", es: "Imágenes de sistema del emulador de Android — se pueden volver a descargar desde el SDK Manager", fr: "Images système de l'émulateur Android — retéléchargeables depuis le SDK Manager", de: "Android-Emulator-Systemabbilder — über den SDK Manager erneut herunterladbar", zh: "Android 模拟器系统镜像——可从 SDK Manager 重新下载") }
    var androidAvd: String { s("Emuladores Android (AVDs) — apagar zera o estado e os dados do emulador", "Android Virtual Devices (AVDs) — deleting wipes the emulator's data and state", es: "Dispositivos virtuales de Android (AVD) — borrarlos elimina los datos y el estado del emulador", fr: "Appareils virtuels Android (AVD) — les supprimer efface les données et l'état de l'émulateur", de: "Android-Emulatoren (AVDs) — Löschen setzt Daten und Status des Emulators zurück", zh: "Android 虚拟设备（AVD）——删除会清除模拟器的数据和状态") }
    var strayGitLabel: String { s("Repositório Git perdido na Home (~/.git)", "Stray Git repo in your Home (~/.git)", es: "Repositorio Git perdido en tu carpeta personal (~/.git)", fr: "Dépôt Git égaré dans votre dossier personnel (~/.git)", de: "Verirrtes Git-Repository im Home-Ordner (~/.git)", zh: "主目录中的游离 Git 仓库（~/.git）") }
    var strayGitDetail: String { s("Um `git init/add` acidental na sua Home pode inchar pra dezenas de GB. Revise com `git --git-dir=~/.git status`; se for lixo, apague `~/.git` no Terminal. O app nunca mexe em repositórios.", "An accidental `git init/add` in your Home can balloon to tens of GB. Review with `git --git-dir=~/.git status`; if it's junk, delete `~/.git` in Terminal. The app never touches repositories.", es: "Un `git init/add` accidental en tu carpeta personal puede inflarse a decenas de GB. Revísalo con `git --git-dir=~/.git status`; si es basura, borra `~/.git` en la Terminal. La app nunca toca repositorios.", fr: "Un `git init/add` accidentel dans votre dossier personnel peut gonfler à des dizaines de Go. Vérifiez avec `git --git-dir=~/.git status` ; si c'est inutile, supprimez `~/.git` dans le Terminal. L'app ne touche jamais aux dépôts.", de: "Ein versehentliches `git init/add` im Home-Ordner kann auf Dutzende GB anwachsen. Prüfe mit `git --git-dir=~/.git status`; wenn es Müll ist, lösche `~/.git` im Terminal. Die App fasst Repositorys nie an.", zh: "在主目录中误运行 `git init/add` 可能膨胀到数十 GB。用 `git --git-dir=~/.git status` 检查；若是垃圾，在终端删除 `~/.git`。应用绝不触碰仓库。") }

    var deviceSupportOld: String { s("Build antigo de DeviceSupport — a versão mais nova foi mantida; esta recria se você reconectar um device nela", "Old DeviceSupport build — the newest version was kept; this one recreates if you reconnect a device on it", es: "Build antiguo de DeviceSupport — se mantuvo la versión más nueva; este se recrea si reconectas un dispositivo con ella", fr: "Ancien build DeviceSupport — la version la plus récente a été conservée ; celui-ci se recrée si vous reconnectez un appareil dessus", de: "Alter DeviceSupport-Build — die neueste Version wurde behalten; dieser wird neu erstellt, wenn du ein Gerät damit verbindest", zh: "旧的 DeviceSupport 版本——已保留最新版；重新连接对应版本的设备时会再次生成") }
    var orphanLeftover: String { s("Sobra de um app que você não tem mais instalado — pode remover", "Leftover from an app you no longer have installed — safe to remove", es: "Restos de una app que ya no tienes instalada — se puede eliminar", fr: "Résidus d'une app que vous n'avez plus installée — supprimable", de: "Überbleibsel einer nicht mehr installierten App — kann entfernt werden", zh: "已卸载应用的残留文件——可以删除") }
    var gitBloat: String { s("Repositório com .git inchado. Não apague (perde história) — rode `git gc` na pasta do projeto pra compactar", "Repo with a bloated .git. Don't delete it (loses history) — run `git gc` in the project folder to compact it", es: "Repo con .git inflado. No lo borres (pierdes el historial) — ejecuta `git gc` en la carpeta del proyecto para compactarlo", fr: "Dépôt avec un .git gonflé. Ne le supprimez pas (perte de l'historique) — lancez `git gc` dans le dossier du projet pour le compacter", de: "Repo mit aufgeblähtem .git. Nicht löschen (Historie geht verloren) — führe `git gc` im Projektordner aus, um es zu komprimieren", zh: "仓库的 .git 已膨胀。不要删除（会丢失历史）——在项目文件夹运行 `git gc` 压缩") }
    var bigFileDetail: String { s("Arquivo grande na sua pasta pessoal. O app não apaga arquivos seus — revele no Finder e decida", "Large file in your personal folder. The app doesn't delete your files — reveal it in Finder and decide", es: "Archivo grande en tu carpeta personal. La app no borra tus archivos — muéstralo en el Finder y decide", fr: "Gros fichier dans votre dossier personnel. L'app ne supprime pas vos fichiers — affichez-le dans le Finder et décidez", de: "Große Datei in deinem persönlichen Ordner. Die App löscht deine Dateien nicht — im Finder anzeigen und entscheiden", zh: "个人文件夹中的大文件。应用不会删除你的文件——在访达中显示并自行决定") }
    var offloadDetail: String { s("Grande e parado há meses — candidato a mover pro SSD externo (você mantém, só não no interno). O app não move nada; revele no Finder e arraste.", "Large and untouched for months — a candidate to move to an external SSD (you keep it, just not on internal). The app moves nothing; reveal it in Finder and drag.", es: "Grande y sin tocar desde hace meses — candidato a mover a un SSD externo (lo conservas, pero no en el interno). La app no mueve nada; muéstralo en el Finder y arrástralo.", fr: "Gros et inchangé depuis des mois — candidat à déplacer vers un SSD externe (vous le gardez, mais pas en interne). L'app ne déplace rien ; affichez-le dans le Finder et glissez-le.", de: "Groß und seit Monaten unberührt — Kandidat zum Verschieben auf eine externe SSD (du behältst es, nur nicht intern). Die App verschiebt nichts; im Finder anzeigen und ziehen.", zh: "又大又数月未动——适合移到外置 SSD 的候选（你保留它，只是不放在内置盘）。应用不会移动任何东西；在访达中显示并拖走。") }
    var orphanAppData: String { s("Dados de um app que você não tem mais instalado. Pode mandar pra Lixeira.", "Data from an app you no longer have installed. Safe to move to the Trash.", es: "Datos de una app que ya no tienes instalada. Puedes enviarla a la Papelera.", fr: "Données d'une app que vous n'avez plus installée. Peut aller à la Corbeille.", de: "Daten einer nicht mehr installierten App. Kann in den Papierkorb.", zh: "已卸载应用的数据。可以移到废纸篓。") }
    var vmDisk: String { s("Discos de máquina virtual — costumam ter dezenas de GB. Gerencie no Parallels/UTM/VMware; revele no Finder.", "Virtual machine disks — often tens of GB. Manage them in Parallels/UTM/VMware; reveal in Finder.", es: "Discos de máquina virtual — suelen ocupar decenas de GB. Gestiónalos en Parallels/UTM/VMware; muéstralos en el Finder.", fr: "Disques de machine virtuelle — souvent des dizaines de Go. Gérez-les dans Parallels/UTM/VMware ; affichez dans le Finder.", de: "Virtuelle-Maschine-Festplatten — oft Dutzende GB. Verwalte sie in Parallels/UTM/VMware; im Finder anzeigen.", zh: "虚拟机磁盘——通常有几十 GB。在 Parallels/UTM/VMware 中管理；在访达中显示。") }
    var growthDetail: String { s("Cresceu desde a última medição — sinal de que está enchendo o disco. Confira antes que aperte.", "Grew since the last measurement — a sign it's filling your disk. Check it before it gets tight.", es: "Creció desde la última medición — señal de que está llenando el disco. Revísalo antes de que apriete.", fr: "A grossi depuis la dernière mesure — signe qu'il remplit votre disque. Vérifiez avant que ça coince.", de: "Seit der letzten Messung gewachsen — ein Zeichen, dass es die Platte füllt. Prüfe es, bevor es eng wird.", zh: "自上次测量以来在增长——磁盘正被悄悄填满的信号。趁还没吃紧时检查一下。") }
    func growthNew(name: String, size: String) -> String {
        s("⚠️ \(name) apareceu e já ocupa \(size)", "⚠️ \(name) appeared and already takes \(size)",
          es: "⚠️ \(name) apareció y ya ocupa \(size)", fr: "⚠️ \(name) est apparu et occupe déjà \(size)",
          de: "⚠️ \(name) ist aufgetaucht und belegt schon \(size)", zh: "⚠️ \(name) 新出现，已占用 \(size)")
    }
    func growthGrew(name: String, size: String, days: Int) -> String {
        s("📈 \(name) cresceu +\(size) em \(days) dias", "📈 \(name) grew +\(size) in \(days) days",
          es: "📈 \(name) creció +\(size) en \(days) días", fr: "📈 \(name) a grossi de +\(size) en \(days) jours",
          de: "📈 \(name) ist in \(days) Tagen um +\(size) gewachsen", zh: "📈 \(name) 在 \(days) 天内增长了 +\(size)")
    }

    var trashLabel: String { s("Lixeira", "Trash", es: "Papelera", fr: "Corbeille", de: "Papierkorb", zh: "废纸篓") }
    var trashDetail: String { s("Mandar pra Lixeira não libera espaço até esvaziar. Esvazie aqui pra recuperar de verdade — é irreversível.", "Moving to the Trash doesn't free space until you empty it. Empty it here to actually reclaim it — irreversible.", es: "Enviar a la Papelera no libera espacio hasta vaciarla. Vacíala aquí para recuperarlo de verdad — es irreversible.", fr: "Mettre à la Corbeille ne libère pas d'espace tant que vous ne la videz pas. Videz-la ici pour le récupérer vraiment — irréversible.", de: "In den Papierkorb verschieben gibt keinen Speicher frei, bis du ihn leerst. Leere ihn hier, um wirklich Platz zurückzugewinnen — unumkehrbar.", zh: "移到废纸篓不会释放空间，直到清空。在此清空才能真正回收——不可撤销。") }
    var emptyTrash: String { s("Esvaziar Lixeira", "Empty Trash", es: "Vaciar Papelera", fr: "Vider la Corbeille", de: "Papierkorb leeren", zh: "清空废纸篓") }
    var emptyTrashConfirm: String { s("Esvaziar de vez? (irreversível)", "Empty for good? (irreversible)", es: "¿Vaciar del todo? (irreversible)", fr: "Vider définitivement ?", de: "Endgültig leeren?", zh: "彻底清空？（不可恢复）") }
    func trashEmptied(_ size: String) -> String { s("Lixeira esvaziada — \(size) recuperados.", "Trash emptied — \(size) reclaimed.", es: "Papelera vaciada — \(size) recuperados.", fr: "Corbeille vidée — \(size) récupérés.", de: "Papierkorb geleert — \(size) freigegeben.", zh: "废纸篓已清空——回收了 \(size)。") }
    var thinSnapshots: String { s("Recuperar espaço dos snapshots", "Reclaim snapshot space", es: "Recuperar espacio de snapshots", fr: "Récupérer l'espace des snapshots", de: "Snapshot-Speicher freigeben", zh: "回收快照空间") }
    var thinSnapshotsConfirm: String { s("Apagar snapshots locais? (pede senha)", "Delete local snapshots? (asks for password)", es: "¿Borrar snapshots locales? (pide contraseña)", fr: "Supprimer les snapshots locaux ? (mot de passe requis)", de: "Lokale Snapshots löschen? (fragt nach Passwort)", zh: "删除本地快照？（需要密码）") }
    var deleteRuntimes: String { s("Apagar runtimes não usados", "Delete unused runtimes", es: "Borrar runtimes sin uso", fr: "Supprimer les runtimes inutilisés", de: "Ungenutzte Runtimes löschen", zh: "删除未使用的运行时") }
    var deleteRuntimesConfirm: String { s("Apagar de vez? (irreversível)", "Delete for good? (irreversible)", es: "¿Borrar del todo? (irreversible)", fr: "Supprimer définitivement ?", de: "Endgültig löschen?", zh: "彻底删除？（不可恢复）") }
    func runtimesDeleted(_ count: Int) -> String {
        s("\(count) runtime(s) não usado(s) apagado(s).", "Deleted \(count) unused runtime(s).",
          es: "Se borraron \(count) runtime(s) sin uso.", fr: "\(count) runtime(s) inutilisé(s) supprimé(s).",
          de: "\(count) ungenutzte(s) Runtime(s) gelöscht.", zh: "已删除 \(count) 个未使用的运行时。")
    }
    var runtimesNoneToDelete: String { s("Nenhum runtime parado há 30+ dias. Os em uso não são tocados.", "No runtimes unused for 30+ days. Ones in use are left untouched.", es: "Ningún runtime sin usar por 30+ días. Los que están en uso no se tocan.", fr: "Aucun runtime inutilisé depuis 30+ jours. Ceux utilisés ne sont pas touchés.", de: "Keine seit 30+ Tagen ungenutzten Runtimes. Genutzte bleiben unberührt.", zh: "没有超过 30 天未使用的运行时。使用中的不会被触碰。") }

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
    var analyticsSubtitle: String { s("Pra aprender o que melhorar pra você — nunca pra te rastrear.", "To learn what to improve for you — never to track you.", es: "Para aprender qué mejorar para ti — nunca para rastrearte.", fr: "Pour apprendre quoi améliorer pour vous — jamais pour vous pister.", de: "Um zu lernen, was wir für dich verbessern können — nie um dich zu tracken.", zh: "用于了解该为你改进什么——绝不用于追踪你。") }
    var analyticsDetail: String { s("Só eventos, tamanhos e categorias genéricas de cache (DerivedData, node_modules…), com modelo do Mac, versão do macOS, idioma, país e tema. Nunca nome, arquivo, caminho, projeto ou IP. Open source e auditável.", "Only events, sizes and generic cache categories (DerivedData, node_modules…), plus Mac model, macOS version, language, country and theme. Never a name, file, path, project or IP. Open source and auditable.", es: "Solo eventos, tamaños y categorías genéricas de caché (DerivedData, node_modules…), con el modelo del Mac, la versión de macOS, el idioma, el país y el tema. Nunca un nombre, archivo, ruta, proyecto ni IP. Open source y auditable.", fr: "Uniquement des événements, tailles et catégories génériques de cache (DerivedData, node_modules…), avec le modèle du Mac, la version de macOS, la langue, le pays et le thème. Jamais de nom, fichier, chemin, projet ni IP. Open source et auditable.", de: "Nur Ereignisse, Größen und generische Cache-Kategorien (DerivedData, node_modules…), dazu Mac-Modell, macOS-Version, Sprache, Land und Design. Nie Name, Datei, Pfad, Projekt oder IP. Open Source und prüfbar.", zh: "仅包含事件、大小和通用缓存类别（DerivedData、node_modules…），以及 Mac 型号、macOS 版本、语言、国家/地区和主题。绝不含名称、文件、路径、项目或 IP。开源可审计。") }

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
    var deleteOldSimsConfirm: String { s("Apagar de vez? (irreversível)", "Delete for good? (irreversible)", es: "¿Borrar del todo? (irreversible)", fr: "Supprimer définitivement ?", de: "Endgültig löschen?", zh: "彻底删除？（不可恢复）") }
    var simNoneToDelete: String { s("Nenhum simulador indisponível pra apagar. O espaço aqui é de simuladores em uso — gerencie-os no Xcode.", "No unavailable simulators to delete. The space here is from simulators in use — manage them in Xcode.", es: "No hay simuladores no disponibles que borrar. El espacio aquí es de simuladores en uso — gestiónalos en Xcode.", fr: "Aucun simulateur indisponible à supprimer. L'espace ici vient de simulateurs utilisés — gérez-les dans Xcode.", de: "Keine nicht verfügbaren Simulatoren zum Löschen. Der Speicher hier stammt von genutzten Simulatoren — verwalte sie in Xcode.", zh: "没有可删除的不可用模拟器。这里的空间来自正在使用的模拟器——请在 Xcode 中管理。") }
    func simDeleted(_ count: Int) -> String {
        s("\(count) simulador(es) indisponível(is) apagado(s).", "Deleted \(count) unavailable simulator(s).",
          es: "Se borraron \(count) simulador(es) no disponible(s).", fr: "\(count) simulateur(s) indisponible(s) supprimé(s).",
          de: "\(count) nicht verfügbare(r) Simulator(en) gelöscht.", zh: "已删除 \(count) 个不可用模拟器。")
    }
    var showSimulators: String { s("Simuladores", "Simulators", es: "Simuladores", fr: "Simulateurs", de: "Simulatoren", zh: "模拟器") }
    func deleteSelectedSims(count: Int, size: String) -> String {
        s("Apagar \(count) selecionado(s) (\(size))", "Delete \(count) selected (\(size))",
          es: "Borrar \(count) seleccionado(s) (\(size))", fr: "Supprimer \(count) sélectionné(s) (\(size))",
          de: "\(count) ausgewählte löschen (\(size))", zh: "删除选中的 \(count) 个（\(size)）")
    }
    var deleteSelectedSimsConfirm: String { s("Apagar de vez? (irreversível)", "Delete for good? (irreversible)", es: "¿Borrar del todo? (irreversible)", fr: "Supprimer définitivement ?", de: "Endgültig löschen?", zh: "彻底删除？（不可恢复）") }
    func simsDeleted(_ count: Int) -> String {
        s("\(count) simulador(es) apagado(s).", "Deleted \(count) simulator(s).",
          es: "Se borraron \(count) simulador(es).", fr: "\(count) simulateur(s) supprimé(s).",
          de: "\(count) Simulator(en) gelöscht.", zh: "已删除 \(count) 个模拟器。")
    }

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
    var autoCleanEndOfDay: String { s("No fim do dia", "At the end of the day", es: "Al final del día", fr: "En fin de journée", de: "Am Ende des Tages", zh: "在一天结束时") }
    var autoCleanStartOfDay: String { s("No começo do dia", "At the start of the day", es: "Al comenzar el día", fr: "En début de journée", de: "Zu Beginn des Tages", zh: "在一天开始时") }
    var autoCleanWeekly: String { s("Toda semana", "Every week", es: "Cada semana", fr: "Chaque semaine", de: "Jede Woche", zh: "每周") }
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

    // MARK: oferta proativa de auto-clean
    func autoOfferTitle(count: Int) -> String {
        s("Você já limpou \(count) vezes 🧹", "You've cleaned up \(count) times 🧹",
          es: "Ya limpiaste \(count) veces 🧹", fr: "Vous avez nettoyé \(count) fois 🧹",
          de: "Du hast schon \(count)-mal aufgeräumt 🧹", zh: "你已经手动清理了 \(count) 次 🧹")
    }
    var autoOfferBody: String { s("Quer que o \(AppInfo.name) faça essa faxina sozinho, no fim de cada dia? Só caches 🟢 seguros, sempre pra Lixeira. Você desliga quando quiser.", "Want \(AppInfo.name) to do this cleanup on its own, at the end of each day? Only 🟢 safe caches, always to the Trash. Turn it off whenever you like.", es: "¿Quieres que \(AppInfo.name) haga esta limpieza solo, al final de cada día? Solo cachés 🟢 seguros, siempre a la Papelera. Lo apagas cuando quieras.", fr: "Vous voulez que \(AppInfo.name) fasse ce nettoyage tout seul, en fin de journée ? Uniquement les caches 🟢 sûrs, toujours vers la Corbeille. Désactivable à tout moment.", de: "Soll \(AppInfo.name) das am Ende jedes Tages von selbst erledigen? Nur 🟢 sichere Caches, immer in den Papierkorb. Jederzeit abschaltbar.", zh: "要不要让 \(AppInfo.name) 在每天结束时自动完成这项清理？只清理 🟢 安全缓存，始终进废纸篓。随时可关闭。") }
    var autoOfferYes: String { s("Sim, cuida disso pra mim", "Yes, handle it for me", es: "Sí, encárgate por mí", fr: "Oui, occupe-t'en pour moi", de: "Ja, übernimm das für mich", zh: "好，帮我自动处理") }
    var openAtLogin: String { s("Abrir no login", "Open at login", es: "Abrir al iniciar sesión", fr: "Ouvrir à la connexion", de: "Beim Anmelden öffnen", zh: "登录时打开") }
    var supportCta: String { s("Apoiar ☕", "Support ☕", es: "Apoyar ☕", fr: "Soutenir ☕", de: "Unterstützen ☕", zh: "支持 ☕") }
    var languageLabel: String { s("Idioma", "Language", es: "Idioma", fr: "Langue", de: "Sprache", zh: "语言") }
    var langSystem: String { s("Sistema", "System", es: "Sistema", fr: "Système", de: "System", zh: "跟随系统") }

    // MARK: feedback
    var feedbackCta: String { s("Fala com o dev", "Talk to the dev", es: "Habla con el dev", fr: "Parle au dev", de: "Schreib dem Dev", zh: "找开发者聊聊") }
    var feedbackTitle: String { s("Fala com o dev", "Talk to the dev", es: "Habla con el dev", fr: "Parle au dev", de: "Schreib dem Dev", zh: "找开发者聊聊") }
    var feedbackSubtitle: String { s("Bug, ideia ou sugestão — vai direto pro criador do app.", "Bug, idea or suggestion — goes straight to the app's creator.", es: "Bug, idea o sugerencia — va directo al creador de la app.", fr: "Bug, idée ou suggestion — envoyé directement au créateur de l'app.", de: "Bug, Idee oder Vorschlag — geht direkt an den Entwickler der App.", zh: "Bug、想法或建议——直接发送给应用的开发者。") }
    var feedbackTypeBug: String { s("Bug", "Bug", es: "Fallo", fr: "Bug", de: "Fehler", zh: "问题") }
    var feedbackTypeIdea: String { s("Ideia", "Idea", es: "Idea", fr: "Idée", de: "Idee", zh: "想法") }
    var feedbackTypeOther: String { s("Outro", "Other", es: "Otro", fr: "Autre", de: "Sonstiges", zh: "其他") }
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

    // MARK: histórico / recap
    var paneStats: String { s("Histórico", "History", es: "Historial", fr: "Historique", de: "Verlauf", zh: "历史") }
    var statsEmpty: String { s("Nada por aqui ainda. Faça sua primeira limpeza e volte pra ver suas estatísticas 📊", "Nothing here yet. Run your first cleanup and come back for your stats 📊", es: "Aún no hay nada. Haz tu primera limpieza y vuelve para ver tus estadísticas 📊", fr: "Rien ici pour l'instant. Lancez votre premier nettoyage et revenez voir vos statistiques 📊", de: "Noch nichts hier. Räume zum ersten Mal auf und schau dann wieder vorbei 📊", zh: "这里还没有内容。先清理一次，再回来查看你的统计数据 📊") }
    func statsRecoveredSince(_ date: String) -> String { s("recuperados desde \(date)", "recovered since \(date)", es: "recuperados desde \(date)", fr: "récupérés depuis le \(date)", de: "freigegeben seit \(date)", zh: "自 \(date) 起已释放") }
    var statsRecoveredSoFar: String { s("recuperados até hoje", "recovered so far", es: "recuperados hasta hoy", fr: "récupérés à ce jour", de: "bisher freigegeben", zh: "累计已释放") }
    func moneyLine(_ usd: String) -> String { s("💸 ≈ \(usd) em upgrades de SSD da Apple que você não precisou comprar", "💸 ≈ \(usd) worth of Apple SSD upgrades you didn't have to buy", es: "💸 ≈ \(usd) en ampliaciones de SSD de Apple que no tuviste que comprar", fr: "💸 ≈ \(usd) de stockage SSD Apple que vous n'avez pas eu à acheter", de: "💸 ≈ \(usd) an Apple-SSD-Upgrades, die du nicht kaufen musstest", zh: "💸 ≈ 帮你省下了相当于 \(usd) 的 Apple SSD 升级费用") }
    func moneyFootnote(_ price: String) -> String { s("No preço de tabela da Apple: \(price) por 512 GB de upgrade.", "At Apple's list price: \(price) per 512 GB upgrade.", es: "Al precio oficial de Apple: \(price) por cada 512 GB de ampliación.", fr: "Au tarif officiel d'Apple : \(price) par palier de 512 Go.", de: "Zum offiziellen Apple-Preis: \(price) pro 512-GB-Upgrade.", zh: "按 Apple 官方价格：每 512 GB 升级 \(price)。") }
    func eqMovies(_ n: Int) -> String { s("🎬 Dá \(n) filmes em 4K", "🎬 That's \(n) 4K movies", es: "🎬 Equivale a \(n) películas en 4K", fr: "🎬 Soit \(n) films en 4K", de: "🎬 Das sind \(n) 4K-Filme", zh: "🎬 约等于 \(n) 部 4K 电影") }
    func eqPhotos(_ n: String) -> String { s("📸 Dá \(n) fotos", "📸 That's \(n) photos", es: "📸 Equivale a \(n) fotos", fr: "📸 Soit \(n) photos", de: "📸 Das sind \(n) Fotos", zh: "📸 约等于 \(n) 张照片") }
    var statsCleans: String { s("Limpezas", "Cleanups", es: "Limpiezas", fr: "Nettoyages", de: "Bereinigungen", zh: "清理次数") }
    var statsBiggest: String { s("Maior limpeza", "Biggest cleanup", es: "Mayor limpieza", fr: "Plus gros nettoyage", de: "Größte Bereinigung", zh: "最大一次清理") }
    var statsLast30d: String { s("Últimos 30 dias", "Last 30 days", es: "Últimos 30 días", fr: "30 derniers jours", de: "Letzte 30 Tage", zh: "最近 30 天") }
    var statsTopVillain: String { s("Maior vilão", "Top offender", es: "Mayor culpable", fr: "Principal coupable", de: "Größter Übeltäter", zh: "头号元凶") }
    var statsChartTitle: String { s("Últimas 12 semanas", "Last 12 weeks", es: "Últimas 12 semanas", fr: "12 dernières semaines", de: "Letzte 12 Wochen", zh: "最近 12 周") }
    var shareRecap: String { s("Compartilhar recap", "Share recap", es: "Compartir resumen", fr: "Partager le récap", de: "Recap teilen", zh: "分享战绩") }
    func recapMoneyShort(_ usd: String) -> String { s("≈ \(usd) em SSD da Apple 💸", "≈ \(usd) in Apple SSD 💸", es: "≈ \(usd) en SSD de Apple 💸", fr: "≈ \(usd) de SSD Apple 💸", de: "≈ \(usd) an Apple-SSD 💸", zh: "≈ 省下 \(usd) 的 Apple SSD 💸") }
    func recapCardFooter(count: Int, villain: String) -> String {
        let cleans = count == 1
            ? s("1 limpeza", "1 cleanup", es: "1 limpieza", fr: "1 nettoyage", de: "1 Bereinigung", zh: "1 次清理")
            : s("\(count) limpezas", "\(count) cleanups", es: "\(count) limpiezas", fr: "\(count) nettoyages", de: "\(count) Bereinigungen", zh: "\(count) 次清理")
        if villain.isEmpty { return cleans }
        return s("\(cleans) · maior vilão: \(villain)", "\(cleans) · top offender: \(villain)",
                 es: "\(cleans) · mayor culpable: \(villain)", fr: "\(cleans) · principal coupable : \(villain)",
                 de: "\(cleans) · größter Übeltäter: \(villain)", zh: "\(cleans) · 头号元凶：\(villain)")
    }
    func recapShareText(size: String, usd: String) -> String {
        s("O Harbofly já recuperou \(size) no meu Mac — ≈ \(usd) que a Apple cobraria em SSD 💸 https://harbofly.app",
          "Harbofly has recovered \(size) on my Mac — ≈ \(usd) Apple would charge for that SSD 💸 https://harbofly.app",
          es: "Harbofly ya recuperó \(size) en mi Mac — ≈ \(usd) que Apple cobraría por ese SSD 💸 https://harbofly.app",
          fr: "Harbofly a déjà récupéré \(size) sur mon Mac — ≈ \(usd) qu'Apple facturerait pour ce SSD 💸 https://harbofly.app",
          de: "Harbofly hat auf meinem Mac schon \(size) freigegeben — ≈ \(usd), die Apple für diese SSD verlangen würde 💸 https://harbofly.app",
          zh: "Harbofly 已在我的 Mac 上释放了 \(size)——约等于 Apple 会收取的 \(usd) SSD 费用 💸 https://harbofly.app")
    }

    // MARK: duplicatas
    var paneCleaner: String { s("Limpeza", "Cleanup", es: "Limpieza", fr: "Nettoyage", de: "Aufräumen", zh: "清理") }
    var paneDuplicates: String { s("Duplicatas", "Duplicates", es: "Duplicados", fr: "Doublons", de: "Duplikate", zh: "重复文件") }
    var paneUninstall: String { s("Apps", "Apps", es: "Apps", fr: "Apps", de: "Apps", zh: "应用") }
    var uninstallIntro: String { s("Desinstala o app + todos os rastros (Application Support, Containers, caches, prefs…) que arrastar pro lixo deixa pra trás. Tudo vai pra Lixeira — dá pra restaurar.", "Uninstall the app + every leftover (Application Support, Containers, caches, prefs…) that dragging to the Trash leaves behind. Everything goes to the Trash — recoverable.", es: "Desinstala la app + todos los restos (Application Support, Containers, cachés, prefs…) que arrastrar a la Papelera deja atrás. Todo va a la Papelera — recuperable.", fr: "Désinstalle l'app + tous les résidus (Application Support, Containers, caches, prefs…) que la mise à la Corbeille laisse. Tout va à la Corbeille — récupérable.", de: "Deinstalliert die App + alle Überbleibsel (Application Support, Containers, Caches, Prefs…), die das Wegwerfen zurücklässt. Alles in den Papierkorb — wiederherstellbar.", zh: "卸载应用 + 拖到废纸篓会遗留的所有残留（Application Support、Containers、缓存、偏好…）。全部进废纸篓——可恢复。") }
    var uninstallScan: String { s("Escanear apps instalados", "Scan installed apps", es: "Escanear apps instaladas", fr: "Analyser les apps installées", de: "Installierte Apps scannen", zh: "扫描已安装应用") }
    var uninstallLeftovers: String { s("rastros", "leftovers", es: "restos", fr: "résidus", de: "Reste", zh: "残留") }
    func uninstallSelected(_ size: String) -> String { s("Desinstalar (\(size))", "Uninstall (\(size))", es: "Desinstalar (\(size))", fr: "Désinstaller (\(size))", de: "Deinstallieren (\(size))", zh: "卸载（\(size)）") }
    func uninstallConfirm(count: Int, size: String) -> String {
        let apps = count == 1
            ? s("1 app", "1 app", es: "1 app", fr: "1 app", de: "1 App", zh: "1 个应用")
            : s("\(count) apps", "\(count) apps", es: "\(count) apps", fr: "\(count) apps", de: "\(count) Apps", zh: "\(count) 个应用")
        return s("Desinstalar \(apps) (\(size))?", "Uninstall \(apps) (\(size))?",
                 es: "¿Desinstalar \(apps) (\(size))?", fr: "Désinstaller \(apps) (\(size)) ?",
                 de: "\(apps) (\(size)) deinstallieren?", zh: "卸载 \(apps)（\(size)）？")
    }
    var uninstallConfirmNote: String { s("O app e seus rastros vão pra Lixeira. Se algo estiver em uso, restaure da Lixeira.", "The app and its leftovers go to the Trash. If something was in use, restore it from the Trash.", es: "La app y sus restos van a la Papelera. Si algo estaba en uso, restáuralo desde la Papelera.", fr: "L'app et ses résidus vont à la Corbeille. Si quelque chose était utilisé, restaurez-le depuis la Corbeille.", de: "Die App und ihre Reste wandern in den Papierkorb. Falls etwas in Benutzung war, aus dem Papierkorb wiederherstellen.", zh: "应用及其残留会进废纸篓。若有正在使用的，可从废纸篓恢复。") }
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
        case .hashing(let done, let total):
            body = s("verificando \(done)/\(total) arquivos por completo", "full-hashing \(done)/\(total) files", es: "verificando \(done)/\(total) archivos por completo", fr: "hachage complet de \(done)/\(total) fichiers", de: "vollständiges Hashen von \(done)/\(total) Dateien", zh: "正在完整校验 \(done)/\(total) 个文件")
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
