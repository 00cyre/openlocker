import Foundation

@main struct AutomaticUpdateTests {
    static func main() {
        var policy = AutomaticUpdatePolicy()
        func allowed(enabled: Bool = true, newer: Bool = true, idle: TimeInterval = 300,
                     interaction: Bool = false, now: TimeInterval = 1000) -> Bool {
            policy.allowsInstallation(enabled: enabled, hasUpdate: newer, idleSeconds: idle,
                                      interactionInProgress: interaction, now: now)
        }
        precondition(!allowed(enabled: false), "Automatic installation must be explicitly enabled")
        precondition(!allowed(newer: false), "Never reinstall the current version")
        precondition(!allowed(idle: 299.99), "Do not restart while the user is active")
        precondition(allowed(), "Install after five quiet minutes")
        precondition(!allowed(interaction: true), "Authentication, setup, menus, and picking must finish first")
        for invalid in [-1.0, .nan, .infinity] {
            precondition(!allowed(idle: invalid))
            precondition(!allowed(now: invalid))
        }
        // Conditions can change while the signed release downloads. The same
        // policy must reject the handoff if the user returns or opts out.
        precondition(allowed())
        precondition(!allowed(idle: 0))
        precondition(!allowed(enabled: false))
        precondition(!allowed(interaction: true))
        policy.recordFailure(now: 1000)
        precondition(!allowed(now: 4599.99), "Network/verification failures must not cause a retry loop")
        precondition(allowed(now: 4600))
        precondition(!allowed(now: 999), "Clock rollback must not bypass retry delay")
        policy.resetRetry()
        precondition(allowed(), "An explicit preference change can retry")
        print("PASS: automatic updates require opt-in, a newer release, five idle minutes, no active interaction, a final recheck, and bounded retries.")
    }
}
