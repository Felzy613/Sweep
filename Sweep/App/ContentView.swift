import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        NavigationSplitView {
            List(selection: $app.selection) {
                ForEach(Module.Group.allCases, id: \.self) { group in
                    let modules = Module.allCases.filter { $0.group == group }
                    if group == .overview {
                        ForEach(modules) { sidebarRow($0) }
                    } else {
                        Section(group.rawValue) {
                            ForEach(modules) { sidebarRow($0) }
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            detail
                .frame(minWidth: 720, minHeight: 540)
                .navigationTitle(app.selection?.title ?? "Sweep")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            app.refreshPermissions()
        }
    }

    private func sidebarRow(_ module: Module) -> some View {
        Label {
            Text(module.title)
        } icon: {
            ModuleIcon(module: module, size: 22)
        }
        .badge(app.badge(for: module).map { Text($0) })
        .tag(module)
    }

    @ViewBuilder
    private var detail: some View {
        switch app.selection ?? .smartScan {
        case .smartScan: SmartScanView()
        case .systemJunk: JunkView()
        case .largeFiles: LargeFilesView()
        case .uninstaller: UninstallerView()
        case .leftovers: LeftoversView()
        case .optimization: OptimizationView()
        case .maintenance: MaintenanceView()
        }
    }
}
