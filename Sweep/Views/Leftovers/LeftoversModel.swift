import SwiftUI

@MainActor
@Observable
final class LeftoversModel {
    var phase: ModulePhase = .idle
    var progressText = ""
    var groups: [LeftoverGroup] = []
    var report = CleanupReport()

    @ObservationIgnored private var task: Task<Void, Never>?

    var totalSize: Int64 { groups.reduce(0) { $0 + $1.totalSize } }
    var selectedItems: [CleanupItem] { groups.flatMap { $0.items.filter(\.isSelected) } }

    func startScan() {
        task = Task { await scan() }
    }

    func cancel() {
        task?.cancel()
        phase = .idle
    }

    func scan() async {
        phase = .scanning
        progressText = "Preparing…"
        report = CleanupReport()
        let reporter = progressReporter()
        let result = await runInBackground {
            LeftoversScanner(progress: ProgressThrottle(report: reporter)).scan()
        }
        guard !Task.isCancelled else { return }
        groups = result
        phase = .results
    }

    func startClean() {
        task = Task { await clean() }
    }

    /// Leftovers always go to the Trash so a wrong guess is easy to undo.
    func clean() async {
        let items = selectedItems
        guard !items.isEmpty else { return }
        phase = .cleaning
        progressText = "Moving leftovers to the Trash…"
        let reporter = progressReporter()
        let result = await runInBackground {
            Remover.remove(items, mode: .trash, progress: ProgressThrottle(report: reporter))
        }
        report = result
        dropRemovedItems(result)
        phase = .finished
    }

    func retryAsAdmin() {
        let urls = Set(report.adminRetryCandidates)
        let items = groups.flatMap(\.items).filter { urls.contains($0.url) }
        phase = .cleaning
        progressText = "Waiting for your administrator password…"
        task = Task {
            let adminReport = await Remover.removeAsAdmin(items)
            var merged = report
            merged.failures.removeAll { urls.contains($0.url) }
            merged.merge(adminReport)
            report = merged
            dropRemovedItems(adminReport)
            phase = .finished
        }
    }

    func finish() {
        phase = groups.isEmpty ? .idle : .results
    }

    func setAll(_ selected: Bool, in groupID: String) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        for item in groups[index].items.indices {
            groups[index].items[item].isSelected = selected
        }
    }

    private func dropRemovedItems(_ report: CleanupReport) {
        let removed = Set(report.removed)
        for index in groups.indices {
            groups[index].items.removeAll { removed.contains($0.url) }
        }
        groups.removeAll { $0.items.isEmpty }
    }

    private func progressReporter() -> @Sendable (String) -> Void {
        { [weak self] message in
            Task { @MainActor in self?.progressText = message }
        }
    }
}
