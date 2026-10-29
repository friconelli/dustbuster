import Foundation
import AppKit

enum DiskScanner {
    static func sizeOfPath(_ url: URL) -> Int64 {
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-sk", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return 0 }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let output = String(data: data, encoding: .utf8) else { return 0 }
        let kb = output.split(separator: "\t").first.flatMap { Int64($0) } ?? 0
        return kb * 1024
    }

    static func defaultItems(in directory: URL) -> [CategoryItem] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            return []
        }
        return entries.map { url in
            let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            return CategoryItem(url: url, sizeBytes: sizeOfPath(url), modifiedAt: modified, label: nil)
        }.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    static func totalSize(of items: [CategoryItem]) -> Int64 {
        items.reduce(0) { $0 + $1.sizeBytes }
    }

    static func runCommand(_ launchPath: String, _ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    static func trash(_ urls: [URL]) -> [URL] {
        var failed: [URL] = []
        for url in urls {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            } catch {
                failed.append(url)
            }
        }
        return failed
    }

    static func emptyTrash() {
        let script = "tell application \"Finder\" to empty trash"
        let appleScript = NSAppleScript(source: script)
        var errorDict: NSDictionary?
        appleScript?.executeAndReturnError(&errorDict)
    }
}
