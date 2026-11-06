import AppKit
import ApplicationServices

final class AccessibilitySetup: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var timer: Timer?
    private var completion: (() -> Void)?
    private var detail: NSTextField?
    private var primary: NSButton?
    private var repairButton: NSButton?
    private let renewalFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/OpenLocker/accessibility-renewal-required")
    private lazy var approval = AccessibilityApproval(renewalFile: renewalFile, trusted: { AXIsProcessTrusted() }, reset: {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        // This only removes OpenLocker's old Accessibility decision. macOS alone
        // grants the replacement permission after the user enables it in Settings.
        process.arguments = ["reset", "Accessibility", "cc.openlocker.mac"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "OpenLocker", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey:
                "macOS couldn't refresh the approval. In Accessibility settings, remove OpenLocker with −, add this app again with +, and enable it."])
        }
    })

    var isVisible: Bool { window?.isVisible == true }
    var needsRenewal: Bool { approval.refresh() == .needsRenewal }

    func show(onReady: (() -> Void)? = nil) {
        if let onReady { completion = onReady }
        if approval.refresh() == .ready {
            finish(); return
        }
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 380), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "Set up OpenLocker"; panel.isReleasedWhenClosed = false; panel.delegate = self
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor, constant: 28), stack.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor, constant: -28), stack.topAnchor.constraint(equalTo: panel.contentView!.topAnchor, constant: 28)])
        let title = NSTextField(labelWithString: "Allow OpenLocker to lock apps")
        title.font = .systemFont(ofSize: 22, weight: .semibold); stack.addArrangedSubview(title)
        let label = NSTextField(wrappingLabelWithString: "")
        label.font = .systemFont(ofSize: 14); label.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(label); label.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true; detail = label
        let open = NSButton(title: "Open Accessibility Settings", target: self, action: #selector(openSettings))
        open.bezelStyle = .rounded; open.controlSize = .large; stack.addArrangedSubview(open); primary = open
        let repair = NSButton(title: "Already enabled? Repair approval", target: self, action: #selector(repairApproval))
        repair.bezelStyle = .rounded; stack.addArrangedSubview(repair); repairButton = repair
        let reveal = NSButton(title: "Show this OpenLocker in Finder", target: self, action: #selector(showApp))
        reveal.bezelStyle = .inline; stack.addArrangedSubview(reveal)
        window = panel; updateText(); panel.center(); panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.approval.refresh() == .ready { self.finish() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
    private func updateText() {
        if approval.state == .needsRenewal {
            detail?.stringValue = "OpenLocker's saved approval needs to be renewed. Click Repair approval, then enable OpenLocker in System Settings. This resets only OpenLocker's Accessibility permission. Your protected app list is kept."
        } else {
            detail?.stringValue = "Enable OpenLocker in System Settings → Privacy & Security → Accessibility (Device Control and Data Access on some Macs). This lets it monitor and control app windows. This window closes automatically when access is ready.\n\nIf OpenLocker is already enabled but access still fails, Repair approval clears its old entry so you can approve this copy."
        }
        primary?.title = approval.state == .needsRenewal ? "Repair approval & open Settings" : "Open Accessibility Settings"
        primary?.action = approval.state == .needsRenewal ? #selector(repairApproval) : #selector(openSettings)
        repairButton?.isHidden = approval.state == .needsRenewal
        repairButton?.isEnabled = !approval.repairPerformed
    }
    @objc private func openSettings() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    @objc private func repairApproval() {
        do {
            try approval.repair()
            if approval.state == .ready { finish(); return }
            updateText(); openSettings()
        } catch {
            detail?.stringValue = error.localizedDescription
            NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
        }
    }
    @objc private func showApp() { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
    private func finish() {
        timer?.invalidate(); timer = nil
        window?.orderOut(nil); window = nil
        let callback = completion; completion = nil
        callback?()
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        completion = nil; finish(); return true
    }
}
