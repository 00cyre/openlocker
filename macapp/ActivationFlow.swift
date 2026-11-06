import Foundation

enum ActivationCommand: Equatable {
    case hide(Int32)
    case cover(Int32)
    case prompt(String)
    case dismiss
}

// Workspace events and effects form a feedback loop: hiding an app can activate
// another app. Keeping this sequence explicit makes that loop reproducible.
func activationCommands(appID: String, pid: Int32, locked: Bool, hasPrompt: Bool) -> [ActivationCommand] {
    if locked { return [.cover(pid), .prompt(appID)] }
    return hasPrompt ? [.dismiss] : []
}
