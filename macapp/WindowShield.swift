import AppKit
import CoreGraphics

struct ShieldTarget {
    let pid: pid_t
    let name: String
}
private final class ShieldPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
private final class ShieldView: NSVisualEffectView {
    var requestUnlock: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(point) ? self : nil }
    override func mouseDown(with event: NSEvent) { requestUnlock?() }
    override func rightMouseDown(with event: NSEvent) { requestUnlock?() }
    override func otherMouseDown(with event: NSEvent) { requestUnlock?() }
    override func scrollWheel(with event: NSEvent) { /* Consume; never forward to the app. */ }
    override func keyDown(with event: NSEvent) { requestUnlock?() }
    override func keyUp(with event: NSEvent) { }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // System app switching remains available. App-specific shortcuts do not
        // reach the protected app while this window owns keyboard focus.
        if event.modifierFlags.contains(.command) && event.keyCode == 48 { return false }
        requestUnlock?(); return true
    }
}

final class WindowShield {
    private struct Cover {
        let panel: ShieldPanel
        let pid: pid_t
    }
    private var covers: [CGWindowID: Cover] = [:]
    var onUnlock: ((pid_t) -> Void)?
    deinit { removeAll() }
    func hasVisibleWindows(for pid: pid_t) -> Bool { covers.values.contains { $0.pid == pid } }
    func removeAll() { covers.values.forEach { $0.panel.orderOut(nil) }; covers.removeAll() }
    func refresh(_ targets: [ShieldTarget]) {
        guard let primary = NSScreen.screens.first else { removeAll(); return }
        let byPID = Dictionary(targets.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var visible = Set<CGWindowID>()
        for window in windows {
            guard let pid = window[kCGWindowOwnerPID as String] as? Int32, let target = byPID[pid],
                  let id = window[kCGWindowNumber as String] as? UInt32,
                  let layer = window[kCGWindowLayer as String] as? Int, layer >= 0, layer <= NSWindow.Level.modalPanel.rawValue,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds), rect.width > 30, rect.height > 30,
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { continue }
            visible.insert(id)
            let frame = NSRect(x: rect.minX, y: primary.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
            let cover: Cover
            if let existing = covers[id] { cover = existing }
            else {
                cover = Cover(panel: makePanel(target: target, frame: frame), pid: pid)
                covers[id] = cover
            }
            cover.panel.level = NSWindow.Level(rawValue: layer)
            if cover.panel.frame != frame { cover.panel.setFrame(frame, display: true) }
            // Stay directly above the protected window, not above unrelated apps.
            // This preserves normal app switching and the window's position.
            cover.panel.order(.above, relativeTo: Int(id))
        }
        for id in Array(covers.keys) where !visible.contains(id) {
            covers.removeValue(forKey: id)?.panel.orderOut(nil)
        }
    }
    private func makePanel(target: ShieldTarget, frame: NSRect) -> ShieldPanel {
        let panel = ShieldPanel(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.title = "\(target.name) — locked by OpenLocker"
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.worksWhenModal = true
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let blur = ShieldView(frame: NSRect(origin: .zero, size: frame.size))
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.appearance = NSAppearance(named: .aqua)
        blur.autoresizingMask = [.width, .height]
        blur.requestUnlock = { [weak self, weak panel] in
            panel?.makeKey()
            self?.onUnlock?(target.pid)
        }
        let tint = NSView(frame: blur.bounds)
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor(srgbRed: 0.94, green: 0.96, blue: 0.91, alpha: 0.36).cgColor
        tint.autoresizingMask = [.width, .height]
        blur.addSubview(tint)
        let label = NSTextField(labelWithString: "🔒  \(target.name) is locked\nClick to unlock with Touch ID")
        label.alignment = .center
        label.maximumNumberOfLines = 2
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = NSColor(srgbRed: 0.20, green: 0.29, blue: 0.21, alpha: 1)
        label.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: blur.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: blur.centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualTo: blur.widthAnchor, constant: -20)
        ])
        panel.contentView = blur
        panel.makeFirstResponder(blur)
        return panel
    }
}
