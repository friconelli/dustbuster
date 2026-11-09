import SwiftUI
import AppKit

// MARK: - Model

struct MapNode: Identifiable, Hashable {
    let url: URL
    let size: Int64
    let isDirectory: Bool
    /// Inside or containing a git repository: shown, but never selectable for the Trash.
    let isProtected: Bool

    var id: String { url.path }
    var name: String { url.lastPathComponent }
}

enum DiskMapScanner {
    /// Sizes of the direct children of `folder`; folders are measured in parallel with `du`.
    /// Each node is reported as soon as it is measured, so large folders do not block the others.
    static func scan(_ folder: URL, onNode: @escaping (MapNode) -> Void) {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey]
        guard let children = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) else { return }
        let parentInRepo = GitGuard.isInsideRepo(folder)

        DispatchQueue.concurrentPerform(iterations: children.count) { index in
            let url = children[index]
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isSymbolicLink != true else { return }
            let isDirectory = values.isDirectory == true
            let size = isDirectory ? DiskScanner.sizeOfPath(url) : Int64(values.totalFileAllocatedSize ?? 0)
            guard size > 0 else { return }
            let node = MapNode(
                url: url,
                size: size,
                isDirectory: isDirectory,
                isProtected: parentInRepo || (isDirectory && GitGuard.containsRepo(url, depth: 2))
            )
            onNode(node)
        }
    }
}

@MainActor
final class DiskMapStore: ObservableObject {
    @Published var path: [URL] = [FileManager.default.homeDirectoryForCurrentUser]
    @Published var nodes: [MapNode] = []
    @Published var isLoading = false
    @Published var selected: Set<String> = []
    private var generation = 0

    var current: URL { path.last! }
    var total: Int64 { nodes.reduce(0) { $0 + $1.size } }

    func load() {
        generation += 1
        let token = generation
        let folder = current
        isLoading = true
        selected = []
        nodes = []
        Task.detached(priority: .userInitiated) {
            DiskMapScanner.scan(folder) { node in
                Task { @MainActor in
                    guard token == self.generation else { return }
                    self.nodes.append(node)
                    self.nodes.sort { $0.size > $1.size }
                }
            }
            await MainActor.run {
                if token == self.generation { self.isLoading = false }
            }
        }
    }

    func open(_ node: MapNode) {
        guard node.isDirectory else { return }
        path.append(node.url)
        load()
    }

    func go(to index: Int) {
        guard index < path.count - 1 else { return }
        path = Array(path.prefix(index + 1))
        load()
    }

    func choose(_ url: URL) {
        path = [url]
        load()
    }

    func toggle(_ node: MapNode) {
        guard !node.isProtected else { return }
        if selected.contains(node.id) { selected.remove(node.id) } else { selected.insert(node.id) }
    }

    var selectedSize: Int64 { nodes.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.size } }

    func trashSelected() {
        let urls = nodes.filter { selected.contains($0.id) && !$0.isProtected }.map(\.url)
        DiskScanner.trash(urls)
        load()
    }
}

// MARK: - Squarified treemap

