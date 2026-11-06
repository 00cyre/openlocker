import Foundation
import Darwin

@main
struct InstallerTests {
    static func main() throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let payload = root.appendingPathComponent("build/installer/Install OpenLocker.app/Contents/Resources/Payload")
        let temporary = fm.temporaryDirectory.appendingPathComponent("openlocker-installer-test-\(UUID().uuidString)")
        try fm.createDirectory(at: temporary, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: temporary) }
        let home = temporary.appendingPathComponent("Test User With Spaces")
        let first = try InstallerEngine(payload: payload, home: home).install()
        precondition(fm.isExecutableFile(atPath: first.desktopApp.appendingPathComponent("Contents/MacOS/OpenLockerMac").path))
        precondition(fm.isExecutableFile(atPath: first.helperExecutable.path), "Native helper must remain executable")
        precondition(fm.fileExists(atPath: first.extensionDirectory.appendingPathComponent("manifest.json").path))
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: first.manifest)) as! [String: Any]
        precondition(manifest["path"] as? String == first.helperExecutable.path)
        precondition(manifest["allowed_origins"] as? [String] == [Config.allowedOrigin])
        let mode = try fm.attributesOfItem(atPath: first.manifest.path)[.posixPermissions] as! NSNumber
        precondition(mode.intValue == 0o600)

        // Upgrades must remove obsolete extension files while leaving unrelated
        // support files alone, and keep the extension's stable load location.
        let obsolete = first.extensionDirectory.appendingPathComponent("obsolete.txt")
        try Data("old".utf8).write(to: obsolete)
        let keep = first.extensionDirectory.deletingLastPathComponent().appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: keep)
        let second = try InstallerEngine(payload: payload, home: home).install()
        precondition(first.extensionDirectory == second.extensionDirectory)
        precondition(!fm.fileExists(atPath: obsolete.path))
        precondition(fm.fileExists(atPath: keep.path))

        let desktopBefore = try Data(contentsOf: second.desktopApp.appendingPathComponent("Contents/MacOS/OpenLockerMac"))
        let chromeOnly = try InstallerEngine(payload: payload, home: home).install(scope: .chrome)
        let desktopAfter = try Data(contentsOf: chromeOnly.desktopApp.appendingPathComponent("Contents/MacOS/OpenLockerMac"))
        precondition(desktopBefore == desktopAfter, "Chrome updates must not replace a running desktop app")
        let managed = try JSONSerialization.jsonObject(with: Data(contentsOf: chromeOnly.extensionDirectory.appendingPathComponent("installation.json"))) as! [String: Bool]
        precondition(managed["managed"] == true)
        let chromeHome = temporary.appendingPathComponent("chrome-only")
        let initialChrome = try InstallerEngine(payload: payload, home: chromeHome).install(scope: .chrome)
        precondition(!fm.fileExists(atPath: initialChrome.desktopApp.path))

        let bundledApp = root.appendingPathComponent("build/release-desktop/OpenLocker.app")
        let appSetup = try InstallerEngine(payload: bundledApp.appendingPathComponent("Contents/Resources/Chrome"),
            home: temporary.appendingPathComponent("app-setup"),
            helper: bundledApp.appendingPathComponent("Contents/Helpers/OpenLocker.app")).install(scope: .chrome)
        precondition(fm.isExecutableFile(atPath: appSetup.helperExecutable.path))
        precondition(!fm.fileExists(atPath: appSetup.desktopApp.path), "Chrome setup must not replace the Mac app")

        // A used source build needs an approval migration on its first full install.
        let sourceHome = temporary.appendingPathComponent("source-migration")
        let sourceSupport = sourceHome.appendingPathComponent("Library/Application Support/OpenLocker")
        try fm.createDirectory(at: sourceSupport, withIntermediateDirectories: true)
        let protectedApps = sourceSupport.appendingPathComponent("protected-apps.json")
        let protectedData = Data("[]".utf8)
        try protectedData.write(to: protectedApps)
        let sourceChrome = try InstallerEngine(payload: payload, home: sourceHome).install(scope: .chrome)
        precondition(!sourceChrome.needsAccessibilityRenewal)
        let sourceInstalled = try InstallerEngine(payload: payload, home: sourceHome).install()
        precondition(sourceInstalled.needsAccessibilityRenewal)
        let preservedData = try Data(contentsOf: protectedApps)
        precondition(preservedData == protectedData)

        // An in-flight install must be rejected before any replacement begins.
        let lock = open(sourceSupport.appendingPathComponent(".install-lock").path, O_RDWR)
        precondition(lock >= 0 && flock(lock, LOCK_EX | LOCK_NB) == 0)
        do { _ = try InstallerEngine(payload: payload, home: sourceHome).install(); fatalError("Concurrent install accepted") }
        catch is InstallFailure { }
        close(lock)

        let helperInfo = initialChrome.helperExecutable.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Info.plist")
        let newerInfo = NSMutableDictionary(contentsOf: helperInfo)!
        newerInfo["CFBundleShortVersionString"] = "0.2.0"
        precondition(newerInfo.write(to: helperInfo, atomically: true))
        do { _ = try InstallerEngine(payload: payload, home: chromeHome).install(scope: .chrome); fatalError("Downgrade accepted") }
        catch is InstallFailure { }
        precondition(NSDictionary(contentsOf: helperInfo)?["CFBundleShortVersionString"] as? String == "0.2.0")

        // Invalid bundled identity must fail before touching an existing install.
        let bad = temporary.appendingPathComponent("invalid-payload")
        try fm.copyItem(at: payload, to: bad)
        let badManifest = bad.appendingPathComponent("extension/manifest.json")
        try Data("{\"key\":\"YmFk\",\"version\":\"0.1.5\"}".utf8).write(to: badManifest)
        do { _ = try InstallerEngine(payload: bad, home: home).install(); fatalError("Invalid identity accepted") }
        catch is InstallFailure { }
        precondition(fm.isExecutableFile(atPath: second.helperExecutable.path))

        // A non-directory host destination must fail before replacing any payload.
        let brokenHome = temporary.appendingPathComponent("broken")
        let chrome = brokenHome.appendingPathComponent("Library/Application Support/Google/Chrome")
        try fm.createDirectory(at: chrome, withIntermediateDirectories: true)
        try Data("not a folder".utf8).write(to: chrome.appendingPathComponent("NativeMessagingHosts"))
        do { _ = try InstallerEngine(payload: payload, home: brokenHome).install(); fatalError("Invalid destination accepted") }
        catch { }
        precondition(!fm.fileExists(atPath: brokenHome.appendingPathComponent("Library/Application Support/OpenLocker/OpenLocker.app").path))
        let conflictHome = temporary.appendingPathComponent("conflict")
        let conflict = conflictHome.appendingPathComponent("Applications/OpenLocker.app/Contents")
        try fm.createDirectory(at: conflict, withIntermediateDirectories: true)
        try NSDictionary(dictionary: ["CFBundleIdentifier": "unrelated.app"]).write(to: conflict.appendingPathComponent("Info.plist"))
        do { _ = try InstallerEngine(payload: payload, home: conflictHome).install(); fatalError("An unrelated app was overwritten") }
        catch is InstallFailure { }
        precondition(fm.fileExists(atPath: conflict.appendingPathComponent("Info.plist").path))
        print("Installer checks passed: clean install, app-bundled Chrome setup, scoped updates, source migration, concurrency, downgrade/identity rejection, and destination failure.")
    }
}
