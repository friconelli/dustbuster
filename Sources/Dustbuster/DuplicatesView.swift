import SwiftUI
import AppKit

struct DuplicatesView: View {
    @ObservedObject var store: CleanupStore
    @State private var showTrashConfirm = false

    private var totalWasted: Int64 {
        store.duplicateGroups.reduce(0) { $0 + $1.wastedBytes }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    symbol: "doc.on.doc",
                    tint: .teal,
                    title: "File duplicati",
                    subtitle: "Cerca file con contenuto identico nelle cartelle scelte. In ogni gruppo la copia più vecchia resta deselezionata e non viene mai toccata."
                ) {
                    if !store.duplicateGroups.isEmpty {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(formatBytes(totalWasted))
                                .font(.system(.title2, design: .rounded).weight(.bold))
                                .monospacedDigit()
                            Text("\(store.duplicateGroups.count) gruppi")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                foldersCard

                results
            }
            .padding(28)
            .padding(.bottom, 70)
        }
        .overlay(alignment: .bottom) {
            if !store.duplicateGroups.isEmpty {
                actionBar
            }
        }
        .navigationTitle("File duplicati")
        .alert("Spostare \(store.duplicateSelection.count) duplicati nel Cestino?", isPresented: $showTrashConfirm) {
            Button("Sposta nel Cestino", role: .destructive) {
                store.trashSelectedDuplicates()
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Per ogni gruppo rimane almeno una copia. Libererai circa \(formatBytes(store.duplicateSelectedWastedBytes)).")
        }
    }

    private var foldersCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Cartelle da analizzare")
                    .font(.headline)

                FlowLayout(spacing: 8) {
                    ForEach(store.duplicateFolders, id: \.self) { folder in
                        HStack(spacing: 6) {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(Theme.teal)
                            Text(folder.lastPathComponent)
                            Button {
                                store.removeDuplicateFolder(folder)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                        .font(.callout)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                        .help(folder.path)
                    }

                    Button {
                        addFolder()
                    } label: {
                        Label("Aggiungi", systemImage: "plus")
                            .font(.callout)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3])))
                    }
                    .buttonStyle(.plain)
                }

                HStack {
                    if store.isScanningDuplicates {
                        ProgressView().controlSize(.small)
                        Text(store.duplicateProgressText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button {
                        store.scanDuplicates()
                    } label: {
                        Label("Avvia scansione", systemImage: "magnifyingglass")
                    }
                    .prominentButton()
                    .tint(Theme.teal)
                    .controlSize(.large)
                    .disabled(store.duplicateFolders.isEmpty || store.isScanningDuplicates)
                }
            }
        }
    }

    @ViewBuilder
    private var results: some View {
        if store.isScanningDuplicates {
            EmptyView()
        } else if store.duplicateGroups.isEmpty {
            Card {
                EmptyStateView(
                    symbol: "doc.on.doc",
                    title: "Nessun duplicato",
                    message: "Avvia una scansione per cercare file identici nelle cartelle selezionate."
                )
                .padding(.vertical, 20)
            }
        } else {
            LazyVStack(spacing: 14) {
                ForEach(store.duplicateGroups) { group in
                    groupCard(group)
                }
            }
        }
    }

    private func groupCard(_ group: DuplicateGroup) -> some View {
        Card(padding: 6) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("\(group.files.count) copie")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("recuperabili \(formatBytes(group.wastedBytes))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.teal)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

                ForEach(group.files) { file in
                    let isSelected = store.duplicateSelection.contains(file.id)
                    HStack(spacing: 12) {
                        SelectionCheckbox(isOn: isSelected) {
                            store.toggleDuplicateSelection(file.id)
                        }
                        Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path))
                            .resizable()
                            .frame(width: 22, height: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(file.url.lastPathComponent)
                                .lineLimit(1)
                            Text(file.url.deletingLastPathComponent().path)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        if !isSelected {
                            Text("tenuto")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                        Text(formatBytes(file.sizeBytes))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isSelected ? Theme.teal.opacity(0.08) : .clear)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { store.toggleDuplicateSelection(file.id) }
                }
            }
        }
    }

    private var actionBar: some View {
        ActionBar {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(store.duplicateSelection.count) file selezionati")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(formatBytes(store.duplicateSelectedWastedBytes))
                    .font(.headline.monospacedDigit())
            }
            Spacer()
            Button(role: .destructive) {
                showTrashConfirm = true
            } label: {
                Label("Sposta nel Cestino", systemImage: "trash")
            }
            .prominentButton()
            .tint(.red)
            .controlSize(.large)
            .disabled(store.duplicateSelection.isEmpty || !store.duplicatesKeepAtLeastOnePerGroup)
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            store.addDuplicateFolder(url)
        }
    }
}

/// Simple wrapping layout for folder chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews: subviews, width: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews: subviews, width: bounds.width)
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: .unspecified)
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            var row = rows[rows.count - 1]
            if !row.indices.isEmpty && row.width + spacing + size.width > width {
                let y = row.y + row.height + spacing
                rows.append(Row(y: y))
                row = rows[rows.count - 1]
            }
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
