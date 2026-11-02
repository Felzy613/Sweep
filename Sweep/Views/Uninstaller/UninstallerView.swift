import SwiftUI

struct UninstallerView: View {
    @Environment(AppModel.self) private var app
    @State private var confirmation: Confirmation?

    private let module = Module.uninstaller

    private enum Confirmation: Identifiable {
        case uninstall, reset
        var id: Self { self }
    }

    var body: some View {
        @Bindable var model = app.uninstaller
        Group {
            switch model.phase {
            case .cleaning:
                WorkingView(module: module, title: "Removing…", detail: model.progressText)
            case .finished:
                CleanupReportView(module: module, report: model.report, removalMode: .trash,
                                  onRetryAsAdmin: model.retryAsAdmin, onDone: model.finish)
            default:
                browser(model)
            }
        }
        .task { await model.loadIfNeeded() }
    }

    private func browser(_ model: UninstallerModel) -> some View {
        @Bindable var model = model
        return HSplitView {
            VStack(spacing: 0) {
                HStack {
                    TextField("Search apps", text: $model.searchText)
                        .textFieldStyle(.roundedBorder)
                    Picker("Sort", selection: $model.sort) {
                        ForEach(UninstallerModel.Sort.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                .padding(10)
                Divider()
                if model.isLoading {
                    ProgressView("Finding apps…").frame(maxHeight: .infinity)
                } else {
                    List(model.visibleApps, selection: Binding(get: { model.selectedAppID }, set: { model.select($0) })) { app in
                        appRow(app).tag(app.id)
                    }
                }
            }
            .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)

            detail(model)
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .confirmationDialog(confirmationTitle(model), isPresented: Binding(
            get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }
        )) {
            if confirmation == .reset {
                Button("Reset", role: .destructive) { model.remove(resetOnly: true) }
            } else {
                Button("Uninstall", role: .destructive) { model.remove(resetOnly: false) }
            }
        } message: {
            Text("Selected items will be moved to the Trash. The app will be asked to quit first.")
        }
    }

    private func appRow(_ app: InstalledApp) -> some View {
        HStack(spacing: 10) {
            FileIcon(url: app.url, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).lineLimit(1)
                Text(app.lastUsed.map { "Opened \($0.relativeDescription)" } ?? (app.version.map { "Version \($0)" } ?? ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let size = app.size {
                Text(size.formattedBytes).monospacedDigit().foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.mini)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func detail(_ model: UninstallerModel) -> some View {
        @Bindable var model = model
        if let selected = model.selectedApp {
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    FileIcon(url: selected.url, size: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selected.name).font(.title2.bold())
                        Text([selected.version.map { "Version \($0)" }, selected.bundleID, selected.isAppStore ? "App Store" : nil]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text(selected.lastUsed.map { "Last opened \($0.relativeDescription)" } ?? "Never opened, or Spotlight doesn't know")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(20)
                Divider()
                if model.isLoadingFiles {
                    ProgressView("Finding related files…").frame(maxHeight: .infinity)
                } else {
                    List($model.files) { $item in CleanupItemRow(item: $item) }
                }
                ActionBar(module: module,
                          summary: "\(model.files.selectedCount) of \(model.files.count) items · \(model.files.selectedSize.formattedBytes)",
                          buttonTitle: "Uninstall",
                          isDisabled: model.isLoadingFiles || !model.files.contains { $0.isSelected && $0.url == selected.url },
                          secondaryTitle: "Reset App",
                          isSecondaryDisabled: model.isLoadingFiles || !model.files.contains { $0.isSelected && $0.url != selected.url },
                          secondaryAction: { confirmation = .reset }) {
                    confirmation = .uninstall
                }
            }
        } else {
            ContentUnavailableView {
                Label("Select an app", systemImage: module.symbol)
            } description: {
                Text("Sweep shows the app together with its preferences, caches, containers and launch agents. **Reset App** keeps the app but removes its data.")
            }
        }
    }

    private func confirmationTitle(_ model: UninstallerModel) -> String {
        let name = model.selectedApp?.name ?? "the app"
        return confirmation == .reset ? "Reset \(name)?" : "Uninstall \(name)?"
    }
}
