import AppKit
import Security

/// An application bundle the user can uninstall or reset.
struct InstalledApp: Identifiable, Hashable, Sendable {
    var id: URL { url }
    let url: URL
    let name: String
    let bundleID: String
    let version: String?
    let teamID: String?
    let isAppStore: Bool
    let lastUsed: Date?
    var size: Int64?

    var isApple: Bool { bundleID.lowercased().hasPrefix("com.apple.") }
    var path: String { url.plainPath }
}

/// Finds installed applications and the identifiers that belong to them.
enum AppCatalog {
    static var applicationFolders: [URL] {
        [URL(filePath: "/Applications", directoryHint: .isDirectory), Home.path("Applications")]
    }

    /// Apps in /Applications and ~/Applications (two levels deep, so vendor
    /// folders like "Microsoft Office" are included) that are safe to offer for
    /// removal. Blocking.
    static func uninstallableApps() -> [InstalledApp] {
        var urls: [URL] = []
        for folder in applicationFolders {
            collectApps(in: folder, depth: 0, maxDepth: 2, into: &urls)
        }
        return urls.compactMap(makeApp).filter { app in
            // Apple's own apps are only removable when they came from the App Store
            // (GarageBand, iMovie, Pages...). Safari & co. are part of macOS.
            !app.isApple || app.isAppStore
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func makeApp(at url: URL) -> InstalledApp? {
        guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { return nil }
        let info = bundle.infoDictionary ?? [:]
        let fallbackName = url.deletingPathExtension().lastPathComponent
        let name = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? fallbackName
        return InstalledApp(
            url: url,
            name: name.isEmpty ? fallbackName : name,
            bundleID: bundleID,
            version: info["CFBundleShortVersionString"] as? String,
            teamID: teamIdentifier(of: url),
            isAppStore: FileScanner.exists(url.appending(path: "Contents/_MASReceipt/receipt")),
            lastUsed: lastUsedDate(of: url),
            size: nil
        )
    }

    private static func collectApps(in folder: URL, depth: Int, maxDepth: Int, into result: inout [URL]) {
        for child in FileScanner.children(of: folder, includeHidden: false) {
            if child.pathExtension == "app" {
                result.append(child)
            } else if depth < maxDepth, FileScanner.isDirectory(child) {
                collectApps(in: child, depth: depth + 1, maxDepth: maxDepth, into: &result)
            }
        }
    }

    /// Developer team that signed the app, e.g. "UBF8T346G9" for Microsoft.
    static func teamIdentifier(of url: URL) -> String? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dictionary = info as? [String: Any]
        else { return nil }
        return dictionary[kSecCodeInfoTeamIdentifier as String] as? String
    }

    private static func lastUsedDate(of url: URL) -> Date? {
        NSMetadataItem(url: url)?.value(forAttribute: "kMDItemLastUsedDate") as? Date
    }

    // MARK: - Installed identifiers (for leftover detection)

    /// Folders inside an app bundle where helpers, login items and extensions live.
    private static let embeddedBundleFolders = [
        "Contents/Library/LoginItems", "Contents/Library/LaunchServices", "Contents/Library/SystemExtensions",
        "Contents/PlugIns", "Contents/XPCServices", "Contents/Frameworks", "Contents/Helpers", "Contents/MacOS",
    ]
    private static let bundleExtensions: Set<String> = ["app", "appex", "xpc", "systemextension", "bundle", "plugin"]

    /// Every bundle identifier that belongs to something installed: all apps
    /// Spotlight knows about, the standard app folders, helpers embedded in those
    /// apps, and running processes. Blocking.
    static func installedIdentifiers(progress: ProgressThrottle? = nil) -> InstalledIdentifiers {
        var identifiers = Set(installedBundles(progress: progress).map(\.identifier))
        identifiers.formUnion(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return InstalledIdentifiers(identifiers)
    }

    /// A bundle identifier and the top-level app it ships in.
    struct BundleRecord: Hashable, Sendable {
        let identifier: String
        /// Path of the outermost .app containing the bundle (or the bundle itself).
        let appPath: String
    }

    /// Every app Spotlight or the standard folders know about, plus the helpers,
    /// login items and extensions embedded in them. Blocking.
    static func installedBundles(progress: ProgressThrottle? = nil) -> [BundleRecord] {
        var appURLs = Set<URL>()
        if let result = try? Shell.runSync("/usr/bin/mdfind", ["kMDItemContentType == 'com.apple.application-bundle'"]) {
            for line in result.output.split(separator: "\n") where !line.contains("/.Trash") {
                appURLs.insert(URL(filePath: String(line), directoryHint: .isDirectory))
            }
        }
        var folderApps: [URL] = []
        for folder in applicationFolders + [URL(filePath: "/System/Applications"), URL(filePath: "/Library/Application Support")] {
            collectApps(in: folder, depth: 0, maxDepth: 3, into: &folderApps)
        }
        appURLs.formUnion(folderApps)

        var records = Set<BundleRecord>()
        for url in appURLs {
            if Task.isCancelled { break }
            progress?("Indexing \(url.lastPathComponent)…")
            let appPath = outermostAppPath(of: url)
            if let id = Bundle(url: url)?.bundleIdentifier {
                records.insert(BundleRecord(identifier: id, appPath: appPath))
            }
            for folder in embeddedBundleFolders {
                for child in FileScanner.children(of: url.appending(path: folder), includeHidden: false)
                where bundleExtensions.contains(child.pathExtension.lowercased()) {
                    if let id = Bundle(url: child)?.bundleIdentifier {
                        records.insert(BundleRecord(identifier: id, appPath: appPath))
                    }
                }
            }
        }

        // Things installed without an app: preference panes, audio plug-ins, screen savers...
        for root in [Home.library, URL(filePath: "/Library")] {
            for folder in pluginFolders {
                for child in FileScanner.children(of: root.appending(path: folder), includeHidden: false) {
                    if let id = Bundle(url: child)?.bundleIdentifier {
                        records.insert(BundleRecord(identifier: id, appPath: child.plainPath))
                    }
                }
            }
        }
        return Array(records)
    }

    private static let pluginFolders = [
        "PreferencePanes", "Internet Plug-Ins", "Audio/Plug-Ins/Components", "Audio/Plug-Ins/VST",
        "Audio/Plug-Ins/VST3", "Audio/Plug-Ins/HAL", "QuickLook", "Screen Savers", "Spotlight",
        "Input Methods", "Services", "Frameworks", "Extensions", "SystemExtensions", "Widgets",
    ]

    /// "/Applications/Slack.app/Contents/Frameworks/Slack Helper.app" → "/Applications/Slack.app"
    static func outermostAppPath(of url: URL) -> String {
        var path = ""
        for component in url.path(percentEncoded: false).split(separator: "/") {
            path += "/" + component
            if component.hasSuffix(".app") { return path }
        }
        return url.plainPath
    }

    /// Bundle identifiers of apps that are running right now.
    static func runningBundleIdentifiers() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier?.lowercased() })
    }
}
