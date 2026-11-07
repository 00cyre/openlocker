# Developing OpenLocker

No npm dependencies. The Chrome extension is plain Manifest V3 HTML/CSS/JavaScript. The native pieces use system Swift frameworks and require Apple's Command Line Tools to build.

## Source install

```sh
git clone https://github.com/00cyre/openlocker.git
cd openlocker
npm run build:installer
```

Open `dist/OpenLocker-0.1.9-macOS.dmg` and run the installer, or build individual pieces:

```sh
npm run build:mac          # Mac menu-bar app in build/desktop/
npm run build:native       # Chrome native helper
./scripts/install-macos.sh # Install just the Chrome helper from source
```

For a development extension, use **Load unpacked** on the repository's `extension/` directory. Keep `manifest.json`'s public development key: it fixes the extension ID to the allowlisted native caller. A future Chrome Web Store identity needs matching updates to `manifest.json`, `extension-id.txt`, and `native/Config.swift`.

## Layout

| Folder | Contents |
| --- | --- |
| `macapp/` | Menu bar, window picker, lock policy, Accessibility watcher, and Touch ID gate. |
| `extension/` | Chrome popup, lock screen, settings, domain rules, and document guard. |
| `native/` | The Chrome native-messaging Touch ID helper. |
| `installer/` | Graphical installer and per-user installation engine. |
| `scripts/` | Build, install, validation, tests, and source packaging. |
| `tests/` | JavaScript behavior tests, Swift policy/installer tests, and protocol tests. |

## Checks

```sh
npm test
npm run check
npm run build:installer
npm run test:mac
npm run test:installer
npm run test:native
npm run package
```

The installer build cross-compiles `arm64` and `x86_64`, merges each executable with `lipo`, and signs the resulting bundles. Local/CI development builds are ad-hoc unless a signing identity is supplied. The DMG and ZIP contain the compiled app, extension, and native helper; they do not download code at install time. Installer tests use temporary home-directory fixtures and do not install to the developer's account.

Do not rebuild the copy currently running. `build-mac-app.sh` refuses that destination, because replacing an ad-hoc signed binary can invalidate Accessibility approval even while Settings displays it as enabled. Use a separate `OPENLOCKER_DESKTOP_DEST` for development builds, or quit before rebuilding and renew approval if needed. Installer builds already use a separate `build/release-desktop` destination.

GitHub checks build both the Chrome code and universal macOS development artifacts. The separate tag-triggered release workflow imports the persistent certificate from encrypted Actions secrets, builds with hardened runtime, checks the pinned signer, tests identity continuity, then publishes. No private key is in the repository. These releases are self-signed, not Apple-notarized; first-launch Gatekeeper approval can still be necessary. See [release identity](../signing/README.md).

## Mac app flow

The menu-bar app persists a list of bundle IDs, names, and bundle paths. Window selection uses on-screen window metadata; it does not capture pixels. Accessibility observes window changes and restores minimized windows after authentication. Workspace notifications handle activation, launches, exits, sleep, and session changes. Focus loss, hiding, and minimizing preserve grants.

`LockPolicy` owns process-scoped unlocks, individual app deadlines, and generation-based authentication invalidation. A successful Touch ID response can create a grant only for the selected protected app and current process. Relocking, cancellation, or changing the target invalidates an old response. No grants are persisted. The application covers locked app windows with native behind-window blur panels that intercept input. A Touch ID modal appears in front when the user returns. It does not hide or minimize the protected app: doing so transfers focus and can dismiss the unlock modal. A deterministic activation-event replay guards this regression. macOS may display content before overlays are positioned.

## Chrome flow

Persistent `declarativeNetRequest` rules redirect protected top-level network requests to a local lock page and block matching subresources. The service worker accepts protection changes and authentication requests only from named extension pages and sends a fresh request ID to the allowlisted native host. Content scripts can check their page's authorization and report activity to renew an existing grant; they cannot create one. Swift uses `deviceOwnerAuthenticationWithBiometrics`, with fallback hidden and reuse disabled.

After a matching successful response, the worker checks that the tab and lock generation have not changed. A session allowance covers the authenticated domain across tabs and windows in the Chrome profile. Returning before expiry preserves and renews it. Five minutes without using that domain, restarting Chrome, locking the screen, or an explicit lock revoke access. A document-start guard and navigation checks add coverage for cached pages.

