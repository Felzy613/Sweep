import Foundation

/// Categories that need more than "list the folder's contents".
extension JunkScanner {
    func brokenPreferences() -> [CleanupItem] {
        let folders = [Home.library("Preferences"), Home.library("Preferences/ByHost")]
        return folders.flatMap { folder in
            FileScanner.children(of: folder)
                .filter { $0.pathExtension == "plist" && !isReadablePropertyList($0) }
                .map { makeItem($0, kind: .brokenPreferences, note: "Damaged preference file") }
        }
    }

    func brokenLoginItems() -> [CleanupItem] {
        LaunchJob.folders.flatMap { folder in
            FileScanner.children(of: folder.url).compactMap { url -> CleanupItem? in
                guard url.pathExtension == "plist",
                      let job = LaunchJob(plistURL: url, domain: folder.domain),
                      let executable = job.executablePath,
                      executable.hasPrefix("/"),
                      !executable.hasPrefix("/Volumes/"),   // may live on a disk that isn't connected
                      !FileScanner.exists(URL(filePath: executable))
                else { return nil }
                return makeItem(url, kind: .brokenLoginItems, note: "Points to missing \(executable)")
            }
        }
    }

    func trash() -> [CleanupItem] {
        var items = contents(of: Home.path(".Trash"), kind: .trash)
        let userTrash = ".Trashes/\(getuid())"
        for volume in FileScanner.children(of: URL(filePath: "/Volumes"), includeHidden: false) {
            // "Macintosh HD" is a symlink to "/"; its trash is ~/.Trash.
            guard (try? volume.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink != true else { continue }
            items += contents(of: volume.appending(path: userTrash), kind: .trash, note: "On \(volume.lastPathComponent)")
        }
        return items
    }

    func systemLogs() -> [CleanupItem] {
        var items = contents(of: URL(filePath: "/Library/Logs"), kind: .systemLogs, excluding: ["DiagnosticReports"])
        items += FileScanner.children(of: URL(filePath: "/private/var/log"))
            .filter { isRotatedLog($0.lastPathComponent) }
            .map { makeItem($0, kind: .systemLogs, note: "Rotated log archive") }
        return items
    }

    func deviceBackups() -> [CleanupItem] {
        FileScanner.children(of: Home.library("Application Support/MobileSync/Backup"), includeHidden: false).map { url in
            let info = NSDictionary(contentsOf: url.appending(path: "Info.plist"))
            let device = info?["Device Name"] as? String ?? "Unknown device"
            let note = (info?["Last Backup Date"] as? Date).map { "\(device), backed up \($0.relativeDescription)" } ?? device
            return makeItem(url, kind: .deviceBackups, note: note)
        }
    }

    func installers() -> [CleanupItem] {
        let extensions: Set<String> = ["dmg", "pkg", "mpkg", "xip"]
        return FileScanner.children(of: Home.path("Downloads"), includeHidden: false)
            .filter { extensions.contains($0.pathExtension.lowercased()) }
            .map { url in
                let note = FileScanner.modificationDate(of: url).map { "Downloaded \($0.relativeDescription)" }
                return makeItem(url, kind: .installers, note: note)
            }
    }

    // MARK: - Helpers

    /// Unreadable files count as fine: we can't tell, so we leave them alone.
    private func isReadablePropertyList(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url) else { return true }
        guard !data.isEmpty else { return false }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) != nil
    }

    /// "system.log.0.gz", "install.log.1", "wifi.log.bz2"
    private func isRotatedLog(_ name: String) -> Bool {
        let compressed = ["gz", "bz2", "xz", "zip"].contains((name as NSString).pathExtension.lowercased())
        return compressed || name.range(of: #"\.\d+$"#, options: .regularExpression) != nil
    }
}
