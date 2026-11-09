import SwiftUI
import AppKit
import CoreServices

struct LargeFile: Identifiable, Hashable {
    let url: URL
    let sizeBytes: Int64
    /// Last time the file was opened, or modified when macOS has no open date.
    let lastTouched: Date?

    var id: String { url.path }
}

enum LargeFileScanner {
    static func scan(roots: [URL], minBytes: Int64, olderThan cutoff: Date?) -> [LargeFile] {
        let fm = FileManager.default
        var found: [LargeFile] = []
        for root in roots where !GitGuard.isInsideRepo(root) {
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .contentModificationDateKey],
                options: [.skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator {
                guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .contentModificationDateKey]) else { continue }
                if values.isDirectory == true {
                    // Repositories and dependency folders are project files, never "old files".
                    if GitGuard.projectFolderNames.contains(url.lastPathComponent) || GitGuard.isRepoRoot(url) { enumerator.skipDescendants() }
                    continue
                }
                guard values.isSymbolicLink != true, let size = values.totalFileAllocatedSize, Int64(size) >= minBytes else { continue }
                let opened = AppScanner.lastUsedDate(url)
                let touched = [opened, values.contentModificationDate].compactMap { $0 }.max()
                if let cutoff, let touched, touched > cutoff { continue }
                found.append(LargeFile(url: url, sizeBytes: Int64(size), lastTouched: touched))
            }
        }
        return found.sorted { $0.sizeBytes > $1.sizeBytes }
    }
}

@MainActor
final class LargeFilesStore: ObservableObject {
    @Published var files: [LargeFile] = []
    @Published var selection: Set<String> = []
    @Published var isScanning = false
    @Published var hasScanned = false

    func scan(minMB: Int, olderThanMonths: Int) {
        guard !isScanning else { return }
        isScanning = true
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures"].map { home.appendingPathComponent($0) }
        let cutoff = olderThanMonths > 0 ? Calendar.current.date(byAdding: .month, value: -olderThanMonths, to: Date()) : nil
        Task.detached(priority: .userInitiated) {
            let result = LargeFileScanner.scan(roots: roots, minBytes: Int64(minMB) * 1_000_000, olderThan: cutoff)
            await MainActor.run {
                self.files = result
                self.selection = []
                self.isScanning = false
                self.hasScanned = true
            }
        }
    }

    var selectedSize: Int64 { files.filter { selection.contains($0.id) }.reduce(0) { $0 + $1.sizeBytes } }

    func trashSelected(rescan: () -> Void) {
        let urls = files.filter { selection.contains($0.id) }.map(\.url).filter { !GitGuard.isInsideRepo($0) }
        DiskScanner.trash(urls)
        files.removeAll { selection.contains($0.id) }
        selection = []
    }
}

struct LargeFilesView: View {
    @StateObject private var store = LargeFilesStore()
    @State private var minMB = 500
    @State private var months = 6
    @State private var showTrashConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    symbol: "externaldrive.badge.clock",
                    tint: Theme.orchid,
                    title: "File grandi e vecchi",
                    subtitle: "Trova in Scrivania, Documenti, Download, Film, Musica e Immagini i file pesanti che non apri da tempo. I file dentro repository git non compaiono mai."
                ) {
                    if store.hasScanned {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(formatBytes(store.files.reduce(0) { $0 + $1.sizeBytes }))
                                .font(.system(.title2, design: .rounded).weight(.bold)).monospacedDigit()
                            Text("\(store.files.count) file").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Card {
                    HStack(spacing: 16) {
                        Picker("Più grandi di", selection: $minMB) {
                            Text("100 MB").tag(100)
                            Text("500 MB").tag(500)
                            Text("1 GB").tag(1000)
                            Text("5 GB").tag(5000)
                        }
                        .fixedSize()
                        Picker("Non aperti da", selection: $months) {
                            Text("Qualsiasi data").tag(0)
                            Text("3 mesi").tag(3)
                            Text("6 mesi").tag(6)
                            Text("1 anno").tag(12)
                        }
                        .fixedSize()
                        Spacer()
                        if store.isScanning { ProgressView().controlSize(.small) }
                        Button { store.scan(minMB: minMB, olderThanMonths: months) } label: { Label("Cerca", systemImage: "magnifyingglass") }
                            .prominentButton().tint(Theme.tint).controlSize(.large).disabled(store.isScanning)
                    }
                }

                if store.hasScanned, !store.isScanning {
                    if store.files.isEmpty {
                        Card { EmptyStateView(symbol: "checkmark.seal", title: "Nessun file trovato", message: "Prova con una soglia più bassa o una data più vicina.").padding(.vertical, 20) }
                    } else {
                        Card(padding: 6) {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(store.files.prefix(300).enumerated()), id: \.element.id) { index, file in
                                    if index > 0 { Divider().padding(.leading, 44) }
                                    row(file)
                                }
                            }
                        }
                    }
                }
            }
            .padding(28)
            .padding(.bottom, 70)
        }
        .overlay(alignment: .bottom) {
            if !store.selection.isEmpty {
                ActionBar {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(store.selection.count) selezionati").font(.caption).foregroundStyle(.secondary)
                        Text(formatBytes(store.selectedSize)).font(.headline.monospacedDigit())
                    }
                    Spacer()
                    Button("Deseleziona") { store.selection = [] }
                    Button(role: .destructive) { showTrashConfirm = true } label: { Label("Sposta nel Cestino", systemImage: "trash") }
                        .prominentButton().tint(.red).controlSize(.large)
                }
            }
        }
        .navigationTitle("File grandi e vecchi")
        .alert("Spostare \(store.selection.count) file nel Cestino?", isPresented: $showTrashConfirm) {
            Button("Sposta nel Cestino", role: .destructive) { store.trashSelected {} }
            Button("Annulla", role: .cancel) {}
        } message: { Text("Libererai circa \(formatBytes(store.selectedSize)). Potrai recuperarli dal Cestino finché non lo svuoti.") }
    }

    private func row(_ file: LargeFile) -> some View {
        let isSelected = store.selection.contains(file.id)
        let toggle = { if isSelected { store.selection.remove(file.id) } else { store.selection.insert(file.id) } }
        return HStack(spacing: 12) {
            SelectionCheckbox(isOn: isSelected, action: toggle)
            Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path)).resizable().frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                Text(file.url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if let date = file.lastTouched {
                Text(relativeDateFormatter.localizedString(for: date, relativeTo: Date())).font(.caption).foregroundStyle(.tertiary).frame(width: 90, alignment: .trailing)
            }
            Text(formatBytes(file.sizeBytes)).font(.callout.monospacedDigit()).foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
            Button { NSWorkspace.shared.activateFileViewerSelecting([file.url]) } label: { Image(systemName: "magnifyingglass.circle") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Mostra nel Finder")
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(isSelected ? Theme.accentDeep.opacity(0.1) : .clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
    }
}
