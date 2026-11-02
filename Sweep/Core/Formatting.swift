import Foundation

extension Int64 {
    /// "1.2 GB", using the same decimal units Finder shows.
    var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

extension Int {
    var formattedBytes: String { Int64(self).formattedBytes }
}

extension Date {
    /// "3 days ago", "2 years ago".
    var relativeDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: .now)
    }

    func isOlder(thanDays days: Int) -> Bool {
        timeIntervalSinceNow < -Double(days) * 86_400
    }
}

extension URL {
    /// File system path without a trailing slash (directory URLs keep one in `path()`).
    var plainPath: String {
        var result = path(percentEncoded: false)
        while result.count > 1 && result.hasSuffix("/") { result.removeLast() }
        return result
    }

    /// Path with the home folder abbreviated to "~".
    var abbreviatedPath: String {
        (plainPath as NSString).abbreviatingWithTildeInPath
    }
}

/// Builds paths relative to the user's home folder.
enum Home {
    static let url = FileManager.default.homeDirectoryForCurrentUser
    static var library: URL { url.appending(path: "Library", directoryHint: .isDirectory) }

    static func path(_ relative: String) -> URL {
        url.appending(path: relative)
    }

    static func library(_ relative: String) -> URL {
        library.appending(path: relative)
    }
}
