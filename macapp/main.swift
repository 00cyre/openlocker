import AppKit
import ApplicationServices
import LocalAuthentication
import ServiceManagement
import CoreGraphics

private enum GateAction: Equatable {
    case unlock(ProtectedApp), remove(ProtectedApp), quit, update
    var automaticallyAuthenticates: Bool { switch self { case .unlock, .update: return true; default: return false } }
    var app: ProtectedApp? { switch self { case .unlock(let app), .remove(let app): return app; case .quit, .update: return nil } }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private var policy = LockPolicy()
    private var status: NSStatusItem!
    private let menu = NSMenu()
    private let picker = WindowPicker()
    private let accessibilitySetup = AccessibilitySetup()
    private var watchers: [pid_t: WindowObserver] = [:]
    private var tokens: [NSObjectProtocol] = []
    private var timer: Timer?
    private var updateTimer: Timer?
    private var chromeStatusTimer: Timer?
    private var gate: NSWindow?
    private var action: GateAction?
    private var authentication: LAContext?
    private var messageLabel: NSTextField?
    private var unlockButton: NSButton?
    private var storageError: String?
    private var availableRelease: OpenLockerRelease?
    private var updateBusy = false
    private var updateChecking = false
    private var automaticUpdatePolicy = AutomaticUpdatePolicy()
    private var menuIsOpen = false
    private let shields = WindowShield()
    private let green = OpenLockerTheme.accent
    private let configURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/OpenLocker/protected-apps.json")
    private var recoveryURL: URL { configURL.deletingLastPathComponent().appendingPathComponent("update-session.json") }
    private let excluded = Set(["cc.openlocker.mac", "cc.openlocker.installer", "cc.openlocker.touchid", "com.apple.finder", "com.apple.dock", "com.apple.loginwindow", "com.apple.systempreferences", "com.apple.SecurityAgent"])

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A second running instance would compete for application focus.
        if NSRunningApplication.runningApplications(withBundleIdentifier: "cc.openlocker.mac").contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil); return
        }
        if FileManager.default.fileExists(atPath: configURL.path) {
            do { policy = LockPolicy(apps: try JSONDecoder().decode([ProtectedApp].self, from: Data(contentsOf: configURL))) }
            catch { storageError = "Couldn't read your protected app list: \(error.localizedDescription)" }
        }
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "lock.circle", accessibilityDescription: "OpenLocker")
        status.button?.image?.isTemplate = true
        status.button?.toolTip = "OpenLocker — lock apps with Touch ID"
        menu.delegate = self
        status.menu = menu
        rebuildMenu()
        if CommandLine.arguments.contains("--automatic-update-failed") {
            automaticUpdatePolicy.recordFailure(now: ProcessInfo.processInfo.systemUptime)
        }
        checkUpdates(silent: true)
        updateTimer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in self?.checkUpdates(silent: true) }
        shields.onUnlock = { [weak self] pid in
            guard let self, let running = NSRunningApplication(processIdentifier: pid),
                  let id = running.bundleIdentifier, let protected = self.policy.app(id),
                  !self.policy.isUnlocked(id, pid: pid) else { return }
            self.refreshShields(); self.showGate(.unlock(protected))
        }
        observeWorkspace()
        syncWatchers()
        lockAll()
        restoreUpdateSession()
        refreshChromeUpdateIndicator()
        chromeStatusTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refreshChromeUpdateIndicator()
            self?.attemptAutomaticUpdate()
        }
        if CommandLine.arguments.contains("--resume-update"),
           !CommandLine.arguments.contains("--automatic-update"),
           !CommandLine.arguments.contains("--automatic-update-failed") {
            DispatchQueue.main.async { [weak self] in self?.showChromeReloadNotice() }
        }
        timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
        if accessibilitySetup.needsRenewal {
            DispatchQueue.main.async { [weak self] in self?.accessibilitySetup.show() }
        } else if !UserDefaults.standard.bool(forKey: "hasOpened") {
            UserDefaults.standard.set(true, forKey: "hasOpened")
            DispatchQueue.main.async { [weak self] in self?.welcome() }
        }
    }
    private func restoreUpdateSession() {
        guard let flag = CommandLine.arguments.firstIndex(of: "--resume-update"),
              CommandLine.arguments.indices.contains(flag + 1), let token = UUID(uuidString: CommandLine.arguments[flag + 1]) else { return }
        do {
            guard let recovery = try UpdateRecovery.consume(from: recoveryURL, token: token) else { return }
            let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
            let protected = Dictionary(policy.apps.map { ($0.bundleID, $0.path) }, uniquingKeysWith: { first, _ in first })
            for record in recovery.missingApps(running: running, protected: protected) {
                let url = URL(fileURLWithPath: record.path)
                guard Bundle(url: url)?.bundleIdentifier == record.bundleID else { continue }
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false; configuration.hides = record.wasHidden
                NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] _, _ in
                    DispatchQueue.main.async { self?.syncWatchers(); self?.refreshShields() }
                }
            }
        } catch { alert("Your app recovery needs attention", "Your protected app list is intact. " + error.localizedDescription) }
    }
    private func persist(_ apps: [ProtectedApp]) throws {
        try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(apps).write(to: configURL, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
    }
    private func observe(_ name: NSNotification.Name, _ callback: @escaping (Notification) -> Void) {
        tokens.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main, using: callback))
    }
    private func observeWorkspace() {
        observe(NSWorkspace.didActivateApplicationNotification) { [weak self] note in
            guard let self, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let id = app.bundleIdentifier, app.activationPolicy == .regular,
                  !["cc.openlocker.mac", "com.apple.SecurityAgent", "com.apple.LocalAuthentication.UIAgent"].contains(id) else { return }
            self.policy.recordUse(id, pid: app.processIdentifier)
            let locked = self.policy.app(id) != nil && !self.policy.isUnlocked(id, pid: app.processIdentifier)
            for command in activationCommands(appID: id, pid: app.processIdentifier, locked: locked, hasPrompt: self.action != nil) {
                switch command {
                case .hide: break // Legacy effect retained only by the regression replay.
                case .cover: self.refreshShields()
                case .prompt(let target): if let protected = self.policy.app(target) { self.showGate(.unlock(protected)) }
                case .dismiss: self.dismissGate()
                }
            }
        }
        observe(NSWorkspace.didUnhideApplicationNotification) { [weak self] note in
            guard let self, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let id = app.bundleIdentifier, let protected = self.policy.app(id),
                  !self.policy.isUnlocked(id, pid: app.processIdentifier) else { return }
            self.refreshShields()
            if app.isActive { self.showGate(.unlock(protected)) }
        }
        observe(NSWorkspace.didLaunchApplicationNotification) { [weak self] note in
            guard let self, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let id = app.bundleIdentifier, self.policy.app(id) != nil else { return }
            self.syncWatchers(); self.refreshShields()
        }
        observe(NSWorkspace.didTerminateApplicationNotification) { [weak self] note in
            guard let self, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self.watchers.removeValue(forKey: app.processIdentifier)
            if let id = app.bundleIdentifier, self.policy.app(id) != nil { self.policy.lock(id) }
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observe(name) { [weak self] _ in self?.lockAll(); self?.dismissGate() }
        }
    }
    private func syncWatchers() {
        let running = NSWorkspace.shared.runningApplications
        let ids = Set(running.map(\.processIdentifier))
        watchers = watchers.filter { ids.contains($0.key) }
        guard AXIsProcessTrusted() else { return }
        for app in running {
            guard let id = app.bundleIdentifier, policy.app(id) != nil, watchers[app.processIdentifier] == nil else { continue }
            watchers[app.processIdentifier] = WindowObserver(pid: app.processIdentifier) { [weak self] in self?.refreshShields() }
        }
    }
    private func refreshActivity() {
        // kCGAnyInputEventType is imported as the all-bits-set event value.
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)
        let active = NSWorkspace.shared.frontmostApplication
        if policy.updateActivity(idleSeconds: idle, activeAppID: active?.bundleIdentifier, activePID: active?.processIdentifier) {
            refreshShields(); dismissGate()
        }
    }
    private func tick() {
        refreshActivity()
        syncWatchers()
        // Keep blur/input-blocking windows aligned even for apps with incomplete
        // window notifications. Minimizing never revokes an active idle session.
        for watcher in Array(watchers.values) { watcher.refresh() }
        for app in NSWorkspace.shared.runningApplications {
            guard let id = app.bundleIdentifier, let protected = policy.app(id) else { continue }
            if policy.isUnlocked(id, pid: app.processIdentifier) {
                if !AXIsProcessTrusted() { lock(id) }
            } else if !policy.isInactive && app.isActive && shields.hasVisibleWindows(for: app.processIdentifier) {
                showGate(.unlock(protected))
            }
        }
        refreshShields()
    }
    private func refreshShields() {
        let targets = NSWorkspace.shared.runningApplications.compactMap { app -> ShieldTarget? in
            guard let id = app.bundleIdentifier, let protected = policy.app(id),
                  !policy.isUnlocked(id, pid: app.processIdentifier) else { return nil }
            return ShieldTarget(pid: app.processIdentifier, name: protected.name)
        }
        shields.refresh(targets)
    }
    private func lock(_ id: String) {
        guard policy.app(id) != nil else { return }
        policy.lock(id)
        refreshShields()
    }
    @objc private func lockAll() {
        policy.lockAll()
        refreshShields()
        if authentication != nil { dismissGate() }
    }
    func menuWillOpen(_ menu: NSMenu) { menuIsOpen = true; rebuildMenu() }
    func menuDidClose(_ menu: NSMenu) { menuIsOpen = false }
    private func item(_ title: String, action: Selector?, represented: Any? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self; item.representedObject = represented
        return item
    }
    private func rebuildMenu() {
        refreshChromeUpdateIndicator()
        menu.removeAllItems()
        let header = item("OpenLocker", action: nil); header.isEnabled = false; menu.addItem(header)
        let timeout = item("Each app relocks after 5 minutes away", action: nil); timeout.isEnabled = false; menu.addItem(timeout)
        menu.addItem(item("Lock an app…", action: #selector(pickApp)))
        menu.addItem(.separator())
        if policy.apps.isEmpty { let empty = item("No protected apps yet", action: nil); empty.isEnabled = false; menu.addItem(empty) }
        for app in policy.apps {
            let unlocked = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).contains { policy.isUnlocked(app.bundleID, pid: $0.processIdentifier) }
            let parent = item(app.name, action: nil)
            parent.image = NSImage(systemSymbolName: unlocked ? "lock.open" : "lock", accessibilityDescription: unlocked ? "Unlocked" : "Locked")
            let submenu = NSMenu()
            submenu.addItem(item(unlocked ? "Lock now" : "Unlock with Touch ID…", action: unlocked ? #selector(lockItem(_:)) : #selector(unlockItem(_:)), represented: app))
            submenu.addItem(item("Stop protecting…", action: #selector(removeItem(_:)), represented: app))
            parent.submenu = submenu; menu.addItem(parent)
        }
        menu.addItem(.separator())
        menu.addItem(item("Lock all now", action: #selector(lockAll)))
        menu.addItem(item(AXIsProcessTrusted() ? "Accessibility: enabled" : "Enable Accessibility…", action: #selector(accessibility)))
        let login = item("Start at login", action: #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        let update = item(updateBusy ? "Updating…" : updateChecking ? "Checking for updates…" : availableRelease.map { "Update to \($0.version.text)…" } ?? "Check for updates…", action: #selector(updateApp))
        update.isEnabled = !updateBusy && !updateChecking; menu.addItem(update)
        let automatic = item("Automatically install updates", action: #selector(toggleAutomaticUpdates))
        automatic.state = automaticUpdatesEnabled ? .on : .off
        menu.addItem(automatic)
        if automaticUpdatesEnabled, automaticUpdatePolicy.failedAt != nil {
            let retry = item("Automatic update delayed — will retry", action: nil)
            retry.isEnabled = false; menu.addItem(retry)
        } else if automaticUpdatesEnabled, availableRelease != nil, !updateBusy {
            let pending = item("Will install after 5 minutes of Mac inactivity", action: nil)
            pending.isEnabled = false; menu.addItem(pending)
        }
        if let chrome = chromeInstallation, chrome.needsReload {
            menu.addItem(item("Chrome \(chrome.installed.text) installed — Reload extension…", action: #selector(openChromeExtensionSettings)))
        }
        menu.addItem(item("Install Chrome extension…", action: #selector(installChrome)))
        menu.addItem(item("About & help", action: #selector(welcome)))
        menu.addItem(.separator())
        menu.addItem(item("Quit OpenLocker…", action: #selector(quit)))
    }
    private var chromeInstallation: ExtensionInstallation? {
        ExtensionInstallation.read(home: FileManager.default.homeDirectoryForCurrentUser)
    }
    private func refreshChromeUpdateIndicator() {
        let pending = chromeInstallation?.needsReload == true
        status.button?.image = NSImage(systemSymbolName: pending ? "lock.circle.fill" : "lock.circle", accessibilityDescription: "OpenLocker")
        status.button?.image?.isTemplate = true
        status.button?.toolTip = pending ? "OpenLocker — Chrome update installed; reload extension" : "OpenLocker — lock apps with Touch ID"
    }
    private func showChromeReloadNotice() {
        guard action == nil, !accessibilitySetup.isVisible, let chrome = chromeInstallation, chrome.needsReload else { return }
        let notice = NSAlert()
        notice.messageText = "Chrome extension update installed"
        notice.informativeText = "Version \(chrome.installed.text) was installed with OpenLocker. Open extension settings and click Reload on OpenLocker to activate it. Keep the extension installed. Refresh already-open webpages when you're ready.\n\nIf you use several Chrome profiles, reload it in each profile."
        notice.addButton(withTitle: "Open extension settings")
        notice.addButton(withTitle: "Later")
        if notice.runModal() == .alertFirstButtonReturn { openChromeExtensionSettings() }
    }
    @objc private func openChromeExtensionSettings() {
        guard let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") else {
            alert("Chrome isn't installed", "Install Google Chrome, then choose Install Chrome extension from OpenLocker's menu."); return
        }
        let id = Config.allowedOrigin.replacingOccurrences(of: "chrome-extension://", with: "").replacingOccurrences(of: "/", with: "")
        let url = URL(string: "chrome://extensions/?id=\(id)")!
        NSWorkspace.shared.open([url], withApplicationAt: chrome, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if error != nil { DispatchQueue.main.async { self.alert("Open Chrome extension settings", "Open chrome://extensions and click Reload on OpenLocker.") } }
        }
    }
    @objc private func pickApp() {
        if let storageError { alert("Your protected app list needs attention", storageError); return }
        guard AXIsProcessTrusted() else {
            dismissGate()
            accessibilitySetup.show { [weak self] in self?.pickApp() }
            return
        }
        let context = LAContext()
        var biometricError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &biometricError), context.biometryType == .touchID else {
            alert("Touch ID isn't ready", "Enroll a fingerprint or unlock your Mac, then try again before protecting an app."); return
        }
        dismissGate()
        // Let the menu close before putting up the click selector.
        DispatchQueue.main.async { [weak self] in
            self?.picker.begin { [weak self] pid in
                guard let self, let pid, let app = NSRunningApplication(processIdentifier: pid),
                      let id = app.bundleIdentifier, let url = app.bundleURL else { return }
                guard !self.excluded.contains(id) else { self.alert("Choose another app", "macOS system apps and OpenLocker can't be protected."); return }
                let protected = ProtectedApp(bundleID: id, name: app.localizedName ?? url.deletingPathExtension().lastPathComponent, path: url.path)
                var updated = self.policy
                updated.protect(protected)
                do { try self.persist(updated.apps); self.policy = updated; self.syncWatchers(); self.lock(id); self.showGate(.unlock(protected)) }
                catch { self.alert("Couldn't save protection", error.localizedDescription) }
            }
        }
    }
    @objc private func lockItem(_ item: NSMenuItem) { if let app = item.representedObject as? ProtectedApp { lock(app.bundleID) } }
    @objc private func unlockItem(_ item: NSMenuItem) { if let app = item.representedObject as? ProtectedApp { showGate(.unlock(app)) } }
    @objc private func removeItem(_ item: NSMenuItem) { if let app = item.representedObject as? ProtectedApp { showGate(.remove(app)) } }
    @objc private func quit() {
        if policy.apps.isEmpty { NSApp.terminate(nil) } else { showGate(.quit) }
    }
    @objc private func accessibility() {
        dismissGate()
        accessibilitySetup.show()
    }
    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch { alert("Couldn't change login settings", "Run OpenLocker from your Applications folder and try again. \(error.localizedDescription)") }
    }
    @objc private func installChrome() {
        do {
            guard let resources = Bundle.main.resourceURL else { throw InstallFailure(message: "Chrome setup files are missing. Reinstall OpenLocker.") }
            let result = try InstallerEngine(payload: resources.appendingPathComponent("Chrome"),
                home: FileManager.default.homeDirectoryForCurrentUser,
                helper: Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/OpenLocker.app")).install(scope: .chrome)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(result.extensionDirectory.path, forType: .string)
            let setup = NSAlert()
            setup.messageText = "Ready to add to Chrome"
            setup.informativeText = "The extension and Touch ID helper are installed. Chrome needs your approval once:\n\n1. Turn on Developer mode.\n2. Click Load unpacked.\n3. Press ⇧⌘G and paste the copied folder path, then select it.\n\nFuture updates use the Update button in OpenLocker. Your existing protected sites stay under the same extension ID."
            setup.addButton(withTitle: "Open Chrome setup"); setup.addButton(withTitle: "Later")
            NSApp.activate(ignoringOtherApps: true)
            if setup.runModal() == .alertFirstButtonReturn {
                guard let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") else {
                    alert("Install Google Chrome to continue", "The extension folder path is copied. Open Chrome's Extensions page when Chrome is installed."); return
                }
                NSWorkspace.shared.open([URL(string: "chrome://extensions")!], withApplicationAt: chrome, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                    if error != nil { DispatchQueue.main.async { self.alert("Open Chrome's Extensions page", "The folder path is copied. Turn on Developer mode, click Load unpacked, and paste the path with ⇧⌘G.") } }
                }
            }
        } catch { alert("Couldn't set up Chrome", error.localizedDescription) }
    }
    private var appVersion: ReleaseVersion { ReleaseVersion(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0")! }
    private var automaticUpdatesEnabled: Bool {
        UserDefaults.standard.bool(forKey: AutomaticUpdatePolicy.preferenceKey)
    }
    @objc private func toggleAutomaticUpdates() {
        let enabled = !automaticUpdatesEnabled
        UserDefaults.standard.set(enabled, forKey: AutomaticUpdatePolicy.preferenceKey)
        automaticUpdatePolicy.resetRetry()
        if enabled { checkUpdates(silent: true) }
    }
    private func automaticUpdateIsAllowed() -> Bool {
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)
        return automaticUpdatePolicy.allowsInstallation(enabled: automaticUpdatesEnabled,
            hasUpdate: availableRelease.map { $0.version > appVersion } ?? false,
            idleSeconds: idle,
            interactionInProgress: action != nil || authentication != nil || accessibilitySetup.isVisible ||
                picker.isPicking || menuIsOpen || NSApp.modalWindow != nil || storageError != nil,
            now: ProcessInfo.processInfo.systemUptime)
    }
    private func attemptAutomaticUpdate() {
        guard !updateBusy, !updateChecking, automaticUpdateIsAllowed() else { return }
        automaticUpdatePolicy.resetRetry()
        installUpdate(automatic: true)
    }
    private func checkUpdates(silent: Bool) {
        guard !updateBusy && !updateChecking else { return }
        updateChecking = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let release = try await ReleaseUpdater.latest()
                self.availableRelease = release.version > self.appVersion ? release : nil
                self.updateChecking = false
                if silent { self.attemptAutomaticUpdate() }
                else {
                    if self.availableRelease != nil { self.updateApp() }
                    else if self.chromeInstallation?.needsReload == true { self.showChromeReloadNotice() }
                    else { self.alert("You're up to date", "OpenLocker \(self.appVersion.text) is the latest installed version.") }
                }
            } catch { self.updateChecking = false; if !silent { self.alert("Couldn't check for updates", error.localizedDescription) } }
        }
    }
    @objc private func updateApp() {
        guard !updateBusy else { return }
        guard availableRelease != nil else { checkUpdates(silent: false); return }
        if policy.apps.isEmpty { installUpdate() } else { showGate(.update) }
    }
    private func installUpdate(automatic: Bool = false) {
        guard let release = availableRelease, !updateBusy else { return }
        if automatic && !automaticUpdateIsAllowed() { return }
        updateBusy = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                guard let certificate = Bundle.main.url(forResource: "ReleaseCertificate", withExtension: "cer") else { throw UpdateFailure("The signing certificate is missing. Reinstall OpenLocker.") }
                let staged = try await ReleaseUpdater.stage(release, certificate: certificate)
                do {
                    let running = NSWorkspace.shared.runningApplications.compactMap { app -> AppRecoveryRecord? in
                        guard let id = app.bundleIdentifier, let protected = self.policy.app(id) else { return nil }
                        return AppRecoveryRecord(bundleID: id, path: protected.path, processID: app.processIdentifier,
                                                 wasHidden: app.isHidden, wasLocked: !self.policy.isUnlocked(id, pid: app.processIdentifier))
                    }
                    // Recheck immediately before the handoff: the user may have
                    // returned, opened a prompt, or opted out during download.
                    if automatic && !self.automaticUpdateIsAllowed() {
                        staged.remove(); self.updateBusy = false; return
                    }
                    let token = try UpdateRecovery.save(running, to: self.recoveryURL)
                    self.lockAll()
                    var arguments = ["--update-app", "--parent-pid", String(ProcessInfo.processInfo.processIdentifier),
                        "--previous-app", Bundle.main.bundleURL.path, "--resume-update", token.uuidString]
                    if automatic { arguments.append("--automatic-update") }
                    _ = try staged.launch(arguments: arguments)
                }
                catch { staged.remove(); throw error }
                NSApp.terminate(nil)
            } catch {
                self.updateBusy = false
                if automatic { self.automaticUpdatePolicy.recordFailure(now: ProcessInfo.processInfo.systemUptime) }
                else { self.alert("Couldn't update OpenLocker", error.localizedDescription) }
            }
        }
    }
    @objc private func welcome() {
        alert("Your apps. Your fingerprint.", "Click OpenLocker's menu-bar icon → Lock an app, then click any window to protect its whole app. Each app stays unlocked while you use it and relocks after 5 minutes without use. Using another app does not restart its timer.\n\nAccessibility and enrolled Touch ID are required. OpenLocker must stay running; enable Start at login if you want it after a restart. This is a convenience lock: macOS may briefly reveal windows before the blur appears, and stopping OpenLocker bypasses it.\n\nVersion 0.1.13 · Local only · No accounts")
    }
    private func alert(_ title: String, _ message: String) {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = message
        NSApp.activate(ignoringOtherApps: true); alert.runModal()
    }
    private func showGate(_ requested: GateAction) {
        refreshActivity()
        guard !policy.isInactive else { return }
        guard !accessibilitySetup.isVisible else { return }
        if action == requested, let gate, gate.isVisible {
            if authentication == nil { gate.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
            return
        }
        dismissGate()
        action = requested
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 420), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "OpenLocker"; window.isReleasedWhenClosed = false; window.delegate = self
        window.level = .modalPanel; window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.backgroundColor = OpenLockerTheme.background
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .centerX; stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 30), stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -30), stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 28)])
        let icon = NSImageView(image: NSImage(systemSymbolName: "touchid", accessibilityDescription: "Touch ID")!)
        icon.contentTintColor = green; icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 58).isActive = true; icon.heightAnchor.constraint(equalToConstant: 58).isActive = true
        stack.addArrangedSubview(icon)
        let title: String, detail: String, buttonTitle: String
        switch requested {
        case .unlock(let app): title = "\(app.name) is locked."; detail = "A quick touch, and you're back in.\nRelocks after 5 minutes without using this app."; buttonTitle = "Unlock with Touch ID"
        case .remove(let app): title = "Stop protecting \(app.name)?"; detail = "Confirm with your fingerprint to remove this app from OpenLocker."; buttonTitle = "Remove with Touch ID"
        case .update: title = "Update OpenLocker?"; detail = "Updates the Mac app and Chrome extension files.\nYour apps stay open. Reload the extension in Chrome afterward."; buttonTitle = "Update with Touch ID"
        case .quit: title = "Quit OpenLocker?"; detail = "Your apps won't be protected while OpenLocker is closed."; buttonTitle = "Quit with Touch ID"
        }
        func label(_ value: String, size: CGFloat, color: NSColor) -> NSTextField {
            let label = NSTextField(wrappingLabelWithString: value); label.alignment = .center
            label.font = .systemFont(ofSize: size, weight: size > 20 ? .semibold : .regular); label.textColor = color
            label.widthAnchor.constraint(equalToConstant: 380).isActive = true
            stack.addArrangedSubview(label); return label
        }
        _ = label(title, size: 26, color: green)
        _ = label(detail, size: 13, color: .secondaryLabelColor)
        let button = NSButton(title: buttonTitle, target: self, action: #selector(authenticate))
        button.bezelStyle = .rounded; button.controlSize = .large; button.bezelColor = OpenLockerTheme.button; button.contentTintColor = .white
        stack.addArrangedSubview(button); unlockButton = button
        let cancel = NSButton(title: "Keep locked", target: self, action: #selector(cancel))
        cancel.bezelStyle = .inline; stack.addArrangedSubview(cancel)
        messageLabel = label("", size: 12, color: .secondaryLabelColor)
        gate = window; window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        if requested.automaticallyAuthenticates {
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, self.gate === window, self.action == requested else { return }
                self.authenticate()
            }
        }
    }
    @objc private func cancel() { dismissGate() }
    func windowShouldClose(_ sender: NSWindow) -> Bool { dismissGate(); return false }
    private func dismissGate(invalidate: Bool = true) {
        if invalidate { policy.invalidateAuthentication() }
        authentication?.invalidate(); authentication = nil
        gate?.orderOut(nil); gate = nil; action = nil; messageLabel = nil; unlockButton = nil
    }
    @objc private func authenticate() {
        refreshActivity()
        guard authentication == nil, let requested = action else { return }
        if case .unlock = requested, !AXIsProcessTrusted() {
            dismissGate()
            accessibilitySetup.show { [weak self] in self?.showGate(requested) }
            return
        }
        let context = LAContext()
        context.localizedFallbackTitle = ""; context.localizedCancelTitle = "Keep locked"
        context.touchIDAuthenticationAllowableReuseDuration = 0
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error), context.biometryType == .touchID else {
            messageLabel?.stringValue = "Touch ID is unavailable. Enroll a fingerprint or unlock your Mac, then try again."; return
        }
        let ticket = policy.ticket(for: requested.app?.bundleID)
        authentication = context; unlockButton?.isEnabled = false; messageLabel?.stringValue = "Waiting for your fingerprint…"
        let reason: String
        switch requested { case .unlock(let app): reason = "unlock \(app.name)"; case .remove(let app): reason = "stop protecting \(app.name)"; case .quit: reason = "quit OpenLocker"; case .update: reason = "update and relaunch OpenLocker" }
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { [weak self] success, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.refreshActivity()
                guard self.authentication === context, self.action == requested else { return }
                self.authentication = nil; self.unlockButton?.isEnabled = true
                guard success, self.policy.accepts(ticket) else {
                    self.messageLabel?.stringValue = success ? "The app state changed. Try again." : "Not unlocked. Try Touch ID again when you're ready."; return
                }
                self.finish(requested, ticket: ticket)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self, weak context] in
            guard let self, let context, self.authentication === context else { return }
            context.invalidate(); self.authentication = nil; self.unlockButton?.isEnabled = true
            self.messageLabel?.stringValue = "Touch ID timed out. Your apps are still locked."
        }
    }
    private func finish(_ requested: GateAction, ticket: AuthenticationTicket) {
        switch requested {
        case .update: dismissGate(); installUpdate()
        case .quit: dismissGate(); NSApp.terminate(nil)
        case .remove(let app):
            var updated = policy
            guard updated.remove(app.bundleID, ticket: ticket) else { return }
            do {
                try persist(updated.apps); policy = updated
                for running in NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID) { watchers.removeValue(forKey: running.processIdentifier); running.unhide() }
                refreshShields(); dismissGate()
            } catch { messageLabel?.stringValue = "Couldn't save this change. The app stays protected." }
        case .unlock(let app):
            if let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).first { grant(app, running: running, ticket: ticket) }
            else {
                let configuration = NSWorkspace.OpenConfiguration(); configuration.activates = false
                NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: app.path), configuration: configuration) { [weak self] running, error in
                    DispatchQueue.main.async {
                        guard let self, self.action == requested else { return }
                        if let running, error == nil { self.grant(app, running: running, ticket: ticket) }
                        else { self.messageLabel?.stringValue = "Couldn't open this app. It may have moved or been removed." }
                    }
                }
            }
        }
    }
    private func grant(_ app: ProtectedApp, running: NSRunningApplication, ticket: AuthenticationTicket) {
        guard running.bundleIdentifier == app.bundleID, !running.isTerminated,
              policy.unlock(app.bundleID, pid: running.processIdentifier, ticket: ticket) else {
            messageLabel?.stringValue = "The app state changed. Try again."; return
        }
        syncWatchers()
        watchers[running.processIdentifier]?.restoreAWindow()
        refreshShields()
        dismissGate(invalidate: false)
        running.unhide()
        // Bringing a window forward is best effort. macOS can decline during
        // concurrent computer use or another focus transition; that must not
        // revoke the Touch ID grant we just issued or open a competing modal.
        _ = running.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }
}
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
