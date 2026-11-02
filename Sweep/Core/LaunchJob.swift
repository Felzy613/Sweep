import Foundation

/// A launchd job definition from a LaunchAgents or LaunchDaemons folder.
struct LaunchJob: Identifiable, Hashable, Sendable {
    enum Domain: String, Sendable, CaseIterable {
        case userAgent
        case globalAgent
        case globalDaemon

        var title: String {
            switch self {
            case .userAgent: "Your Launch Agents"
            case .globalAgent: "Launch Agents for All Users"
            case .globalDaemon: "System Launch Daemons"
            }
        }

        /// Editing jobs outside the user's own folder needs root.
        var requiresAdmin: Bool { self != .userAgent }

        /// launchctl domain target: gui/501 or system.
        var launchctlTarget: String {
            self == .globalDaemon ? "system" : "gui/\(getuid())"
        }
    }

    static let folders: [(url: URL, domain: Domain)] = [
        (Home.library("LaunchAgents"), .userAgent),
        (URL(filePath: "/Library/LaunchAgents"), .globalAgent),
        (URL(filePath: "/Library/LaunchDaemons"), .globalDaemon),
    ]

    var id: URL { plistURL }
    let plistURL: URL
    let domain: Domain
    let label: String
    let executablePath: String?
    let runAtLoad: Bool
    let keepAlive: Bool

    init?(plistURL: URL, domain: Domain) {
        guard let plist = NSDictionary(contentsOf: plistURL) as? [String: Any] else { return nil }
        self.plistURL = plistURL
        self.domain = domain
        label = plist["Label"] as? String ?? plistURL.deletingPathExtension().lastPathComponent
        executablePath = (plist["Program"] as? String) ?? (plist["ProgramArguments"] as? [String])?.first
        runAtLoad = plist["RunAtLoad"] as? Bool ?? false
        keepAlive = plist["KeepAlive"] as? Bool ?? (plist["KeepAlive"] != nil)
    }

    var executableName: String {
        executablePath.map { ($0 as NSString).lastPathComponent } ?? label
    }

    /// Whether the executable lives inside the given app bundle.
    func belongs(to appPath: String) -> Bool {
        guard let executablePath else { return false }
        return executablePath.hasPrefix(appPath.hasSuffix("/") ? appPath : appPath + "/")
    }
}
