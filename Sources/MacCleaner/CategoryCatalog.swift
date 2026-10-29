import Foundation
import Darwin

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
                id: "claude-scratch",
                title: "Claude Code — file di lavoro",
                explanation: "Cartelle scratchpad temporanee create da Claude Code durante le sessioni passate (file scaricati, estratti, output intermedi). Sono pensate per essere temporanee: sicure da eliminare, tranne le sessioni modificate di recente che potrebbero essere ancora in corso.",
                safety: .safe,
                resolvePaths: { [URL(fileURLWithPath: "/private/tmp/claude-\(getuid())")] },
                customItemLister: claudeScratchItems
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
        ]
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
                items.append(CategoryItem(url: top, sizeBytes: DiskScanner.sizeOfPath(top), modifiedAt: modified, label: top.lastPathComponent))
            } else {
                for session in subdirs {
                    let modified = try? session.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                    let label = "\(top.lastPathComponent) / \(session.lastPathComponent.prefix(8))"
                    items.append(CategoryItem(url: session, sizeBytes: DiskScanner.sizeOfPath(session), modifiedAt: modified, label: label))
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
