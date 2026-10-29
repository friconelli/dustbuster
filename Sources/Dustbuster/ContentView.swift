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
                sidebarRow("Panoramica", symbol: "gauge.with.dots.needle.67percent", tint: Theme.teal)
                    .tag(SidebarSelection.overview)

                Section("Cache e temporanei") {
                    ForEach(store.categories) { category in
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

                Section("Strumenti") {
                    sidebarRow("File duplicati", symbol: "doc.on.doc", tint: .teal)
                        .tag(SidebarSelection.duplicates)
                    sidebarRow("Docker", symbol: "cube.box", tint: .blue)
                        .tag(SidebarSelection.docker)
                }
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        } detail: {
            detailView
                .frame(minWidth: 560, minHeight: 480)
        }
        .onAppear {
            store.scanAll()
            store.refreshDockerInfo()
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
        case .duplicates:
            DuplicatesView(store: store)
        case .docker:
            DockerView(store: store)
        }
    }
}
