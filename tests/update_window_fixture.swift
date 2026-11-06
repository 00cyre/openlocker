// Disposable GUI fixture for tests/update_windows.py. Never reads or edits a
// user's documents/protection settings; the only target PID is the test child.
import AppKit

final class UpdateWindowFixture: NSObject, NSApplicationDelegate {
    var windows: [NSWindow] = []
    var fields: [NSTextField] = []
    var timer: Timer?
    let shields = WindowShield()
    let directory = URL(fileURLWithPath: CommandLine.arguments[1])
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.count == 3, let pid = Int32(CommandLine.arguments[2]) {
            NSApp.setActivationPolicy(.accessory)
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.shields.refresh([ShieldTarget(pid: pid, name: "Disposable update test")])
                let state: [String: Any] = ["pid": ProcessInfo.processInfo.processIdentifier, "covered": self.shields.hasVisibleWindows(for: pid)]
                if let data = try? JSONSerialization.data(withJSONObject: state) {
                    try? data.write(to: self.directory.appendingPathComponent("shield-state.json"), options: [.atomic])
                }
                if FileManager.default.fileExists(atPath: self.directory.appendingPathComponent("stop-shield").path) { NSApp.terminate(nil) }
            }
            return
        }
        NSApp.setActivationPolicy(.regular)
        for index in 0..<2 {
            let window = NSWindow(contentRect: NSRect(x: 120 + index * 120, y: 160 + index * 100, width: 520, height: 260),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "OpenLocker update test \(index + 1)"
            window.isReleasedWhenClosed = false
            let field = NSTextField(string: "Unsaved test draft \(index + 1) stays intact")
            field.frame = NSRect(x: 30, y: 110, width: 460, height: 30)
            window.contentView!.addSubview(field)
            window.orderFront(nil)
            windows.append(window); fields.append(field)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let state: [String: Any] = ["pid": ProcessInfo.processInfo.processIdentifier,
                "windows": self.windows.enumerated().map { index, window in ["id": window.windowNumber, "visible": window.isVisible,
                    "minimized": window.isMiniaturized, "draft": self.fields[index].stringValue] as [String: Any] }]
            if let data = try? JSONSerialization.data(withJSONObject: state) {
                try? data.write(to: self.directory.appendingPathComponent("window-state.json"), options: [.atomic])
            }
            if FileManager.default.fileExists(atPath: self.directory.appendingPathComponent("stop-window").path) { NSApp.terminate(nil) }
        }
    }
}
@main
struct FixtureMain {
    static func main() {
        let delegate = UpdateWindowFixture()
        NSApplication.shared.delegate = delegate
        withExtendedLifetime(delegate) { NSApplication.shared.run() }
    }
}
