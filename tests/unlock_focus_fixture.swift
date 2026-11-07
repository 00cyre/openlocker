import Foundation

// Only macOS effects are substituted. The grant method below is copied from
// main.swift at test time and runs against the real LockPolicy.
struct ActivationOptions: OptionSet {
    let rawValue: Int
    static let activateAllWindows = ActivationOptions(rawValue: 1)
    static let activateIgnoringOtherApps = ActivationOptions(rawValue: 2)
}
final class NSRunningApplication {
    var bundleIdentifier: String? = "test.claude"
    var processIdentifier: Int32 = 42
    var isTerminated = false
    var activationSucceeds = false
    var isActive = false
    var unhideCount = 0
    var activationCount = 0
    func unhide() { unhideCount += 1 }
    func activate(options: ActivationOptions) -> Bool {
        activationCount += 1
        return activationSucceeds
    }
}
final class TestLabel { var stringValue = "" }
final class TestWatcher {
    var restored = false
    func restoreAWindow() { restored = true }
}
final class GrantHarness {
    var now: TimeInterval = 100
    lazy var policy = LockPolicy(apps: [app], clock: { [unowned self] in self.now })
    let app = ProtectedApp(bundleID: "test.claude", name: "Claude", path: "/Applications/Claude.app")
    var watchers: [Int32: TestWatcher] = [42: TestWatcher()]
    var messageLabel: TestLabel? = TestLabel()
    var promptDismissed = false
    var protectedAfterRefresh = true
    var alerts = 0
    func syncWatchers() {}
    func refreshShields() { protectedAfterRefresh = !policy.isUnlocked(app.bundleID, pid: 42) }
    func dismissGate(invalidate: Bool = true) {
        promptDismissed = true
        if invalidate { policy.invalidateAuthentication() }
    }
    func lock(_ id: String) { policy.lock(id); refreshShields() }
    func alert(_ title: String, _ detail: String) { alerts += 1 }
    func complete(_ running: NSRunningApplication, ticket: AuthenticationTicket? = nil) {
        grant(app, running: running, ticket: ticket ?? policy.ticket(for: app.bundleID))
    }
/* APP_GRANT_METHOD */
}

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
for activationSucceeds in [false, true] {
    let test = GrantHarness()
    let running = NSRunningApplication()
    running.activationSucceeds = activationSucceeds
    test.complete(running)
    test.now += 0.15
    check(test.policy.isUnlocked(test.app.bundleID, pid: 42), "successful Touch ID was revoked after 0.15 seconds when activationSucceeded=\(activationSucceeds)")
    check(test.promptDismissed && !test.protectedAfterRefresh, "successful authentication must remove the modal and shield")
    check(test.watchers[42]?.restored == true && running.unhideCount == 1, "the app's existing window must be preserved/restored")
    check(test.alerts == 0, "a declined focus request must not open another modal")
    test.now = 399.9
    check(test.policy.isUnlocked(test.app.bundleID, pid: 42), "the grant must last five minutes without use")
    test.now = 400
    check(!test.policy.isUnlocked(test.app.bundleID, pid: 42), "the normal five-minute expiry must remain enforced")
}
for invalid in ["stale-ticket", "terminated", "wrong-app"] {
    let test = GrantHarness()
    let running = NSRunningApplication()
    let ticket = test.policy.ticket(for: test.app.bundleID)
    if invalid == "stale-ticket" { test.policy.lockAll() }
    if invalid == "terminated" { running.isTerminated = true }
    if invalid == "wrong-app" { running.bundleIdentifier = "other.app" }
    test.complete(running, ticket: ticket)
    check(!test.policy.isUnlocked(test.app.bundleID, pid: 42), "\(invalid) must not grant access")
    check(!test.promptDismissed && running.activationCount == 0 && running.unhideCount == 0, "\(invalid) must not present the app")
}
print("PASS: the production unlock flow preserves Touch ID grants when macOS declines focus, keeps five-minute expiry, and rejects invalid authentication/processes.")
