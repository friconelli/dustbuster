import Foundation
import CryptoKit

struct DuplicateFile: Identifiable, Hashable {
    let url: URL
    let sizeBytes: Int64
    let modifiedAt: Date?

    var id: String { url.path }
}

struct DuplicateGroup: Identifiable {
    let id = UUID()
    let files: [DuplicateFile]

    var wastedBytes: Int64 {
        guard let first = files.first, files.count > 1 else { return 0 }
        return first.sizeBytes * Int64(files.count - 1)
    }
}

enum DuplicateFinder {
    static func scan(folders: [URL], progress: @escaping (String) -> Void) -> [DuplicateGroup] {
        let fm = FileManager.default
        var bySize: [Int64: [URL]] = [:]

        for folder in folders {
            guard let enumerator = fm.enumerator(
                at: folder,
                includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey, .isSymbolicLinkKey]),
                      values.isDirectory != true,
                      values.isSymbolicLink != true,
                      let size = values.fileSize, size > 4096
                else { continue }
                bySize[Int64(size), default: []].append(url)
            }
        }

        var groups: [DuplicateGroup] = []
        for (_, urls) in bySize where urls.count > 1 {
            var byHash: [String: [URL]] = [:]
            for url in urls {
                progress(url.lastPathComponent)
                guard let hash = hash(of: url) else { continue }
                byHash[hash, default: []].append(url)
            }
            for (_, matching) in byHash where matching.count > 1 {
                let files = matching.map { url -> DuplicateFile in
                    let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                    return DuplicateFile(
                        url: url,
                        sizeBytes: Int64(values?.fileSize ?? 0),
                        modifiedAt: values?.contentModificationDate
                    )
                }.sorted { ($0.modifiedAt ?? .distantFuture) < ($1.modifiedAt ?? .distantFuture) }
                groups.append(DuplicateGroup(files: files))
            }
        }

        return groups.sorted { $0.wastedBytes > $1.wastedBytes }
    }

    private static func hash(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let chunk = handle.readData(ofLength: 1024 * 1024)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
