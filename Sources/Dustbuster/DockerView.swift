import SwiftUI
import AppKit

struct DockerView: View {
    @ObservedObject var store: CleanupStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Docker")
                .font(.title2.bold())

            Text("Immagini, container e volumi Docker possono contenere dati di applicazioni o database che questa app non può valutare in sicurezza. Per questo motivo Dustbuster non elimina nulla qui automaticamente: ti mostra lo spazio occupato e ti lascia decidere da terminale.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if let output = store.dockerOutput {
                ScrollView {
                    Text(output)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Text("Docker non è installato, non è in esecuzione, oppure non è stato trovato nel PATH.")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button {
                    store.refreshDockerInfo()
                } label: {
                    Label("Aggiorna", systemImage: "arrow.clockwise")
                }
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString("docker system prune", forType: .string)
                } label: {
                    Label("Copia comando `docker system prune`", systemImage: "doc.on.clipboard")
                }
            }

            Spacer()
        }
        .padding(24)
        .navigationTitle("Docker")
    }
}
