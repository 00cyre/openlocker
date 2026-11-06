import Foundation

@main
struct AccessibilityApprovalTests {
    static func main() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("openlocker-approval-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: temp) }
        let suite = "openlocker-approval-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let marker = temp.appendingPathComponent("renewal")
        try Data().write(to: marker)
        var trusted = false, resets = 0, failReset = true
        let approval = AccessibilityApproval(renewalFile: marker, defaults: defaults, trusted: { trusted }, reset: {
            resets += 1
            if failReset { throw NSError(domain: "test", code: 1) }
        })
        precondition(approval.state == .needsRenewal)
        for _ in 0..<10 { approval.refresh() }
        precondition(resets == 0, "Polling must never reset permissions")
        do { try approval.repair(); fatalError("Reset failure was hidden") } catch { }
        precondition(!approval.repairPerformed && FileManager.default.fileExists(atPath: marker.path))
        failReset = false
        try approval.repair()
        precondition(approval.state == .needsApproval && resets == 2)
        for _ in 0..<10 { try approval.repair(); approval.refresh() }
        precondition(resets == 2, "Repeated clicks must not erase a fresh pending approval")
        let waiting = AccessibilityApproval(renewalFile: marker, defaults: defaults, trusted: { trusted }, reset: { resets += 1 })
        precondition(waiting.state == .needsApproval, "A restart while awaiting approval must not repeat the renewal")
        trusted = true
        precondition(approval.refresh() == .ready)
        try approval.repair()
        precondition(resets == 2, "Never reset working access")
        // Remember prior approval so a source rebuild also offers renewal, even
        // when the installer did not run and no marker is available.
        trusted = false
        let restarted = AccessibilityApproval(renewalFile: marker, defaults: defaults, trusted: { trusted }, reset: { resets += 1 })
        precondition(restarted.state == .needsRenewal)
        print("PASS: explicit renewal, retry after failure, no polling resets, and live approval recovery")
    }
}
