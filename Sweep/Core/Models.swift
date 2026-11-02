import Foundation

/// A single file or folder that a module proposes to remove.
struct CleanupItem: Identifiable, Hashable, Sendable {
    var id: URL { url }
    let url: URL
    let size: Int64
    var isSelected: Bool
    /// Short explanation shown under the name, e.g. "Last opened 2 years ago".
    var note: String?
    /// The item lives somewhere only root can write to.
    var requiresAdmin: Bool = false

    var name: String { url.lastPathComponent }
    var path: String { url.plainPath }
}

/// How removed items are disposed of.
enum RemovalMode: String, Sendable, CaseIterable, Codable, Identifiable {
    /// Recoverable from the Trash; frees space only once the Trash is emptied.
    case trash
    /// Deleted immediately; frees space right away.
    case permanent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trash: "Move to Trash"
        case .permanent: "Delete immediately"
        }
    }
}

/// Outcome of a removal pass.
struct CleanupReport: Sendable {
    struct Failure: Sendable, Identifiable, Hashable {
        var id: URL { url }
        let url: URL
        let reason: String
        /// Removing it again with administrator privileges would probably succeed.
        let needsAdmin: Bool
    }

    var removed: [URL] = []
    var freedBytes: Int64 = 0
    var failures: [Failure] = []

    var isEmpty: Bool { removed.isEmpty && failures.isEmpty }
    var adminRetryCandidates: [URL] { failures.filter(\.needsAdmin).map(\.url) }

    mutating func merge(_ other: CleanupReport) {
        removed += other.removed
        freedBytes += other.freedBytes
        failures += other.failures
    }
}

/// Lifecycle shared by every scan-then-clean module.
enum ModulePhase: Equatable, Sendable {
    case idle
    case scanning
    case results
    case cleaning
    case finished
}

extension Sequence where Element == CleanupItem {
    var totalSize: Int64 { reduce(0) { $0 + $1.size } }
    var selectedSize: Int64 { filter(\.isSelected).totalSize }
    var selectedCount: Int { filter(\.isSelected).count }
}
