import SwiftUI
import AppKit
import CoreServices

// MARK: - Scanning

struct InstalledApp: Identifiable, Hashable {
    let url: URL
    let name: String
    let bundleID: String?
    let sizeBytes: Int64
    let lastUsed: Date?

    var id: String { url.path }
    /// Apps that are part of macOS cannot be removed; Apple apps installed in /Applications (Xcode, iMovie…) can.
    var isProtected: Bool { url.path.hasPrefix("/System") || bundleID == "com.apple.Safari" || bundleID == "com.apple.finder" }
}

enum AppScanner {
    private static let home = FileManager.default.homeDirectoryForCurrentUser

    /// Folders under ~/Library where apps keep their data, with how an entry is matched to an app.
    private static let libraryFolders = [
        "Application Support", "Caches", "Preferences", "Containers", "Group Containers", "Logs",
        "Saved Application State", "HTTPStorages", "WebKit", "Application Scripts", "LaunchAgents", "Cookies",
    ]

    static func installedApps() -> [InstalledApp] {
        let roots = [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
        var apps: [InstalledApp] = []
        for root in roots {
            let entries = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            for url in entries where url.pathExtension == "app" {
                let bundle = Bundle(url: url)
                let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                apps.append(InstalledApp(
                    url: url, name: name, bundleID: bundle?.bundleIdentifier,
                    sizeBytes: DiskScanner.sizeOfPath(url), lastUsed: lastUsedDate(url)))
            }
        }
        return apps.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    static func lastUsedDate(_ url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(nil, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    /// Data an app left in ~/Library, matched by bundle identifier (or exact app name where apps use it).
    static func leftovers(of app: InstalledApp) -> [CategoryItem] {
        let library = home.appendingPathComponent("Library")
        let bundleID = app.bundleID?.lowercased()
        let names: Set<String> = [app.name.lowercased(), app.url.deletingPathExtension().lastPathComponent.lowercased()]
        var found: [CategoryItem] = []
        for folder in libraryFolders {
            let base = library.appendingPathComponent(folder)
            for url in (try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
                let lower = url.lastPathComponent.lowercased()
                let stem = lower.replacingOccurrences(of: ".plist", with: "").replacingOccurrences(of: ".savedstate", with: "")
                let byID = bundleID.map { stem == $0 || stem.hasPrefix($0 + ".") || stem.hasSuffix("." + $0) } ?? false
                let byName = ["Application Support", "Caches", "Logs"].contains(folder) && names.contains(stem)
                guard byID || byName else { continue }
                let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                found.append(CategoryItem(
                    url: url, sizeBytes: DiskScanner.sizeOfPath(url), modifiedAt: modified,
                    label: "\(folder) / \(url.lastPathComponent)"))
            }
        }
        return found.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    /// Data left behind by apps that are no longer installed: reverse-DNS names with no matching app.
    static func orphans(installed: [InstalledApp]) -> [CategoryItem] {
        let library = home.appendingPathComponent("Library")
        let ids = Set(installed.compactMap { $0.bundleID?.lowercased() })
        let pattern = try! NSRegularExpression(pattern: "^[a-z0-9-]+\\.[a-z0-9-]+\\.[a-z0-9._-]+$")
        var found: [CategoryItem] = []
        for folder in ["Application Support", "Caches", "Preferences", "Containers", "Saved Application State", "HTTPStorages", "WebKit", "Logs"] {
            let base = library.appendingPathComponent(folder)
            for url in (try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
                var stem = url.lastPathComponent.lowercased()
                for suffix in [".plist", ".savedstate"] where stem.hasSuffix(suffix) { stem = String(stem.dropLast(suffix.count)) }
                guard pattern.firstMatch(in: stem, range: NSRange(stem.startIndex..., in: stem)) != nil,
                      !stem.hasPrefix("com.apple."), !stem.hasPrefix("group.com.apple.") else { continue }
                // Still owned by an installed app (the app itself, or one of its helpers and extensions).
                if ids.contains(where: { stem == $0 || stem.hasPrefix($0 + ".") || $0.hasPrefix(stem + ".") }) { continue }
                if NSWorkspace.shared.urlForApplication(withBundleIdentifier: stem) != nil { continue }
                let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                found.append(CategoryItem(
                    url: url, sizeBytes: DiskScanner.sizeOfPath(url), modifiedAt: modified,
                    label: "\(folder) / \(url.lastPathComponent)"))
            }
        }
        return found.sorted { $0.sizeBytes > $1.sizeBytes }
    }
}

// MARK: - Store

@MainActor
final class AppsStore: ObservableObject {
    @Published var apps: [InstalledApp] = []
    @Published var isLoading = false
    @Published var leftovers: [CategoryItem] = []
    @Published var leftoverSelection: Set<String> = []
    @Published var isLoadingLeftovers = false
    @Published var orphans: [CategoryItem] = []
    @Published var orphanSelection: Set<String> = []
    @Published var isLoadingOrphans = false
    @Published var message: String?

    func load() {
        guard !isLoading else { return }
        isLoading = true
        Task.detached(priority: .userInitiated) {
            let result = AppScanner.installedApps()
            await MainActor.run { self.apps = result; self.isLoading = false }
        }
    }

    func loadLeftovers(for app: InstalledApp) {
        isLoadingLeftovers = true
        leftovers = []
        Task.detached(priority: .userInitiated) {
            let result = AppScanner.leftovers(of: app)
            await MainActor.run {
                self.leftovers = result
                self.leftoverSelection = Set(result.map(\.id))
                self.isLoadingLeftovers = false
            }
        }
    }

    func loadOrphans() {
        guard !isLoadingOrphans else { return }
        isLoadingOrphans = true
        let installed = apps
        Task.detached(priority: .userInitiated) {
            let result = AppScanner.orphans(installed: installed)
            await MainActor.run {
                self.orphans = result
                self.orphanSelection = []
                self.isLoadingOrphans = false
            }
        }
    }

    func isRunning(_ app: InstalledApp) -> Bool {
        guard let id = app.bundleID else { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty
    }

    func uninstall(_ app: InstalledApp) {
        guard !app.isProtected, !isRunning(app) else { return }
        let urls = [app.url] + leftovers.filter { leftoverSelection.contains($0.id) }.map(\.url)
        let failed = DiskScanner.trash(urls)
        message = failed.isEmpty ? "\(app.name) spostata nel Cestino." : "Non sono riuscito a spostare \(failed.count) elementi."
        apps.removeAll { $0.id == app.id }
        leftovers = []
        loadOrphans()
    }

    func trashOrphans() {
        let urls = orphans.filter { orphanSelection.contains($0.id) }.map(\.url)
        DiskScanner.trash(urls)
        loadOrphans()
    }

    var orphanSelectedSize: Int64 { orphans.filter { orphanSelection.contains($0.id) }.reduce(0) { $0 + $1.sizeBytes } }
}

// MARK: - View

struct AppsView: View {
    @StateObject private var store = AppsStore()
    @State private var mode = 0
    @State private var search = ""
    @State private var sortBySize = true
    @State private var selected: InstalledApp?
    @State private var showUninstall = false
    @State private var showOrphanTrash = false

    private var visible: [InstalledApp] {
        let filtered = search.isEmpty ? store.apps : store.apps.filter { $0.name.localizedCaseInsensitiveContains(search) }
        return sortBySize ? filtered : filtered.sorted { ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    symbol: "app.badge.checkmark",
                    tint: Theme.plum,
                    title: "App",
                    subtitle: "Disinstalla un'app insieme ai file che lascia in Libreria, oppure trova i resti di app che non hai più."
                ) { EmptyView() }

                Picker("", selection: $mode) {
                    Text("Disinstalla").tag(0)
                    Text("Resti di app rimosse").tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 360)

                if let message = store.message {
                    Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(Theme.plum).font(.callout)
                }

                if mode == 0 { appList } else { orphanList }
            }
            .padding(28)
            .padding(.bottom, 70)
        }
        .overlay(alignment: .bottom) {
            if mode == 1, !store.orphanSelection.isEmpty {
                ActionBar {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(store.orphanSelection.count) selezionati").font(.caption).foregroundStyle(.secondary)
                        Text(formatBytes(store.orphanSelectedSize)).font(.headline.monospacedDigit())
                    }
                    Spacer()
                    Button(role: .destructive) { showOrphanTrash = true } label: { Label("Sposta nel Cestino", systemImage: "trash") }
                        .prominentButton().tint(.red).controlSize(.large)
                }
            }
        }
        .navigationTitle("App")
        .onAppear { if store.apps.isEmpty { store.load() } }
        .onChange(of: mode) { newValue in if newValue == 1, store.orphans.isEmpty { store.loadOrphans() } }
        .alert("Spostare \(store.orphanSelection.count) elementi nel Cestino?", isPresented: $showOrphanTrash) {
            Button("Sposta nel Cestino", role: .destructive) { store.trashOrphans() }
            Button("Annulla", role: .cancel) {}
        } message: { Text("Libererai circa \(formatBytes(store.orphanSelectedSize)). Potrai recuperarli dal Cestino.") }
    }

    // MARK: Apps

    private var appList: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                TextField("Cerca un'app", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                Picker("Ordina", selection: $sortBySize) {
                    Text("Più grandi").tag(true)
                    Text("Meno usate").tag(false)
                }
                .pickerStyle(.segmented).frame(maxWidth: 220)
                Spacer()
                if store.isLoading { ProgressView().controlSize(.small) }
            }

            if let app = selected { detail(app) }

            Card(padding: 6) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, app in
                        if index > 0 { Divider().padding(.leading, 44) }
                        appRow(app)
                    }
                }
            }
        }
    }

    private func appRow(_ app: InstalledApp) -> some View {
        let isSelected = selected?.id == app.id
        return HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).lineLimit(1)
                Text(app.lastUsed.map { "Usata \(relativeDateFormatter.localizedString(for: $0, relativeTo: Date()))" } ?? "Mai usata o sconosciuto")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if app.isProtected {
                Label("macOS", systemImage: "lock.fill").font(.caption).foregroundStyle(.secondary)
            }
            Text(formatBytes(app.sizeBytes)).font(.callout.monospacedDigit()).foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(isSelected ? Theme.accentDeep.opacity(0.12) : .clear))
        .contentShape(Rectangle())
        .onTapGesture {
            guard !app.isProtected else { return }
            selected = app
            store.message = nil
            store.loadLeftovers(for: app)
        }
    }

    private func detail(_ app: InstalledApp) -> some View {
        let leftoverSize = store.leftovers.filter { store.leftoverSelection.contains($0.id) }.reduce(0) { $0 + $1.sizeBytes }
        let running = store.isRunning(app)
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name).font(.title3.bold())
                        Text(app.bundleID ?? app.url.path).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { selected = nil } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
                Text("File lasciati in Libreria").font(.headline)
                if store.isLoadingLeftovers {
                    ProgressView().controlSize(.small)
                } else if store.leftovers.isEmpty {
                    Text("Nessun file associato trovato: verrà spostata solo l'app.").font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(store.leftovers) { item in
                        HStack(spacing: 10) {
                            SelectionCheckbox(isOn: store.leftoverSelection.contains(item.id)) {
                                if store.leftoverSelection.contains(item.id) { store.leftoverSelection.remove(item.id) } else { store.leftoverSelection.insert(item.id) }
                            }
                            Text(item.displayName).font(.callout).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(formatBytes(item.sizeBytes)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
                HStack {
                    if running {
                        Label("L'app è aperta: chiudila per disinstallarla.", systemImage: "exclamationmark.triangle.fill")
                            .font(.callout).foregroundStyle(.orange)
                    } else {
                        Text("Libererai circa \(formatBytes(app.sizeBytes + leftoverSize)).").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) { showUninstall = true } label: { Label("Disinstalla", systemImage: "trash") }
                        .prominentButton().tint(.red).disabled(running || store.isLoadingLeftovers)
                }
            }
        }
        .alert("Disinstallare \(app.name)?", isPresented: $showUninstall) {
            Button("Sposta nel Cestino", role: .destructive) { store.uninstall(app); selected = nil }
            Button("Annulla", role: .cancel) {}
        } message: { Text("L'app e i file selezionati vanno nel Cestino, da cui puoi recuperarli.") }
    }

    // MARK: Orphans

    private var orphanList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Elementi con nome tipo com.azienda.app il cui programma non è più installato. Potrebbero però servire a strumenti da riga di comando o a estensioni: controlla prima di eliminare, nulla è preselezionato.", systemImage: "exclamationmark.triangle.fill")
                .font(.callout).foregroundStyle(.orange)
            if store.isLoadingOrphans {
                Card { HStack { ProgressView().controlSize(.small); Text("Cerco i resti…").foregroundStyle(.secondary) }.frame(maxWidth: .infinity).padding(.vertical, 40) }
            } else if store.orphans.isEmpty {
                Card { EmptyStateView(symbol: "checkmark.seal", title: "Nessun resto trovato").padding(.vertical, 20) }
            } else {
                Card(padding: 6) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(store.orphans.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { Divider().padding(.leading, 44) }
                            HStack(spacing: 12) {
                                SelectionCheckbox(isOn: store.orphanSelection.contains(item.id)) {
                                    if store.orphanSelection.contains(item.id) { store.orphanSelection.remove(item.id) } else { store.orphanSelection.insert(item.id) }
                                }
                                Text(item.displayName).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text(formatBytes(item.sizeBytes)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 8)
                        }
                    }
                }
            }
        }
    }
}
