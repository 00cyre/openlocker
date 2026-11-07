import Foundation

// This is display-only update state. It never grants access to apps or sites.
struct ExtensionInstallation {
    let installed: ReleaseVersion
    let reported: ReleaseVersion?
    var needsReload: Bool { reported.map { installed > $0 } ?? true }
    static func support(_ home: URL) -> URL { home.appendingPathComponent("Library/Application Support/OpenLocker") }
    static func read(home: URL) -> ExtensionInstallation? {
        let folder = support(home)
        guard let marker = try? Data(contentsOf: folder.appendingPathComponent("extension/installation.json")),
              let managed = try? JSONSerialization.jsonObject(with: marker) as? [String: Any], managed["managed"] as? Bool == true,
              let data = try? Data(contentsOf: folder.appendingPathComponent("extension/manifest.json")),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = manifest["version"] as? String, let installed = ReleaseVersion(value) else { return nil }
        let receipt = (try? Data(contentsOf: folder.appendingPathComponent("extension-runtime.json")))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] }
        let reported = receipt?["version"].flatMap(ReleaseVersion.init)
        return ExtensionInstallation(installed: installed, reported: reported)
    }
    static func report(_ version: String, home: URL) throws {
        guard ReleaseVersion(version) != nil else { return }
        let folder = support(home)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let destination = folder.appendingPathComponent("extension-runtime.json")
        try JSONSerialization.data(withJSONObject: ["version": version]).write(to: destination, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }
}
