import Foundation

/// Keeps project files safe: anything that lives in a git repository (or in a dependency
/// folder rebuilt from one) is never offered for cleanup.
enum GitGuard {
    /// Folders that hold project dependencies or build output; copies in there are not real duplicates.
    static let projectFolderNames: Set<String> = [
        "node_modules", "Pods", "vendor", ".build", "DerivedData", "build", "dist", ".venv", "venv", "__pycache__",
    ]

    /// True if `url` has a `.git` entry (folder or file, as in worktrees and submodules).
    static func isRepoRoot(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path)
    }

    /// True if `url` or any of its parents is a repository root.
    static func isInsideRepo(_ url: URL) -> Bool {
        var current = url.standardizedFileURL
        while current.pathComponents.count > 1 {
            if isRepoRoot(current) { return true }
            current = current.deletingLastPathComponent()
        }
        return false
    }

    /// True if a repository sits at `url` or up to `depth` levels below it.
    static func containsRepo(_ url: URL, depth: Int = 3) -> Bool {
        if isRepoRoot(url) { return true }
        guard depth > 0,
              let children = try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [])
        else { return false }
        for child in children where (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            if child.lastPathComponent == ".git" { return true }
            if containsRepo(child, depth: depth - 1) { return true }
        }
        return false
    }
}
