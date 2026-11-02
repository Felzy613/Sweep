import SwiftUI

/// Live system stats in the menu bar.
struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @State private var sampler = CPUSampler()
    @State private var cpu: Double?
    @State private var memory = MemoryStats.current()
    @State private var disk = DiskStats.current()
    @State private var isFreeingRAM = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                ModuleIcon(module: .smartScan, size: 22)
                Text("Sweep").font(.headline)
            }
            stat("CPU", value: cpu.map { "\(Int($0 * 100))%" } ?? "…", fraction: cpu ?? 0, tint: .blue)
            if let memory {
                stat("Memory", value: "\(memory.used.formattedBytes) of \(memory.total.formattedBytes)",
                     fraction: memory.usedFraction, tint: .green)
            }
            if let disk {
                stat("Startup Disk", value: "\(disk.available.formattedBytes) free",
                     fraction: disk.usedFraction, tint: .orange)
            }
            Divider()
            HStack {
                Button {
                    isFreeingRAM = true
                    Task {
                        _ = await MaintenanceRunner.run([.freeRAM])
                        memory = MemoryStats.current()
                        isFreeingRAM = false
                    }
                } label: {
                    Text(isFreeingRAM ? "Freeing…" : "Free Up RAM")
                }
                .disabled(isFreeingRAM)
                Spacer()
                Button("Open Sweep") {
                    openWindow(id: "main")
                    NSApp.activate()
                }
                .buttonStyle(.borderedProminent)
            }
            Button("Quit Sweep") { NSApp.terminate(nil) }
                .buttonStyle(.link)
                .font(.caption)
        }
        .padding(14)
        .frame(width: 280)
        .task {
            while !Task.isCancelled {
                cpu = sampler.sample() ?? cpu
                memory = MemoryStats.current()
                disk = DiskStats.current()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func stat(_ title: String, value: String, fraction: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(value).foregroundStyle(.secondary).monospacedDigit()
            }
            .font(.callout)
            ProgressView(value: min(max(fraction, 0), 1)).tint(tint)
        }
    }
}
