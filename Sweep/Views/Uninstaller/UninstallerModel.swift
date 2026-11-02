import AppKit
import SwiftUI

@MainActor
@Observable
final class UninstallerModel {
    enum Sort: String, CaseIterable, Identifiable {
        case name = "Name"
        case size = "Size"
        case lastUsed = "Last Used"
        var id: String { rawValue }
    }

    var apps: [InstalledApp] = []
    var isLoading = false
    var searchText = ""
    var sort: Sort = .name
    private(set) var selectedAppID: URL?
    var files: [CleanupItem] = []
    var isLoadingFiles = false

    var phase: ModulePhase = .idle
    var progressText = ""
    var report = CleanupReport()

    @ObservationIgnored private var installedBundles: [AppCatalog.BundleRecord] = []
    @ObservationIgnored private var filesTask: Task<Void, Never>?
    @ObservationIgnored private var sizesTask: Task<Void, Never>?

    var selectedApp: InstalledApp? { apps.first { $0.id == selectedAppID } }

    var visibleApps: [InstalledApp] {
        let filtered = searchText.isEmpty ? apps : apps.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) || $0.bundleID.localizedCaseInsensitiveContains(searchText)
        }
        switch sort {
        case .name: return filtered
        case .size: return filtered.sorted { ($0.size ?? 0) > ($1.size ?? 0) }
        case .lastUsed: return filtered.sorted { ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast) }
        }
    }

    func loadIfNeeded() async {
        guard apps.isEmpty, !isLoading else { return }
        await load()
    }

    func load() async {
        isLoading = true
        let (apps, bundles) = await runInBackground {
            (AppCatalog.uninstallableApps(), AppCatalog.installedBundles())
        }
        self.apps = apps
        installedBundles = bundles
        isLoading = false
        measureSizes()
    }

    /// Fills in app sizes one by one in the background; big apps take a while.
    private func measureSizes() {
        sizesTask?.cancel()
        let urls = apps.filter { $0.size == nil }.map(\.url)
        sizesTask = Task {
            for url in urls {
                let size = await runInBackground { FileScanner.size(of: url) }
                guard !Task.isCancelled else { return }
                if let index = apps.firstIndex(where: { $0.url == url }) {
                    apps[index].size = size
                }
            }
        }
    }

    func select(_ appID: URL?) {
        guard appID != selectedAppID else { return }
        selectedAppID = appID
        files = []
        filesTask?.cancel()
        guard let app = selectedApp else { return }

        isLoadingFiles = true
        let bundles = installedBundles
        let otherTeams = Set(apps.filter { $0.id != app.id }.compactMap(\.teamID))
        filesTask = Task {
            let found = await runInBackground {
                AppFilesFinder(installedBundles: bundles, otherTeamIDs: otherTeams).files(for: app)
            }
            guard !Task.isCancelled else { return }
            files = found
            isLoadingFiles = false
        }
    }

    /// Moves the app and its selected files to the Trash. With `resetOnly` the
    /// app stays and only its data goes, returning it to a fresh state.
    func remove(resetOnly: Bool) {
        guard let app = selectedApp else { return }
        let items = files.filter { $0.isSelected && !(resetOnly && $0.url == app.url) }
        guard !items.isEmpty else { return }

        phase = .cleaning
        progressText = "Quitting \(app.name)…"
        Task {
            guard await quitIfRunning(app) else {
                report = CleanupReport(failures: [.init(url: app.url, reason: "\(app.name) is still running. Quit it and try again.", needsAdmin: false)])
                phase = .finished
                return
            }
            await stopLaunchAgents(in: items)
            progressText = "Moving files to the Trash…"
            let result = await runInBackground { Remover.remove(items, mode: .trash) }
            apply(result, for: app)
        }
    }

    func retryAsAdmin() {
        guard let app = selectedApp else { return }
        let urls = Set(report.adminRetryCandidates)
        let items = files.filter { urls.contains($0.url) }
        phase = .cleaning
        progressText = "Waiting for your administrator password…"
        Task {
            let adminReport = await Remover.removeAsAdmin(items)
            var merged = report
            merged.failures.removeAll { urls.contains($0.url) }
            merged.merge(adminReport)
            apply(merged, for: app)
        }
    }

    func finish() {
        phase = .idle
    }

    private func apply(_ result: CleanupReport, for app: InstalledApp) {
        report = result
        let removed = Set(result.removed)
        if removed.contains(app.url) {
            apps.removeAll { $0.id == app.id }
            selectedAppID = nil
            files = []
        } else {
            files.removeAll { removed.contains($0.url) }
        }
        phase = .finished
    }

    /// Asks the app to quit and waits up to ten seconds. Returns false if it's still running.
    private func quitIfRunning(_ app: InstalledApp) async -> Bool {
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == app.bundleID || $0.bundleURL?.plainPath == app.path
        }
        guard !running.isEmpty else { return true }
        running.forEach { $0.terminate() }
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(500))
            if running.allSatisfy(\.isTerminated) { return true }
        }
        return false
    }

    /// Unloads the user's own launch agents before their plists are removed.
    private func stopLaunchAgents(in items: [CleanupItem]) async {
        let agentsFolder = Home.library("LaunchAgents").plainPath
        for item in items where item.url.pathExtension == "plist" && item.path.hasPrefix(agentsFolder + "/") {
            _ = try? await Shell.run("/bin/launchctl", ["bootout", "gui/\(getuid())", item.path])
        }
    }
}
