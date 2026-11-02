import AppKit

/// One-click system maintenance routines.
enum MaintenanceTask: String, CaseIterable, Identifiable, Sendable {
    case freeRAM
    case flushDNS
    case rebuildLaunchServices
    case reindexSpotlight
    case thinSnapshots
    case speedUpMail
    case clearFontCaches
    case deleteUnavailableSimulators
    case verifyStartupDisk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .freeRAM: "Free Up RAM"
        case .flushDNS: "Flush DNS Cache"
        case .rebuildLaunchServices: "Rebuild Launch Services"
        case .reindexSpotlight: "Reindex Spotlight"
        case .thinSnapshots: "Thin Time Machine Snapshots"
        case .speedUpMail: "Speed Up Mail"
        case .clearFontCaches: "Clear Font Caches"
        case .deleteUnavailableSimulators: "Delete Unavailable Simulators"
        case .verifyStartupDisk: "Verify Startup Disk"
        }
    }

    var detail: String {
        switch self {
        case .freeRAM: "Flushes inactive memory and disk caches so apps get free RAM right away."
        case .flushDNS: "Clears cached domain lookups. Helps when websites fail to load after network changes."
        case .rebuildLaunchServices: "Fixes duplicate apps in \"Open With\" menus and wrong default apps."
        case .reindexSpotlight: "Rebuilds the Spotlight index when search results are missing or wrong. Indexing runs for a while in the background."
        case .thinSnapshots: "Removes local Time Machine snapshots to give back purgeable disk space."
        case .speedUpMail: "Compacts Mail's message database. Quit Mail first."
        case .clearFontCaches: "Removes your font caches, which fixes garbled or missing fonts. Restart apps afterwards."
        case .deleteUnavailableSimulators: "Deletes Xcode simulators for runtimes that are no longer installed."
        case .verifyStartupDisk: "Checks the file system of your startup disk for errors (read-only)."
        }
    }

    var symbol: String {
        switch self {
        case .freeRAM: "memorychip"
        case .flushDNS: "network"
        case .rebuildLaunchServices: "square.stack.3d.up"
        case .reindexSpotlight: "magnifyingglass"
        case .thinSnapshots: "clock.arrow.circlepath"
        case .speedUpMail: "envelope"
        case .clearFontCaches: "textformat"
        case .deleteUnavailableSimulators: "iphone.slash"
        case .verifyStartupDisk: "internaldrive"
        }
    }

    var requiresAdmin: Bool { adminCommand != nil }

    /// Shown only when the routine applies to this Mac.
    var isAvailable: Bool {
        switch self {
        case .deleteUnavailableSimulators: FileScanner.exists(Home.library("Developer/CoreSimulator"))
        case .speedUpMail: FileScanner.exists(Home.library("Containers/com.apple.mail"))
        default: true
        }
    }

    /// Command run through /bin/sh as root.
    var adminCommand: String? {
        switch self {
        case .freeRAM: "/usr/sbin/purge"
        case .flushDNS: "/usr/bin/dscacheutil -flushcache && /usr/bin/killall -HUP mDNSResponder"
        case .reindexSpotlight: "/usr/bin/mdutil -E /"
        case .thinSnapshots: "/usr/bin/tmutil thinlocalsnapshots / 999999999999 4"
        default: nil
        }
    }

    private static let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    /// Programs run as the current user, in order.
    func userSteps() throws -> [(executable: String, arguments: [String])] {
        switch self {
        case .rebuildLaunchServices:
            return [(Self.lsregister, ["-r", "-f", "-apps", "u,s,l"]), (Self.lsregister, ["-gc"])]
        case .clearFontCaches:
            return [("/usr/bin/atsutil", ["databases", "-removeUser"])]
        case .deleteUnavailableSimulators:
            return [("/usr/bin/xcrun", ["simctl", "delete", "unavailable"])]
        case .verifyStartupDisk:
            return [("/usr/sbin/diskutil", ["verifyVolume", "/"])]
        case .speedUpMail:
            if NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == "com.apple.mail" }) {
                throw ShellError.failed("Quit Mail, then run this again.")
            }
            let databases = FileScanner.children(of: Home.library("Mail"))
                .filter { $0.lastPathComponent.hasPrefix("V") }
                .map { $0.appending(path: "MailData/Envelope Index") }
                .filter(FileScanner.exists)
            guard !databases.isEmpty else {
                throw ShellError.failed("Mail's database wasn't found. Give Sweep Full Disk Access and try again.")
            }
            return databases.map { ("/usr/bin/sqlite3", [$0.plainPath, "VACUUM;"]) }
        case .freeRAM, .flushDNS, .reindexSpotlight, .thinSnapshots:
            return []
        }
    }
}

enum TaskOutcome: Equatable, Sendable {
    case success(String)
    case failure(String)
}

enum MaintenanceRunner {
    /// Runs the tasks. All root tasks share a single password prompt.
    static func run(_ tasks: [MaintenanceTask]) async -> [MaintenanceTask: TaskOutcome] {
        var outcomes: [MaintenanceTask: TaskOutcome] = [:]

        let adminTasks = tasks.filter(\.requiresAdmin)
        if !adminTasks.isEmpty {
            let script = adminTasks.compactMap { task in
                task.adminCommand.map { "if ( \($0) ) >/dev/null 2>&1; then echo OK:\(task.rawValue); fi" }
            }.joined(separator: "; ")
            do {
                let result = try await Shell.runAsAdmin(script, prompt: "Sweep needs your password to run maintenance tasks.")
                for task in adminTasks {
                    outcomes[task] = result.output.contains("OK:\(task.rawValue)") ? .success("Done") : .failure("The task reported an error.")
                }
            } catch {
                for task in adminTasks { outcomes[task] = .failure(error.localizedDescription) }
            }
        }

        for task in tasks where !task.requiresAdmin {
            do {
                var lastOutput = ""
                for step in try task.userSteps() {
                    let result = try await Shell.run(step.executable, step.arguments)
                    guard result.succeeded else {
                        throw ShellError.failed(lastLine(of: result.error.isEmpty ? result.output : result.error))
                    }
                    lastOutput = result.output
                }
                let summary = lastLine(of: lastOutput)
                outcomes[task] = .success(summary.isEmpty ? "Done" : summary)
            } catch {
                outcomes[task] = .failure(error.localizedDescription)
            }
        }
        return outcomes
    }

    private static func lastLine(of output: String) -> String {
        let line = output.split(separator: "\n").last { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        return String(line.trimmingCharacters(in: .whitespaces).prefix(160))
    }
}
