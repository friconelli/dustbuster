import SwiftUI

struct OverviewView: View {
    @ObservedObject var store: CleanupStore

    private var safeCategories: [CleanCategory] { store.categories.filter { $0.safety == .safe } }
    private var cautionCategories: [CleanCategory] { store.categories.filter { $0.safety == .caution } }

    private var safeTotal: Int64 {
        safeCategories.reduce(0) { $0 + store.sizeFor($1) }
    }

    private var cautionTotal: Int64 {
        cautionCategories.reduce(0) { $0 + store.sizeFor($1) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Dustbuster")
                        .font(.largeTitle.bold())
                    Spacer()
                    Button {
                        store.scanAll()
                    } label: {
                        Label("Rianalizza tutto", systemImage: "arrow.clockwise")
                    }
                }

                HStack(spacing: 16) {
                    summaryCard(
                        title: "Liberabile in sicurezza",
                        value: formatBytes(safeTotal),
                        color: .green
                    )
                    summaryCard(
                        title: "Da valutare caso per caso",
                        value: formatBytes(cautionTotal),
                        color: .orange
                    )
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Sicuri da eliminare")
                        .font(.headline)
                    ForEach(safeCategories) { category in
                        recommendationRow(category)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Richiedono attenzione")
                        .font(.headline)
                    ForEach(cautionCategories) { category in
                        recommendationRow(category)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Docker")
                        .font(.headline)
                    Text("Le immagini, i container e i volumi Docker possono contenere dati di database o servizi che non siamo in grado di valutare in automatico. Vai nella sezione Docker per vedere lo spazio occupato e il comando consigliato per liberarlo manualmente.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
    }

    private func summaryCard(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title.bold())
                .foregroundStyle(color)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func recommendationRow(_ category: CleanCategory) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(category.title)
                    .font(.subheadline.weight(.medium))
                Text(category.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(formatBytes(store.sizeFor(category)))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
