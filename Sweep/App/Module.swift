import SwiftUI

/// The sections shown in the sidebar.
enum Module: String, CaseIterable, Identifiable, Hashable {
    case smartScan
    case systemJunk
    case largeFiles
    case uninstaller
    case leftovers
    case optimization
    case maintenance

    var id: String { rawValue }

    enum Group: String, CaseIterable {
        case overview = ""
        case cleanup = "Cleanup"
        case applications = "Applications"
        case speed = "Speed"
    }

    var group: Group {
        switch self {
        case .smartScan: .overview
        case .systemJunk, .largeFiles: .cleanup
        case .uninstaller, .leftovers: .applications
        case .optimization, .maintenance: .speed
        }
    }

    var title: String {
        switch self {
        case .smartScan: "Smart Scan"
        case .systemJunk: "System Junk"
        case .largeFiles: "Large & Old Files"
        case .uninstaller: "Uninstaller"
        case .leftovers: "Leftovers"
        case .optimization: "Optimization"
        case .maintenance: "Maintenance"
        }
    }

    var subtitle: String {
        switch self {
        case .smartScan: "Find junk, leftovers and things slowing your Mac down, all in one pass."
        case .systemJunk: "Clear caches, logs, broken files and developer junk to free up space."
        case .largeFiles: "Find big files in your home folder that you may no longer need."
        case .uninstaller: "Remove apps completely, along with every support file they created."
        case .leftovers: "Remove files left behind by apps that were deleted the usual way."
        case .optimization: "Control what starts with your Mac and quit apps that hog resources."
        case .maintenance: "Run routines that fix glitches and keep macOS running smoothly."
        }
    }

    var symbol: String {
        switch self {
        case .smartScan: "sparkles"
        case .systemJunk: "trash.circle"
        case .largeFiles: "doc.text.magnifyingglass"
        case .uninstaller: "xmark.app"
        case .leftovers: "archivebox"
        case .optimization: "gauge.with.dots.needle.67percent"
        case .maintenance: "wrench.and.screwdriver"
        }
    }

    var colors: [Color] {
        switch self {
        case .smartScan: [Color(red: 0.55, green: 0.33, blue: 0.95), Color(red: 0.93, green: 0.35, blue: 0.62)]
        case .systemJunk: [Color(red: 0.96, green: 0.38, blue: 0.42), Color(red: 0.98, green: 0.62, blue: 0.35)]
        case .largeFiles: [Color(red: 0.98, green: 0.58, blue: 0.20), Color(red: 0.98, green: 0.80, blue: 0.30)]
        case .uninstaller: [Color(red: 0.20, green: 0.50, blue: 0.98), Color(red: 0.35, green: 0.78, blue: 0.98)]
        case .leftovers: [Color(red: 0.10, green: 0.68, blue: 0.68), Color(red: 0.35, green: 0.85, blue: 0.70)]
        case .optimization: [Color(red: 0.20, green: 0.72, blue: 0.40), Color(red: 0.60, green: 0.86, blue: 0.35)]
        case .maintenance: [Color(red: 0.36, green: 0.40, blue: 0.95), Color(red: 0.55, green: 0.62, blue: 0.99)]
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var tint: Color { colors[0] }
}
