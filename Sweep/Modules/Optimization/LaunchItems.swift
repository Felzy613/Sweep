import Foundation

/// A launch agent or daemon together with its launchd override state.
struct LaunchItem: Identifiable, Hashable, Sendable {
    let job: LaunchJob
    var isEnabled: Bool

    var id: URL { job.id }
}

/// Lists, enables, disables and removes launch agents and daemons.
enum LaunchItemsManager {
    /// Blocking; run it off the main actor.
    static func load() -> [LaunchItem] {
        let disabledUser = disabledLabels(in: "gui/\(getuid())")
        let disabledSystem = disabledLabels(in: "system")

        return LaunchJob.folders.flatMap { folder in
            FileScanner.children(of: folder.url)
                .filter { $0.pathExtension == "plist" }
                .compactMap { LaunchJob(plistURL: $0, domain: folder.domain) }
                .filter { !$0.label.hasPrefix("com.apple.") }
                .map { job in
                    let disabled = job.domain == .globalDaemon ? disabledSystem : disabledUser
                    return LaunchItem(job: job, isEnabled: !disabled.contains(job.label))
                }
        }
        .sorted { $0.job.label.localizedStandardCompare($1.job.label) == .orderedAscending }
    }

    /// Persistently enables or disables the job and starts or stops it right away.
    static func setEnabled(_ enabled: Bool, for item: LaunchItem) async throws {
        let job = item.job
        let target = job.domain.launchctlTarget
        let service = "\(target)/\(job.label)"
        let plist = job.plistURL.plainPath

        if job.domain == .globalDaemon {
            let command = enabled
                ? "/bin/launchctl enable \(Shell.quoted(service)); /bin/launchctl bootstrap system \(Shell.quoted(plist)) 2>/dev/null; true"
                : "/bin/launchctl disable \(Shell.quoted(service)); /bin/launchctl bootout \(Shell.quoted(service)) 2>/dev/null; true"
            try await Shell.runAsAdmin(command, prompt: "Sweep needs your password to change \(job.label).")
            return
        }

        let result = try await Shell.run("/bin/launchctl", [enabled ? "enable" : "disable", service])
        guard result.succeeded else { throw ShellError.failed(result.error) }
        if enabled {
            _ = try? await Shell.run("/bin/launchctl", ["bootstrap", target, plist])
        } else {
            _ = try? await Shell.run("/bin/launchctl", ["bootout", service])
        }
    }

    /// Stops the job and removes its plist (to the Trash when it's the user's own).
    static func remove(_ item: LaunchItem) async throws {
        let job = item.job
        let service = "\(job.domain.launchctlTarget)/\(job.label)"
        try SafetyPolicy.validate(job.plistURL)

        if job.domain.requiresAdmin {
            let command = "/bin/launchctl bootout \(Shell.quoted(service)) 2>/dev/null; /bin/rm -f -- \(Shell.quoted(job.plistURL.plainPath))"
            try await Shell.runAsAdmin(command, prompt: "Sweep needs your password to remove \(job.label).")
        } else {
            _ = try? await Shell.run("/bin/launchctl", ["bootout", service])
            try FileManager.default.trashItem(at: job.plistURL, resultingItemURL: nil)
        }
    }

    /// Labels launchd has been told to keep disabled in a domain.
    /// Output lines look like: `"com.foo.agent" => disabled` (or `=> true` on older systems).
    private static func disabledLabels(in domain: String) -> Set<String> {
        guard let result = try? Shell.runSync("/bin/launchctl", ["print-disabled", domain]) else { return [] }
        var labels = Set<String>()
        for line in result.output.split(separator: "\n") {
            let parts = line.components(separatedBy: "=>")
            guard parts.count == 2 else { continue }
            let state = parts[1].trimmingCharacters(in: .whitespaces)
            guard state == "disabled" || state == "true" else { continue }
            labels.insert(parts[0].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
        }
        return labels
    }
}
