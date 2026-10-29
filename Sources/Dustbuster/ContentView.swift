import SwiftUI

enum SidebarSelection: Hashable {
    case overview
    case category(String)
    case duplicates
    case docker
}

func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

struct ContentView: View {
    @StateObject private var store = CleanupStore()
    @State private var selection: SidebarSelection? = .overview

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("Panoramica", systemImage: "square.grid.2x2")
                    .tag(SidebarSelection.overview)

                Section("Cache e temporanei") {
                    ForEach(store.categories) { category in
                        Label(category.title, systemImage: icon(for: category.safety))
                            .tag(SidebarSelection.category(category.id))
                    }
                }

                Section("Altro") {
                    Label("File duplicati", systemImage: "doc.on.doc")
                        .tag(SidebarSelection.duplicates)
                    Label("Docker", systemImage: "shippingbox")
                        .tag(SidebarSelection.docker)
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            detailView
                .frame(minWidth: 520, minHeight: 420)
        }
        .onAppear {
            store.scanAll()
            store.refreshDockerInfo()
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .none, .overview:
            OverviewView(store: store)
        case .category(let id):
            if let category = store.categories.first(where: { $0.id == id }) {
                CategoryDetailView(store: store, category: category)
            }
        case .duplicates:
            DuplicatesView(store: store)
        case .docker:
            DockerView(store: store)
        }
    }

    private func icon(for safety: SafetyLevel) -> String {
        switch safety {
        case .safe: return "checkmark.circle"
        case .caution: return "exclamationmark.triangle"
        case .info: return "info.circle"
        }
    }
}
