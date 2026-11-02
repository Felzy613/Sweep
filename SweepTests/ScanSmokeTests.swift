import Foundation
import Testing
@testable import Sweep

/// Read-only scans against the real machine, printing summaries. Nothing is removed.
/// Off by default; run with `TEST_RUNNER_SWEEP_SMOKE=1 xcodebuild test ...`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["SWEEP_SMOKE"] != nil))
struct ScanSmokeTests {
    @Test func junkScan() {
        let categories = JunkScanner().scan()
        for category in categories {
            print("JUNK \(category.kind.title): \(category.items.count) items, \(category.totalSize.formattedBytes), selected \(category.selectedSize.formattedBytes)")
            for item in category.items.prefix(3) { print("    \(item.url.abbreviatedPath) \(item.size.formattedBytes) sel=\(item.isSelected) admin=\(item.requiresAdmin) \(item.note ?? "")") }
        }
        let unsafe = categories.flatMap(\.items).filter { !SafetyPolicy.isSafe($0.url) }
        for item in unsafe { print("UNSAFE \(item.path): \((try? SafetyPolicy.validate(item.url)).map { _ in "" } ?? "")") }
        #expect(unsafe.isEmpty)
    }

    @Test func leftoversScan() {
        let groups = LeftoversScanner().scan()
        print("LEFTOVERS \(groups.count) groups, \(groups.reduce(0) { $0 + $1.totalSize }.formattedBytes)")
        for group in groups.prefix(40) {
            print("  \(group.identifier) review=\(group.needsReview) \(group.totalSize.formattedBytes) :: " + group.items.map { AppFilesFinder.describeLocation(of: $0.url) }.joined(separator: ","))
        }
    }

    @Test func uninstallerFiles() {
        let apps = AppCatalog.uninstallableApps()
        let bundles = AppCatalog.installedBundles()
        print("APPS \(apps.count) uninstallable, \(bundles.count) bundle records")
        let finder = AppFilesFinder(installedBundles: bundles, otherTeamIDs: Set(apps.compactMap(\.teamID)))
        for name in ["Slack", "Google Chrome", "Visual Studio Code", "Discord", "Spotify", "Zoom", "Docker", "KiCad"] {
            guard let app = apps.first(where: { $0.name.localizedCaseInsensitiveContains(name) }) else { continue }
            let files = finder.files(for: app)
            print("APP \(app.name) [\(app.bundleID)] team=\(app.teamID ?? "-") -> \(files.count) items")
            for item in files { print("    \(item.url.abbreviatedPath) \(item.size.formattedBytes) \(item.note ?? "")") }
        }
    }
}

extension ScanSmokeTests {
    @Test func launchItems() {
        for item in LaunchItemsManager.load().prefix(8) {
            print("LAUNCH \(item.job.label) enabled=\(item.isEnabled) domain=\(item.job.domain)")
        }
    }
}
