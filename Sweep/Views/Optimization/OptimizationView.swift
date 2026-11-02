import SwiftUI

struct OptimizationView: View {
    @Environment(AppModel.self) private var app
    @State private var pendingRemoval: LaunchItem?

    private let module = Module.optimization

    var body: some View {
        @Bindable var model = app.optimization
        VStack(spacing: 0) {
            ResultsHeader(module: module, title: module.title, subtitle: module.subtitle) {
                Picker("View", selection: $model.tab) {
                    ForEach(OptimizationModel.Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            Divider()
            switch model.tab {
            case .launchAgents: launchAgents(model)
            case .heavyConsumers: heavyConsumers(model)
            }
        }
        .task { await model.loadAgents() }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .confirmationDialog("Remove \(pendingRemoval?.job.label ?? "")?", isPresented: Binding(
            get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }
        )) {
            Button("Remove", role: .destructive) {
                if let item = pendingRemoval { Task { await model.remove(item) } }
            }
        } message: {
            Text("The job is stopped and its file removed. The app that installed it may add it back the next time it runs.")
        }
    }

    // MARK: Launch agents

    private func launchAgents(_ model: OptimizationModel) -> some View {
        List {
            Section {
                HStack {
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                    Text("Apps registered with **Open at Login** are managed in System Settings.")
                    Spacer()
                    Button("Open Login Items") { Permissions.openLoginItemsSettings() }
                }
            }
            ForEach(LaunchJob.Domain.allCases, id: \.self) { domain in
                let items = model.items(in: domain)
                if !items.isEmpty {
                    Section {
                        ForEach(items) { item in launchRow(item, model: model) }
                    } header: {
                        Text(domain.title + (domain.requiresAdmin ? " (administrator password required)" : ""))
                    }
                }
            }
        }
        .overlay {
            if model.isLoadingAgents && model.launchItems.isEmpty {
                ProgressView()
            } else if model.launchItems.isEmpty {
                ContentUnavailableView("No launch agents", systemImage: "checkmark.seal",
                                       description: Text("Nothing from third-party apps starts in the background."))
            }
        }
    }

    private func launchRow(_ item: LaunchItem, model: OptimizationModel) -> some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { item.isEnabled },
                set: { enabled in Task { await model.setEnabled(enabled, for: item) } }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .disabled(model.busyItem == item.id)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.job.label).lineLimit(1)
                Text(item.job.executablePath ?? item.job.plistURL.abbreviatedPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if !item.isEnabled { tag("Disabled") }
            if item.job.runAtLoad { tag("At login") }
            if item.job.keepAlive { tag("Always running") }
            if model.busyItem == item.id {
                ProgressView().controlSize(.small)
            }
            Button {
                pendingRemoval = item
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove this launch agent")
        }
        .contextMenu {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.job.plistURL]) }
        }
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
    }

    // MARK: Heavy consumers

    private func heavyConsumers(_ model: OptimizationModel) -> some View {
        @Bindable var model = model
        return VStack(spacing: 0) {
            if let memory = model.memory {
                MemoryBar(memory: memory, module: module, isFreeing: model.isFreeingRAM) {
                    Task { await model.freeRAM() }
                }
                .padding(20)
            }
            HStack {
                Text("Apps and processes using the most resources").font(.headline)
                Spacer()
                Picker("Sort by", selection: $model.processSort) {
                    ForEach(OptimizationModel.ProcessSort.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            Table(model.topProcesses) {
                TableColumn("Name") { group in
                    HStack(spacing: 8) {
                        if let appPath = group.appPath {
                            FileIcon(url: URL(filePath: appPath), size: 20)
                        } else {
                            Image(systemName: "gearshape").frame(width: 20)
                        }
                        Text(group.name).lineLimit(1)
                        if group.pids.count > 1 {
                            Text("\(group.pids.count) processes").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                TableColumn("CPU") { group in
                    Text(String(format: "%.1f%%", group.cpu)).monospacedDigit()
                }
                .width(min: 60, ideal: 70)
                TableColumn("Memory") { group in
                    Text(group.memory.formattedBytes).monospacedDigit()
                }
                .width(min: 70, ideal: 90)
                TableColumn("") { group in
                    if group.isOwnedByUser {
                        HStack {
                            Button("Quit") { model.quit(group, force: false) }
                            Button("Force Quit") { model.quit(group, force: true) }
                        }
                        .controlSize(.small)
                    }
                }
                .width(min: 150, ideal: 160)
            }
        }
        .task {
            while !Task.isCancelled {
                await model.refreshProcesses()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }
}

/// Stacked bar of memory use, like Activity Monitor's memory pressure section.
struct MemoryBar: View {
    let memory: MemoryStats
    let module: Module
    let isFreeing: Bool
    let freeRAM: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Memory").font(.headline)
                Text("\(memory.used.formattedBytes) of \(memory.total.formattedBytes) used")
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: freeRAM) {
                    if isFreeing { ProgressView().controlSize(.small) } else { Text("Free Up RAM") }
                }
                .disabled(isFreeing)
            }
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    segment(memory.app, color: module.colors[0], width: proxy.size.width)
                    segment(memory.wired, color: .orange, width: proxy.size.width)
                    segment(memory.compressed, color: .purple, width: proxy.size.width)
                    segment(memory.cachedFiles, color: .gray.opacity(0.5), width: proxy.size.width)
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 14)
            .background(.quaternary, in: Capsule())
            .clipShape(Capsule())
            HStack(spacing: 16) {
                legend("App", memory.app, module.colors[0])
                legend("Wired", memory.wired, .orange)
                legend("Compressed", memory.compressed, .purple)
                legend("Cached files", memory.cachedFiles, .gray.opacity(0.5))
            }
            .font(.caption)
        }
    }

    private func segment(_ bytes: Int64, color: Color, width: CGFloat) -> some View {
        color.frame(width: max(0, width * CGFloat(bytes) / CGFloat(max(memory.total, 1)) - 2))
    }

    private func legend(_ title: String, _ bytes: Int64, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(title) \(bytes.formattedBytes)").foregroundStyle(.secondary)
        }
    }
}
