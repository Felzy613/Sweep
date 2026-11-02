import Foundation

/// Finds the support files an app spreads across the Library folders.
/// Blocking; run it off the main actor.
struct AppFilesFinder: Sendable {
    /// Every installed bundle, used to recognise files shared with other apps.
    let installedBundles: [AppCatalog.BundleRecord]
    /// Team identifiers of the other uninstallable apps.
    let otherTeamIDs: Set<String>

    /// Library folders whose items are named after bundle identifiers.
    static let identifierFolders: [String] = [
        "Application Support", "Caches", "Containers", "Group Containers", "HTTPStorages", "WebKit",
        "Saved Application State", "Preferences", "Preferences/ByHost", "Cookies", "Logs",
        "Application Scripts", "LaunchAgents", "LaunchDaemons", "PrivilegedHelperTools",
    ]

    /// Library folders where apps also use their display name ("Application Support/Slack").
    private static let nameFolders = ["Application Support", "Caches", "Logs"]

    /// Folder names too generic to attribute to a single app.
    private static let genericNames: Set<String> = [
        "google", "microsoft", "adobe", "apple", "mozilla", "jetbrains", "crashreporter", "com.apple",
        "cache", "caches", "logs", "temp", "tmp", "data", "app", "helper", "updater", "plugins",
    ]

    static var libraryRoots: [URL] { [Home.library, URL(filePath: "/Library", directoryHint: .isDirectory)] }

    /// Folders whose entries are only meaningful as property lists. Anything else
    /// in them (license databases, lock files) is left alone.
    private static let plistOnlyFolders: Set<String> = ["Preferences", "Preferences/ByHost", "LaunchAgents", "LaunchDaemons"]

    /// Whether an entry of a Library folder looks like an app support item at all.
    static func isSupportItem(_ url: URL, in folder: String) -> Bool {
        !plistOnlyFolders.contains(folder) || url.pathExtension == "plist"
    }

    /// The app bundle (unless `includeBundle` is false) followed by its support files.
    func files(for app: InstalledApp, includeBundle: Bool = true) -> [CleanupItem] {
        let ownIdentifiers = Set(installedBundles.filter { $0.appPath == app.path }.map(\.identifier) + [app.bundleID])
        let owner = InstalledIdentifiers(ownIdentifiers)
        let others = InstalledIdentifiers(installedBundles.filter { $0.appPath != app.path }.map(\.identifier))
        let names = Set([app.name, app.url.deletingPathExtension().lastPathComponent].map { $0.lowercased() })
            .filter { $0.count >= 3 && !Self.genericNames.contains($0) }

        var found: [URL: String?] = [:]

        func consider(_ url: URL, note: String? = nil) {
            if found[url] == nil { found[url] = note }
        }

        for root in Self.libraryRoots {
            for folder in Self.identifierFolders {
                for url in FileScanner.children(of: root.appending(path: folder)) where Self.isSupportItem(url, in: folder) {
                    let name = url.lastPathComponent
                    if let identifier = BundleID.identifier(fromFileName: name) {
                        if owner.owns(identifier) && !others.owns(identifier) {
                            consider(url)
                        }
                    } else if folder == "Group Containers", let teamID = app.teamID,
                              name.hasPrefix(teamID + "."), !otherTeamIDs.contains(teamID) {
                        consider(url, note: "Shared container of the same developer")
                    }
                }
            }
            for folder in Self.nameFolders {
                for url in FileScanner.children(of: root.appending(path: folder))
                where names.contains(url.lastPathComponent.lowercased()) {
                    consider(url, note: "Matched by name")
                }
                // "Google Chrome" keeps its data in "Application Support/Google/Chrome".
                let words = app.name.split(separator: " ").map(String.init)
                if words.count >= 2 {
                    let nested = root.appending(path: folder).appending(path: words[0])
                        .appending(path: words.dropFirst().joined(separator: " "))
                    if FileScanner.exists(nested) { consider(nested, note: "Matched by name") }
                }
            }
        }

        // Launch agents and daemons that run something inside the app, whatever their label.
        for folder in LaunchJob.folders {
            for url in FileScanner.children(of: folder.url) where url.pathExtension == "plist" {
                if let job = LaunchJob(plistURL: url, domain: folder.domain), job.belongs(to: app.path) {
                    consider(url, note: "Starts \(job.executableName) automatically")
                }
            }
        }

        // Per-user cache and temp folders under /var/folders.
        for root in [FileScanner.darwinUserCacheDirectory, FileScanner.darwinUserTempDirectory].compactMap({ $0 }) {
            for url in FileScanner.children(of: root) {
                if let identifier = BundleID.identifier(fromFileName: url.lastPathComponent),
                   owner.owns(identifier), !others.owns(identifier) {
                    consider(url)
                }
            }
        }

        var items = found
            .map { url, note in makeItem(url, note: note) }
            .filter { SafetyPolicy.isSafe($0.url) }
            .sorted { $0.size > $1.size }
        if includeBundle {
            items.insert(makeItem(app.url, note: "Application"), at: 0)
        }
        return items
    }

    private func makeItem(_ url: URL, note: String?) -> CleanupItem {
        CleanupItem(
            url: url,
            size: FileScanner.size(of: url),
            isSelected: true,
            note: note ?? Self.describeLocation(of: url),
            requiresAdmin: !FileManager.default.isDeletableFile(atPath: url.path(percentEncoded: false))
        )
    }

    /// "Caches", "Preferences", "Containers"... from the item's parent folder.
    static func describeLocation(of url: URL) -> String {
        let parent = url.deletingLastPathComponent()
        if parent.lastPathComponent == "ByHost" { return "Preferences" }
        return parent.lastPathComponent
    }
}
