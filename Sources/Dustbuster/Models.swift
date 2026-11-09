import Foundation

enum SafetyLevel: String {
    case safe = "Sicuro"
    case caution = "Attenzione"
    case info = "Informativo"

    var tint: String {
        switch self {
        case .safe: return "green"
        case .caution: return "orange"
        case .info: return "gray"
        }
    }
}

enum CategoryGroup {
    case cleanup
    case ai
    case privacy
}

struct CategoryItem: Identifiable, Hashable {
    let url: URL
    let sizeBytes: Int64
    let modifiedAt: Date?
    let label: String?
    /// A git repository sits inside this item: never preselected, flagged in the list.
    var containsRepo = false

    var id: String { url.path }

    var displayName: String { label ?? url.lastPathComponent }

    var isRecent: Bool {
        guard let modifiedAt else { return false }
        return Date().timeIntervalSince(modifiedAt) < 6 * 3600
    }
}

struct CleanCategory: Identifiable {
    let id: String
    let title: String
    let explanation: String
    let safety: SafetyLevel
    let resolvePaths: () -> [URL]
    var group: CategoryGroup = .cleanup
    var customItemLister: ((URL) -> [CategoryItem])? = nil
}
