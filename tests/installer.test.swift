import Foundation

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

        // Invalid bundled identity must fail before touching an existing install.
        let bad = temporary.appendingPathComponent("invalid-payload")
        try fm.copyItem(at: payload, to: bad)
        let badManifest = bad.appendingPathComponent("extension/manifest.json")
        try Data("{\"key\":\"YmFk\",\"version\":\"0.1.0\"}".utf8).write(to: badManifest)
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
        print("Installer checks passed: clean install, paths with spaces, permissions, upgrade, identity rejection, and destination failure.")
    }
}
