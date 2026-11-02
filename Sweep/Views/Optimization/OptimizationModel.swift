import SwiftUI

@MainActor
@Observable
final class OptimizationModel {
    enum Tab: String, CaseIterable, Identifiable {
        case launchAgents = "Launch Agents"
        case heavyConsumers = "Heavy Consumers"
        var id: String { rawValue }
    }

    enum ProcessSort: String, CaseIterable, Identifiable {
        case memory = "Memory"
        case cpu = "CPU"
        var id: String { rawValue }
    }

    var tab: Tab = .launchAgents
    var launchItems: [LaunchItem] = []
    var processes: [ProcessGroup] = []
    var processSort: ProcessSort = .memory
    var memory: MemoryStats?
    var isLoadingAgents = false
    var busyItem: URL?
    var isFreeingRAM = false
    var errorMessage: String?

    var topProcesses: [ProcessGroup] {
        let sorted = processes.sorted {
            processSort == .memory ? $0.memory > $1.memory : $0.cpu > $1.cpu
        }
        return Array(sorted.prefix(20))
    }

    func items(in domain: LaunchJob.Domain) -> [LaunchItem] {
        launchItems.filter { $0.job.domain == domain }
    }

    func loadAgents() async {
        isLoadingAgents = true
        launchItems = await runInBackground { LaunchItemsManager.load() }
        isLoadingAgents = false
    }

    func refreshProcesses() async {
        processes = await ProcessMonitor.groups()
        memory = MemoryStats.current()
    }

    func setEnabled(_ enabled: Bool, for item: LaunchItem) async {
        busyItem = item.id
        defer { busyItem = nil }
        do {
            try await LaunchItemsManager.setEnabled(enabled, for: item)
            if let index = launchItems.firstIndex(where: { $0.id == item.id }) {
                launchItems[index].isEnabled = enabled
            }
        } catch ShellError.cancelledByUser {
            return
        } catch {
            errorMessage = "Couldn't change \(item.job.label): \(error.localizedDescription)"
        }
    }

    func remove(_ item: LaunchItem) async {
        busyItem = item.id
        defer { busyItem = nil }
        do {
            try await LaunchItemsManager.remove(item)
            launchItems.removeAll { $0.id == item.id }
        } catch ShellError.cancelledByUser {
            return
        } catch {
            errorMessage = "Couldn't remove \(item.job.label): \(error.localizedDescription)"
        }
    }

    func quit(_ group: ProcessGroup, force: Bool) {
        ProcessMonitor.quit(group, force: force)
        Task {
            try? await Task.sleep(for: .seconds(1))
            await refreshProcesses()
        }
    }

    func freeRAM() async {
        isFreeingRAM = true
        let outcome = await MaintenanceRunner.run([.freeRAM])[.freeRAM]
        if case .failure(let message) = outcome, message != ShellError.cancelledByUser.localizedDescription {
            errorMessage = message
        }
        memory = MemoryStats.current()
        isFreeingRAM = false
    }
}