enum Treemap {
    /// Lays `values` (sorted descending) out in `rect` with cells as close to square as possible.
    static func layout(_ values: [Double], in rect: CGRect) -> [CGRect] {
        let total = values.reduce(0, +)
        guard total > 0, rect.width > 0, rect.height > 0 else { return values.map { _ in .zero } }
        let scale = Double(rect.width * rect.height) / total
        let areas = values.map { $0 * scale }
        var result = [CGRect](repeating: .zero, count: areas.count)
        var remaining = rect
        var start = 0

        func worst(_ row: ArraySlice<Double>, side: Double) -> Double {
            let sum = row.reduce(0, +)
            guard let high = row.max(), let low = row.min(), sum > 0, low > 0 else { return .infinity }
            return max(side * side * high / (sum * sum), sum * sum / (side * side * low))
        }

        while start < areas.count {
            let side = Double(min(remaining.width, remaining.height))
            var end = start + 1
            while end < areas.count, worst(areas[start...end], side: side) <= worst(areas[start..<end], side: side) {
                end += 1
            }
            let row = areas[start..<end]
            let sum = row.reduce(0, +)
            if remaining.width >= remaining.height {
                let width = CGFloat(sum) / remaining.height
                var y = remaining.minY
                for i in start..<end {
                    let height = CGFloat(areas[i]) / width
                    result[i] = CGRect(x: remaining.minX, y: y, width: width, height: height)
                    y += height
                }
                remaining = CGRect(x: remaining.minX + width, y: remaining.minY, width: remaining.width - width, height: remaining.height)
            } else {
                let height = CGFloat(sum) / remaining.width
                var x = remaining.minX
                for i in start..<end {
                    let width = CGFloat(areas[i]) / height
                    result[i] = CGRect(x: x, y: remaining.minY, width: width, height: height)
                    x += width
                }
                remaining = CGRect(x: remaining.minX, y: remaining.minY + height, width: remaining.width, height: remaining.height - height)
            }
            start = end
        }
        return result
    }
}

// MARK: - View

struct DiskMapView: View {
    @StateObject private var map = DiskMapStore()
    @State private var showTrashConfirm = false

