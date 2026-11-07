import Foundation

@main
struct UpdaterTests {
    static func main() throws {
        precondition(ReleaseVersion("1.0.10")! > ReleaseVersion("1.0.9")!)
        for bad in ["1.2", "01.2.3", "1.2.3-beta", "../../1", "999999999.1.1"] { precondition(ReleaseVersion(bad) == nil) }
        let name = "OpenLocker-0.1.12-macOS.dmg"
        let good: [String: Any] = ["tag_name": "v0.1.12", "draft": false, "prerelease": false, "assets": [["name": name, "size": 1234, "browser_download_url": "https://github.com/00cyre/openlocker/releases/download/v0.1.12/\(name)"]]]
        let release = try OpenLockerRelease.parse(JSONSerialization.data(withJSONObject: good))
        precondition(release.version.text == "0.1.12")
        for bad: [String: Any] in [
            ["draft": true], ["prerelease": true], ["tag_name": "v../wrong"],
            ["assets": [["name": name, "size": 1234, "browser_download_url": "https://evil.test/update.dmg"]]],
            ["assets": [["name": name, "size": 200_000_000, "browser_download_url": release.download.absoluteString]]]
        ] {
            var value = good; value.merge(bad) { _, new in new }
            do { _ = try OpenLockerRelease.parse(JSONSerialization.data(withJSONObject: value)); fatalError("Untrusted release accepted") }
            catch is UpdateFailure { }
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let testHome = FileManager.default.temporaryDirectory.appendingPathComponent("openlocker-extension-state-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: testHome) }
        precondition(ExtensionInstallation.read(home: testHome) == nil)
        let extensionFolder = ExtensionInstallation.support(testHome).appendingPathComponent("extension")
        try FileManager.default.createDirectory(at: extensionFolder, withIntermediateDirectories: true)
        try Data(#"{"managed":true}"#.utf8).write(to: extensionFolder.appendingPathComponent("installation.json"))
        try Data(#"{"version":"1.0.10"}"#.utf8).write(to: extensionFolder.appendingPathComponent("manifest.json"))
        precondition(ExtensionInstallation.read(home: testHome)!.needsReload, "Unknown runtime needs an activation reminder")
        try ExtensionInstallation.report("1.0.9", home: testHome)
        precondition(ExtensionInstallation.read(home: testHome)!.needsReload)
        try ExtensionInstallation.report("1.0.10", home: testHome)
        precondition(!ExtensionInstallation.read(home: testHome)!.needsReload, "Matching runtime clears the reminder")
        try ExtensionInstallation.report("invalid", home: testHome)
        precondition(!ExtensionInstallation.read(home: testHome)!.needsReload, "Malformed reports do not overwrite the receipt")
        try ExtensionInstallation.report("1.0.11", home: testHome)
        precondition(!ExtensionInstallation.read(home: testHome)!.needsReload)
        let receiptMode = try FileManager.default.attributesOfItem(atPath: ExtensionInstallation.support(testHome).appendingPathComponent("extension-runtime.json").path)[.posixPermissions] as! NSNumber
        precondition(receiptMode.intValue == 0o600)
        try Data(#"{"managed":false}"#.utf8).write(to: extensionFolder.appendingPathComponent("installation.json"))
        precondition(ExtensionInstallation.read(home: testHome) == nil, "Development folders are never presented as a managed update")
        let certificate = root.appendingPathComponent("signing/release.cer")
        let disk = root.appendingPathComponent("dist/\(name)")
        let signedRelease = ProcessInfo.processInfo.environment["OPENLOCKER_RELEASE"] == "1"
        if signedRelease {
            try CodeIdentity.validateRelease(disk, certificate: certificate, identifier: "cc.openlocker.disk")
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("openlocker-tamper-\(UUID().uuidString).dmg")
            try FileManager.default.copyItem(at: disk, to: temp)
            defer { try? FileManager.default.removeItem(at: temp) }
            let file = try FileHandle(forWritingTo: temp); try file.seek(toOffset: 1024); try file.write(contentsOf: Data("tampered".utf8)); try file.close()
            do { try CodeIdentity.validateRelease(temp, certificate: certificate, identifier: "cc.openlocker.disk"); fatalError("Tampered image accepted") }
            catch { }
        } else {
            do { try CodeIdentity.validateRelease(disk, certificate: certificate, identifier: "cc.openlocker.disk"); fatalError("Unsigned update accepted") }
            catch { }
        }
        print("PASS: version ordering, release URL validation, and signed-image enforcement before mounting")
    }
}
