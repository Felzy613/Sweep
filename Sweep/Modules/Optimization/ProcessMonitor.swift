import AppKit

/// An app (with all its helper processes) or a standalone process, with combined usage.
struct ProcessGroup: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    /// Path of the .app bundle, if the processes belong to one.
    let appPath: String?
    let pids: [Int32]
    let cpu: Double
    let memory: Int64
    /// All processes belong to the current user, so we're allowed to stop them.
    let isOwnedByUser: Bool
}

enum ProcessMonitor {
    /// Snapshot of every process, grouped by app.
    static func groups() async -> [ProcessGroup] {
        guard let result = try? await Shell.run("/bin/ps", ["-axo", "pid=,uid=,pcpu=,rss=,comm="]) else { return [] }
        let uid = getuid()

        struct Accumulator {
            var name: String
            var appPath: String?
            var pids: [Int32] = []
            var cpu = 0.0
            var memory: Int64 = 0
            var ownedByUser = true
        }
        var groups: [String: Accumulator] = [:]

        for line in result.output.split(separator: "\n") {
            let fields = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
            guard fields.count == 5,
                  let pid = Int32(fields[0]), let owner = UInt32(fields[1]),
                  let cpu = Double(fields[2]), let rssKB = Int64(fields[3])
            else { continue }
            let executable = String(fields[4])

            let appPath = executable.contains(".app/") ? AppCatalog.outermostAppPath(of: URL(filePath: executable)) : nil
            let key = appPath ?? "\(executable)#\(pid)"
            let name = appPath.map { URL(filePath: $0).deletingPathExtension().lastPathComponent }
                ?? (executable as NSString).lastPathComponent

            var group = groups[key] ?? Accumulator(name: name, appPath: appPath)
            group.pids.append(pid)
            group.cpu += cpu
            group.memory += rssKB * 1024
            group.ownedByUser = group.ownedByUser && owner == uid
            groups[key] = group
        }

        return groups.map { key, group in
            ProcessGroup(id: key, name: group.name, appPath: group.appPath, pids: group.pids,
                         cpu: group.cpu, memory: group.memory, isOwnedByUser: group.ownedByUser)
        }
    }

    /// Asks the app to quit (it may show a save dialog); plain processes get SIGTERM.
    @MainActor
    static func quit(_ group: ProcessGroup, force: Bool = false) {
        if let appPath = group.appPath {
            let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.plainPath == appPath }
            if !apps.isEmpty {
                for app in apps {
                    if force { app.forceTerminate() } else { app.terminate() }
                }
                return
            }
        }
        for pid in group.pids {
            kill(pid, force ? SIGKILL : SIGTERM)
        }
    }
}