    private let palette: [Color] = [Theme.accentDeep, Theme.plum, Theme.indigo, Theme.orchid, Theme.mauve, Theme.slate]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    symbol: "square.grid.3x3.fill",
                    tint: Theme.indigo,
                    title: "Mappa dello spazio",
                    subtitle: "Ogni blocco è una cartella o un file: più è grande, più spazio occupa. Tocca una cartella per entrarci. Le cartelle con repository git sono bloccate e non si possono eliminare da qui."
                ) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(formatBytes(map.total))
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .monospacedDigit()
                        Text("\(map.nodes.count) elementi")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                breadcrumb

                if map.isLoading && map.nodes.isEmpty {
                    Card {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("Misuro le dimensioni…").foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    }
                } else if map.nodes.isEmpty && !map.isLoading {
                    Card {
                        EmptyStateView(symbol: "folder", title: "Cartella vuota", message: "Qui non c'è niente che occupi spazio.")
                            .padding(.vertical, 20)
                    }
                } else {
                    if map.isLoading {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Sto ancora misurando le cartelle più grandi…").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    Card(padding: 8) { treemap }
                    list
                }
            }
            .padding(28)
            .padding(.bottom, 70)
        }
        .overlay(alignment: .bottom) {
            if !map.selected.isEmpty { actionBar }
        }
        .navigationTitle("Mappa dello spazio")
        .onAppear { if map.nodes.isEmpty { map.load() } }
        .alert("Spostare \(map.selected.count) elementi nel Cestino?", isPresented: $showTrashConfirm) {
            Button("Sposta nel Cestino", role: .destructive) { map.trashSelected() }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Libererai circa \(formatBytes(map.selectedSize)). Potrai recuperarli dal Cestino finché non lo svuoti.")
        }
    }

    private var breadcrumb: some View {
        HStack(spacing: 6) {
            ForEach(Array(map.path.enumerated()), id: \.offset) { index, url in
                if index > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                Button(index == 0 ? (url == FileManager.default.homeDirectoryForCurrentUser ? "Home" : url.lastPathComponent) : url.lastPathComponent) {
                    map.go(to: index)
                }
                .buttonStyle(.plain)
                .font(.callout.weight(index == map.path.count - 1 ? .semibold : .regular))
                .foregroundStyle(index == map.path.count - 1 ? .primary : .secondary)
            }
            Spacer()
            Menu {
                Button("Home") { map.choose(FileManager.default.homeDirectoryForCurrentUser) }
                Button("Macintosh HD") { map.choose(URL(fileURLWithPath: "/")) }
                Button("Altra cartella…") { chooseFolder() }
            } label: {
                Label("Parti da", systemImage: "folder")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Button { map.load() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain)
                .help("Rimisura")
        }
    }

    private var treemap: some View {
        let shown = Array(map.nodes.prefix(60))
        return GeometryReader { proxy in
            let rects = Treemap.layout(shown.map { Double($0.size) }, in: CGRect(origin: .zero, size: proxy.size))
            ZStack(alignment: .topLeading) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, node in
                    cell(node, index: index, rect: rects[index])
                }
            }
        }
        .frame(height: 380)
    }

    private func cell(_ node: MapNode, index: Int, rect: CGRect) -> some View {
        let color = node.isDirectory ? palette[index % palette.count] : Theme.night
        let isSelected = map.selected.contains(node.id)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color.opacity(node.isProtected ? 0.45 : 0.9))
            if rect.width > 70, rect.height > 38 {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 3) {
                        if node.isProtected { Image(systemName: "lock.fill").font(.system(size: 9)) }
                        Text(node.name).lineLimit(1)
                    }
                    .font(.caption.weight(.semibold))
                    Text(formatBytes(node.size)).font(.caption2.monospacedDigit()).opacity(0.85)
                }
                .foregroundStyle(.white)
                .padding(6)
            }
            if isSelected {
                RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.accent, lineWidth: 3)
            }
        }
        .frame(width: max(rect.width - 2, 0), height: max(rect.height - 2, 0))
        .offset(x: rect.minX + 1, y: rect.minY + 1)
        .contentShape(Rectangle())
        .onTapGesture { node.isDirectory ? map.open(node) : map.toggle(node) }
        .help("\(node.name) — \(formatBytes(node.size))")
    }

    private var list: some View {
        Card(padding: 6) {
            LazyVStack(spacing: 0) {
                ForEach(Array(map.nodes.prefix(200).enumerated()), id: \.element.id) { index, node in
                    if index > 0 { Divider().padding(.leading, 44) }
                    row(node)
                }
            }
        }
    }

    private func row(_ node: MapNode) -> some View {
        let isSelected = map.selected.contains(node.id)
        return HStack(spacing: 12) {
            if node.isProtected {
                Image(systemName: "lock.fill").foregroundStyle(.secondary).frame(width: 18)
            } else {
                SelectionCheckbox(isOn: isSelected) { map.toggle(node) }
            }
            Image(nsImage: NSWorkspace.shared.icon(forFile: node.url.path)).resizable().frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(node.name).lineLimit(1).truncationMode(.middle)
                    if node.isProtected {
                        Text("repository git")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Color.red.opacity(0.15), in: Capsule())
                            .foregroundStyle(.red)
                    }
                }
                GeometryReader { proxy in
                    Capsule().fill(Theme.accentDeep.opacity(0.18))
                        .overlay(alignment: .leading) {
                            Capsule().fill(Theme.accentDeep.opacity(0.75))
                                .frame(width: max(3, proxy.size.width * CGFloat(Double(node.size) / Double(max(map.nodes.first?.size ?? 1, 1)))))
                        }
                }
                .frame(height: 4)
            }
            Text(formatBytes(node.size)).font(.callout.monospacedDigit()).foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
            Button { NSWorkspace.shared.activateFileViewerSelecting([node.url]) } label: { Image(systemName: "magnifyingglass.circle") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Mostra nel Finder")
            Image(systemName: node.isDirectory ? "chevron.right" : "").font(.caption).foregroundStyle(.tertiary).frame(width: 10)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(isSelected ? Theme.accentDeep.opacity(0.1) : .clear))
        .contentShape(Rectangle())
        .onTapGesture { node.isDirectory ? map.open(node) : map.toggle(node) }
    }

    private var actionBar: some View {
        ActionBar {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(map.selected.count) selezionati").font(.caption).foregroundStyle(.secondary)
                Text(formatBytes(map.selectedSize)).font(.headline.monospacedDigit())
            }
            Spacer()
            Button("Deseleziona") { map.selected = [] }
            Button(role: .destructive) { showTrashConfirm = true } label: { Label("Sposta nel Cestino", systemImage: "trash") }
                .prominentButton().tint(.red).controlSize(.large)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url { map.choose(url) }
    }
}
