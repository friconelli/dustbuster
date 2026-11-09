import SwiftUI

enum SidebarSelection: Hashable {
    case overview
    case category(String)
    case diskMap
    case apps
    case largeFiles
    case startup
    case duplicates
    case docker
}

func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

struct ContentView: View {
    @StateObject private var store = CleanupStore()
    @State private var selection: SidebarSelection? = ContentView.launchSelection()

    /// `-section diskMap|apps|largeFiles|duplicates` opens that page at launch (used for checking screenshots).
    private static func launchSelection() -> SidebarSelection {
        switch UserDefaults.standard.string(forKey: "section") {
        case "diskMap": return .diskMap
        case "apps": return .apps
        case "largeFiles": return .largeFiles
        case "startup": return .startup
        case "duplicates": return .duplicates
        default: return .overview
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                sidebarRow("Panoramica", symbol: "gauge.with.dots.needle.67percent", tint: Theme.tint)
                    .tag(SidebarSelection.overview)

                categorySection("Cache e temporanei", group: .cleanup)
                categorySection("Creati dall'AI", group: .ai)
                categorySection("Privacy", group: .privacy)

                Section("Strumenti") {
                    sidebarRow("Mappa dello spazio", symbol: "square.grid.3x3.fill", tint: Theme.indigo)
                        .tag(SidebarSelection.diskMap)
                    sidebarRow("App e resti", symbol: "app.badge.checkmark", tint: Theme.plum)
                        .tag(SidebarSelection.apps)
                    sidebarRow("File grandi e vecchi", symbol: "externaldrive.badge.clock", tint: Theme.orchid)
                        .tag(SidebarSelection.largeFiles)
                    sidebarRow("Elementi di avvio", symbol: "power", tint: Theme.mauve)
                        .tag(SidebarSelection.startup)
                    sidebarRow("File duplicati", symbol: "doc.on.doc", tint: Theme.plum)
                        .tag(SidebarSelection.duplicates)
                    sidebarRow("Docker", symbol: "cube.box", tint: Theme.slate)
                        .tag(SidebarSelection.docker)
                }
            }
            .safeAreaInset(edge: .bottom) { UpdateFooter() }
            .navigationSplitViewColumnWidth(min: 260, ideal: 300)
        } detail: {
            detailView
                .frame(minWidth: 560, minHeight: 480)
        }
        .tint(Theme.tint)
        .onAppear {
            store.scanAll()
            store.refreshDockerInfo()
            Updater.shared.checkIfDue()
        }
    }

    private func categorySection(_ title: String, group: CategoryGroup) -> some View {
        Section(title) {
            ForEach(store.categories(in: group)) { category in
                sidebarRow(category.title, symbol: category.symbol, tint: category.tint) {
                    if store.scanningCategoryIDs.contains(category.id) {
                        ProgressView().controlSize(.mini)
                    } else {
                        Text(formatBytes(store.sizeFor(category)))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .tag(SidebarSelection.category(category.id))
            }
        }
    }

    private func sidebarRow(_ title: String, symbol: String, tint: Color) -> some View {
        sidebarRow(title, symbol: symbol, tint: tint) { EmptyView() }
    }

    private func sidebarRow<Trailing: View>(
        _ title: String,
        symbol: String,
        tint: Color,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 10) {
            IconTile(symbol: symbol, tint: tint, size: 22)
            Text(title)
                .lineLimit(1)
            Spacer(minLength: 4)
            trailing()
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .none, .overview:
            OverviewView(store: store, selection: $selection)
        case .category(let id):
            if let category = store.categories.first(where: { $0.id == id }) {
                CategoryDetailView(store: store, category: category)
            }
        case .diskMap:
            DiskMapView()
        case .apps:
            AppsView()
        case .largeFiles:
            LargeFilesView()
        case .startup:
            StartupView()
        case .duplicates:
            DuplicatesView(store: store)
        case .docker:
            DockerView(store: store)
        }
    }
}
