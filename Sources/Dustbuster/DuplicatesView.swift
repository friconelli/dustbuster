import SwiftUI
import AppKit

struct DuplicatesView: View {
    @ObservedObject var store: CleanupStore
    @State private var showTrashConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if store.isScanningDuplicates {
                ProgressView("Scansione in corso… \(store.duplicateProgressText)")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.duplicateGroups.isEmpty {
                VStack {
                    Spacer()
                    Text("Nessun duplicato trovato. Avvia una scansione.")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(store.duplicateGroups) { group in
                        groupSection(group)
                    }
                }
            }

            footer
        }
        .navigationTitle("File duplicati")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cerca file identici (stesso contenuto) nelle cartelle selezionate. Per ogni gruppo viene tenuta selezionata per l'eliminazione ogni copia tranne la più vecchia.")
                .font(.callout)
                .foregroundStyle(.secondary)

            ForEach(store.duplicateFolders, id: \.self) { folder in
                HStack {
                    Image(systemName: "folder")
                    Text(folder.path)
                    Spacer()
                    Button {
                        store.removeDuplicateFolder(folder)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button("Aggiungi cartella…") {
                    addFolder()
                }
                Spacer()
                Button {
                    store.scanDuplicates()
                } label: {
                    Label("Scansiona", systemImage: "magnifyingglass")
                }
                .disabled(store.duplicateFolders.isEmpty || store.isScanningDuplicates)
            }
        }
        .padding()
    }

    private func groupSection(_ group: DuplicateGroup) -> some View {
        Section {
            ForEach(group.files) { file in
                HStack {
                    Toggle("", isOn: Binding(
                        get: { store.duplicateSelection.contains(file.id) },
                        set: { _ in store.toggleDuplicateSelection(file.id) }
                    ))
                    .labelsHidden()

                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.url.lastPathComponent)
                        Text(file.url.deletingLastPathComponent().path)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(formatBytes(file.sizeBytes))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        } header: {
            Text("Spazio recuperabile: \(formatBytes(group.wastedBytes))")
                .font(.caption.weight(.semibold))
        }
    }

    private var footer: some View {
        HStack {
            Text("\(store.duplicateSelection.count) file selezionati · \(formatBytes(store.duplicateSelectedWastedBytes))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(role: .destructive) {
                showTrashConfirm = true
            } label: {
                Label("Sposta duplicati selezionati nel Cestino", systemImage: "trash")
            }
            .disabled(store.duplicateSelection.isEmpty || !store.duplicatesKeepAtLeastOnePerGroup)
        }
        .padding()
        .alert("Spostare \(store.duplicateSelection.count) duplicati nel Cestino?", isPresented: $showTrashConfirm) {
            Button("Sposta nel Cestino", role: .destructive) {
                store.trashSelectedDuplicates()
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Per ogni gruppo rimane almeno una copia. Libererai circa \(formatBytes(store.duplicateSelectedWastedBytes)).")
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
