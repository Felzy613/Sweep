import SwiftUI

@main
struct SweepApp: App {
    @State private var model = AppModel()
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true

    var body: some Scene {
        Window("Sweep", id: "main") {
            ContentView()
                .environment(model)
        }
        .defaultSize(width: 1120, height: 740)

        Settings {
            SettingsView()
                .environment(model)
        }

        MenuBarExtra("Sweep", systemImage: "sparkles", isInserted: $showMenuBarExtra) {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)
    }
}
