import Foundation

/// Helpers for recognising reverse-DNS bundle identifiers in Library file names.
enum BundleID {
    private static let topLevelDomains: Set<String> = [
        "com", "org", "net", "io", "app", "dev", "co", "me", "ai", "sh", "so", "to", "tv", "cc", "im", "is", "ly",
        "xyz", "info", "biz", "edu", "us", "uk", "de", "fr", "nl", "be", "ch", "at", "it", "es", "pt", "se", "no",
        "dk", "fi", "pl", "cz", "sk", "hu", "ro", "ru", "ua", "jp", "cn", "kr", "tw", "hk", "in", "au", "nz",
        "ca", "br", "mx", "ar", "za", "il", "tr", "gr", "ie", "lt", "lv", "ee", "si", "hr", "rs", "bg", "eu",
    ]
    private static let strippableExtensions: Set<String> = ["plist", "savedstate", "binarycookies", "lockfile"]

    /// Extracts the identifier from a Library item name, or nil if the name isn't one:
    ///
    ///     "com.foo.Bar.plist"           → "com.foo.Bar"
    ///     "com.foo.Bar.savedState"      → "com.foo.Bar"
    ///     "group.com.foo.shared"        → "com.foo.shared"
    ///     "ABCDE12345.com.foo.Bar"      → "com.foo.Bar"
    ///     "com.foo.Bar.<UUID>.plist"    → "com.foo.Bar"  (ByHost preferences)
    ///     "Google"                      → nil
    static func identifier(fromFileName name: String) -> String? {
        var components = name.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard components.count >= 3, !components.contains(where: \.isEmpty) else { return nil }

        if let last = components.last, strippableExtensions.contains(last.lowercased()) {
            components.removeLast()
        }
        if let last = components.last, isUUIDLike(last) {
            components.removeLast()
        }
        if components.first?.lowercased() == "group" {
            components.removeFirst()
        }
        if let first = components.first, isTeamID(first) {
            components.removeFirst()
        }

        guard components.count >= 3,
              let tld = components.first?.lowercased(), topLevelDomains.contains(tld),
              components.allSatisfy(isValidComponent)
        else { return nil }
        return components.joined(separator: ".")
    }

    /// "com.google.Chrome" → "com.google"
    static func vendor(of identifier: String) -> String {
        identifier.split(separator: ".").prefix(2).joined(separator: ".").lowercased()
    }

    /// All prefixes that end on a component boundary and keep at least three components:
    /// "com.a.b.c" → ["com.a.b", "com.a.b.c"]
    static func prefixes(of identifier: String) -> [String] {
        let parts = identifier.lowercased().split(separator: ".")
        guard parts.count >= 3 else { return [identifier.lowercased()] }
        return (3...parts.count).map { parts.prefix($0).joined(separator: ".") }
    }

    private static func isUUIDLike(_ string: String) -> Bool {
        UUID(uuidString: string) != nil
    }

    /// Apple developer team identifiers are ten upper-case letters or digits.
    static func isTeamID(_ string: String) -> Bool {
        string.count == 10 && string.allSatisfy { $0.isUppercase || $0.isNumber } && string.contains(where: \.isNumber)
    }

    private static func isValidComponent(_ component: String) -> Bool {
        component.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }
}

/// Answers "does this identifier belong to something still installed?".
struct InstalledIdentifiers: Sendable {
    private let exact: Set<String>
    private let prefixes: Set<String>
    private let vendors: Set<String>

    init(_ identifiers: some Sequence<String>) {
        var exact = Set<String>()
        var prefixes = Set<String>()
        var vendors = Set<String>()
        for identifier in identifiers {
            exact.insert(identifier.lowercased())
            prefixes.formUnion(BundleID.prefixes(of: identifier))
            vendors.insert(BundleID.vendor(of: identifier))
        }
        self.exact = exact
        self.prefixes = prefixes
        self.vendors = vendors
    }

    var count: Int { exact.count }

    /// True if `identifier`, a parent of it (com.foo.app for com.foo.app.helper)
    /// or a child of it (com.foo.app.mac for com.foo.app) is installed.
    func owns(_ identifier: String) -> Bool {
        let lowered = identifier.lowercased()
        if prefixes.contains(lowered) { return true }
        return BundleID.prefixes(of: lowered).contains(where: exact.contains)
    }

    /// True if another installed app comes from the same vendor (com.google.*),
    /// in which case an unowned item may still be shared and needs review.
    func sharesVendor(with identifier: String) -> Bool {
        vendors.contains(BundleID.vendor(of: identifier))
    }
}
