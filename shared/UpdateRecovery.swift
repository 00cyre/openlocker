import Foundation

struct AppRecoveryRecord: Codable, Equatable {
    let bundleID: String
    let path: String
    let processID: Int32
    let wasHidden: Bool
    let wasLocked: Bool
}

// A short-lived inventory, not an authentication token. The new process always
// starts locked. Only apps already in the current protected list can reopen.
struct UpdateRecovery: Codable {
    let token: UUID
    let createdAt: Date
    let apps: [AppRecoveryRecord]
    static let lifetime: TimeInterval = 300

    func missingApps(running: Set<String>, protected: [String: String]) -> [AppRecoveryRecord] {
        apps.filter { record in
            guard !running.contains(record.bundleID), let path = protected[record.bundleID] else { return false }
            return URL(fileURLWithPath: path).standardizedFileURL == URL(fileURLWithPath: record.path).standardizedFileURL
        }
    }
    static func save(_ apps: [AppRecoveryRecord], to url: URL, now: Date = Date()) throws -> UUID {
        let recovery = Self(token: UUID(), createdAt: now, apps: apps)
        let data = try JSONEncoder().encode(recovery)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return recovery.token
    }
    static func consume(from url: URL, token: UUID, now: Date = Date()) throws -> Self? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        guard data.count <= 1_000_000 else { return nil }
        let recovery = try JSONDecoder().decode(Self.self, from: data)
        guard recovery.token == token else { return nil }
        try FileManager.default.removeItem(at: url)
        let age = now.timeIntervalSince(recovery.createdAt)
        return age >= 0 && age <= lifetime ? recovery : nil
    }
}
