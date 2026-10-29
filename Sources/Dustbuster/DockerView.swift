import SwiftUI
import AppKit

struct DockerView: View {
    @ObservedObject var store: CleanupStore
    @State private var copied = false

    private let pruneCommand = "docker system prune"

    /// Rows of `docker system df`: TYPE, TOTAL, ACTIVE, SIZE, RECLAIMABLE.
    private var rows: [[String]] {
        guard let output = store.dockerOutput else { return [] }
        return output
            .split(separator: "\n")
            .dropFirst()
            .map { line in
                line.components(separatedBy: "  ")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
            .filter { $0.count >= 5 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    symbol: "cube.box",
                    tint: .blue,
                    title: "Docker",
                    subtitle: "Immagini, container e volumi possono contenere dati di applicazioni o database che Dustbuster non può valutare in sicurezza. Qui vedi lo spazio occupato e decidi tu da terminale."
                ) {
                    EmptyView()
                }

                if store.dockerOutput == nil {
                    Card {
                        EmptyStateView(
                            symbol: "cube.transparent",
                            title: "Docker non disponibile",
                            message: "Docker non è installato, non è in esecuzione, oppure non è stato trovato nel PATH."
                        )
                        .padding(.vertical, 20)
                    }
                } else if rows.isEmpty {
                    Card {
                        Text(store.dockerOutput ?? "")
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 14)], spacing: 14) {
                        ForEach(rows, id: \.self) { row in
                            dockerCard(row)
                        }
                    }
                }

                commandCard
            }
            .padding(28)
        }
        .navigationTitle("Docker")
        .toolbar {
            ToolbarItem {
                Button {
                    store.refreshDockerInfo()
                } label: {
                    Label("Aggiorna", systemImage: "arrow.clockwise")
                }
                .help("Aggiorna")
            }
        }
    }

    private func dockerCard(_ row: [String]) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    IconTile(symbol: symbol(for: row[0]), tint: .blue, size: 32)
                    Text(row[0])
                        .font(.headline)
                    Spacer()
                }
                Text(row[3])
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .monospacedDigit()
                HStack {
                    Text("\(row[1]) totali · \(row[2]) attivi")
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Text("Recuperabili: \(row[4])")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
            }
        }
    }

    private var commandCard: some View {
        Card {
            HStack(spacing: 12) {
                Image(systemName: "terminal")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Per liberare spazio manualmente")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(pruneCommand)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                Spacer()
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(pruneCommand, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Label(copied ? "Copiato" : "Copia", systemImage: copied ? "checkmark" : "doc.on.clipboard")
                }
                .secondaryButton()
            }
        }
    }

    private func symbol(for type: String) -> String {
        switch type.lowercased() {
        case let t where t.contains("image"): return "square.stack.3d.up"
        case let t where t.contains("container"): return "shippingbox"
        case let t where t.contains("volume"): return "externaldrive"
        case let t where t.contains("cache"): return "bolt.horizontal"
        default: return "cube"
        }
    }
}
