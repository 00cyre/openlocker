import Foundation
@main
struct UpdateRecoveryTests {
    static func main() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("openlocker-recovery-test-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: dir) }
        let file = dir.appendingPathComponent("update-session.json")
        let now = Date()
        let visible = AppRecoveryRecord(bundleID: "test.editor", path: "/Applications/Editor.app", processID: 101, wasHidden: false, wasLocked: false)
        let hidden = AppRecoveryRecord(bundleID: "test.notes", path: "/Applications/Notes.app", processID: 102, wasHidden: true, wasLocked: true)
        let protected = [visible.bundleID: visible.path, hidden.bundleID: hidden.path]
        let token = try UpdateRecovery.save([visible, hidden], to: file, now: now)
        let mode = try fm.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        precondition(mode == 0o600)
        let wrong = try UpdateRecovery.consume(from: file, token: UUID(), now: now)
        precondition(wrong == nil && fm.fileExists(atPath: file.path))
        let restored = try UpdateRecovery.consume(from: file, token: token, now: now.addingTimeInterval(20))!
        precondition(restored.apps == [visible, hidden], "Remember running app and lock state")
        precondition(restored.missingApps(running: Set(protected.keys), protected: protected).isEmpty, "Leave surviving apps untouched")
        precondition(restored.missingApps(running: [visible.bundleID], protected: protected) == [hidden])
        precondition(restored.missingApps(running: [], protected: [:]).isEmpty, "Never reopen an app removed from protection")
        precondition(restored.missingApps(running: [], protected: [visible.bundleID: "/different.app"]).isEmpty)
        let twice = try UpdateRecovery.consume(from: file, token: token, now: now)
        precondition(twice == nil, "Consume only once")
        let token2 = try UpdateRecovery.save([visible], to: file, now: now)
        let expired = try UpdateRecovery.consume(from: file, token: token2, now: now.addingTimeInterval(301))
        precondition(expired == nil)
        print("PASS: update recovery remembers open/locked apps, leaves running apps untouched, and expires once consumed")
    }
}
