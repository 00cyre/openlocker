import Foundation

@main
struct AccessibilityUpgradeTests {
    static func main() throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let payload = root.appendingPathComponent("build/installer/Install OpenLocker.app/Contents/Resources/Payload")
        let temp = fm.temporaryDirectory.appendingPathComponent("openlocker-upgrade-\(UUID().uuidString)")
        try fm.createDirectory(at: temp, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: temp) }
        let home = temp.appendingPathComponent("home")
        let original = try InstallerEngine(payload: payload, home: home).install()
        precondition(!original.needsAccessibilityRenewal)
        let same = try InstallerEngine(payload: payload, home: home).install()
        precondition(!same.needsAccessibilityRenewal, "Reinstalling the same identity must preserve approval")
        let oldRequirement = try CodeIdentity.requirement(for: original.desktopApp)
        let config = home.appendingPathComponent("Library/Application Support/OpenLocker/protected-apps.json")
        let saved = Data("[]".utf8)
        try saved.write(to: config)
        let changed = temp.appendingPathComponent("payload")
        try fm.copyItem(at: payload, to: changed)
        let app = changed.appendingPathComponent("Desktop/OpenLocker.app")
        let plist = app.appendingPathComponent("Contents/Info.plist")
        let info = NSMutableDictionary(contentsOf: plist)!
        info["CFBundleVersion"] = "987"
        precondition(info.write(to: plist, atomically: true))
        let resign = Process(); resign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        resign.arguments = ["--force", "--sign", "-", "--identifier", "cc.openlocker.mac", app.path]
        try resign.run(); resign.waitUntilExit(); precondition(resign.terminationStatus == 0)
        precondition(!CodeIdentity.satisfies(oldRequirement, app: app), "Fixture must change the actual code requirement")
        // Reproduce the user's update: the bundle ID and path stay identical,
        // but the ad-hoc designated requirement no longer matches the old app.
        _ = try InstallerEngine(payload: changed, home: home).install()
        let renewal = home.appendingPathComponent("Library/Application Support/OpenLocker/accessibility-renewal-required")
        guard fm.fileExists(atPath: renewal.path) else {
            print("FAIL: changed signing identity was installed without an Accessibility renewal flow")
            exit(1)
        }
        let preserved = try Data(contentsOf: config)
        precondition(preserved == saved)
        precondition(fm.fileExists(atPath: original.desktopApp.path))
        print("PASS: a changed signing identity requires explicit renewal and preserves protected apps")
        if let identity = ProcessInfo.processInfo.environment["OPENLOCKER_SIGNING_IDENTITY"], identity != "-" {
            let sign = Process(); sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            sign.arguments = ["--force", "--timestamp=none", "--sign", identity, "--identifier", "cc.openlocker.mac"]
            if let keychain = ProcessInfo.processInfo.environment["OPENLOCKER_SIGNING_KEYCHAIN"] {
                sign.arguments! += ["--keychain", keychain]
            }
            sign.arguments!.append(app.path)
            try sign.run(); sign.waitUntilExit(); precondition(sign.terminationStatus == 0)
            precondition(CodeIdentity.satisfies(oldRequirement, app: app), "Updated release must satisfy the previous release's requirement")
            let stableHome = temp.appendingPathComponent("stable-home")
            _ = try InstallerEngine(payload: payload, home: stableHome).install()
            let update = try InstallerEngine(payload: changed, home: stableHome).install()
            precondition(!update.needsAccessibilityRenewal, "A stable signed update must retain approval")
            print("PASS: changed release binary retains signing identity without permission renewal")
        }
    }
}
