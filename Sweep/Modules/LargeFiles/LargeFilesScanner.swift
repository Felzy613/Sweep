import Foundation
import UniformTypeIdentifiers

/// A big file in the user's home folder.
struct LargeFile: Identifiable, Hashable, Sendable {
    enum Kind: String, CaseIterable, Sendable, Identifiable {
        case video, audio, image, archive, diskImage, document, other

        var id: String { rawValue }

        var title: String {
            switch self {
            case .video: "Movies"
            case .audio: "Music"
            case .image: "Pictures"
            case .archive: "Archives"
            case .diskImage: "Disk Images"
            case .document: "Documents"
            case .other: "Other"
            }
        }

        var symbol: String {
            switch self {
            case .video: "film"
            case .audio: "music.note"
            case .image: "photo"
            case .archive: "doc.zipper"
            case .diskImage: "externaldrive"
            case .document: "doc.richtext"
            case .other: "doc"
            }
        }

        init(url: URL) {
            guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else {
                self = .other
                return
            }
            if type.conforms(to: .audiovisualContent) && !type.conforms(to: .audio) { self = .video }
            else if type.conforms(to: .audio) { self = .audio }
            else if type.conforms(to: .image) { self = .image }
            else if type.conforms(to: .diskImage) || ["dmg", "iso", "img", "vmdk", "qcow2", "raw"].contains(url.pathExtension.lowercased()) { self = .diskImage }
            else if type.conforms(to: .archive) { self = .archive }
            else if type.conforms(to: .content) { self = .document }
            else { self = .other }
        }
    }

    var id: URL { url }
    let url: URL
    let size: Int64
    let modified: Date?
    let accessed: Date?
    let kind: Kind
    var isSelected = false

    /// The most recent sign of use.
    var lastUsed: Date? { [modified, accessed].compactMap { $0 }.max() }

    var asCleanupItem: CleanupItem {
        CleanupItem(url: url, size: size, isSelected: isSelected)
    }
}

/// Walks the home folder for big files, skipping ~/Library, hidden folders and
/// packages (apps, photo libraries). Blocking; run it off the main actor.
struct LargeFilesScanner: Sendable {
    var minimumSize: Int64 = 50_000_000
    var progress: ProgressThrottle?

    private static let keys: [URLResourceKey] = [
        .isRegularFileKey, .isPackageKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
        .contentModificationDateKey, .contentAccessDateKey,
    ]

    func scan() -> [LargeFile] {
        let skipped: Set<String> = [Home.library.plainPath, Home.path(".Trash").plainPath]
        guard let enumerator = FileManager.default.enumerator(
            at: Home.url,
            includingPropertiesForKeys: Self.keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return [] }

        var files: [LargeFile] = []
        var visited = 0
        for case let url as URL in enumerator {
            if Task.isCancelled { break }
            visited += 1
            if visited % 500 == 0 {
                progress?("Searched \(visited.formatted()) items · \(url.deletingLastPathComponent().abbreviatedPath)")
            }
            if skipped.contains(url.plainPath) {
                enumerator.skipDescendants()
                continue
            }
            guard let values = try? url.resourceValues(forKeys: Set(Self.keys)),
                  values.isRegularFile == true, values.isPackage != true
            else { continue }
            let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            guard size >= minimumSize else { continue }
            files.append(LargeFile(
                url: url,
                size: size,
                modified: values.contentModificationDate,
                accessed: values.contentAccessDate,
                kind: LargeFile.Kind(url: url)
            ))
        }
        return files.sorted { $0.size > $1.size }
    }
}
