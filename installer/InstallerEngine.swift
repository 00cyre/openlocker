import CryptoKit
import Foundation
import Darwin

enum InstallScope { case all, chrome }

struct InstallResult {
    let extensionDirectory: URL
    let helperExecutable: URL
    let manifest: URL
    let desktopApp: URL
    let needsAccessibilityRenewal: Bool
}

struct InstallFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct InstallerEngine {
    let payload: URL
    let home: URL
    private let bundledHelper: URL?
    init(payload: URL, home: URL, helper: URL? = nil) {
        self.payload = payload; self.home = home; self.bundledHelper = helper
    }
    private let fm = FileManager.default

    func install(scope: InstallScope = .all) throws -> InstallResult {
        let extensionSource = payload.appendingPathComponent("extension")
        let helperSource = bundledHelper ?? payload.appendingPathComponent("OpenLocker.app")
        let desktopSource = payload.appendingPathComponent("Desktop/OpenLocker.app")
        let manifestData = try Data(contentsOf: extensionSource.appendingPathComponent("manifest.json"))
        guard let manifest = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
              let key = manifest["key"] as? String, let publicKey = Data(base64Encoded: key),
              let version = manifest["version"] as? String, version == "0.1.9" else {
            throw InstallFailure(message: "The bundled extension is incomplete. Download OpenLocker again.")
        }
        let extensionID = SHA256.hash(data: publicKey).prefix(16).flatMap { byte in
            [Character(UnicodeScalar(97 + Int(byte >> 4))!), Character(UnicodeScalar(97 + Int(byte & 15))!)]
        }
        guard "chrome-extension://\(String(extensionID))/" == Config.allowedOrigin,
              fm.isExecutableFile(atPath: helperSource.appendingPathComponent("Contents/MacOS/OpenLocker").path),
              (scope == .chrome || fm.isExecutableFile(atPath: desktopSource.appendingPathComponent("Contents/MacOS/OpenLockerMac").path)) else {
            throw InstallFailure(message: "The bundled helper does not match the extension. Download OpenLocker again.")
        }

        let support = home.appendingPathComponent("Library/Application Support")
        let destination = support.appendingPathComponent("OpenLocker")
        try fm.createDirectory(at: destination, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let lockFD = open(destination.appendingPathComponent(".install-lock").path, O_CREAT | O_RDWR, 0o600)
        guard lockFD >= 0 else { throw InstallFailure(message: "Couldn't prepare the installation lock.") }
        defer { close(lockFD) }
        guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { throw InstallFailure(message: "Another OpenLocker update is already running.") }
        if let installed = NSDictionary(contentsOf: destination.appendingPathComponent("OpenLocker.app/Contents/Info.plist"))?["CFBundleShortVersionString"] as? String,
           installed.compare(version, options: .numeric) == .orderedDescending {
            throw InstallFailure(message: "A newer Chrome helper is already installed. Update the Mac app before running Chrome setup again.")
        }
        let hosts = support.appendingPathComponent("Google/Chrome/NativeMessagingHosts")
        let applications = home.appendingPathComponent("Applications")
        let desktopApp = applications.appendingPathComponent("OpenLocker.app")
        if scope == .all { try CodeIdentity.validate(desktopSource) }
        try CodeIdentity.validate(helperSource)
        let renewalFile = destination.appendingPathComponent("accessibility-renewal-required")
        let identityChanged: Bool
        if scope == .all && fm.fileExists(atPath: desktopApp.path) {
            identityChanged = (try? CodeIdentity.requirement(for: desktopApp))
                .map { !CodeIdentity.satisfies($0, app: desktopSource) } ?? true
        } else {
            // A user may be migrating an already-used source build into ~/Applications.
            identityChanged = scope == .all && fm.fileExists(atPath: destination.appendingPathComponent("protected-apps.json").path)
        }
        try fm.createDirectory(at: hosts, withIntermediateDirectories: true, attributes: nil)
        try fm.createDirectory(at: applications, withIntermediateDirectories: true, attributes: nil)
        if scope == .all && fm.fileExists(atPath: desktopApp.path) {
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
        // Distinguish the managed folder from a developer's unpacked checkout.
        try Data("{\"managed\":true}\n".utf8).write(to: stage.appendingPathComponent("extension/installation.json"))
        try fm.copyItem(at: helperSource, to: stage.appendingPathComponent("OpenLocker.app"))
        if scope == .all { try fm.copyItem(at: desktopSource, to: stage.appendingPathComponent("desktop.app")) }
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
            if scope == .all && fm.fileExists(atPath: desktopApp.path) {
                try fm.moveItem(at: desktopApp, to: stage.appendingPathComponent("backup-desktop.app"))
                desktopBackedUp = true
            }
            if scope == .all {
                try fm.moveItem(at: stage.appendingPathComponent("desktop.app"), to: desktopApp)
                desktopInstalled = true
            }
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
            // Commit this only after all payloads have installed successfully.
            // The app offers an explicit reset of its own old grant, then waits
            // for macOS approval. Never treat an enabled Settings row as trust.
            if identityChanged {
                try Data("OpenLocker changed signing identity. Renew Accessibility approval.\n".utf8)
                    .write(to: renewalFile, options: [.atomic])
            }
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
        return InstallResult(extensionDirectory: destination.appendingPathComponent("extension"), helperExecutable: helper, manifest: hostManifest, desktopApp: desktopApp, needsAccessibilityRenewal: fm.fileExists(atPath: renewalFile.path))
    }
}
