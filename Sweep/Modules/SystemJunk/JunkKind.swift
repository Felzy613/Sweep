import Foundation

/// The kinds of junk System Junk looks for, in display order.
enum JunkKind: String, CaseIterable, Identifiable, Sendable {
    case userCaches
    case userLogs
    case crashReports
    case temporaryFiles
    case xcodeJunk
    case developerCaches
    case brokenPreferences
    case brokenLoginItems
    case mailAttachments
    case deviceUpdates
    case trash
    case systemCaches
    case systemLogs
    case deviceBackups
    case installers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .userCaches: "User Cache Files"
        case .userLogs: "User Log Files"
        case .crashReports: "Crash Reports"
        case .temporaryFiles: "Temporary Files"
        case .xcodeJunk: "Xcode Junk"
        case .developerCaches: "Developer Tool Caches"
        case .brokenPreferences: "Broken Preferences"
        case .brokenLoginItems: "Broken Login Items"
        case .mailAttachments: "Mail Attachments"
        case .deviceUpdates: "iOS Software Updates"
        case .trash: "Trash"
        case .systemCaches: "System Cache Files"
        case .systemLogs: "System Log Files"
        case .deviceBackups: "iOS Device Backups"
        case .installers: "Installer Files in Downloads"
        }
    }

    var detail: String {
        switch self {
        case .userCaches: "Data apps store to speed things up. Apps rebuild it as needed. Caches of apps that are running are skipped."
        case .userLogs: "Activity logs written by apps. Useful only when troubleshooting."
        case .crashReports: "Diagnostic reports created when apps crash or hang."
        case .temporaryFiles: "Temporary items older than three days that apps left behind."
        case .xcodeJunk: "Build products, device support files and simulator caches. Xcode recreates them on demand. Archives hold the dSYMs needed to symbolicate crashes, so they're not selected."
        case .developerCaches: "Package manager caches (npm, Yarn, Gradle, Cargo, Bun...). They are re-downloaded when needed."
        case .brokenPreferences: "Preference files that are damaged and can no longer be read."
        case .brokenLoginItems: "Launch agents that point to programs which no longer exist."
        case .mailAttachments: "Copies of attachments you opened in Mail. The originals stay in your mailbox."
        case .deviceUpdates: "iPhone and iPad firmware files downloaded by Finder."
        case .trash: "Items in your Trash. Emptying it is permanent."
        case .systemCaches: "Caches of third-party system components. Requires your administrator password."
        case .systemLogs: "Logs written by system services and installers. Requires your administrator password."
        case .deviceBackups: "Local backups of your iPhone or iPad. Remove only backups you no longer need."
        case .installers: "Disk images and installer packages in your Downloads folder."
        }
    }

    var symbol: String {
        switch self {
        case .userCaches: "internaldrive"
        case .userLogs: "doc.text"
        case .crashReports: "exclamationmark.triangle"
        case .temporaryFiles: "clock.arrow.circlepath"
        case .xcodeJunk: "hammer"
        case .developerCaches: "shippingbox"
        case .brokenPreferences: "gearshape.2"
        case .brokenLoginItems: "person.badge.clock"
        case .mailAttachments: "paperclip"
        case .deviceUpdates: "iphone.and.arrow.forward"
        case .trash: "trash"
        case .systemCaches: "server.rack"
        case .systemLogs: "list.bullet.rectangle"
        case .deviceBackups: "externaldrive.badge.timemachine"
        case .installers: "arrow.down.app"
        }
    }

    /// Whether the category's items start out selected.
    var selectedByDefault: Bool {
        switch self {
        case .systemCaches, .systemLogs, .deviceBackups, .installers: false
        default: true
        }
    }

    /// Trash contents can only be deleted, never moved to the Trash again.
    var alwaysPermanent: Bool { self == .trash }

    /// Needs Full Disk Access to be scanned.
    var needsFullDiskAccess: Bool {
        switch self {
        case .mailAttachments, .deviceBackups, .trash: true
        default: false
        }
    }
}

/// Scan results for one kind of junk.
struct JunkCategory: Identifiable, Sendable {
    let kind: JunkKind
    var items: [CleanupItem]

    var id: JunkKind { kind }
    var totalSize: Int64 { items.totalSize }
    var selectedSize: Int64 { items.selectedSize }
}
