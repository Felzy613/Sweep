import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @AppStorage(Preferences.junkRemovalModeKey) private var removalMode: RemovalMode = .permanent
    @AppStorage(Preferences.largeFileMinimumKey) private var minimumMB = 50
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true

    var body: some View {
        Form {
            Section("Cleaning") {
                Picker("Remove junk by", selection: $removalMode) {
                    ForEach(RemovalMode.allCases) { Text($0.title).tag($0) }
                }
                Text("Applies to System Junk and Smart Scan. Uninstalled apps, leftovers and large files always go to the Trash so you can undo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Large file threshold", selection: $minimumMB) {
                    ForEach([10, 50, 100, 500, 1000], id: \.self) { Text(Int64($0 * 1_000_000).formattedBytes).tag($0) }
                }
            }
            Section("Menu Bar") {
                Toggle("Show CPU, memory and disk in the menu bar", isOn: $showMenuBarExtra)
            }
            Section("Permissions") {
                LabeledContent("Full Disk Access") {
                    HStack {
                        Label(app.hasFullDiskAccess ? "Allowed" : "Not allowed",
                              systemImage: app.hasFullDiskAccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(app.hasFullDiskAccess ? .green : .orange)
                        Button("Open Settings") { Permissions.openFullDiskAccessSettings() }
                    }
                }
                Text("Full Disk Access lets Sweep see the Trash, Mail downloads, device backups and other apps' containers. Add Sweep in System Settings, then relaunch it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { app.refreshPermissions() }
    }
}
