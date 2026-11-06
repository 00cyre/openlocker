import Foundation

/// A single setup session. Only an explicit repair action may revoke an old grant.
final class AccessibilityApproval {
    enum State: Equatable { case needsApproval, needsRenewal, ready }
    private let trusted: () -> Bool
    private let reset: () throws -> Void
    private let renewalFile: URL
    private let defaults: UserDefaults
    private(set) var state: State = .needsApproval
    private(set) var repairPerformed = false

    init(renewalFile: URL, defaults: UserDefaults = .standard,
         trusted: @escaping () -> Bool, reset: @escaping () throws -> Void) {
        self.renewalFile = renewalFile; self.defaults = defaults
        self.trusted = trusted; self.reset = reset
        refresh()
    }
    @discardableResult func refresh() -> State {
        if trusted() {
            state = .ready
            defaults.set(true, forKey: "accessibilityWasApproved")
            try? FileManager.default.removeItem(at: renewalFile)
        } else if !repairPerformed && (FileManager.default.fileExists(atPath: renewalFile.path) || defaults.bool(forKey: "accessibilityWasApproved")) {
            state = .needsRenewal
        } else { state = .needsApproval }
        return state
    }
    func repair() throws {
        // A stale UI click must never reset a grant that has just become valid.
        guard refresh() != .ready, !repairPerformed else { return }
        try reset()
        repairPerformed = true
        defaults.set(false, forKey: "accessibilityWasApproved")
        try? FileManager.default.removeItem(at: renewalFile)
        state = .needsApproval
    }
}
