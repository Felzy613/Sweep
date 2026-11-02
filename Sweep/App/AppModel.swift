import SwiftUI

/// Shared state for the whole app: navigation and one model per module.
@MainActor
@Observable
final class AppModel {
    var selection: Module? = .smartScan
    var hasFullDiskAccess = Permissions.hasFullDiskAccess

    let junk = JunkModel()
    let leftovers = LeftoversModel()
    let largeFiles = LargeFilesModel()
    let uninstaller = UninstallerModel()
    let optimization = OptimizationModel()
    let maintenance = MaintenanceModel()
    let smartScan: SmartScanModel

    init() {
        smartScan = SmartScanModel(junk: junk, leftovers: leftovers, optimization: optimization)
    }

    func refreshPermissions() {
        hasFullDiskAccess = Permissions.hasFullDiskAccess
    }

    /// Short sidebar badge, e.g. the amount of junk found.
    func badge(for module: Module) -> String? {
        switch module {
        case .systemJunk where junk.phase == .results && junk.totalSize > 0:
            junk.totalSize.formattedBytes
        case .leftovers where leftovers.phase == .results && !leftovers.groups.isEmpty:
            leftovers.totalSize.formattedBytes
        case .largeFiles where largeFiles.phase == .results && !largeFiles.files.isEmpty:
            "\(largeFiles.files.count)"
        default:
            nil
        }
    }
}