Domain grants carry a `lastActivity` timestamp. The worker schedules the nearest deadline with [`chrome.alarms`](https://developer.chrome.com/docs/extensions/reference/api/alarms), recreating the alarm on worker startup. Chrome may delay alarms; expiry is also enforced on navigation, focus, authorization, and guard checks, and an open protected document covers itself and rechecks at its grant deadline. Timestamp-less legacy grants and backward clock jumps fail closed. `chrome.idle` remains a screen-lock/global-idle fallback. Worker suspension preserves unexpired deadlines; browser restart does not. `activity.js` reports only trusted visible-document input, throttled to once per second, including frames. The worker verifies the live active tab and focused window and only renews existing unexpired grants. Selecting a tab or returning to its Chrome window renews that domain, never an expired grant. Synthetic DOM events, background pages, navigation requests, and activity elsewhere do not keep it unlocked. A lock page only starts authentication on trusted pointer, keyboard, or wheel input inside its document. Focus, visibility, mouse movement, and global idle-to-active events never start authentication. Browser shortcuts, modifier-only keys, Tab/Escape, and settings interactions are ignored; scroll momentum is coalesced into one attempt. An already-authorized domain can resume on focus without another fingerprint.

`LockedTabs` records titles from committed protected web documents before redirecting, tracks title changes, and carries titles through its recovery journal when Chrome replaces tab IDs. Only current protected tabs are retained. Lock pages use [Chrome’s favicon API](https://developer.chrome.com/docs/extensions/how-to/ui/favicons) under the extension origin, never a direct remote icon URL. The `favicon` permission is covered by the existing `tabs` permission; no favicon resource is exposed to websites.

The Mac app samples [`CGEventSource.secondsSinceLastEventType`](https://developer.apple.com/documentation/coregraphics/cgeventsource/secondssincelasteventtype(_:eventtype:)) for `kCGAnyInputEventType` in the combined session state. The foreground app ID attributes newly observed input to that app alone; a 20ms tolerance ignores clock-sampling jitter. Grants carry a monotonic last-use timestamp, and both polling and authorization queries enforce the individual deadline. Activating an app renews only an unexpired grant. A system-idle transition still revokes everything. OpenLocker reads input timing, not input contents. No additional monitoring permission is needed.

Grant rules explicitly list resource types, including `main_frame`, so they match the page navigation as well as page resources. Chrome excludes `main_frame` when both resource-type masks are empty, including an empty exclusion list; such a grant redirects straight back to the lock page after successful authentication. The worker regression tests model Chromium's `ComputeElementTypes` behavior at the navigation boundary.

## Release

Push a version tag matching `package.json`. The release workflow builds, tests, and publishes these assets only with the pinned persistent signing identity. For local release builds, use `npm run build:release` with the existing signing keychain configured; ad-hoc fallback is rejected:

- `OpenLocker-0.1.9-macOS.dmg`
- `OpenLocker-0.1.9-macOS.zip`
- `OpenLocker-0.1.9-source.zip`
- `SHA256SUMS.txt`

The [manual checklist](TESTING.md) covers the hardware and OS integration that automated checks cannot establish. Record unperformed checks in release notes.

Official references: [Chrome native messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging), [Chrome network rules](https://developer.chrome.com/docs/extensions/reference/api/declarativeNetRequest), [Apple biometric-only authentication](https://developer.apple.com/documentation/localauthentication/lapolicy/deviceownerauthenticationwithbiometrics), and [native behind-window blur](https://developer.apple.com/documentation/appkit/nsvisualeffectview/blendingmode-swift.enum/behindwindow).

## Accessibility renewal

`CodeIdentity` validates replacements against the installed app's designated requirement using Security.framework. Only an identity-changing update writes a pending-renewal marker, inside the install transaction. The app's single setup window polls actual `AXIsProcessTrusted()`, offers an explicit app-scoped `tccutil reset Accessibility cc.openlocker.mac`, and resumes the pending action when trust is granted. The reset never grants access, never runs merely because polling returns false, and never runs again after a successful reset in the session. Existing 0.1.0 installs migrate once. A previously approved source build is also detected via the saved approval state.

## Updates and Chrome setup

`ReleaseUpdater` validates stable GitHub release metadata, downloads the fixed repository's DMG, checks its pinned certificate before mounting read-only, and verifies the copied installer and version before execution. The installer exposes Chrome-only and parent-waiting app update modes backed by the same rollback transaction and an exclusive install lock. The Mac app bundles the extension and helper for offline Chrome setup. `installation.json` marks the managed folder; source checkouts must migrate once and are never overwritten. Chrome storage remains keyed to the fixed extension ID.

The extension's pending authentication tracks its initiating tab. Returning from Touch ID to the same tab does not advance its invalidation generation; tab switches or navigation during pending authentication still do. Completed domain grants survive subsequent tab/window switches and navigation. Website prompting requires deliberate input in a visible, focused lock page and never loops on system-dialog focus changes.

## Update persistence and recovery

`protected-sites.js` loads the primary list, its recovery copy, or existing DNR protection before startup rebuilds rules. Writes update the primary and recovery list together. The original installer did not touch Chrome profile storage; its temporary-home tests now explicitly preserve a nonempty website fixture and protected Mac app list. The original trigger that cleared the reported Chrome settings was not established; the destructive fallback on missing settings was reproduced and fixed.

`locked-tabs.js` journals locked destinations/placement in `storage.local`. A `storage.session` marker distinguishes a worker restart from a full reload. Updates checkpoint and park lock pages on opaque `about:blank` URLs, wait for those navigations to commit, and reload. Startup restores existing placeholders or recreates missing tabs/windows, matching duplicate occurrences once. Tab-close/navigation events remove obsolete entries. No grants are persisted in this journal.

`UpdateRecovery.swift` provides the Mac handoff inventory. The app records it immediately before the verified installer starts; the installer also captures running apps for updates from older versions. Only OpenLocker exits. The replacement consumes the expiring inventory and leaves every surviving process alone. A missing protected app can reopen after checking its path and bundle ID. Fingerprint authentication remains separate.

Run `python3 tests/update_windows.py` after building the installer and running installer tests for the local GUI integration check. It uses disposable AppKit windows with unsaved sample text and temporary home directories, verifies process/window identity across installer transactions and blur-process restart, and closes its own fixtures. It does not modify user apps or their protection settings.
