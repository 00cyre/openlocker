# Install OpenLocker

## Download and open

[Download the macOS installer](https://github.com/00cyre/openlocker/releases/download/v0.1.8/OpenLocker-0.1.8-macOS.dmg), open the disk image, and open **Install OpenLocker.app**. Click **Install OpenLocker**.

The universal installer contains Apple Silicon and Intel binaries. You need macOS 13+ and an enrolled Touch ID fingerprint; no compiler, Node, Terminal, or admin password is needed for the downloaded build.

### macOS blocked the installer

Version 0.1.8 uses a persistent self-signed certificate and is **not notarized by Apple**. After you try to open it, macOS may require you to approve that specific app in **System Settings → Privacy & Security → Open Anyway**. Follow [Apple's instructions](https://support.apple.com/en-us/102445) only if you trust the download. Do not disable Gatekeeper or remove quarantine attributes. The installer does neither.

If macOS reports that a download is damaged or contains malware, stop and obtain a fresh release or build from source; do not treat that warning as the ordinary unidentified-developer prompt.

## Mac app locking

1. Click **Open OpenLocker** in the installer, or open `~/Applications/OpenLocker.app` later.
2. Click the lock icon in your menu bar, then **Lock an app**.
3. Allow OpenLocker in **System Settings → Privacy & Security → Accessibility**, then choose **Lock an app** again.
4. Click any window of the app you want to protect. OpenLocker protects that whole app and places a blur panel over its windows until Touch ID succeeds.

An unlocked app stays available across app switches, hiding, and minimizing. Five minutes without keyboard or mouse activity anywhere on your Mac relocks it; each input restarts the timer. Click its blurred window, the app in the Dock, or choose it in OpenLocker's menu to unlock. The app stays in place; a modal appears in front and the blur panel consumes mouse, scroll, and keyboard input. Window monitoring uses Accessibility notifications plus a short polling fallback to keep the blur positioned. Touch ID appears when you return after the idle timeout.

OpenLocker must be running. You can enable **Start at login** in its menu; you may also need to approve it in macOS Login Items. Login launch is off by default. The app does not record the screen, install a keyboard listener, terminate your apps, or manage system policy.

The menu requires Touch ID to stop protecting an app or quit while apps are protected. Finder, System Settings, core macOS processes, and OpenLocker itself cannot be selected. This is a convenience lock: brief content flashes and OS-generated previews can occur, and someone with local process access can stop it.

## Chrome website locking

1. In the Mac menu, choose **Install Chrome extension…**, then **Open Chrome setup**. This installs the bundled helper and copies the extension folder path. The standalone installer also offers **Copy folder path & open Chrome**.
2. At `chrome://extensions`, enable **Developer mode** and click **Load unpacked**.
3. Press **⇧⌘G**, paste the copied folder path, and choose the folder.
4. Pin OpenLocker in Chrome's Extensions menu. Visit a site, click OpenLocker, then **Lock this site**.

The extension lives at:

```text
~/Library/Application Support/OpenLocker/extension
```

Do not delete that folder. Chrome loads it directly. The native helper is registered for Google Chrome's default macOS user-data directory. Other Chromium browsers and custom `--user-data-dir` locations require separate registration.

**Why the extra Chrome step?** Chrome does not allow an ordinary macOS app to silently install an extension from a local CRX. External installs on macOS must use a Chrome Web Store listing and still require user approval. OpenLocker has not been published there. [Chrome's installation rules](https://developer.chrome.com/docs/extensions/how-to/distribute/install-extensions)

## Installed files

| Location | Purpose |
| --- | --- |
| `~/Applications/OpenLocker.app` | Menu-bar app for native app locking. |
| `~/Library/Application Support/OpenLocker/OpenLocker.app` | Chrome's on-demand Touch ID helper. |
| `~/Library/Application Support/OpenLocker/extension` | Unpacked Chrome extension. |
| `~/Library/Application Support/OpenLocker/protected-apps.json` | Your protected Mac app list, created when you add an app. |
| `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/cc.openlocker.touchid.json` | Allows this extension to invoke the helper. |

The installer writes only to the current user's folders. It checks the extension/helper identity, preserves the protected app list, and keeps the extension path stable for updates. It refuses to replace an unrelated app with the same name in your Applications folder.

## Updating

Starting with 0.1.2, use **Update to…** in the Mac menu or extension popup/settings. The Mac app checks on launch and every six hours; the extension checks when opened, caching for one hour. **Check for updates** forces a fresh check. Updates are installed only when you press the button. The app relaunches and the extension reloads automatically. Your protected app list and Chrome settings stay in place.

Install 0.1.2 once using the standalone installer if your old version has no update button. For a repository-loaded extension, use the Mac app's **Install Chrome extension…** action and load the managed folder shown above. Do not uninstall the existing extension during migration. Repository folders are never overwritten by the updater.

Both clients verify the signed disk image before mounting it and verify the enclosed installer again before running it. If apps are protected, Touch ID confirms the app's restart. Chrome-only updates leave a running Mac app alone.

## Troubleshooting

- **Accessibility enabled but OpenLocker still asks:** choose **Already enabled? Repair approval** in OpenLocker's setup window (or **Repair approval & open Settings** after an update). This clears only OpenLocker's stale permission; enable it again in Settings. If it is missing from the list, use **+** to add `~/Applications/OpenLocker.app`. The setup window detects access and continues automatically. If macOS refuses the reset, the app shows the manual remove/re-add steps and reveals the exact app in Finder. Approval must still come from you.
- **An app is briefly visible or not fully covered:** app locking reacts to macOS events; it cannot block launches or guarantee that every window is covered in every OS transition. Do not rely on it for sensitive material on an untrusted Mac.
- **Touch ID unavailable:** enroll a fingerprint, open your MacBook lid, or use an eligible Touch ID keyboard. After biometric lockout or a restart, unlock macOS with your password first. OpenLocker itself never falls back to a password.
- **Chrome helper not found:** choose **Install Chrome extension…** in the Mac menu (or run the installer again), then use **Check again** in extension settings. Confirm the extension ID is `hnbakoefkkiblpegjcefcilkdplphmbg`.
- **A Chrome page stays covered:** restore/reload the extension and refresh. If uninstalling, refresh any previously covered tabs after removal.

## Uninstall

Turn off **Start at login**, quit OpenLocker, and remove the Chrome extension in `chrome://extensions`. Then remove the menu-bar app and installed files listed above. Remove its Accessibility approval in System Settings if desired.

Developers can run `./scripts/uninstall-macos.sh`; it removes the installed app, helper, extension folder, and native-host registration. It preserves `protected-apps.json` unless you remove that file yourself. Removing only the helper leaves protected Chrome domains locked until the extension is removed.

## Updates and Accessibility

Starting with 0.1.1, published installers reuse one persistent signing certificate. Updates with that same identity should retain Accessibility approval. Migrating from the ad-hoc signed 0.1.0 release requires one renewal; the installer detects it and the app guides you through it. Source builds can still change identity. Never copy a rebuilt app over a running instance.
