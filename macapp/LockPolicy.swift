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
    private(set) var apps: [ProtectedApp]
    private var grants: [String: Int32] = [:]
    private var generation: UInt64 = 0
    init(apps: [ProtectedApp] = []) { self.apps = apps }
    func app(_ id: String) -> ProtectedApp? { apps.first { $0.bundleID == id } }
    func isUnlocked(_ id: String, pid: Int32) -> Bool { grants[id] == pid }
    mutating func protect(_ app: ProtectedApp) {
        guard self.app(app.bundleID) == nil else { return }
        apps.append(app); apps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        lock(app.bundleID)
    }
    mutating func lock(_ id: String) { grants.removeValue(forKey: id); generation &+= 1 }
    mutating func lockAll() { grants.removeAll(); generation &+= 1 }
    mutating func invalidateAuthentication() { generation &+= 1 }
    func ticket(for appID: String? = nil) -> AuthenticationTicket { AuthenticationTicket(generation: generation, appID: appID) }
    func accepts(_ ticket: AuthenticationTicket) -> Bool { ticket.generation == generation }
    mutating func unlock(_ id: String, pid: Int32, ticket: AuthenticationTicket) -> Bool {
        guard ticket.appID == id, accepts(ticket), app(id) != nil else { return false }
        grants[id] = pid
        return true
    }
    mutating func remove(_ id: String, ticket: AuthenticationTicket) -> Bool {
        guard ticket.appID == id, accepts(ticket) else { return false }
        apps.removeAll { $0.bundleID == id }
        lock(id)
        return true
    }
}

struct MinimizeTracker {
    private var previous: [Int: Bool] = [:]
    mutating func update(_ windows: [Int: Bool]) -> Bool {
        defer { previous = windows }
        return windows.contains { previous[$0.key] == false && $0.value }
    }
}
