import Foundation

enum DockerInfo {
    static func systemDF() -> String? {
        DiskScanner.runCommand("/usr/bin/env", ["docker", "system", "df"])
    }
}
