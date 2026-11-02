import SwiftUI

@MainActor
@Observable
final class MaintenanceModel {
    let tasks = MaintenanceTask.allCases.filter(\.isAvailable)
    var selected: Set<MaintenanceTask> = [.freeRAM, .flushDNS]
    var outcomes: [MaintenanceTask: TaskOutcome] = [:]
    var isRunning = false

    func run() {
        let toRun = tasks.filter(selected.contains)
        guard !toRun.isEmpty else { return }
        isRunning = true
        outcomes = [:]
        Task {
            outcomes = await MaintenanceRunner.run(toRun)
            isRunning = false
        }
    }

    func toggle(_ task: MaintenanceTask) {
        if selected.contains(task) { selected.remove(task) } else { selected.insert(task) }
    }
}

struct MaintenanceView: View {
    @Environment(AppModel.self) private var app

    private let module = Module.maintenance

    var body: some View {
        let model = app.maintenance
        VStack(spacing: 0) {
            ResultsHeader(module: module, title: module.title, subtitle: module.subtitle) { EmptyView() }
            Divider()
            List(model.tasks) { task in
                row(task, model: model)
            }
            ActionBar(module: module,
                      summary: summary(model),
                      buttonTitle: model.isRunning ? "Running…" : "Run",
                      isDisabled: model.isRunning || model.selected.isEmpty,
                      action: model.run)
        }
    }

    private func row(_ task: MaintenanceTask, model: MaintenanceModel) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle("", isOn: Binding(get: { model.selected.contains(task) }, set: { _ in model.toggle(task) }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(model.isRunning)
            Image(systemName: task.symbol)
                .font(.title3)
                .foregroundStyle(module.gradient)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(task.title).font(.headline)
                    if task.requiresAdmin {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help("Needs your administrator password")
                    }
                }
                Text(task.detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let outcome = model.outcomes[task] {
                    outcomeLabel(outcome)
                }
            }
            Spacer()
            if model.isRunning && model.selected.contains(task) && model.outcomes[task] == nil {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func outcomeLabel(_ outcome: TaskOutcome) -> some View {
        switch outcome {
        case .success(let message):
            Label(message, systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.green)
        case .failure(let message):
            Label(message, systemImage: "xmark.octagon.fill")
                .font(.callout)
                .foregroundStyle(.red)
        }
    }

    private func summary(_ model: MaintenanceModel) -> String {
        let count = model.selected.count
        let admin = model.tasks.filter { model.selected.contains($0) && $0.requiresAdmin }.count
        var text = "\(count) task\(count == 1 ? "" : "s") selected"
        if admin > 0 { text += " · you'll be asked for your password once" }
        return text
    }
}
