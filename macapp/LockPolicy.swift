import Foundation

struct ProtectedApp: Codable, Equatable {
    let bundleID: String
    let name: String
    let path: String
}
struct AuthenticationTicket: Equatable {
    let generation: UInt64
    let appID: String?
}

// All calls run on the main thread. Only decisions live here: no AppKit, no
// biometric prompt, and no persistence side effects. Process IDs bind a grant
// to one launch of an app, and generation invalidates late authentication.
struct LockPolicy {
    static let inactivityTimeout: TimeInterval = 5 * 60
    private(set) var apps: [ProtectedApp]
    private(set) var isInactive = false
    private struct Grant { let pid: Int32; var lastActivity: TimeInterval }
    private var grants: [String: Grant] = [:]
    private var lastInputAt: TimeInterval?
    private var generation: UInt64 = 0
    private let clock: () -> TimeInterval
    init(apps: [ProtectedApp] = [], clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) { self.apps = apps; self.clock = clock }
    func app(_ id: String) -> ProtectedApp? { apps.first { $0.bundleID == id } }
    func isUnlocked(_ id: String, pid: Int32) -> Bool {
        guard let grant = grants[id], grant.pid == pid else { return false }
        let elapsed = clock() - grant.lastActivity
        return elapsed.isFinite && elapsed >= 0 && elapsed < Self.inactivityTimeout
    }
    // App activation is use, but may only extend a still-valid grant.
    mutating func recordUse(_ id: String, pid: Int32) {
        guard isUnlocked(id, pid: pid) else { return }
        grants[id]?.lastActivity = clock()
    }
    mutating func protect(_ app: ProtectedApp) {
        guard self.app(app.bundleID) == nil else { return }
        apps.append(app); apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        lock(app.bundleID)
    }
    mutating func lock(_ id: String) { grants.removeValue(forKey: id); generation &+= 1 }
    mutating func lockAll() { grants.removeAll(); generation &+= 1 }
    // Read only input timing, and attribute new input to the foreground app.
    // An idle app expires even while another app keeps the system active.
    mutating func updateActivity(idleSeconds: TimeInterval, activeAppID: String? = nil, activePID: Int32? = nil) -> Bool {
        let now = clock()
        let inactive = !idleSeconds.isFinite || idleSeconds < 0 || idleSeconds >= Self.inactivityTimeout
        let enteredIdle = inactive && !isInactive
        isInactive = inactive
        if enteredIdle { lockAll(); lastInputAt = nil; return true }
        let expired = grants.filter { !isUnlocked($0.key, pid: $0.value.pid) }.map(\.key)
        if !expired.isEmpty { expired.forEach { grants.removeValue(forKey: $0) }; generation &+= 1 }
        if !inactive {
            let inputAt = now - idleSeconds
            // Ignore tiny sampling differences in the OS clock; polling alone
            // must not keep the foreground app unlocked while the user is away.
            let newInput = lastInputAt.map { inputAt > $0 + 0.02 } ?? true
            if newInput {
                lastInputAt = inputAt
                if let id = activeAppID, let pid = activePID, isUnlocked(id, pid: pid),
                   let previous = grants[id]?.lastActivity, inputAt > previous {
                    grants[id]?.lastActivity = min(now, inputAt)
                }
            }
        }
        return !expired.isEmpty
    }
    mutating func invalidateAuthentication() { generation &+= 1 }
    func ticket(for appID: String? = nil) -> AuthenticationTicket { AuthenticationTicket(generation: generation, appID: appID) }
    func accepts(_ ticket: AuthenticationTicket) -> Bool { !isInactive && ticket.generation == generation }
    mutating func unlock(_ id: String, pid: Int32, ticket: AuthenticationTicket) -> Bool {
        guard ticket.appID == id, accepts(ticket), app(id) != nil else { return false }
        grants[id] = Grant(pid: pid, lastActivity: clock())
        return true
    }
    mutating func remove(_ id: String, ticket: AuthenticationTicket) -> Bool {
        guard ticket.appID == id, accepts(ticket) else { return false }
        apps.removeAll { $0.bundleID == id }
        lock(id)
        return true
    }
}
