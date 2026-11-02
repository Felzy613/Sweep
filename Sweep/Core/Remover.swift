import Foundation

/// The only code in the app that deletes anything. Every item is checked
/// against `SafetyPolicy` first.
enum Remover {
    /// Removes items as the current user. Blocking; call it off the main actor.
    /// Items that fail for lack of permission come back with `needsAdmin` set.
    static func remove(_ items: [CleanupItem], mode: RemovalMode, progress: ProgressThrottle? = nil) -> CleanupReport {
        var report = CleanupReport()
        for item in items {
            if Task.isCancelled { break }
            progress?("Removing \(item.name)…")
            do {
                try SafetyPolicy.validate(item.url)
                guard existsOrIsLink(item.url) else {
                    // Already gone (an app or macOS removed it since the scan).
                    report.removed.append(item.url)
                    continue
                }
                switch mode {
                case .trash: try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                case .permanent: try FileManager.default.removeItem(at: item.url)
                }
                report.removed.append(item.url)
                report.freedBytes += item.size
            } catch let violation as SafetyPolicy.Violation {
                report.failures.append(.init(url: item.url, reason: violation.localizedDescription, needsAdmin: false))
            } catch {
                report.failures.append(.init(url: item.url, reason: describe(error), needsAdmin: isPermissionError(error)))
            }
        }
        return report
    }

    /// Deletes items permanently as root, asking for the administrator password
    /// once for the whole batch.
    static func removeAsAdmin(_ items: [CleanupItem]) async -> CleanupReport {
        var report = CleanupReport()
        var allowed: [CleanupItem] = []
        for item in items {
            do {
                try SafetyPolicy.validate(item.url)
                allowed.append(item)
            } catch {
                report.failures.append(.init(url: item.url, reason: error.localizedDescription, needsAdmin: false))
            }
        }
        guard !allowed.isEmpty else { return report }

        let command = "/bin/rm -rf -- " + allowed.map { Shell.quoted($0.path) }.joined(separator: " ")
        let prompt = "Sweep needs your password to remove \(allowed.count) protected item\(allowed.count == 1 ? "" : "s")."
        var shellFailure: String?
        do {
            try await Shell.runAsAdmin(command, prompt: prompt)
        } catch ShellError.cancelledByUser {
            report.failures += allowed.map { .init(url: $0.url, reason: "Cancelled.", needsAdmin: true) }
            return report
        } catch {
            // rm keeps going after a failure, so check each item below.
            shellFailure = error.localizedDescription
        }

        for item in allowed {
            if existsOrIsLink(item.url) {
                let reason = shellFailure ?? "macOS prevented removal (System Integrity Protection)."
                report.failures.append(.init(url: item.url, reason: reason, needsAdmin: false))
            } else {
                report.removed.append(item.url)
                report.freedBytes += item.size
            }
        }
        return report
    }

    // MARK: - Helpers

    private static func existsOrIsLink(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path(percentEncoded: false), &info) == 0
    }

    static func isPermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           [NSFileWriteNoPermissionError, NSFileReadNoPermissionError].contains(nsError.code) {
            return true
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            return underlying.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(underlying.code)
        }
        return nsError.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(nsError.code)
    }

    private static func describe(_ error: Error) -> String {
        if isPermissionError(error) { return "Permission denied." }
        return (error as NSError).localizedFailureReason ?? error.localizedDescription
    }
}
