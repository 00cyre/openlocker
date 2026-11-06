import AppKit
import Foundation
import Darwin

final class InstallerDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let stack = NSStackView()
    private var result: InstallResult?
    private let green = NSColor(srgbRed: 0.20, green: 0.29, blue: 0.21, alpha: 1)
    private let muted = NSColor(srgbRed: 0.45, green: 0.48, blue: 0.42, alpha: 1)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 650),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Install OpenLocker"
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(srgbRed: 0.96, green: 0.96, blue: 0.94, alpha: 1)
        window.appearance = NSAppearance(named: .aqua)
        window.center()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 42),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -42),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 34)
        ])
        showWelcome()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    private func reset() { stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() } }
    private func text(_ value: String, size: CGFloat = 14, weight: NSFont.Weight = .regular, color: NSColor? = nil) {
        let label = NSTextField(wrappingLabelWithString: value)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color ?? muted
        label.maximumNumberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(label)
        label.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    private func brand() {
        let image = NSImageView(image: NSImage(systemSymbolName: "touchid", accessibilityDescription: "Touch ID")!)
        image.contentTintColor = green
        image.imageScaling = .scaleProportionallyUpOrDown
        image.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([image.widthAnchor.constraint(equalToConstant: 54), image.heightAnchor.constraint(equalToConstant: 54)])
        stack.addArrangedSubview(image)
        text("openlocker", size: 17, weight: .semibold, color: green)
    }
    private func button(_ title: String, action: Selector, primary: Bool = false) {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.font = .systemFont(ofSize: 14, weight: .semibold)
        if primary { button.bezelColor = green; button.contentTintColor = .white }
        stack.addArrangedSubview(button)
    }
    private func showWelcome() {
        reset(); brand()
        text("A little privacy.\nOne quick setup.", size: 34, weight: .semibold, color: green)
        text("Lock Mac apps and Chrome websites with Touch ID. One installer. Everything stays on this Mac.", size: 16)
        text("✓  Apple Silicon + Intel\n✓  No Terminal, Xcode, or admin password\n✓  No accounts or cloud")
        button("Install OpenLocker", action: #selector(install), primary: true)
        text("Mac app locking needs Accessibility permission. Chrome will ask you to load the extension once. We'll guide you through both.", size: 12)
        text("Version 0.1.2 · macOS 13+ · Google Chrome 120+", size: 11)
    }
    @objc private func install() {
        if !NSRunningApplication.runningApplications(withBundleIdentifier: "cc.openlocker.mac").isEmpty {
            let alert = NSAlert(); alert.messageText = "Quit OpenLocker before updating"
            alert.informativeText = "Use OpenLocker's menu-bar menu to quit, then click Install again. Your protected app list will be preserved."
            alert.runModal(); return
        }
        do {
            guard let resources = Bundle.main.resourceURL else { throw InstallFailure(message: "Installer resources are missing.") }
            result = try InstallerEngine(payload: resources.appendingPathComponent("Payload"), home: FileManager.default.homeDirectoryForCurrentUser).install()
            showFinish()
        } catch {
            let alert = NSAlert()
            alert.messageText = "OpenLocker couldn't finish installing"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
    private func showFinish() {
        reset(); brand()
        text("Installed. Make it yours.", size: 30, weight: .semibold, color: green)
        text(result?.needsAccessibilityRenewal == true
             ? "This update needs fresh Accessibility approval. Open OpenLocker, click Repair approval, then enable it in System Settings. Your protected apps are preserved."
             : "Mac apps: open OpenLocker, then click its menu-bar icon → Lock an app. Enable Accessibility when asked.", size: 14)
        button("Open OpenLocker", action: #selector(openDesktop), primary: true)
        text("Chrome websites", size: 17, weight: .semibold, color: green)
        text("1. Open chrome://extensions and turn on Developer mode.\n2. Click Load unpacked.\n3. Press ⇧⌘G, paste the copied folder path, and click Select.", size: 15)
        button("Copy folder path & open Chrome", action: #selector(openChrome))
        button("Show extension folder", action: #selector(showFolder))
        text("Then pin the extension. Already loaded from this folder? Click Reload. You can eject the installer disk when you're done.", size: 12)
    }
    @objc private func openDesktop() {
        if let result { NSWorkspace.shared.openApplication(at: result.desktopApp, configuration: NSWorkspace.OpenConfiguration()) }
    }
    @objc private func openChrome() {
        guard let result else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result.extensionDirectory.path, forType: .string)
        guard let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") else {
            let alert = NSAlert(); alert.messageText = "Install Google Chrome to continue"
            alert.informativeText = "The extension folder path is copied. When Chrome is installed, open chrome://extensions and load that folder."
            alert.runModal(); return
        }
        NSWorkspace.shared.open([URL(string: "chrome://extensions")!], withApplicationAt: chrome, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if error != nil { DispatchQueue.main.async {
                let alert = NSAlert(); alert.messageText = "Open chrome://extensions in Chrome"
                alert.informativeText = "The extension folder path is copied. Turn on Developer mode, click Load unpacked, and paste the path with ⇧⌘G."
                alert.runModal()
            } }
        }
    }
    @objc private func showFolder() {
        if let result { NSWorkspace.shared.activateFileViewerSelecting([result.extensionDirectory]) }
    }
}
// Updates use the same transaction as the graphical installer. The caller has
// already verified this entire bundle against the pinned release certificate.
if CommandLine.arguments.contains("--update-chrome") || CommandLine.arguments.contains("--update-app") {
    let desktop = CommandLine.arguments.contains("--update-app")
    if desktop {
        // The app launches this process before terminating. Wait for its exact
        // instance to exit; do not kill it or bypass its Touch ID confirmation.
        guard let flag = CommandLine.arguments.firstIndex(of: "--parent-pid"),
              CommandLine.arguments.indices.contains(flag + 1), let pid = Int32(CommandLine.arguments[flag + 1]), pid > 1 else { exit(2) }
        let deadline = Date().addingTimeInterval(15)
        while kill(pid, 0) == 0 && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        guard kill(pid, 0) != 0,
              NSRunningApplication.runningApplications(withBundleIdentifier: "cc.openlocker.mac").allSatisfy({ $0.isTerminated }) else { exit(3) }
    }
    let temporary = Bundle.main.bundleURL.deletingLastPathComponent()
    func cleanupUpdate() {
        if temporary.lastPathComponent.hasPrefix("openlocker-update-"),
           temporary.deletingLastPathComponent().standardizedFileURL == FileManager.default.temporaryDirectory.standardizedFileURL {
            try? FileManager.default.removeItem(at: temporary)
        }
    }
    do {
        guard let resources = Bundle.main.resourceURL else { throw InstallFailure(message: "Update resources are missing.") }
        let result = try InstallerEngine(payload: resources.appendingPathComponent("Payload"), home: FileManager.default.homeDirectoryForCurrentUser)
            .install(scope: desktop ? .all : .chrome)
        cleanupUpdate()
        if desktop {
            NSWorkspace.shared.openApplication(at: result.desktopApp, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if error != nil {
                    let alert = NSAlert(); alert.messageText = "Update installed"
                    alert.informativeText = "Open OpenLocker from your Applications folder to resume app protection."; alert.runModal()
                }
                exit(0)
            }
            RunLoop.main.run()
        }
        exit(0)
    } catch {
        if desktop {
            let alert = NSAlert(); alert.messageText = "OpenLocker couldn't finish updating"
            alert.informativeText = "Your protected app list is preserved. Reopen OpenLocker and try again. " + error.localizedDescription
            alert.runModal()
            if let flag = CommandLine.arguments.firstIndex(of: "--previous-app"), CommandLine.arguments.indices.contains(flag + 1) {
                let previous = URL(fileURLWithPath: CommandLine.arguments[flag + 1])
                if NSDictionary(contentsOf: previous.appendingPathComponent("Contents/Info.plist"))?["CFBundleIdentifier"] as? String == "cc.openlocker.mac" {
                    NSWorkspace.shared.openApplication(at: previous, configuration: NSWorkspace.OpenConfiguration()) { _, _ in exit(1) }
                    RunLoop.main.run()
                }
            }
        }
        exit(1)
    }
}
let delegate = InstallerDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
