import SwiftUI

struct CategoryDetailView: View {
    @ObservedObject var store: CleanupStore
    let category: CleanCategory

    @State private var showTrashConfirm = false

    private var items: [CategoryItem] { store.items[category.id] ?? [] }
    private var selected: Set<String> { store.selectedItemIDs[category.id] ?? [] }
    private var selectedSize: Int64 {
        items.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.sizeBytes }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if store.scanningCategoryIDs.contains(category.id) {
                ProgressView("Analisi in corso…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                ContentUnavailableLikeView(text: "Nessun elemento trovato")
            } else {
                List {
                    ForEach(items) { item in
                        itemRow(item)
                    }
                }
            }

            footer
        }
        .navigationTitle(category.title)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(category.safety.rawValue)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(color(for: category.safety).opacity(0.15))
                    .foregroundStyle(color(for: category.safety))
                    .clipShape(Capsule())
                Spacer()
                Button {
                    store.scan(category)
                } label: {
                    Label("Aggiorna", systemImage: "arrow.clockwise")
                }
            }
            Text(category.explanation)
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Button("Seleziona tutto") {
                    store.selectAll(categoryID: category.id, excludingRecent: true)
                }
                Button("Deseleziona tutto") {
                    store.selectNone(categoryID: category.id)
                }
                Spacer()
                Text("Totale: \(formatBytes(DiskScanner.totalSize(of: items)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private func itemRow(_ item: CategoryItem) -> some View {
        HStack {
            Toggle("", isOn: Binding(
                get: { selected.contains(item.id) },
                set: { _ in store.toggleSelection(categoryID: category.id, itemID: item.id) }
            ))
            .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .lineLimit(1)
                if item.isRecent {
                    Text("sessione/elemento recente, potrebbe essere in uso")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            Text(formatBytes(item.sizeBytes))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var footer: some View {
        HStack {
            Text("\(selected.count) selezionati · \(formatBytes(selectedSize))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(role: .destructive) {
                showTrashConfirm = true
            } label: {
                Label("Sposta nel Cestino", systemImage: "trash")
            }
            .disabled(selected.isEmpty)
        }
        .padding()
        .alert("Spostare \(selected.count) elementi nel Cestino?", isPresented: $showTrashConfirm) {
            Button("Sposta nel Cestino", role: .destructive) {
                store.trashSelected(categoryID: category.id)
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Libererai circa \(formatBytes(selectedSize)). Potrai recuperarli dal Cestino finché non lo svuoti.")
        }
    }

    private func color(for safety: SafetyLevel) -> Color {
        switch safety {
        case .safe: return .green
        case .caution: return .orange
        case .info: return .gray
        }
    }
}

private struct ContentUnavailableLikeView: View {
    let text: String
    var body: some View {
        VStack {
            Spacer()
            Text(text)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
