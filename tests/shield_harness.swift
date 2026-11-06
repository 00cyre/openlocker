// Manual UI fixture. Separate bundle IDs keep test windows out of real app
// protection settings. No Touch ID bypass exists in the production app.
import AppKit

final class FixtureDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    var gate: NSWindow?
    let shields = WindowShield()
    var timer: Timer?
    func applicationDidFinishLaunching(_ notification: Notification) {
        if Bundle.main.bundleIdentifier == "cc.openlocker.test-window" {
            NSApp.setActivationPolicy(.regular)
            let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 600, height: 380), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "OpenLocker disposable test window"; window.isReleasedWhenClosed = false
            let label = NSTextField(labelWithString: "PRIVATE TEST CONTENT — no real user data")
            label.font = .systemFont(ofSize: 23, weight: .semibold); label.frame = NSRect(x: 35, y: 270, width: 530, height: 50)
            window.contentView!.addSubview(label)
            let field = NSTextField(string: "This text must remain unchanged")
            field.setAccessibilityLabel("Protected test input")
            field.frame = NSRect(x: 35, y: 180, width: 530, height: 35)
            window.contentView!.addSubview(field)
            self.window = window; window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        } else {
            NSApp.setActivationPolicy(.accessory)
            shields.onUnlock = { [weak self] _ in self?.showPrompt() }
            refresh()
            timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in self?.refresh() }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func refresh() {
        let targets = NSRunningApplication.runningApplications(withBundleIdentifier: "cc.openlocker.test-window").map { ShieldTarget(pid: $0.processIdentifier, name: "Test app") }
        shields.refresh(targets)
    }
    func showPrompt() {
        if let gate { gate.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let gate = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 170), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        gate.isReleasedWhenClosed = false; gate.title = "Unlock modal — UI test"; gate.level = .modalPanel
        let label = NSTextField(wrappingLabelWithString: "Input is blocked. The protected app stays open behind a blur.\n\nThis fixture does not authenticate or unlock.")
        label.frame = NSRect(x: 25, y: 30, width: 310, height: 110)
        gate.contentView!.addSubview(label)
        self.gate = gate; gate.center(); gate.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
}
let delegate = FixtureDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
