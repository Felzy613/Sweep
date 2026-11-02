import SwiftUI

struct JunkView: View {
    @Environment(AppModel.self) private var app
    @AppStorage(Preferences.junkRemovalModeKey) private var removalMode: RemovalMode = .permanent
    @State private var confirming = false

    private let module = Module.systemJunk

    var body: some View {
        let model = app.junk
        switch model.phase {
        case .idle:
            ModuleLanding(module: module, action: model.startScan) {
                FullDiskAccessBanner().frame(maxWidth: 640)
            }
        case .scanning:
            WorkingView(module: module, title: "Looking for junk…", detail: model.progressText, onStop: model.cancel)
        case .cleaning:
            WorkingView(module: module, title: "Cleaning…", detail: model.progressText)
        case .finished:
            CleanupReportView(module: module, report: model.report, removalMode: model.lastRemovalMode,
                              onRetryAsAdmin: model.retryAsAdmin, onDone: model.finish)
        case .results:
            results(model)
        }
    }

    @ViewBuilder
    private func results(_ model: JunkModel) -> some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            ResultsHeader(module: module, title: "\(model.totalSize.formattedBytes) of junk found",
                          subtitle: "Review the categories, then clean what you don't need.") {
                Button("Scan Again", systemImage: "arrow.clockwise", action: model.startScan)
            }
            Divider()
            if model.categories.isEmpty {
                ContentUnavailableView("Your Mac is clean", systemImage: "checkmark.seal",
                                       description: Text("No junk was found."))
            } else {
                HSplitView {
                    List(selection: $model.selectedKind) {
                        ForEach(model.categories) { category in
                            categoryRow(category, model: model).tag(category.kind)
                        }
                    }
                    .frame(minWidth: 260, idealWidth: 290, maxWidth: 340)

                    if let index = model.categories.firstIndex(where: { $0.kind == model.selectedKind }) {
                        categoryDetail($model.categories[index])
                    } else {
                        ContentUnavailableView("Select a category", systemImage: "sidebar.left")
                    }
                }
            }
            ActionBar(module: module,
                      summary: "\(model.selectedCount) items selected · \(model.selectedSize.formattedBytes)",
                      buttonTitle: "Clean",
                      isDisabled: model.selectedCount == 0) {
                confirming = true
            }
        }
        .confirmationDialog("Clean \(model.selectedSize.formattedBytes) of junk?", isPresented: $confirming) {
            Button("Clean", role: .destructive, action: model.startClean)
        } message: {
            Text(removalMode == .trash
                 ? "Selected items will be moved to the Trash. Items already in the Trash are deleted permanently."
                 : "Selected items will be deleted permanently.")
        }
    }

    private func categoryRow(_ category: JunkCategory, model: JunkModel) -> some View {
        HStack(spacing: 10) {
            GroupCheckbox(state: SelectionState(category.items)) { model.setAll($0, in: category.kind) }
            Image(systemName: category.kind.symbol)
                .frame(width: 22)
                .foregroundStyle(module.tint)
            Text(category.kind.title).lineLimit(1)
            Spacer()
            Text(category.selectedSize.formattedBytes)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

    private func categoryDetail(_ category: Binding<JunkCategory>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(category.wrappedValue.kind.title).font(.title3.bold())
                Text(category.wrappedValue.kind.detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            Divider()
            List(category.items) { $item in
                CleanupItemRow(item: $item)
            }
        }
        .frame(minWidth: 380, maxWidth: .infinity)
    }
}
