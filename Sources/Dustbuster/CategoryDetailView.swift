import SwiftUI
import AppKit

struct CategoryDetailView: View {
    @ObservedObject var store: CleanupStore
    let category: CleanCategory

    @State private var showTrashConfirm = false

    private var items: [CategoryItem] { store.items[category.id] ?? [] }
    private var selected: Set<String> { store.selectedItemIDs[category.id] ?? [] }
    private var selectedSize: Int64 {
        items.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.sizeBytes }
    }
    private var largestSize: Int64 { items.first?.sizeBytes ?? 0 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    symbol: category.symbol,
                    tint: category.tint,
                    title: category.title,
                    subtitle: category.explanation,
                    safety: category.safety
                ) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(formatBytes(DiskScanner.totalSize(of: items)))
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .monospacedDigit()
                        Text("\(items.count) elementi")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                content
            }
            .padding(28)
            .padding(.bottom, 70)
        }
        .overlay(alignment: .bottom) {
            if !items.isEmpty {
                actionBar
            }
        }
        .navigationTitle(category.title)
        .toolbar {
            ToolbarItem {
                Button {
                    store.scan(category)
                } label: {
                    Label("Aggiorna", systemImage: "arrow.clockwise")
                }
                .help("Aggiorna")
            }
        }
        .alert("Spostare \(selected.count) elementi nel Cestino?", isPresented: $showTrashConfirm) {
            Button("Sposta nel Cestino", role: .destructive) {
                store.trashSelected(categoryID: category.id)
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Libererai circa \(formatBytes(selectedSize)). Potrai recuperarli dal Cestino finché non lo svuoti.")
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.scanningCategoryIDs.contains(category.id) {
            Card {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Analisi in corso…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            }
        } else if items.isEmpty {
            Card {
                EmptyStateView(
                    symbol: "checkmark.seal",
                    title: "Tutto pulito",
                    message: "Non c'è niente da eliminare in questa categoria."
                )
                .padding(.vertical, 20)
            }
        } else {
            Card(padding: 6) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Divider().padding(.leading, 44)
                        }
                        ItemRow(
                            item: item,
                            isSelected: selected.contains(item.id),
                            fraction: largestSize > 0 ? Double(item.sizeBytes) / Double(largestSize) : 0,
                            tint: category.tint
                        ) {
                            store.toggleSelection(categoryID: category.id, itemID: item.id)
                        }
                    }
                }
            }
        }
    }

    private var actionBar: some View {
        ActionBar {
            Menu {
                Button("Seleziona tutto") {
                    store.selectAll(categoryID: category.id, excludingRecent: true)
                }
                Button("Deseleziona tutto") {
                    store.selectNone(categoryID: category.id)
                }
            } label: {
                Label("Selezione", systemImage: "checklist")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Divider().frame(height: 18)

            VStack(alignment: .leading, spacing: 0) {
                Text("\(selected.count) selezionati")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(formatBytes(selectedSize))
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
            .disabled(selected.isEmpty)
        }
    }
}

private struct ItemRow: View {
    let item: CategoryItem
    let isSelected: Bool
    let fraction: Double
    let tint: Color
    let toggle: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            SelectionCheckbox(isOn: isSelected, action: toggle)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.displayName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if item.isRecent {
                        Text("in uso?")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                            .foregroundStyle(.orange)
                            .help("Modificato nelle ultime 6 ore: potrebbe essere ancora in uso")
                    }
                }
                GeometryReader { proxy in
                    Capsule()
                        .fill(tint.opacity(0.18))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(tint.opacity(0.7))
                                .frame(width: max(3, proxy.size.width * fraction))
                        }
                }
                .frame(height: 4)
            }

            if let modified = item.modifiedAt {
                Text(relativeDateFormatter.localizedString(for: modified, relativeTo: Date()))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(width: 90, alignment: .trailing)
            }

            Text(formatBytes(item.sizeBytes))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Image(systemName: "magnifyingglass.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(isHovering ? 1 : 0)
            .help("Mostra nel Finder")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? tint.opacity(0.08) : (isHovering ? Color.primary.opacity(0.04) : .clear))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
        .onHover { isHovering = $0 }
    }
}
