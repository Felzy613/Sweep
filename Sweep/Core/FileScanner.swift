import Foundation
import os

/// Low-level file system helpers. Everything here is synchronous and meant to run
/// off the main actor (directory enumerators cannot be iterated from async code).
enum FileScanner {
    private static let sizeKeys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]

    /// Allocated size of a file, or the recursive size of a folder. Symlinks count as zero.
    static func size(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = sizeKeys.union([.isDirectoryKey, .isSymbolicLinkKey])
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        if values.isSymbolicLink == true { return 0 }
        guard values.isDirectory == true else { return allocatedSize(values) }

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(sizeKeys),
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        for case let child as URL in enumerator {
            if Task.isCancelled { break }
            if let childValues = try? child.resourceValues(forKeys: sizeKeys) {
                total += allocatedSize(childValues)
            }
        }
        return total
    }

    private static func allocatedSize(_ values: URLResourceValues) -> Int64 {
        Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
    }

    /// Immediate children of a folder, or an empty array if it is missing or unreadable.
    static func children(of url: URL, includeHidden: Bool = true) -> [URL] {
        let options: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .contentAccessDateKey]
        return (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: options)) ?? []
    }

    static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    static func modificationDate(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    /// Whether the current process can actually open the folder (TCC can block
    /// listing even when POSIX permissions allow it).
    static func isListable(_ url: URL) -> Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: url.path(percentEncoded: false))) != nil
    }

    // MARK: Per-user folders under /var/folders

    /// `getconf DARWIN_USER_CACHE_DIR`, e.g. /var/folders/xx/yyyy/C/
    static let darwinUserCacheDirectory: URL? = confstrURL(_CS_DARWIN_USER_CACHE_DIR)
    /// `getconf DARWIN_USER_TEMP_DIR`, e.g. /var/folders/xx/yyyy/T/
    static let darwinUserTempDirectory: URL? = confstrURL(_CS_DARWIN_USER_TEMP_DIR)

    private static func confstrURL(_ name: Int32) -> URL? {
        let length = confstr(name, nil, 0)
        guard length > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: length)
        guard confstr(name, &buffer, length) > 0 else { return nil }
        let path = buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        return URL(filePath: path, directoryHint: .isDirectory)
    }
}

/// Forwards progress messages at most once per `interval`, so a scan touching
/// hundreds of thousands of files doesn't flood the main actor.
final class ProgressThrottle: Sendable {
    private let interval: TimeInterval
    private let lastReport = OSAllocatedUnfairLock(initialState: Date.distantPast)
    private let report: @Sendable (String) -> Void

    init(interval: TimeInterval = 0.1, report: @escaping @Sendable (String) -> Void) {
        self.interval = interval
        self.report = report
    }

    func callAsFunction(_ message: @autoclosure () -> String, force: Bool = false) {
        let now = Date()
        let shouldReport = lastReport.withLock { last in
            guard force || now.timeIntervalSince(last) >= interval else { return false }
            last = now
            return true
        }
        if shouldReport { report(message()) }
    }
}
