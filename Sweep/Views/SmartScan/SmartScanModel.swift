import SwiftUI

/// Runs the junk, leftover and launch agent scans in one go and cleans the
/// items each module selects by default.
@MainActor
@Observable
final class SmartScanModel {
    var phase: ModulePhase = .idle
    var step = ""
    var report = CleanupReport()
    var removalMode: RemovalMode = .permanent

    private let junk: JunkModel
    private let leftovers: LeftoversModel
    private let optimization: OptimizationModel
    @ObservationIgnored private var task: Task<Void, Never>?

    init(junk: JunkModel, leftovers: LeftoversModel, optimization: OptimizationModel) {
        self.junk = junk
        self.leftovers = leftovers
        self.optimization = optimization
    }

    var progressText: String {
        leftovers.phase == .scanning || leftovers.phase == .cleaning ? leftovers.progressText : junk.progressText
    }

    var junkSize: Int64 { junk.selectedSize }
    var leftoversSize: Int64 { leftovers.selectedItems.totalSize }
    var totalSize: Int64 { junkSize + leftoversSize }
    var enabledAgentCount: Int { optimization.launchItems.filter(\.isEnabled).count }
    var memory: MemoryStats? { optimization.memory }

    func scan() {
        phase = .scanning
        report = CleanupReport()
        task = Task {
            step = "Scanning for system junk…"
            await junk.scan()
            guard !Task.isCancelled else { return }
            step = "Looking for leftovers of removed apps…"
            await leftovers.scan()
            guard !Task.isCancelled else { return }
            step = "Checking what starts with your Mac…"
            await optimization.loadAgents()
            optimization.memory = MemoryStats.current()
            phase = .results
        }
    }

    func cancel() {
        task?.cancel()
        junk.cancel()
        leftovers.cancel()
        phase = .idle
    }

    func clean() {
        phase = .cleaning
        removalMode = Preferences.junkRemovalMode
        task = Task {
            var combined = CleanupReport()
            if junk.selectedCount > 0 {
                step = "Removing junk…"
                await junk.clean()
                combined.merge(junk.report)
            }
            if !leftovers.selectedItems.isEmpty {
                step = "Moving leftovers to the Trash…"
                await leftovers.clean()
                combined.merge(leftovers.report)
            }
            report = combined
            phase = .finished
        }
    }

    func finish() {
        junk.finish()
        leftovers.finish()
        phase = .idle
    }
}
