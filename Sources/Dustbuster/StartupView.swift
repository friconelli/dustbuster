import SwiftUI
import AppKit

// MARK: - Model

struct StartupItem: Identifiable, Hashable {
    enum Scope: String { case user = "Tuo utente", system = "Tutti gli utenti", daemon = "Sistema" }

    let url: URL
    let label: String
    let program: String?
    let scope: Scope
    let runsAtLoad: Bool
    let isLoaded: Bool
    /// The program the item starts no longer exists: usually left behind by an app that was removed.
    let programMissing: Bool

    var id: String { url.path }
    /// Only items in the user's own LaunchAgents can be changed without administrator rights.
    var canDisable: Bool { scope == .user }
}

enum StartupScanner {
    static func scan() -> [StartupItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let sources: [(URL, StartupItem.Scope)] = [
            (home.appendingPathComponent("Library/LaunchAgents"), .user),
            (URL(fileURLWithPath: "/Library/LaunchAgents"), .system),
            (URL(fileURLWithPath: "/Library/LaunchDaemons"), .daemon),
        ]
        let loaded = loadedLabels()
        var items: [StartupItem] = []
        for (folder, scope) in sources {
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for url in files where url.pathExtension == "plist" {
                guard let data = try? Data(contentsOf: url),
                      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { continue }
                let label = plist["Label"] as? String ?? url.deletingPathExtension().lastPathComponent
                if label.hasPrefix("com.apple.") { continue }
                let program = (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [String])?.first
                let missing = program.map { $0.hasPrefix("/") && !FileManager.default.fileExists(atPath: $0) } ?? false
                items.append(StartupItem(
                    url: url, label: label, program: program, scope: scope,
                    runsAtLoad: plist["RunAtLoad"] as? Bool ?? false,
                    isLoaded: loaded.contains(label), programMissing: missing))
            }
        }
        return items.sorted { ($0.programMissing ? 0 : 1, $0.label) < ($1.programMissing ? 0 : 1, $1.label) }
    }

    private static func loadedLabels() -> Set<String> {
        guard let output = DiskScanner.runCommand("/bin/launchctl", ["list"]) else { return [] }
        return Set(output.split(separator: "\n").dropFirst().compactMap { $0.split(separator: "\t").last.map(String.init) })
    }

    /// Stops the agent for this login session, then moves its plist to the Trash (so it can be restored).
    static func disable(_ item: StartupItem) -> Bool {
        guard item.canDisable else { return false }
        _ = DiskScanner.runCommand("/bin/launchctl", ["bootout", "gui/\(getuid())", item.url.path])
        return DiskScanner.trash([item.url]).isEmpty
    }
}

// MARK: - View

struct StartupView: View {
    @State private var items: [StartupItem] = []
    @State private var isLoading = false
    @State private var pending: StartupItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    symbol: "power",
                    tint: Theme.mauve,
                    title: "Elementi di avvio",
                    subtitle: "Programmi che partono da soli all'accesso o in background (launch agent). Puoi disattivare quelli del tuo utente; gli altri richiedono l'amministratore e si possono solo mostrare nel Finder."
                ) {
                    Button {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
                    } label: { Label("Apri Elementi di login", systemImage: "gearshape") }
                        .secondaryButton()
                }

                if isLoading {
                    Card { HStack { ProgressView().controlSize(.small); Text("Leggo gli elementi…").foregroundStyle(.secondary) }.frame(maxWidth: .infinity).padding(.vertical, 40) }
                } else if items.isEmpty {
                    Card { EmptyStateView(symbol: "checkmark.seal", title: "Nessun elemento di terze parti").padding(.vertical, 20) }
                } else {
                    let broken = items.filter(\.programMissing)
                    if !broken.isEmpty {
                        Label("\(broken.count) elementi puntano a un programma che non esiste più: di solito sono resti di app rimosse. Controlla che l'app non sia ancora installata prima di disattivarli.", systemImage: "exclamationmark.triangle.fill")
                            .font(.callout).foregroundStyle(.orange)
                    }
                    Card(padding: 6) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                if index > 0 { Divider().padding(.leading, 14) }
                                row(item)
                            }
                        }
                    }
                }
            }
            .padding(28)
        }
        .navigationTitle("Elementi di avvio")
        .onAppear { if items.isEmpty { load() } }
        .alert("Disattivare \(pending?.label ?? "")?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button("Disattiva", role: .destructive) {
                if let item = pending { _ = StartupScanner.disable(item); load() }
                pending = nil
            }
            Button("Annulla", role: .cancel) { pending = nil }
        } message: { Text("L'elemento smette di partire da solo e il suo file va nel Cestino: potrai ripristinarlo da lì.") }
    }

    private func load() {
        isLoading = true
        Task.detached(priority: .userInitiated) {
            let result = StartupScanner.scan()
            await MainActor.run { items = result; isLoading = false }
        }
    }

    private func row(_ item: StartupItem) -> some View {
        HStack(spacing: 12) {
            Circle().fill(item.isLoaded ? Theme.accentDeep : Color.secondary.opacity(0.4)).frame(width: 8, height: 8)
                .help(item.isLoaded ? "In esecuzione" : "Non attivo ora")
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.label).lineLimit(1).truncationMode(.middle)
                    if item.programMissing {
                        Text("programma mancante")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }
                Text(item.program ?? item.url.path).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(item.scope.rawValue).font(.caption).foregroundStyle(.tertiary)
            if item.runsAtLoad { Text("all'accesso").font(.caption2).foregroundStyle(.secondary) }
            if item.canDisable {
                Button("Disattiva") { pending = item }.secondaryButton().controlSize(.small)
            } else {
                Button { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } label: { Image(systemName: "magnifyingglass.circle") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Mostra nel Finder")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}
