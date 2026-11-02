import SwiftUI

@MainActor
@Observable
final class JunkModel {
    var phase: ModulePhase = .idle
    var progressText = ""
    var categories: [JunkCategory] = []
    var selectedKind: JunkKind?
    var report = CleanupReport()
    var lastRemovalMode: RemovalMode = .permanent

    @ObservationIgnored private var task: Task<Void, Never>?

    var totalSize: Int64 { categories.reduce(0) { $0 + $1.totalSize } }
    var selectedSize: Int64 { categories.reduce(0) { $0 + $1.selectedSize } }
    var selectedCount: Int { categories.reduce(0) { $0 + $1.items.selectedCount } }

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
            JunkScanner(progress: ProgressThrottle(report: reporter)).scan()
        }
        guard !Task.isCancelled else { return }
        categories = result
        selectedKind = result.first?.kind
        phase = .results
    }

    func startClean() {
        task = Task { await clean() }
    }

    func clean() async {
        let mode = Preferences.junkRemovalMode
        let regular = categories.filter { !$0.kind.alwaysPermanent }.flatMap { $0.items.filter(\.isSelected) }
        let trash = categories.filter { $0.kind.alwaysPermanent }.flatMap { $0.items.filter(\.isSelected) }
        guard !regular.isEmpty || !trash.isEmpty else { return }

        phase = .cleaning
        progressText = "Removing…"
        lastRemovalMode = mode
        let reporter = progressReporter()
        let result = await runInBackground {
            let throttle = ProgressThrottle(report: reporter)
            var report = Remover.remove(regular, mode: mode, progress: throttle)
            report.merge(Remover.remove(trash, mode: .permanent, progress: throttle))
            return report
        }
        report = result
        dropRemovedItems(result)
        phase = .finished
    }

    func retryAsAdmin() {
        let urls = Set(report.adminRetryCandidates)
        let items = categories.flatMap(\.items).filter { urls.contains($0.url) }
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
        phase = categories.isEmpty ? .idle : .results
    }

    func setAll(_ selected: Bool, in kind: JunkKind) {
        guard let index = categories.firstIndex(where: { $0.kind == kind }) else { return }
        for item in categories[index].items.indices {
            categories[index].items[item].isSelected = selected
        }
    }

    private func dropRemovedItems(_ report: CleanupReport) {
        let removed = Set(report.removed)
        for index in categories.indices {
            categories[index].items.removeAll { removed.contains($0.url) }
        }
        categories.removeAll { $0.items.isEmpty }
        if let selectedKind, !categories.contains(where: { $0.kind == selectedKind }) {
            self.selectedKind = categories.first?.kind
        }
    }

    private func progressReporter() -> @Sendable (String) -> Void {
        { [weak self] message in
            Task { @MainActor in self?.progressText = message }
        }
    }
}
