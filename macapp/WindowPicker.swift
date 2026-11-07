import AppKit
import CoreGraphics

final class PickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
private final class PickerView: NSView {
    override var acceptsFirstResponder: Bool { true }
    var selected: ((NSPoint) -> Void)?
    var cancelled: (() -> Void)?
    override func mouseDown(with event: NSEvent) { selected?(NSEvent.mouseLocation) }
    override func keyDown(with event: NSEvent) { if event.keyCode == 53 { cancelled?() } }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
}
final class WindowPicker {
    private var panels: [NSPanel] = []
    private var windows: [[String: Any]] = []
    private var finished: ((pid_t?) -> Void)?
    var isPicking: Bool { !panels.isEmpty }
    func begin(completion: @escaping (pid_t?) -> Void) {
        finish(nil)
        windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        finished = completion
        for screen in NSScreen.screens {
            let panel = PickerPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.isOpaque = false
            panel.hidesOnDeactivate = false
            panel.backgroundColor = NSColor.black.withAlphaComponent(0.10)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let view = PickerView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.selected = { [weak self] point in self?.pick(point) }
            view.cancelled = { [weak self] in self?.finish(nil) }
            let label = NSTextField(labelWithString: "Click a window to lock its app  ·  Esc to cancel")
            label.font = .systemFont(ofSize: 20, weight: .semibold)
            label.textColor = .white
            label.backgroundColor = NSColor(srgbRed: 0.20, green: 0.29, blue: 0.21, alpha: 1)
            label.drawsBackground = true
            label.alignment = .center
            label.frame = NSRect(x: max(20, (screen.frame.width - 570) / 2), y: screen.frame.height - 130, width: min(570, screen.frame.width - 40), height: 40)
            view.addSubview(label)
            panel.contentView = view
            panels.append(panel)
            panel.orderFrontRegardless()
            panel.makeKey()
            panel.makeFirstResponder(view)
        }
    }
    private func pick(_ point: NSPoint) {
        guard let primary = NSScreen.screens.first else { finish(nil); return }
        let quartzPoint = CGPoint(x: point.x, y: primary.frame.maxY - point.y)
        for window in windows {
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = window[kCGWindowOwnerPID as String] as? Int32, pid != ProcessInfo.processInfo.processIdentifier,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds), rect.contains(quartzPoint),
                  let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular else { continue }
            finish(pid); return
        }
        finish(nil)
    }
    private func finish(_ pid: pid_t?) {
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll(); windows.removeAll()
        let callback = finished; finished = nil; callback?(pid)
    }
}
