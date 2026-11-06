import AppKit
import ApplicationServices

final class WindowObserver {
    private let application: AXUIElement
    private var observer: AXObserver?
    private var watched: [AXUIElement] = []
    private let onWindowChange: () -> Void

    init(pid: pid_t, onWindowChange: @escaping () -> Void) {
        self.application = AXUIElementCreateApplication(pid)
        self.onWindowChange = onWindowChange
        AXUIElementSetMessagingTimeout(application, 0.15)
        var created: AXObserver?
        if AXObserverCreate(pid, { _, _, notification, reference in
            guard let reference else { return }
            let watcher = Unmanaged<WindowObserver>.fromOpaque(reference).takeUnretainedValue()
            watcher.refresh()
            watcher.onWindowChange()
        }, &created) == .success, let created {
            observer = created
            let pointer = Unmanaged.passUnretained(self).toOpaque()
            AXObserverAddNotification(created, application, kAXWindowCreatedNotification as CFString, pointer)
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        }
        refresh()
    }
    deinit {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
    }
    func refresh() {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return }
        for window in windows {
            if !watched.contains(where: { CFEqual($0, window) }), let observer {
                AXObserverAddNotification(observer, window, kAXWindowMiniaturizedNotification as CFString, Unmanaged.passUnretained(self).toOpaque())
                AXObserverAddNotification(observer, window, kAXWindowDeminiaturizedNotification as CFString, Unmanaged.passUnretained(self).toOpaque())
                watched.append(window)
            }
        }
        watched.removeAll { old in !windows.contains { CFEqual(old, $0) } }
    }
    func restoreAWindow() {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return }
        for window in windows {
            var minimized: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimized) == .success,
               (minimized as? Bool) == false { return }
        }
        if let first = windows.first { AXUIElementSetAttributeValue(first, kAXMinimizedAttribute as CFString, kCFBooleanFalse) }
        refresh()
    }
}
