import SwiftUI

struct OverviewView: View {
    @ObservedObject var store: CleanupStore
    @Binding var selection: SidebarSelection?

    @State private var disk = DiskUsage.current()

    private var safeCategories: [CleanCategory] { sorted(store.categories.filter { $0.safety == .safe }) }
    private var cautionCategories: [CleanCategory] { sorted(store.categories.filter { $0.safety == .caution }) }

    private var safeTotal: Int64 {
        safeCategories.reduce(0) { $0 + store.sizeFor($1) }
    }

    private var cautionTotal: Int64 {
        cautionCategories.reduce(0) { $0 + store.sizeFor($1) }
    }

    private var isScanning: Bool { !store.scanningCategoryIDs.isEmpty }

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                hero

                section("Sicuri da eliminare", subtitle: "Vengono rigenerati automaticamente", categories: safeCategories)
                section("Da valutare", subtitle: "Controlla il contenuto prima di eliminare", categories: cautionCategories)

                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("Strumenti", subtitle: "Analisi su richiesta")
                    LazyVGrid(columns: columns, spacing: 14) {
                        toolCard(
                            title: "File duplicati",
                            detail: "Trova copie identiche in Download, Scrivania e Documenti",
                            symbol: "doc.on.doc",
                            tint: .teal,
                            target: .duplicates
                        )
                        toolCard(
                            title: "Docker",
                            detail: "Spazio occupato da immagini, container e volumi",
                            symbol: "cube.box",
                            tint: .blue,
                            target: .docker
                        )
                    }
                }
            }
            .padding(28)
        }
        .navigationTitle("Panoramica")
        .toolbar {
            ToolbarItem {
                Button {
                    store.scanAll()
                    disk = DiskUsage.current()
                } label: {
                    Label("Rianalizza tutto", systemImage: "arrow.clockwise")
                }
                .help("Rianalizza tutto")
                .disabled(isScanning)
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        HStack(spacing: 28) {
            DiskRing(usage: disk)
                .frame(width: 150, height: 150)

            VStack(alignment: .leading, spacing: 6) {
                Text(isScanning ? "Analisi in corso…" : "Puoi liberare in sicurezza")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.85))
                Text(formatBytes(safeTotal))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .animation(.default, value: safeTotal)
                Text("+ \(formatBytes(cautionTotal)) da valutare caso per caso")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.8))

                HStack(spacing: 10) {
                    Button {
                        if let biggest = safeCategories.first {
                            selection = .category(biggest.id)
                        }
                    } label: {
                        Label("Inizia dal più grande", systemImage: "arrow.right.circle.fill")
                    }
                    .prominentButton()
                    .tint(.white.opacity(0.25))
                    .disabled(safeTotal == 0)

                    if isScanning {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    }
                }
                .padding(.top, 8)
            }
            Spacer(minLength: 0)
        }
        .padding(28)
        .background(
            ZStack {
                Theme.brandGradient
                Image(systemName: "sparkles")
                    .font(.system(size: 160))
                    .foregroundStyle(.white.opacity(0.07))
                    .offset(x: 220, y: -30)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Theme.teal.opacity(0.3), radius: 16, y: 8)
    }

    // MARK: - Sections

    private func section(_ title: String, subtitle: String, categories: [CleanCategory]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(title, subtitle: subtitle)
            let visible = categories.filter { store.sizeFor($0) > 0 || store.scanningCategoryIDs.contains($0.id) }
            let clean = categories.filter { store.sizeFor($0) == 0 && !store.scanningCategoryIDs.contains($0.id) }
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(visible) { category in
                    CategoryCard(
                        category: category,
                        size: store.sizeFor(category),
                        isScanning: store.scanningCategoryIDs.contains(category.id)
                    ) {
                        selection = .category(category.id)
                    }
                }
            }
            if !clean.isEmpty {
                cleanRow(clean)
            }
        }
    }

    private func cleanRow(_ categories: [CleanCategory]) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
            Text("Già puliti:")
                .font(.callout.weight(.medium))
            FlowLayout(spacing: 6) {
                ForEach(categories) { category in
                    Button {
                        selection = .category(category.id)
                    } label: {
                        HStack(spacing: 5) {
                            IconTile(symbol: category.symbol, tint: category.tint, size: 16)
                            Text(category.title)
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.05), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.bold())
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func toolCard(title: String, detail: String, symbol: String, tint: Color, target: SidebarSelection) -> some View {
        HoverCard(action: { selection = target }) {
            HStack(spacing: 12) {
                IconTile(symbol: symbol, tint: tint, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func sorted(_ categories: [CleanCategory]) -> [CleanCategory] {
        categories.sorted { store.sizeFor($0) > store.sizeFor($1) }
    }
}

// MARK: - Components

private struct DiskRing: View {
    let usage: DiskUsage?

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.2), lineWidth: 14)
            Circle()
                .trim(from: 0, to: usage?.usedFraction ?? 0)
                .stroke(.white, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                if let usage {
                    Text(formatBytes(usage.available))
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .monospacedDigit()
                    Text("liberi su \(formatBytes(usage.total))")
                        .font(.caption2)
                        .opacity(0.8)
                } else {
                    Image(systemName: "internaldrive")
                        .font(.title)
                }
            }
            .foregroundStyle(.white)
        }
    }
}

private struct CategoryCard: View {
    let category: CleanCategory
    let size: Int64
    let isScanning: Bool
    let action: () -> Void

    var body: some View {
        HoverCard(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    IconTile(symbol: category.symbol, tint: category.tint, size: 36)
                    Spacer()
                    SafetyBadge(safety: category.safety)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if isScanning {
                        ProgressView()
                            .controlSize(.small)
                            .frame(height: 30)
                    } else {
                        Text(formatBytes(size))
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(size == 0 ? .secondary : .primary)
                    }
                }
            }
        }
    }
}

/// Clickable card that lifts slightly on hover.
struct HoverCard<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: Content

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Card { content }
                .scaleEffect(isHovering ? 1.015 : 1)
                .shadow(color: .black.opacity(isHovering ? 0.08 : 0), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
        }
    }
}
