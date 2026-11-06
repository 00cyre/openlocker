import Foundation

struct ReleaseVersion: Comparable, Equatable {
    let parts: [Int]
    let text: String
    init?(_ text: String) {
        let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 3, pieces.allSatisfy({ !$0.isEmpty && $0.count <= 8 && $0.allSatisfy(\.isNumber) && ($0 == "0" || !$0.hasPrefix("0")) }),
              pieces.allSatisfy({ Int($0) != nil }) else { return nil }
        self.parts = pieces.map { Int($0)! }; self.text = text
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }
}

struct OpenLockerRelease {
    let version: ReleaseVersion
    let download: URL
    static func parse(_ data: Data) throws -> Self {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["draft"] as? Bool == false, object["prerelease"] as? Bool == false,
              let tag = object["tag_name"] as? String, tag.hasPrefix("v"), let version = ReleaseVersion(String(tag.dropFirst())),
              let assets = object["assets"] as? [[String: Any]] else { throw UpdateFailure("The update server returned an invalid release.") }
        let name = "OpenLocker-\(version.text)-macOS.dmg"
        let expected = "https://github.com/00cyre/openlocker/releases/download/\(tag)/\(name)"
        guard let asset = assets.first(where: { $0["name"] as? String == name }),
              asset["browser_download_url"] as? String == expected,
              let size = asset["size"] as? Int, size > 0, size <= 100_000_000,
              let url = URL(string: expected) else { throw UpdateFailure("The release has no supported Mac update.") }
        return Self(version: version, download: url)
    }
}
struct UpdateFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct StagedUpdate {
    let folder: URL
    var installer: URL { folder.appendingPathComponent("Install OpenLocker.app") }
    var executable: URL { installer.appendingPathComponent("Contents/MacOS/InstallOpenLocker") }
    func remove() { try? FileManager.default.removeItem(at: folder) }
    func launch(arguments: [String]) throws -> Process {
        let process = Process(); process.executableURL = executable; process.arguments = arguments
        // Never let installer logging corrupt Chrome's native messaging stream.
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); return process
    }
}

enum ReleaseUpdater {
    static func latest() async throws -> OpenLockerRelease {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/00cyre/openlocker/releases/latest")!)
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("OpenLocker", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200, data.count < 1_000_000 else {
            throw UpdateFailure("Couldn't check for updates. Try again when you're online.")
        }
        return try OpenLockerRelease.parse(data)
    }
    static func stage(_ release: OpenLockerRelease, certificate: URL) async throws -> StagedUpdate {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent("openlocker-update-\(UUID().uuidString)")
        try fm.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var staged = false
        defer { if !staged { try? fm.removeItem(at: folder) } }
        let disk = folder.appendingPathComponent("update.dmg")
        var request = URLRequest(url: release.download); request.timeoutInterval = 120
        let (downloaded, response) = try await URLSession.shared.download(for: request)
        defer { try? fm.removeItem(at: downloaded) }
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              let size = try fm.attributesOfItem(atPath: downloaded.path)[.size] as? NSNumber,
              size.intValue > 0, size.intValue <= 100_000_000 else { throw UpdateFailure("The update download is incomplete.") }
        try fm.moveItem(at: downloaded, to: disk)
        // Verify the entire image BEFORE mounting or interpreting its contents.
        try CodeIdentity.validateRelease(disk, certificate: certificate, identifier: "cc.openlocker.disk")
        let mount = folder.appendingPathComponent("mounted")
        try fm.createDirectory(at: mount, withIntermediateDirectories: false)
        try run("/usr/bin/hdiutil", ["attach", "-readonly", "-nobrowse", "-quiet", "-mountpoint", mount.path, disk.path])
        defer { try? run("/usr/bin/hdiutil", ["detach", "-quiet", mount.path]) }
        let source = mount.appendingPathComponent("Install OpenLocker.app")
        try CodeIdentity.validateRelease(source, certificate: certificate, identifier: "cc.openlocker.installer")
        guard let info = NSDictionary(contentsOf: source.appendingPathComponent("Contents/Info.plist")),
              info["CFBundleShortVersionString"] as? String == release.version.text else { throw UpdateFailure("The downloaded version doesn't match the release.") }
        let result = StagedUpdate(folder: folder)
        try fm.copyItem(at: source, to: result.installer)
        try CodeIdentity.validateRelease(result.installer, certificate: certificate, identifier: "cc.openlocker.installer")
        staged = true
        return result
    }
    private static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateFailure("Couldn't prepare the update. Your current installation was kept.") }
    }
}
