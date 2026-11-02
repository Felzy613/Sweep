import SwiftUI

struct LeftoversView: View {
    @Environment(AppModel.self) private var app
    @State private var confirming = false
    @State private var expanded: Set<String> = []

    private let module = Module.leftovers

    var body: some View {
        let model = app.leftovers
        switch model.phase {
        case .idle:
            ModuleLanding(module: module, action: model.startScan) {
                FullDiskAccessBanner().frame(maxWidth: 640)
            }
        case .scanning:
            WorkingView(module: module, title: "Looking for leftovers…", detail: model.progressText, onStop: model.cancel)
        case .cleaning:
            WorkingView(module: module, title: "Removing…", detail: model.progressText)
        case .finished:
            CleanupReportView(module: module, report: model.report, removalMode: .trash,
                              onRetryAsAdmin: model.retryAsAdmin, onDone: model.finish)
        case .results:
            results(model)
        }
    }

    private func results(_ model: LeftoversModel) -> some View {
        @Bindable var model = model
        let selected = model.selectedItems
        return VStack(spacing: 0) {
            ResultsHeader(module: module,
                          title: "\(model.totalSize.formattedBytes) left by \(model.groups.count) removed apps",
                          subtitle: "Groups marked for review are not selected. Everything goes to the Trash.") {
                Button("Scan Again", systemImage: "arrow.clockwise", action: model.startScan)
            }
            Divider()
            if model.groups.isEmpty {
                ContentUnavailableView("No leftovers", systemImage: "checkmark.seal",
                                       description: Text("Every support file belongs to an installed app."))
            } else {
                List {
                    ForEach($model.groups) { $group in
                        DisclosureGroup(isExpanded: expansion(for: group.id)) {
                            ForEach($group.items) { $item in
                                CleanupItemRow(item: $item)
                            }
                        } label: {
                            groupLabel(group, model: model)
                        }
                    }
                }
            }
            ActionBar(module: module,
                      summary: "\(selected.count) items selected · \(selected.totalSize.formattedBytes)",
                      buttonTitle: "Remove",
                      isDisabled: selected.isEmpty) {
                confirming = true
            }
        }
        .confirmationDialog("Move \(selected.totalSize.formattedBytes) of leftovers to the Trash?", isPresented: $confirming) {
            Button("Move to Trash", role: .destructive, action: model.startClean)
        } message: {
            Text("You can put anything back from the Trash if an app turns out to need it.")
        }
    }

    private func groupLabel(_ group: LeftoverGroup, model: LeftoversModel) -> some View {
        HStack(spacing: 10) {
            GroupCheckbox(state: SelectionState(group.items)) { model.setAll($0, in: group.id) }
            Image(systemName: "app.dashed")
                .font(.title2)
                .foregroundStyle(module.tint)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(group.vendorName).font(.headline)
                    if group.needsReview {
                        Text("Review")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.orange.opacity(0.2), in: Capsule())
                            .foregroundStyle(.orange)
                            .help(group.reviewReason ?? "")
                    }
                }
                Text(group.identifier).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(group.items.count) items").foregroundStyle(.secondary)
            Text(group.totalSize.formattedBytes)
                .monospacedDigit()
                .frame(minWidth: 70, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    private func expansion(for id: String) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { isExpanded in
                if isExpanded { expanded.insert(id) } else { expanded.remove(id) }
            }
        )
    }
}
