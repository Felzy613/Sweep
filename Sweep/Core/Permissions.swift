import AppKit

/// Full Disk Access and System Settings shortcuts.
enum Permissions {
    /// True when Sweep has Full Disk Access. Without it macOS hides the Trash,
    /// Mail downloads, other apps' containers and Safari data from us.
    static var hasFullDiskAccess: Bool {
        // TCC.db is readable only by processes with Full Disk Access.
        let descriptor = open("/Library/Application Support/com.apple.TCC/TCC.db", O_RDONLY)
        if descriptor >= 0 {
            close(descriptor)
            return true
        }
        return FileScanner.isListable(Home.library("Safari"))
    }

    @MainActor
    static func openFullDiskAccessSettings() {
        openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
    }

    @MainActor
    static func openLoginItemsSettings() {
        openSettings("x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
    }

    @MainActor
    private static func openSettings(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}
