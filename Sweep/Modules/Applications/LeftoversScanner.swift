import Foundation

/// Files left behind by one app that is no longer installed.
struct LeftoverGroup: Identifiable, Sendable {
    let identifier: String
    var items: [CleanupItem]
    /// Something from the same developer is still installed, or the files were
    /// touched recently, so the group needs a human look before removal.
    let needsReview: Bool
    let reviewReason: String?

    var id: String { identifier.lowercased() }

    /// "com.tinyspeck.slackmacgap" → "Tinyspeck"
    var vendorName: String {
        let parts = identifier.split(separator: ".")
        return parts.count > 1 ? parts[1].capitalized : identifier
    }

    var totalSize: Int64 { items.totalSize }
}

/// Finds support files whose owning app is gone. Blocking; run it off the main actor.
struct LeftoversScanner: Sendable {
    var progress: ProgressThrottle?

    /// Identifiers that belong to macOS or to shared runtimes that have no app bundle.
    private static let ignoredPrefixes = [
        "com.apple.", "apple.", "com.oracle.java", "net.java.", "com.sun.", "org.python.", "org.swift.", "org.sparkle-project.",
        "com.microsoft.autoupdate", "com.google.keystone", "org.mozilla.updater",
    ]

    func scan() -> [LeftoverGroup] {
        progress?("Indexing installed apps…", force: true)
        let installed = AppCatalog.installedIdentifiers(progress: progress)

        var itemsByID: [String: [CleanupItem]] = [:]
        var displayID: [String: String] = [:]

        var folders: [(url: URL, name: String)] = AppFilesFinder.libraryRoots.flatMap { root in
            AppFilesFinder.identifierFolders.map { (root.appending(path: $0), $0) }
        }
        folders += [FileScanner.darwinUserCacheDirectory, FileScanner.darwinUserTempDirectory].compactMap { $0 }.map { ($0, "") }

        for folder in folders {
            progress?("Checking \(folder.url.abbreviatedPath)…", force: true)
            for url in FileScanner.children(of: folder.url) where AppFilesFinder.isSupportItem(url, in: folder.name) {
                if Task.isCancelled { return [] }
                guard let identifier = BundleID.identifier(fromFileName: url.lastPathComponent),
                      !isIgnored(identifier),
                      !installed.owns(identifier),
                      !isLiveLaunchJob(url, in: folder.name),
                      SafetyPolicy.isSafe(url)
                else { continue }
                progress?("Measuring \(url.abbreviatedPath)")
                let key = identifier.lowercased()
                displayID[key] = displayID[key] ?? identifier
                itemsByID[key, default: []].append(CleanupItem(
                    url: url,
                    size: FileScanner.size(of: url),
                    isSelected: true,
                    note: AppFilesFinder.describeLocation(of: url),
                    requiresAdmin: !FileManager.default.isDeletableFile(atPath: url.path(percentEncoded: false))
                ))
            }
        }

        return itemsByID.map { key, items in
            let identifier = displayID[key] ?? key
            let reason = reviewReason(for: identifier, items: items, installed: installed)
            let reviewed = items
                .map { item in
                    var item = item
                    item.isSelected = reason == nil
                    return item
                }
                .sorted { $0.size > $1.size }
            return LeftoverGroup(identifier: identifier, items: reviewed, needsReview: reason != nil, reviewReason: reason)
        }
        .sorted { $0.totalSize > $1.totalSize }
    }

    /// A launch job whose program still exists outside PrivilegedHelperTools belongs
    /// to software installed without an app bundle (file systems, drivers, CLIs).
    private func isLiveLaunchJob(_ url: URL, in folder: String) -> Bool {
        guard folder == "LaunchAgents" || folder == "LaunchDaemons",
              let job = LaunchJob(plistURL: url, domain: .globalDaemon),
              let executable = job.executablePath
        else { return false }
        return !executable.hasPrefix("/Library/PrivilegedHelperTools/") && FileScanner.exists(URL(filePath: executable))
    }

    private func isIgnored(_ identifier: String) -> Bool {
        let lowered = identifier.lowercased()
        return Self.ignoredPrefixes.contains { lowered.hasPrefix($0) }
    }

    private func reviewReason(for identifier: String, items: [CleanupItem], installed: InstalledIdentifiers) -> String? {
        if installed.sharesVendor(with: identifier) {
            return "Another app from this developer is installed and may share these files."
        }
        let recentlyUsed = items.contains { item in
            FileScanner.modificationDate(of: item.url).map { !$0.isOlder(thanDays: 7) } ?? false
        }
        if recentlyUsed {
            return "Changed in the last week, so something may still use it."
        }
        return nil
    }
}
