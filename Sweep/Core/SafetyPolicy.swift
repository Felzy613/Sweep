import Foundation

/// Last line of defence before anything is removed. Every deletion path in the
/// app calls `validate(_:)`, so a bug in a scanner can never take out the
/// system, a whole Library folder or the user's documents.
enum SafetyPolicy {
    enum Violation: LocalizedError, Equatable {
        case relativePath
        case protectedLocation(String)
        case outsideAllowedArea(String)

        var errorDescription: String? {
            switch self {
            case .relativePath: "Refusing to remove a relative path."
            case .protectedLocation(let path): "\(path) is a protected location."
            case .outsideAllowedArea(let path): "\(path) is outside the folders Sweep is allowed to clean."
            }
        }
    }

    static func isSafe(_ url: URL) -> Bool {
        (try? validate(url)) != nil
    }

    static func validate(_ url: URL) throws {
        guard url.isFileURL, url.path(percentEncoded: false).hasPrefix("/") else {
            throw Violation.relativePath
        }
        let path = canonicalPath(of: url)
        let home = canonicalHome

        // Never a protected folder itself, nor any folder that contains one.
        for protected in protectedFolders where path == protected || protected.hasPrefix(path + "/") {
            throw Violation.protectedLocation(path)
        }
        // Never anything inside a protected tree.
        for tree in protectedTrees where path == tree || path.hasPrefix(tree + "/") {
            throw Violation.protectedLocation(path)
        }

        let parent = (path as NSString).deletingLastPathComponent
        // Whole category folders such as ~/Library/Caches or /Library/LaunchDaemons.
        if parent == home + "/Library" || parent == "/Library" {
            throw Violation.protectedLocation(path)
        }
        // Top-level folders in the home folder (~/Projects, ~/.ssh, ...). Single files are fine.
        if parent == home && FileScanner.isDirectory(URL(filePath: path)) {
            throw Violation.protectedLocation(path)
        }

        // Applications folders: only app bundles may go.
        for appsFolder in ["/Applications", home + "/Applications"] where path.hasPrefix(appsFolder + "/") {
            if !path.split(separator: "/").contains(where: { $0.hasSuffix(".app") }) {
                throw Violation.protectedLocation(path)
            }
        }

        let allowedRoots = [home, "/Library", "/Applications", "/private/var/folders", "/private/tmp", "/private/var/log", "/Users/Shared"]
        let insideAllowedRoot = allowedRoots.contains { path.hasPrefix($0 + "/") }
        let insideVolumeTrash = path.hasPrefix("/Volumes/") && path.contains("/.Trashes/")
        guard insideAllowedRoot || insideVolumeTrash else {
            throw Violation.outsideAllowedArea(path)
        }
    }

    // MARK: - Paths

    /// Standardized path with symlinks in the parent resolved (so /tmp/x becomes
    /// /private/tmp/x) but the item itself left alone: removing a symlink only
    /// removes the link.
    static func canonicalPath(of url: URL) -> String {
        let standardized = url.standardizedFileURL
        let name = standardized.lastPathComponent
        let parent = realPath(standardized.deletingLastPathComponent().plainPath)
        if name == "/" || name.isEmpty { return parent }
        return parent == "/" ? "/" + name : parent + "/" + name
    }

    private static var canonicalHome: String {
        realPath(Home.url.plainPath)
    }

    /// Resolves symlinks with realpath(3). Unlike `URL.resolvingSymlinksInPath()`
    /// it keeps the /private prefix (/tmp → /private/tmp). Paths that don't
    /// exist fall back to mapping the well-known /private symlinks by hand.
    private static func realPath(_ path: String) -> String {
        if let resolved = realpath(path, nil) {
            defer { free(resolved) }
            return String(cString: resolved)
        }
        for link in ["/tmp", "/var", "/etc"] where path == link || path.hasPrefix(link + "/") {
            return "/private" + path
        }
        return path
    }

    /// Folders that must survive, along with every folder above them.
    private static var protectedFolders: [String] {
        let home = canonicalHome
        var folders = [
            "/", "/Applications", "/Library", "/System", "/Users", "/Users/Shared", "/Volumes",
            "/private", "/private/var", "/private/tmp", "/private/var/folders", "/private/var/log",
            home, home + "/Library", home + "/Applications", home + "/.Trash",
        ]
        folders += ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Public"].map { home + "/" + $0 }
        for dir in [FileScanner.darwinUserCacheDirectory, FileScanner.darwinUserTempDirectory].compactMap({ $0 }) {
            folders.append(canonicalPath(of: dir))
        }
        return folders
    }

    /// Trees whose contents are never touched.
    private static var protectedTrees: [String] {
        let home = canonicalHome
        return [
            "/System", "/usr", "/bin", "/sbin", "/cores", "/opt",
            "/private/etc", "/private/var/db", "/private/var/root",
            "/Library/Apple", "/Library/Keychains", "/Library/Frameworks",
            home + "/Library/Keychains",
            home + "/Library/Mobile Documents",   // iCloud Drive
            home + "/Library/CloudStorage",       // Dropbox, OneDrive, Google Drive
            home + "/Library/Mail",
            home + "/Library/Messages",
            home + "/Library/Photos",
        ]
    }
}
