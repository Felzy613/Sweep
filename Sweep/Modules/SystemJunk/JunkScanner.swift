import Foundation

/// Finds junk files. Blocking; run it off the main actor.
struct JunkScanner: Sendable {
    var progress: ProgressThrottle?

    /// Caches that macOS services depend on; deleting them causes re-syncs or sign-outs.
    private static let protectedCaches: Set<String> = [
        "cloudkit", "com.apple.bird", "com.apple.homekit", "familycircle", "com.apple.containermanagerd",
        "com.apple.akd", "com.apple.nsurlsessiond", "com.apple.safari.safebrowsing", "com.apple.homed",
        "com.apple.passd", "com.apple.trustedpeershelper", "com.apple.screentimeagent", ".ds_store",
    ]

    func scan(kinds: [JunkKind] = JunkKind.allCases) -> [JunkCategory] {
        let running = InstalledIdentifiers(AppCatalog.runningBundleIdentifiers())
        var categories: [JunkCategory] = []
        for kind in kinds {
            if Task.isCancelled { break }
            progress?("Scanning \(kind.title)…", force: true)
            let keepsEmptyItems = kind == .brokenPreferences || kind == .brokenLoginItems
            let items = items(for: kind, runningApps: running)
                .filter { $0.size > 0 || keepsEmptyItems }
                .sorted { $0.size > $1.size }
            if !items.isEmpty {
                categories.append(JunkCategory(kind: kind, items: items))
            }
        }
        return categories
    }

    private func items(for kind: JunkKind, runningApps: InstalledIdentifiers) -> [CleanupItem] {
        switch kind {
        case .userCaches:
            userCaches(runningApps: runningApps)
        case .userLogs:
            contents(of: Home.library("Logs"), kind: kind, excluding: ["DiagnosticReports"])
        case .crashReports:
            contents(of: Home.library("Logs/DiagnosticReports"), kind: kind)
                + contents(of: URL(filePath: "/Library/Logs/DiagnosticReports"), kind: kind)
        case .temporaryFiles:
            temporaryFiles()
        case .xcodeJunk:
            xcodeJunk()
        case .developerCaches:
            developerCaches()
        case .brokenPreferences:
            brokenPreferences()
        case .brokenLoginItems:
            brokenLoginItems()
        case .mailAttachments:
            contents(of: Home.library("Containers/com.apple.mail/Data/Library/Mail Downloads"), kind: kind)
        case .deviceUpdates:
            ["iPhone", "iPad", "iPod"].flatMap { contents(of: Home.library("iTunes/\($0) Software Updates"), kind: kind) }
        case .trash:
            trash()
        case .systemCaches:
            contents(of: URL(filePath: "/Library/Caches"), kind: kind, skipApple: true)
        case .systemLogs:
            systemLogs()
        case .deviceBackups:
            deviceBackups()
        case .installers:
            installers()
        }
    }

    // MARK: - Building items

    /// One item per child of `folder`.
    func contents(
        of folder: URL,
        kind: JunkKind,
        excluding excluded: Set<String> = [],
        skipApple: Bool = false,
        selected: Bool? = nil,
        note: String? = nil
    ) -> [CleanupItem] {
        FileScanner.children(of: folder).compactMap { url in
            let name = url.lastPathComponent
            if excluded.contains(name) || name == ".DS_Store" || name == ".localized" { return nil }
            if skipApple && name.lowercased().hasPrefix("com.apple.") { return nil }
            return makeItem(url, kind: kind, selected: selected, note: note)
        }
    }

    func makeItem(_ url: URL, kind: JunkKind, selected: Bool? = nil, note: String? = nil) -> CleanupItem {
        progress?("Scanning \(url.abbreviatedPath)")
        return CleanupItem(
            url: url,
            size: FileScanner.size(of: url),
            isSelected: selected ?? kind.selectedByDefault,
            note: note,
            requiresAdmin: !FileManager.default.isDeletableFile(atPath: url.path(percentEncoded: false))
        )
    }

    // MARK: - Categories

    private func userCaches(runningApps: InstalledIdentifiers) -> [CleanupItem] {
        FileScanner.children(of: Home.library("Caches")).compactMap { url in
            let name = url.lastPathComponent
            guard !Self.protectedCaches.contains(name.lowercased()) else { return nil }
            if let identifier = BundleID.identifier(fromFileName: name), runningApps.owns(identifier) {
                return makeItem(url, kind: .userCaches, selected: false, note: "In use by a running app. Quit it to clean this cache.")
            }
            return makeItem(url, kind: .userCaches)
        }
    }

    private func temporaryFiles() -> [CleanupItem] {
        let roots = [FileScanner.darwinUserTempDirectory, URL(filePath: "/private/tmp")].compactMap { $0 }
        var items: [CleanupItem] = []
        for root in roots {
            for url in FileScanner.children(of: root) {
                let name = url.lastPathComponent
                // Sockets and folders that live services keep open (ssh-agent, tmux, atomic saves).
                if name.hasPrefix("com.apple.") || name.hasPrefix("tmux-") || name == "TemporaryItems"
                    || name.hasSuffix(".sock") || name.hasSuffix(".socket") || name.hasPrefix(".") {
                    continue
                }
                guard isOwnedByCurrentUser(url),
                      let modified = FileScanner.modificationDate(of: url), modified.isOlder(thanDays: 3)
                else { continue }
                items.append(makeItem(url, kind: .temporaryFiles, note: "Last modified \(modified.relativeDescription)"))
            }
        }
        return items
    }

    private func xcodeJunk() -> [CleanupItem] {
        let developer = Home.library("Developer")
        var items = contents(of: developer.appending(path: "Xcode/DerivedData"), kind: .xcodeJunk, note: "Derived data")
        for platform in ["iOS", "watchOS", "tvOS", "visionOS", "macOS"] {
            items += contents(of: developer.appending(path: "Xcode/\(platform) DeviceSupport"), kind: .xcodeJunk, note: "\(platform) device support")
        }
        items += contents(of: developer.appending(path: "Xcode/Archives"), kind: .xcodeJunk, selected: false, note: "Archives. Keep them if you need their dSYMs.")
        items += contents(of: developer.appending(path: "CoreSimulator/Caches"), kind: .xcodeJunk, note: "Simulator cache")
        items += contents(of: developer.appending(path: "Xcode/UserData/Previews"), kind: .xcodeJunk, note: "SwiftUI previews")
        return items
    }

    private func developerCaches() -> [CleanupItem] {
        let safeToClear = [
            ".npm/_cacache", ".npm/_logs", ".yarn/berry/cache", ".gradle/caches", ".cargo/registry/cache",
            ".cargo/registry/src", ".bun/install/cache", ".android/cache", ".pub-cache/hosted",
        ]
        let shared = [".gradle/wrapper/dists", ".m2/repository", ".cocoapods/repos", ".nuget/packages", "Library/pnpm/store"]

        var items = safeToClear.map(Home.path).filter(FileScanner.exists).map {
            makeItem($0, kind: .developerCaches)
        }
        items += shared.map(Home.path).filter(FileScanner.exists).map {
            makeItem($0, kind: .developerCaches, selected: false, note: "Shared by your projects. Downloaded again when needed.")
        }
        items += contents(of: Home.path(".cache"), kind: .developerCaches, selected: false, note: "Tool cache in ~/.cache")
        return items
    }

    private func isOwnedByCurrentUser(_ url: URL) -> Bool {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        return (attributes?[.ownerAccountID] as? NSNumber)?.uint32Value == getuid()
    }
}
