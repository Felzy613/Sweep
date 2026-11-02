import Foundation
import Testing
@testable import Sweep

struct SafetyPolicyTests {
    @Test(arguments: [
        "/", "/System", "/System/Library/CoreServices", "/usr/bin/true", "/Library", "/Library/Caches",
        "/Applications", "/Users", "/private/var/db/receipts/x.bom", "/etc/hosts", "/tmp",
    ])
    func rejectsSystemLocations(_ path: String) {
        #expect(!SafetyPolicy.isSafe(URL(filePath: path)))
    }

    @Test func rejectsHomeAndItsStandardFolders() {
        for relative in ["", "Library", "Library/Caches", "Library/Preferences", "Documents", "Desktop", ".Trash", "Library/Mobile Documents/x"] {
            #expect(!SafetyPolicy.isSafe(Home.path(relative)), "\(relative)")
        }
    }

    @Test func allowsItemsInsideCategoryFolders() {
        #expect(SafetyPolicy.isSafe(Home.library("Caches/com.example.app")))
        #expect(SafetyPolicy.isSafe(Home.library("Preferences/com.example.app.plist")))
        #expect(SafetyPolicy.isSafe(Home.path(".Trash/old.zip")))
        #expect(SafetyPolicy.isSafe(URL(filePath: "/Library/Caches/com.example.app")))
        #expect(SafetyPolicy.isSafe(URL(filePath: "/Applications/Example.app")))
        #expect(SafetyPolicy.isSafe(URL(filePath: "/tmp/leftover.txt")))
        #expect(SafetyPolicy.isSafe(URL(filePath: "/private/tmp/leftover.txt")))
        if let temp = FileScanner.darwinUserTempDirectory {
            #expect(SafetyPolicy.isSafe(temp.appending(path: "com.example.app")))
            #expect(!SafetyPolicy.isSafe(temp))
        }
    }

    @Test func applicationsFolderOnlyAllowsAppBundles() {
        #expect(!SafetyPolicy.isSafe(URL(filePath: "/Applications/Utilities")))
        #expect(!SafetyPolicy.isSafe(URL(filePath: "/Applications/Vendor Folder")))
        #expect(SafetyPolicy.isSafe(URL(filePath: "/Applications/Vendor Folder/Tool.app")))
    }

    @Test func resolvesDotDotBeforeChecking() {
        #expect(!SafetyPolicy.isSafe(Home.library("Caches/../Preferences")))
        #expect(!SafetyPolicy.isSafe(URL(filePath: "/Library/Caches/../../System")))
    }
}

struct BundleIDTests {
    @Test(arguments: [
        ("com.foo.Bar.plist", "com.foo.Bar"),
        ("com.foo.Bar.savedState", "com.foo.Bar"),
        ("group.com.foo.shared", "com.foo.shared"),
        ("ABCDE12345.com.foo.Bar", "com.foo.Bar"),
        ("com.foo.Bar.0C5F1C2E-9A6B-4C55-9F2F-3D1E2B3A4C5D.plist", "com.foo.Bar"),
    ])
    func extractsIdentifiers(_ name: String, _ expected: String) {
        #expect(BundleID.identifier(fromFileName: name) == expected)
    }

    @Test(arguments: ["Google", "Slack", "foo.bar", "something.plist", "My.Cool.App", "readme.txt.bak"])
    func ignoresNonIdentifiers(_ name: String) {
        #expect(BundleID.identifier(fromFileName: name) == nil)
    }

    @Test func ownershipMatchesParentsAndChildren() {
        let installed = InstalledIdentifiers(["com.tinyspeck.slackmacgap", "com.google.Chrome"])
        #expect(installed.owns("com.tinyspeck.slackmacgap"))
        #expect(installed.owns("com.tinyspeck.slackmacgap.ShipIt"))
        #expect(installed.owns("COM.GOOGLE.CHROME"))
        #expect(!installed.owns("com.google.Drive"))
        #expect(installed.sharesVendor(with: "com.google.Drive"))
        #expect(!installed.owns("com.spotify.client"))
        #expect(!installed.sharesVendor(with: "com.spotify.client"))
    }
}
