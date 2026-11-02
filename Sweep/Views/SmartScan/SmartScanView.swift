import SwiftUI

struct SmartScanView: View {
    @Environment(AppModel.self) private var app
    @State private var disk = DiskStats.current()

    private let module = Module.smartScan

    var body: some View {
        let model = app.smartScan
        switch model.phase {
        case .idle:
            ModuleLanding(module: module, action: model.scan) {
                VStack(spacing: 16) {
                    if let disk { DiskUsageBar(disk: disk).frame(maxWidth: 460) }
                    FullDiskAccessBanner().frame(maxWidth: 640)
                }
                .padding(.top, 8)
            }
            .onAppear { disk = DiskStats.current() }
        case .scanning:
            WorkingView(module: module, title: model.step, detail: model.progressText, onStop: model.cancel)
        case .cleaning:
            WorkingView(module: module, title: model.step, detail: model.progressText)
        case .finished:
            CleanupReportView(module: module, report: model.report, removalMode: model.removalMode, onDone: model.finish)
        case .results:
            results(model)
        }
    }

    private func results(_ model: SmartScanModel) -> some View {
        VStack(spacing: 28) {
            Spacer()
            VStack(spacing: 6) {
                Text("Scan complete").font(.largeTitle.bold())
                Text(model.totalSize > 0
                     ? "Sweep can free up \(model.totalSize.formattedBytes) right now."
                     : "Nothing to clean right now. Your Mac is in good shape.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 18) {
                SummaryCard(module: .systemJunk, value: model.junkSize.formattedBytes,
                            caption: "of junk selected", button: "Review") { app.selection = .systemJunk }
                SummaryCard(module: .leftovers, value: model.leftoversSize.formattedBytes,
                            caption: "of leftovers selected", button: "Review") { app.selection = .leftovers }
                SummaryCard(module: .optimization, value: "\(model.enabledAgentCount)",
                            caption: memoryCaption(model), button: "Manage") { app.selection = .optimization }
            }
            .frame(maxWidth: 820)
            HStack(spacing: 12) {
                Button("Start Over", action: model.finish).controlSize(.large)
                Button(action: model.clean) {
                    Text("Clean \(model.totalSize.formattedBytes)").frame(minWidth: 160)
                }
                .buttonStyle(.borderedProminent)
                .tint(module.tint)
                .controlSize(.large)
                .disabled(model.totalSize == 0)
                .keyboardShortcut(.defaultAction)
            }
            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func memoryCaption(_ model: SmartScanModel) -> String {
        var caption = "background agents enabled"
        if let memory = model.memory {
            caption += " · \(Int(memory.usedFraction * 100))% memory used"
        }
        return caption
    }
}

private struct SummaryCard: View {
    let module: Module
    let value: String
    let caption: String
    let button: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            ModuleIcon(module: module, size: 56)
            Text(module.title).font(.headline)
            Text(value).font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
            Text(caption)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(minHeight: 36, alignment: .top)
            Button(button, action: action)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.quaternary))
    }
}

/// Used and free space on the startup disk.
struct DiskUsageBar: View {
    let disk: DiskStats

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Startup Disk", systemImage: "internaldrive")
                Spacer()
                Text("\(disk.available.formattedBytes) available of \(disk.total.formattedBytes)")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            ProgressView(value: disk.usedFraction)
                .tint(disk.usedFraction > 0.9 ? .red : .accentColor)
        }
    }
}
