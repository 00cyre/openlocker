import AppKit
import Foundation
import LocalAuthentication

// Chrome invokes this executable once per sendNativeMessage request.
// stdout is exclusively the length-prefixed JSON protocol.
func reply(_ value: [String: Any]) -> Never {
    guard let data = try? JSONSerialization.data(withJSONObject: value) else { exit(1) }
    var size = UInt32(data.count).littleEndian
    withUnsafeBytes(of: &size) { FileHandle.standardOutput.write(Data($0)) }
    FileHandle.standardOutput.write(data)
    exit(0)
}

func readExactly(_ size: Int) -> Data? {
    var result = Data()
    while result.count < size {
        let part = FileHandle.standardInput.readData(ofLength: size - result.count)
        if part.isEmpty { return nil }
        result.append(part)
    }
    return result
}

func message(for error: Error?) -> String {
    guard let error = error as? LAError else { return "Touch ID could not complete. Please try again." }
    switch error.code {
    case .userCancel, .appCancel, .systemCancel: return "Cancelled. Your site is still locked."
    case .biometryLockout: return "Touch ID is temporarily locked. Unlock your Mac with its password, then try Touch ID again."
    case .biometryNotEnrolled: return "Add a fingerprint in System Settings → Touch ID & Password."
    case .biometryNotAvailable: return "Touch ID is unavailable. Use a Mac with Touch ID and open its lid."
    case .authenticationFailed: return "Fingerprint not recognized. Your site is still locked."
    default: return "Touch ID could not complete. Please try again."
    }
}

guard CommandLine.arguments.count == 2,
      CommandLine.arguments[1] == Config.allowedOrigin else { exit(1) }
guard let header = readExactly(4) else { exit(1) }
let size = header.enumerated().reduce(UInt32(0)) { $0 | (UInt32($1.element) << (8 * $1.offset)) }
guard size > 0, size <= 16_384, let data = readExactly(Int(size)),
      let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let id = request["id"] as? String, UUID(uuidString: id) != nil,
      let operation = request["operation"] as? String else { exit(1) }

let context = LAContext()
context.localizedFallbackTitle = ""
context.localizedCancelTitle = "Keep locked"
context.touchIDAuthenticationAllowableReuseDuration = 0
var error: NSError?
let available = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) && context.biometryType == .touchID

if operation == "status" {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let runningManaged = request["extensionManaged"] as? Bool == true
    if runningManaged, let version = request["extensionVersion"] as? String { try? ExtensionInstallation.report(version, home: home) }
    let installation = ExtensionInstallation.read(home: home)
    var response: [String: Any] = ["id": id, "available": available, "version": "0.1.12", "supportsUpdates": true,
        "extensionManaged": installation != nil, "runningExtensionManaged": runningManaged,
        "message": available ? "Touch ID is ready." : message(for: error)]
    if let installation { response["installedExtensionVersion"] = installation.installed.text }
    reply(response)
}
if operation == "update-extension" {
    Task {
        do {
            let release = try await ReleaseUpdater.latest()
            let current = ReleaseVersion(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0")!
            guard release.version >= current else { throw UpdateFailure("A newer helper is already installed.") }
            guard let certificate = Bundle.main.url(forResource: "ReleaseCertificate", withExtension: "cer") else { throw UpdateFailure("The signing certificate is missing. Reinstall OpenLocker.") }
            let staged = try await ReleaseUpdater.stage(release, certificate: certificate)
            defer { staged.remove() }
            let process = try staged.launch(arguments: ["--update-chrome"])
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw UpdateFailure("The update couldn't be installed. Your existing files were kept.") }
            reply(["id": id, "success": true, "version": release.version.text])
        } catch { reply(["id": id, "success": false, "message": error.localizedDescription]) }
    }
    RunLoop.main.run()
    exit(1)
}
guard operation == "authenticate" else { reply(["id": id, "success": false, "message": "Unsupported operation."]) }
guard let domain = request["domain"] as? String, domain.count <= 253,
      domain.range(of: #"^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)*[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$"#, options: .regularExpression) != nil
else { reply(["id": id, "success": false, "message": "Invalid domain."]) }
guard available else { reply(["id": id, "success": false, "message": message(for: error)]) }

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
// Do not activate a separate app/window: the system owns the Touch ID sheet.
context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                       localizedReason: "access \(domain) in OpenLocker") { success, authError in
    DispatchQueue.main.async {
        reply(["id": id, "success": success, "message": success ? "Unlocked." : message(for: authError)])
    }
}
DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
    context.invalidate()
    reply(["id": id, "success": false, "message": "Touch ID timed out. Your site is still locked."])
}
app.run()
