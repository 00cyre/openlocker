import CryptoKit
import Foundation

struct InstallResult {
    let extensionDirectory: URL
    let helperExecutable: URL
    let manifest: URL
    let desktopApp: URL
}

struct InstallFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct InstallerEngine {
    let payload: URL
    let home: URL
    private let fm = FileManager.default

    func install() throws -> InstallResult {
        let extensionSource = payload.appendingPathComponent("extension")
        let helperSource = payload.appendingPathComponent("OpenLocker.app")
        let desktopSource = payload.appendingPathComponent("Desktop/OpenLocker.app")
        let manifestData = try Data(contentsOf: extensionSource.appendingPathComponent("manifest.json"))
        guard let manifest = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
              let key = manifest["key"] as? String, let publicKey = Data(base64Encoded: key),
              let version = manifest["version"] as? String, version == "0.1.0" else {
            throw InstallFailure(message: "The bundled extension is incomplete. Download OpenLocker again.")
        }
        let extensionID = SHA256.hash(data: publicKey).prefix(16).flatMap { byte in
            [Character(UnicodeScalar(97 + Int(byte >> 4))!), Character(UnicodeScalar(97 + Int(byte & 15))!)]
        }
        guard "chrome-extension://\(String(extensionID))/" == Config.allowedOrigin,
              fm.isExecutableFile(atPath: helperSource.appendingPathComponent("Contents/MacOS/OpenLocker").path),
              fm.isExecutableFile(atPath: desktopSource.appendingPathComponent("Contents/MacOS/OpenLockerMac").path) else {
            throw InstallFailure(message: "The bundled helper does not match the extension. Download OpenLocker again.")
        }

        let support = home.appendingPathComponent("Library/Application Support")
        let destination = support.appendingPathComponent("OpenLocker")
        let hosts = support.appendingPathComponent("Google/Chrome/NativeMessagingHosts")
        let applications = home.appendingPathComponent("Applications")
        let desktopApp = applications.appendingPathComponent("OpenLocker.app")
        try fm.createDirectory(at: destination, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.createDirectory(at: hosts, withIntermediateDirectories: true, attributes: nil)
        try fm.createDirectory(at: applications, withIntermediateDirectories: true, attributes: nil)
        if fm.fileExists(atPath: desktopApp.path) {
            let info = NSDictionary(contentsOf: desktopApp.appendingPathComponent("Contents/Info.plist"))
            guard info?["CFBundleIdentifier"] as? String == "cc.openlocker.mac" else {
                throw InstallFailure(message: "Another app named OpenLocker already exists in your Applications folder. Move it before installing.")
            }
        }
        let stage = destination.appendingPathComponent(".install-\(UUID().uuidString)")
        try fm.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: stage) }

        // Copy and validate before replacing an existing installation. Keep the
        // same extension path so Chrome retains the user's existing settings.
        try fm.copyItem(at: extensionSource, to: stage.appendingPathComponent("extension"))
        try fm.copyItem(at: helperSource, to: stage.appendingPathComponent("OpenLocker.app"))
        try fm.copyItem(at: desktopSource, to: stage.appendingPathComponent("desktop.app"))
        let helper = destination.appendingPathComponent("OpenLocker.app/Contents/MacOS/OpenLocker")
        let hostManifest = hosts.appendingPathComponent("cc.openlocker.touchid.json")
        let host: [String: Any] = [
            "name": "cc.openlocker.touchid", "description": "OpenLocker Touch ID helper",
            "path": helper.path, "type": "stdio", "allowed_origins": [Config.allowedOrigin]
        ]
        let encoded = try JSONSerialization.data(withJSONObject: host, options: [.prettyPrinted, .sortedKeys])
        let oldManifest = fm.fileExists(atPath: hostManifest.path) ? try Data(contentsOf: hostManifest) : nil
        var backedUp: [String] = []
        var installed: [String] = []
        var desktopBackedUp = false
        var desktopInstalled = false
        do {
            if fm.fileExists(atPath: desktopApp.path) {
                try fm.moveItem(at: desktopApp, to: stage.appendingPathComponent("backup-desktop.app"))
                desktopBackedUp = true
            }
            try fm.moveItem(at: stage.appendingPathComponent("desktop.app"), to: desktopApp)
            desktopInstalled = true
            for name in ["OpenLocker.app", "extension"] {
                let target = destination.appendingPathComponent(name)
                if fm.fileExists(atPath: target.path) {
                    try fm.moveItem(at: target, to: stage.appendingPathComponent("backup-\(name)"))
                    backedUp.append(name)
                }
                try fm.moveItem(at: stage.appendingPathComponent(name), to: target)
                installed.append(name)
            }
            try encoded.write(to: hostManifest, options: [.atomic])
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: hostManifest.path)
        } catch {
            if desktopInstalled { try? fm.removeItem(at: desktopApp) }
            if desktopBackedUp { try? fm.moveItem(at: stage.appendingPathComponent("backup-desktop.app"), to: desktopApp) }
            for name in installed.reversed() { try? fm.removeItem(at: destination.appendingPathComponent(name)) }
            for name in backedUp.reversed() {
                try? fm.moveItem(at: stage.appendingPathComponent("backup-\(name)"), to: destination.appendingPathComponent(name))
            }
            if let oldManifest { try? oldManifest.write(to: hostManifest, options: [.atomic]) }
            else { try? fm.removeItem(at: hostManifest) }
            throw error
        }
        return InstallResult(extensionDirectory: destination.appendingPathComponent("extension"), helperExecutable: helper, manifest: hostManifest, desktopApp: desktopApp)
    }
}
