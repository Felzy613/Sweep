import Foundation

/// Runs blocking work on a background thread. Cancelling the calling task
/// cancels the work too (scanners check `Task.isCancelled`).
func runInBackground<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
    let task = Task.detached(priority: .userInitiated, operation: work)
    return await withTaskCancellationHandler {
        await task.value
    } onCancel: {
        task.cancel()
    }
}

/// User settings shared by views (through @AppStorage) and models.
enum Preferences {
    static let junkRemovalModeKey = "junkRemovalMode"
    static let largeFileMinimumKey = "largeFileMinimumMB"

    /// How System Junk and Smart Scan dispose of junk. Apps and leftovers always go to the Trash.
    static var junkRemovalMode: RemovalMode {
        UserDefaults.standard.string(forKey: junkRemovalModeKey).flatMap(RemovalMode.init) ?? .permanent
    }

    static var largeFileMinimumBytes: Int64 {
        let megabytes = UserDefaults.standard.integer(forKey: largeFileMinimumKey)
        return Int64(megabytes > 0 ? megabytes : 50) * 1_000_000
    }
}
