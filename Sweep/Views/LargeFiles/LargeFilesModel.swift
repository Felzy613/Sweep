import SwiftUI

@MainActor
@Observable
final class LargeFilesModel {
    enum AgeFilter: Int, CaseIterable, Identifiable {
        case any = 0
        case month = 30
        case sixMonths = 180
        case year = 365

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .any: "Any Age"
            case .month: "Unused for 1 Month"
            case .sixMonths: "Unused for 6 Months"
            case .year: "Unused for 1 Year"
            }
        }
    }

    var phase: ModulePhase = .idle
    var progressText = ""
    var files: [LargeFile] = []
    var kindFilter: LargeFile.Kind?
    var ageFilter: AgeFilter = .any
    var report = CleanupReport()

    @ObservationIgnored private var task: Task<Void, Never>?

    var visibleFiles: [LargeFile] {
        files.filter { file in
            (kindFilter == nil || file.kind == kindFilter)
                && (ageFilter == .any || (file.lastUsed?.isOlder(thanDays: ageFilter.rawValue) ?? true))
        }
    }

    var selectedFiles: [LargeFile] { files.filter(\.isSelected) }
    var selectedSize: Int64 { selectedFiles.reduce(0) { $0 + $1.size } }

    func setSelected(_ selected: Bool, for id: URL) {
        if let index = files.firstIndex(where: { $0.id == id }) {
            files[index].isSelected = selected
        }
    }

    func size(of kind: LargeFile.Kind) -> Int64 {
        files.filter { $0.kind == kind }.reduce(0) { $0 + $1.size }
    }

    func startScan() {
        let minimum = Preferences.largeFileMinimumBytes
        phase = .scanning
        progressText = "Preparing…"
        report = CleanupReport()
        let reporter: @Sendable (String) -> Void = { [weak self] message in
            Task { @MainActor in self?.progressText = message }
        }
        task = Task {
            let result = await runInBackground {
                LargeFilesScanner(minimumSize: minimum, progress: ProgressThrottle(report: reporter)).scan()
            }
            guard !Task.isCancelled else { return }
            files = result
            phase = .results
        }
    }

    func cancel() {
        task?.cancel()
        phase = .idle
    }

    /// Large files are personal data, so they only ever go to the Trash.
    func removeSelected() {
        let items = selectedFiles.map(\.asCleanupItem)
        guard !items.isEmpty else { return }
        phase = .cleaning
        progressText = "Moving files to the Trash…"
        task = Task {
            let result = await runInBackground { Remover.remove(items, mode: .trash) }
            report = result
            let removed = Set(result.removed)
            files.removeAll { removed.contains($0.url) }
            phase = .finished
        }
    }

    func finish() {
        phase = files.isEmpty ? .idle : .results
    }
}
