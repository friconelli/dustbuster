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

struct CategoryItem: Identifiable, Hashable {
    let url: URL
    let sizeBytes: Int64
    let modifiedAt: Date?
    let label: String?

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
    var customItemLister: ((URL) -> [CategoryItem])? = nil
}
