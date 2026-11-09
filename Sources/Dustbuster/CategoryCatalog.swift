import Foundation
import Darwin
import AppKit

enum CategoryCatalog {
    static func all() -> [CleanCategory] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            CleanCategory(
                id: "caches",
                title: "Cache applicazioni",
                explanation: "Dati temporanei rigenerati automaticamente dalle app. Sicuro da eliminare; alcune app potrebbero essere leggermente più lente al primo avvio successivo.",
                safety: .safe,
                resolvePaths: { [home.appendingPathComponent("Library/Caches")] }
            ),
            CleanCategory(
                id: "logs",
                title: "Log applicazioni",
                explanation: "File di log generati dalle app per il debug. Sicuri da eliminare, non servono al funzionamento.",
                safety: .safe,
                resolvePaths: { [home.appendingPathComponent("Library/Logs")] }
            ),
            CleanCategory(
                id: "xcode-derived",
                title: "Xcode – DerivedData",
                explanation: "Build intermedie di Xcode. Vengono rigenerate automaticamente alla prossima compilazione. Sicuro da eliminare.",
                safety: .safe,
                resolvePaths: { [home.appendingPathComponent("Library/Developer/Xcode/DerivedData")] }
            ),
            CleanCategory(
                id: "xcode-archives",
                title: "Xcode – Archivi",
                explanation: "Build archiviate (.xcarchive) usate per caricare su App Store e per simbolicare i crash report. Elimina solo gli archivi di versioni vecchie che non ti servono più.",
                safety: .caution,
                resolvePaths: { [home.appendingPathComponent("Library/Developer/Xcode/Archives")] }
            ),
            CleanCategory(
                id: "sim-caches",
                title: "Simulatore iOS – cache",
                explanation: "Cache del Simulatore iOS/watchOS/tvOS. Sicuro da eliminare.",
                safety: .safe,
                resolvePaths: { [home.appendingPathComponent("Library/Developer/CoreSimulator/Caches")] }
            ),
            CleanCategory(
                id: "sim-devices",
                title: "Simulatore iOS – dispositivi",
                explanation: "Dati dei singoli simulatori (app installate, dati salvati). Elimina solo i dispositivi/OS che non usi più: non si recuperano in modo affidabile dal Cestino.",
                safety: .caution,
                resolvePaths: { [home.appendingPathComponent("Library/Developer/CoreSimulator/Devices")] }
            ),
            CleanCategory(
                id: "npm",
                title: "Cache npm",
                explanation: "Pacchetti npm scaricati e cachati. Vengono riscaricati automaticamente quando servono. Sicuro da eliminare.",
                safety: .safe,
                resolvePaths: { npmCachePaths(home: home) }
            ),
            CleanCategory(
                id: "yarn",
                title: "Cache Yarn",
                explanation: "Pacchetti Yarn cachati. Sicuro da eliminare, verranno riscaricati.",
                safety: .safe,
                resolvePaths: { [home.appendingPathComponent("Library/Caches/Yarn")] }
            ),
            CleanCategory(
                id: "pnpm",
                title: "Store pnpm",
                explanation: "Store centralizzato di pnpm condiviso tra tutti i progetti. Svuotarlo non causa perdita di dati ma rallenta temporaneamente le prossime installazioni perché i pacchetti vanno riscaricati.",
                safety: .caution,
                resolvePaths: { pnpmStorePaths() }
            ),
            CleanCategory(
                id: "homebrew",
                title: "Cache Homebrew",
                explanation: "Pacchetti scaricati da Homebrew già installati sul sistema. Sicuro da eliminare.",
                safety: .safe,
                resolvePaths: { homebrewCachePaths() }
            ),
            CleanCategory(
                id: "cocoapods",
                title: "Cache CocoaPods",
                explanation: "Pod scaricati e cachati. Sicuro da eliminare, verranno riscaricati al prossimo `pod install`.",
                safety: .safe,
                resolvePaths: { [home.appendingPathComponent("Library/Caches/CocoaPods")] }
            ),
        ] + aiCategories(home: home) + privacyCategories(home: home)
    }

    // MARK: - Privacy

    private static func privacyCategories(home: URL) -> [CleanCategory] {
        [
            CleanCategory(
                id: "browser-history",
                title: "Cronologia dei browser",
                explanation: "Pagine visitate, siti più visitati e dati di navigazione di Chrome, Edge, Brave, Arc e Firefox. Chiudi il browser prima di eliminare. Perdi la cronologia ma non i segnalibri né le password.",
                safety: .caution,
                resolvePaths: { [home] },
                group: .privacy,
                customItemLister: { browserItems(home: $0, kinds: ["History", "Top Sites", "Visited Links", "Favicons", "places.sqlite", "favicons.sqlite"]) }
            ),
            CleanCategory(
                id: "browser-cookies",
                title: "Cookie dei browser",
                explanation: "Cookie di Chrome, Edge, Brave, Arc e Firefox. Eliminandoli esci da tutti i siti in cui sei collegato e dovrai rifare l'accesso. Chiudi il browser prima di procedere.",
                safety: .caution,
                resolvePaths: { [home] },
                group: .privacy,
                customItemLister: { browserItems(home: $0, kinds: ["Cookies", "Cookies-journal", "cookies.sqlite"]) }
            ),
            CleanCategory(
                id: "mail-downloads",
                title: "Allegati aperti da Mail",
                explanation: "Copie degli allegati che hai aperto da Mail, salvate in una cartella temporanea. Gli originali restano nei messaggi. Se qui risulta vuoto può dipendere dai permessi: concedi l'accesso completo al disco a Dustbuster nelle Impostazioni di Sistema.",
                safety: .safe,
                resolvePaths: { [home.appendingPathComponent("Library/Containers/com.apple.mail/Data/Library/Mail Downloads")] },
                group: .privacy,
                customItemLister: { childItems(of: $0) }
            ),
        ]
    }

    private static let browserRoots: [(name: String, path: String, bundleID: String)] = [
        ("Chrome", "Library/Application Support/Google/Chrome", "com.google.Chrome"),
        ("Edge", "Library/Application Support/Microsoft Edge", "com.microsoft.edgemac"),
        ("Brave", "Library/Application Support/BraveSoftware/Brave-Browser", "com.brave.Browser"),
        ("Arc", "Library/Application Support/Arc/User Data", "company.thebrowser.Browser"),
        ("Firefox", "Library/Application Support/Firefox/Profiles", "org.mozilla.firefox"),
    ]

    /// Files with the given names inside each browser profile (and `Network/` for newer Chromium cookies).
    private static func browserItems(home: URL, kinds: [String]) -> [CategoryItem] {
        let fm = FileManager.default
        var items: [CategoryItem] = []
        for browser in browserRoots {
            let root = home.appendingPathComponent(browser.path)
            let profiles = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
            let running = !NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID).isEmpty
            for profile in profiles where (try? profile.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                for folder in [profile, profile.appendingPathComponent("Network")] {
                    for kind in kinds {
                        let url = folder.appendingPathComponent(kind)
                        guard fm.fileExists(atPath: url.path),
                              let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { continue }
                        items.append(CategoryItem(
                            url: url,
                            sizeBytes: Int64(values.fileSize ?? 0),
                            modifiedAt: values.contentModificationDate,
                            label: "\(browser.name) / \(profile.lastPathComponent) / \(kind)" + (running ? " (browser aperto)" : "")
                        ))
                    }
                }
            }
        }
        return items.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    // MARK: - Temporary and backup files left by AI tools

    private static func aiCategories(home: URL) -> [CleanCategory] {
        let claudeDirs = claudeConfigDirs(home: home)
        func inClaude(_ names: String...) -> [URL] {
            claudeDirs.flatMap { dir in names.map { dir.appendingPathComponent($0) } }
        }
        return [
            CleanCategory(
                id: "claude-scratch",
                title: "Claude · lavoro",
                explanation: "Cartelle scratchpad temporanee create da Claude Code durante le sessioni passate (file scaricati, estratti, output intermedi). Sono pensate per essere temporanee: sicure da eliminare, tranne le sessioni modificate di recente che potrebbero essere ancora in corso.",
                safety: .safe,
                resolvePaths: { [URL(fileURLWithPath: "/private/tmp/claude-\(getuid())")] },
                group: .ai,
                customItemLister: claudeScratchItems
            ),
            CleanCategory(
                id: "claude-edit-backups",
                title: "Claude · pre-modifica",
                explanation: "Prima di ogni modifica Claude Code salva una copia del file (cartella file-history), usata solo per annullare le modifiche di una sessione. Eliminarle non tocca i tuoi progetti: perdi solo la possibilità di tornare indietro in quelle sessioni.",
                safety: .safe,
                resolvePaths: { inClaude("file-history") },
                group: .ai,
                customItemLister: { childItems(of: $0) }
            ),
            CleanCategory(
                id: "claude-temp",
                title: "Claude · temporanei",
                explanation: "Snapshot della shell, testi incollati, ambienti di sessione, telemetria, log di debug e copie di sicurezza della configurazione. Vengono ricreati quando servono. Le conversazioni (cartella projects) non vengono mai toccate.",
                safety: .safe,
                resolvePaths: { inClaude("shell-snapshots", "paste-cache", "session-env", "telemetry", "debug", "backups") },
                group: .ai,
                customItemLister: { childItems(of: $0) }
            ),
            CleanCategory(
                id: "codex-temp",
                title: "Codex · cache",
                explanation: "Cache dei plugin, snapshot della shell e file temporanei di Codex. Vengono ricreati automaticamente. Cronologia e sessioni non sono incluse.",
                safety: .safe,
                resolvePaths: { ["cache", "tmp", "shell_snapshots"].map { home.appendingPathComponent(".codex/\($0)") } },
                group: .ai,
                customItemLister: { childItems(of: $0) }
            ),
            CleanCategory(
                id: "codex-images",
                title: "Codex · immagini",
                explanation: "Immagini create da Codex. Se non le hai salvate altrove, eliminandole le perdi: controlla prima di procedere.",
                safety: .caution,
                resolvePaths: { [home.appendingPathComponent(".codex/generated_images")] },
                group: .ai,
                customItemLister: { childItems(of: $0) }
            ),
            CleanCategory(
                id: "ai-backup-files",
                title: "Backup lasciati dall'AI",
                explanation: "Copie di sicurezza che l'AI mette da parte prima di modificare un file: cartelle come _sostituiti o _backup (mostrate per intero) e file come .orig_backup, .bak, .orig, .backup in Scrivania, Documenti, Download, Film e progetti. Controlla che la modifica sia andata a buon fine prima di eliminarle: sono spesso le uniche versioni precedenti. I file dentro repository git non vengono mai mostrati e nessuna voce è preselezionata.",
                safety: .caution,
                resolvePaths: { ["Desktop", "Documents", "Downloads", "Movies", "projects"].map { home.appendingPathComponent($0) } },
                group: .ai,
                customItemLister: backupFileItems
            ),
        ]
    }

    /// `~/.claude`, `~/.claude-work`, … : one configuration folder per Claude account.
    private static func claudeConfigDirs(home: URL) -> [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(at: home, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return entries.filter {
            $0.lastPathComponent.hasPrefix(".claude")
                && (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }.sorted { $0.path < $1.path }
    }

    /// Lists the entries of `base`, labelled with the tool folder they come from.
    private static func childItems(of base: URL) -> [CategoryItem] {
        let owner = base.deletingLastPathComponent().lastPathComponent
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: base, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return entries.filter { $0.lastPathComponent != ".DS_Store" }.map { url in
            let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            return CategoryItem(
                url: url,
                sizeBytes: DiskScanner.sizeOfPath(url),
                modifiedAt: modified,
                label: "\(owner) / \(base.lastPathComponent) / \(url.lastPathComponent.prefix(18))"
            )
        }
    }

    /// Folders where backups are parked (e.g. "_sostituiti"): listed as a whole, never opened into.
    private static let backupFolderNames: Set<String> = [
        "_sostituiti", "_sostituito", "_superati", "_vecchi", "_old", "_bak", "_backup", "_backups", "_replaced", "_archivio_vecchio",
    ]
    private static let backupSuffixes = [".bak", ".orig", ".backup", ".old"]

    private static func isBackupFile(_ name: String) -> Bool {
        let lower = name.lowercased()
        // ".orig_backup" is often followed by a reason and the real extension: video.orig_backup_toodark.mp4
        return lower.contains(".orig_backup") || backupSuffixes.contains { lower.hasSuffix($0) }
    }

    /// Backup folders and files under `root`, skipping repositories and dependency folders.
    private static func backupFileItems(_ root: URL) -> [CategoryItem] {
        let fm = FileManager.default
        guard !GitGuard.isInsideRepo(root),
              let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsPackageDescendants])
        else { return [] }

        let home = fm.homeDirectoryForCurrentUser.path
        var items: [CategoryItem] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]) else { continue }
            if values.isDirectory == true {
                if name == ".git" || GitGuard.projectFolderNames.contains(name) || GitGuard.isRepoRoot(url) {
                    enumerator.skipDescendants()
                } else if backupFolderNames.contains(name.lowercased()) {
                    enumerator.skipDescendants()
                    items.append(CategoryItem(
                        url: url,
                        sizeBytes: DiskScanner.sizeOfPath(url),
                        modifiedAt: values.contentModificationDate,
                        label: "Cartella · " + url.path.replacingOccurrences(of: home, with: "~")
                    ))
                }
                continue
            }
            guard isBackupFile(name), let size = values.fileSize else { continue }
            items.append(CategoryItem(
                url: url,
                sizeBytes: Int64(size),
                modifiedAt: values.contentModificationDate,
                label: url.path.replacingOccurrences(of: home, with: "~")
            ))
        }
        return items
    }

    private static func claudeScratchItems(_ base: URL) -> [CategoryItem] {
        guard let topLevel = try? FileManager.default.contentsOfDirectory(
            at: base,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey]
        ) else {
            return []
        }

        var items: [CategoryItem] = []
        for top in topLevel {
            guard (try? top.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }

            let subdirs = (try? FileManager.default.contentsOfDirectory(
                at: top,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey]
            ))?.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true } ?? []

            if subdirs.isEmpty {
                let modified = try? top.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                items.append(CategoryItem(url: top, sizeBytes: DiskScanner.sizeOfPath(top), modifiedAt: modified, label: top.lastPathComponent, containsRepo: GitGuard.containsRepo(top)))
            } else {
                for session in subdirs {
                    let modified = try? session.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                    let label = "\(top.lastPathComponent) / \(session.lastPathComponent.prefix(8))"
                    items.append(CategoryItem(url: session, sizeBytes: DiskScanner.sizeOfPath(session), modifiedAt: modified, label: label, containsRepo: GitGuard.containsRepo(session)))
                }
            }
        }
        return items.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    private static func npmCachePaths(home: URL) -> [URL] {
        if let path = DiskScanner.runCommand("/usr/bin/env", ["npm", "config", "get", "cache"]), !path.isEmpty {
            return [URL(fileURLWithPath: path)]
        }
        return [home.appendingPathComponent(".npm")]
    }

    private static func pnpmStorePaths() -> [URL] {
        if let path = DiskScanner.runCommand("/usr/bin/env", ["pnpm", "store", "path"]), !path.isEmpty {
            return [URL(fileURLWithPath: path)]
        }
        return []
    }

    private static func homebrewCachePaths() -> [URL] {
        if let path = DiskScanner.runCommand("/usr/bin/env", ["brew", "--cache"]), !path.isEmpty {
            return [URL(fileURLWithPath: path)]
        }
        return []
    }
}
