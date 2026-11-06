import Foundation
@main
struct ActivationRegression {
    static func main() {
        var gateVisible = false
        var covered = false
        var pendingActivations = [(id: "protected.editor", pid: Int32(42), locked: true)]
        while !pendingActivations.isEmpty {
            let event = pendingActivations.removeFirst()
            for effect in activationCommands(appID: event.id, pid: event.pid, locked: event.locked, hasPrompt: gateVisible) {
                switch effect {
                case .hide:
                    // macOS falls back to the previous app when the foreground
                    // app hides. Delivery follows the current notification.
                    pendingActivations.append((id: "previous.app", pid: 7, locked: false))
                case .cover: covered = true
                case .prompt: gateVisible = true
                case .dismiss: gateVisible = false
                }
            }
        }
        guard gateVisible else {
            fputs("FAIL: reopening a locked app hides it, transfers focus, and dismisses the unlock modal.\n", stderr)
            exit(1)
        }
        guard covered else { fputs("FAIL: protected content is not covered.\n", stderr); exit(1) }
        let switchedAway = activationCommands(appID: "another.app", pid: 9, locked: false, hasPrompt: true)
        precondition(switchedAway == [.dismiss], "An intentional switch should dismiss the prompt while preserving protection")
        print("PASS: reopening keeps the app covered and its unlock modal visible; no focus bounce.")
    }
}
