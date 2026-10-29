import Foundation

@MainActor
final class CleanupStore: ObservableObject {
    @Published var categories: [CleanCategory] = CategoryCatalog.all()
    @Published var items: [String: [CategoryItem]] = [:]
    @Published var scanningCategoryIDs: Set<String> = []
    @Published var selectedItemIDs: [String: Set<String>] = [:]

    @Published var duplicateGroups: [DuplicateGroup] = []
    @Published var duplicateSelection: Set<String> = []
    @Published var isScanningDuplicates = false
    @Published var duplicateProgressText = ""
    @Published var duplicateFolders: [URL] = CleanupStore.defaultDuplicateFolders()

    @Published var dockerOutput: String?

    func sizeFor(_ category: CleanCategory) -> Int64 {
        DiskScanner.totalSize(of: items[category.id] ?? [])
    }

    func scan(_ category: CleanCategory) {
        guard !scanningCategoryIDs.contains(category.id) else { return }
        scanningCategoryIDs.insert(category.id)

        Task.detached(priority: .userInitiated) {
            var found: [CategoryItem] = []
            for path in category.resolvePaths() {
                if let lister = category.customItemLister {
                    found += lister(path)
                } else {
                    found += DiskScanner.defaultItems(in: path)
                }
            }
            let sorted = found.sorted { $0.sizeBytes > $1.sizeBytes }
            await MainActor.run {
                self.items[category.id] = sorted
                self.scanningCategoryIDs.remove(category.id)
            }
        }
    }

    func scanAll() {
        for category in categories {
            scan(category)
        }
    }

    func toggleSelection(categoryID: String, itemID: String) {
        var set = selectedItemIDs[categoryID] ?? []
        if set.contains(itemID) {
            set.remove(itemID)
        } else {
            set.insert(itemID)
        }
        selectedItemIDs[categoryID] = set
    }

    func selectAll(categoryID: String, excludingRecent: Bool) {
        let all = items[categoryID] ?? []
        let eligible = excludingRecent ? all.filter { !$0.isRecent } : all
        selectedItemIDs[categoryID] = Set(eligible.map(\.id))
    }

    func selectNone(categoryID: String) {
        selectedItemIDs[categoryID] = []
    }

    func trashSelected(categoryID: String) {
        let selected = selectedItemIDs[categoryID] ?? []
        guard !selected.isEmpty else { return }
        let urls = (items[categoryID] ?? []).filter { selected.contains($0.id) }.map(\.url)
        DiskScanner.trash(urls)
        if let category = categories.first(where: { $0.id == categoryID }) {
            scan(category)
        }
        selectedItemIDs[categoryID] = []
    }

    func emptySystemTrash() {
        DiskScanner.emptyTrash()
    }

    // MARK: - Duplicates

    static func defaultDuplicateFolders() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("Downloads"),
            home.appendingPathComponent("Desktop"),
            home.appendingPathComponent("Documents"),
        ].filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func addDuplicateFolder(_ url: URL) {
        guard !duplicateFolders.contains(url) else { return }
        duplicateFolders.append(url)
    }

    func removeDuplicateFolder(_ url: URL) {
        duplicateFolders.removeAll { $0 == url }
    }

    func scanDuplicates() {
        guard !isScanningDuplicates else { return }
        isScanningDuplicates = true
        duplicateGroups = []
        duplicateSelection = []
        let folders = duplicateFolders

        Task.detached(priority: .userInitiated) {
            let groups = DuplicateFinder.scan(folders: folders) { name in
                Task { @MainActor in
                    self.duplicateProgressText = name
                }
            }
            let preselected = Set(groups.flatMap { $0.files.dropFirst().map(\.id) })
            await MainActor.run {
                self.duplicateGroups = groups
                self.duplicateSelection = preselected
                self.isScanningDuplicates = false
                self.duplicateProgressText = ""
            }
        }
    }

    func toggleDuplicateSelection(_ fileID: String) {
        if duplicateSelection.contains(fileID) {
            duplicateSelection.remove(fileID)
        } else {
            duplicateSelection.insert(fileID)
        }
    }

    var duplicatesKeepAtLeastOnePerGroup: Bool {
        duplicateGroups.allSatisfy { group in
            group.files.contains { !duplicateSelection.contains($0.id) }
        }
    }

    var duplicateSelectedWastedBytes: Int64 {
        duplicateGroups.flatMap(\.files)
            .filter { duplicateSelection.contains($0.id) }
            .reduce(0) { $0 + $1.sizeBytes }
    }

    func trashSelectedDuplicates() {
        let urls = duplicateGroups.flatMap(\.files)
            .filter { duplicateSelection.contains($0.id) }
            .map(\.url)
        DiskScanner.trash(urls)
        scanDuplicates()
    }

    // MARK: - Docker

    func refreshDockerInfo() {
        Task.detached(priority: .utility) {
            let output = DockerInfo.systemDF()
            await MainActor.run {
                self.dockerOutput = output
            }
        }
    }
}
