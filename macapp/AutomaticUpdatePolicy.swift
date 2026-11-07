import Foundation

// Installation is allowed only during a quiet period, both before downloading
// and immediately before handing off to the verified installer.
struct AutomaticUpdatePolicy {
    static let preferenceKey = "automaticallyInstallUpdates"
    static let idleDelay: TimeInterval = 5 * 60
    static let retryDelay: TimeInterval = 60 * 60
    private(set) var failedAt: TimeInterval?

    func allowsInstallation(enabled: Bool, hasUpdate: Bool, idleSeconds: TimeInterval,
                            interactionInProgress: Bool, now: TimeInterval) -> Bool {
        guard enabled, hasUpdate, !interactionInProgress,
              now.isFinite, now >= 0, idleSeconds.isFinite,
              idleSeconds >= Self.idleDelay else { return false }
        if let failedAt { return now - failedAt >= Self.retryDelay }
        return true
    }
    mutating func recordFailure(now: TimeInterval) { failedAt = now }
    mutating func resetRetry() { failedAt = nil }
}
