import SwiftUI

struct LargeFilesView: View {
    @Environment(AppModel.self) private var app
    @AppStorage(Preferences.largeFileMinimumKey) private var minimumMB = 50
    @State private var confirming = false

    private let module = Module.largeFiles

    var body: some View {
        let model = app.largeFiles
        switch model.phase {
        case .idle:
            ModuleLanding(module: module, action: model.startScan) {
                Picker("Find files larger than", selection: $minimumMB) {
                    ForEach([10, 50, 100, 500, 1000], id: \.self) { Text(Int64($0 * 1_000_000).formattedBytes).tag($0) }
                }
                .fixedSize()
            }
        case .scanning:
            WorkingView(module: module, title: "Searching your home folder…", detail: model.progressText, onStop: model.cancel)
        case .cleaning:
            WorkingView(module: module, title: "Moving to Trash…", detail: model.progressText)
        case .finished:
            CleanupReportView(module: module, report: model.report, removalMode: .trash, onDone: model.finish)
        case .results:
            results(model)
        }
    }

    private func results(_ model: LargeFilesModel) -> some View {
        @Bindable var model = model
        return VStack(spacing: 0) {
            ResultsHeader(module: module, title: "\(model.files.count) large files",
                          subtitle: "Files over \(Int64(minimumMB * 1_000_000).formattedBytes) in your home folder, biggest first.") {
                Picker("Kind", selection: $model.kindFilter) {
                    Text("All Kinds").tag(LargeFile.Kind?.none)
                    ForEach(LargeFile.Kind.allCases) { kind in
                        let size = model.size(of: kind)
                        if size > 0 {
                            Label("\(kind.title) (\(size.formattedBytes))", systemImage: kind.symbol).tag(Optional(kind))
                        }
                    }
                }
                .labelsHidden()
                .fixedSize()
                Picker("Age", selection: $model.ageFilter) {
                    ForEach(LargeFilesModel.AgeFilter.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                Button("Scan Again", systemImage: "arrow.clockwise", action: model.startScan)
            }
            Divider()
            if model.visibleFiles.isEmpty {
                ContentUnavailableView("No matching files", systemImage: "doc.text.magnifyingglass",
                                       description: Text("Try a different kind or age filter."))
            } else {
                fileTable(model)
            }
            ActionBar(module: module,
                      summary: "\(model.selectedFiles.count) selected · \(model.selectedSize.formattedBytes)",
                      buttonTitle: "Move to Trash",
                      isDisabled: model.selectedFiles.isEmpty) {
                confirming = true
            }
        }
        .confirmationDialog("Move \(model.selectedFiles.count) files to the Trash?", isPresented: $confirming) {
            Button("Move to Trash", role: .destructive, action: model.removeSelected)
        }
    }

    private func fileTable(_ model: LargeFilesModel) -> some View {
        Table(model.visibleFiles) {
            TableColumn("") { file in
                Toggle("", isOn: Binding(get: { file.isSelected }, set: { model.setSelected($0, for: file.id) }))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
            }
            .width(24)
            TableColumn("Name") { file in
                HStack(spacing: 8) {
                    FileIcon(url: file.url, size: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(file.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                        Text(file.url.deletingLastPathComponent().abbreviatedPath)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                }
                .contextMenu {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
                }
            }
            TableColumn("Kind") { file in
                Label(file.kind.title, systemImage: file.kind.symbol).foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 110)
            TableColumn("Last Used") { file in
                Text(file.lastUsed?.relativeDescription ?? "—").foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 120)
            TableColumn("Size") { file in
                Text(file.size.formattedBytes).monospacedDigit()
            }
            .width(min: 70, ideal: 80)
        }
    }
}
