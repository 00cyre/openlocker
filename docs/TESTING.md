# Real-Mac acceptance tests

Automated tests exercise policy logic with a Chrome API mock and native protocol framing against the compiled executable. They do **not** simulate a real fingerprint or constitute an end-to-end Chrome test.

Load the unpacked extension and install the helper on a Mac with enrolled Touch ID, then check:

- [ ] Settings reports “Touch ID is ready”. No errors appear on the extension card.
- [ ] Open `https://example.com`, click the toolbar icon, then **Lock this site**. The existing page is replaced with OpenLocker's lock screen.
- [ ] Open a second tab to the domain: it starts locked, with no protected page contents visible.
- [ ] Click **Unlock with Touch ID**. The macOS prompt names the domain; a valid fingerprint unlocks that domain across tabs.
- [ ] Cancel the prompt: the page remains locked. No password/Apple Watch fallback unlocks it.
- [ ] Switch tabs, Chrome windows, and apps; navigate away and back. Previously unlocked domains remain available without another prompt. Use another site or Mac app for five minutes: the original protected domain relocks. Keep interacting with a second protected domain and verify only that domain stays unlocked. Return within five minutes to renew that site; return after expiry and verify it stays locked until page input starts Touch ID. Stop all input for five minutes: every protected page relocks. Lock macOS separately: it revokes access immediately.
- [ ] Click **Lock all now** and verify every protected page is replaced, including background tabs.
- [ ] While an authentication prompt is pending, change tabs or request a lock. A late successful response must not unlock.
- [ ] Try a protected URL with query parameters and encoded characters. Confirm the destination after unlocking. Network redirect fragments are not guaranteed; do not promise POST replay.
- [ ] Try same-domain client-side navigation, reload, back/forward cache, and a service-worker/offline page. They must not expose a protected document while locked.
- [ ] Test a domain with subdomains, overlapping parent/child locks, and lookalikes such as `example.com.attacker.test`.
- [ ] Try a protected embedded frame/resource in another tab. It remains blocked before domain authentication and is allowed during that domain’s active session; unrelated protected domains remain blocked.
- [ ] Remove a domain in settings: fresh Touch ID is required. Cancelling preserves it.
- [ ] Restart Chrome with protected tabs restored: all start locked.
- [ ] Remove/unregister the helper: protected domains remain locked and the UI offers setup guidance.
- [ ] Uninstall the extension: Chrome rules disappear. Refresh any covered page and remove the helper with the uninstall script.

For meaningful testing, use disposable tabs with no unsaved work. Locking intentionally replaces the original document.

## Current validation

Initial development validation: Node policy/worker tests, manifest and syntax checks, Swift compilation/ad-hoc signing, native-host protocol tests, and visual review of the extension UI with a clearly isolated preview adapter. Physical fingerprint success/cancellation and installed Chrome integration require the manual checks above.

## Native Mac app acceptance tests

These checks require an installed app, user-approved Accessibility, and a physical Touch ID sensor. Automated policy tests do not prove real OS event ordering or window behavior.

- [ ] Install the DMG into a fresh user account. No compiler or administrator password is required. The app appears in `~/Applications`, and Chrome setup loads the stable extension folder.
- [ ] Launch the menu-bar app. Choose **Lock an app**, approve Accessibility, then select a disposable test app's window. It protects the whole app and covers its windows with blur panels.
- [ ] Cancel Touch ID: the target stays covered and cannot receive mouse/scroll/keyboard input. A valid fingerprint removes the panels and returns focus. No password or Apple Watch fallback unlocks it.
- [ ] Switch to another app, hide the target, and minimize a target window separately. Each preserves its unlock. Use another app for five minutes and verify the target’s blur returns. Input in one protected app must keep that app unlocked while another unused protected app relocks. Return within five minutes to renew just that app; returning after expiry must not revive a grant. Leave all input idle for five minutes and verify all apps relock. Returning requires Touch ID. Test single-window and multi-window apps.
- [ ] Reopen the app from the Dock, Spotlight, and Mission Control. Record any content flashes or stale thumbnails; these are limitations of event-driven overlays, not a guaranteed trusted display.
- [ ] Switch to Finder or another app while Touch ID is pending. A late successful reply must not unlock the old target.
- [ ] Quit/relaunch the target app: it needs a new fingerprint. Restart OpenLocker: no grant survives.
- [ ] Test Spaces, full-screen apps, multiple displays, and windows spanning displays. Confirm selection chooses the visible app at the click location.
- [ ] Verify a minimized app restores a window after success and does not immediately relock from the old minimized state.
- [ ] Remove protection and quit through the menu: Touch ID is required when applicable. Cancelling preserves protection.
- [ ] Enable/disable Start at login and test a login cycle. Turn it off before uninstalling.
- [ ] Revoke Accessibility while an app is unlocked: it should relock, and unlocking should explain the missing permission.
- [ ] Re-run the installer with existing settings and verify the protected app list survives. An unrelated `~/Applications/OpenLocker.app` must not be overwritten.

Current automated additions: universal Apple Silicon/Intel builds, code-signature verification, DMG integrity, temporary-directory install/upgrade checks, and process-scoped lock policy tests. Initial UI review covers the installer, menu-bar welcome, and production blur/input-blocking panels against a disposable text-entry app. Clicking the blur opened a persistent modal and test typing left the protected field unchanged. Physical-sensor and full Accessibility acceptance checks remain manual.

### Reopen/blur regression

`bash scripts/test-activation.sh` replays the real activation-effects path, including macOS falling back to the previous app when the foreground app hides. The original implementation fails because that fallback dismisses the unlock modal. The overlay implementation keeps the prompt visible and the target covered.

`tests/shield_harness.swift` is a separate manual UI fixture using the production `WindowShield`. Its disposable app contains no real user data, and the fixture cannot authenticate. Check that clicking the blur opens its modal and typing does not change the protected text field. The fixture is never included in the compiled installer.

## Accessibility update regression

- Install 0.1.0, approve Accessibility, protect an app, quit, then install 0.1.1. Confirm the installer indicates renewal, the setup window offers Repair approval, Settings grants access to the exact installed copy, and the pending action resumes without repeated alerts. Confirm the protected list survives.
- Approve a 0.1.1 stable-signed release, then install a changed build signed by the same certificate. Confirm no renewal is requested and `AXIsProcessTrusted()` stays true. Test on Apple Silicon and Intel.
- Decline access, close/reopen setup, and retry. No background permission resets may occur. Cancel Touch ID and confirm the protected app remains covered.
- Automatic coverage: the real installer + Security.framework test rejects the old requirement for a changed ad-hoc identity, accepts it for a changed stable-signed binary, and tests preservation of app settings. Approval state tests check reset failure, retry, already-trusted protection, and repeated polling/clicks. Real macOS permission dialogs and physical Touch ID remain manual checks.

## Successful navigation after Touch ID

- Protect a local site on `127.0.0.1`, open it, and complete Touch ID. The site must load without a second prompt. Repeat for an HTTPS domain.
- Confirm scripts, fetch requests, and WebSockets still work in the unlocked tab. The same protected domain in another tab should reuse the current five-minute idle session.
- Switch tabs: the active idle session stays valid. Use Lock all, then interact with the lock page: Touch ID should be required again.

## 0.1.2 updates and automatic prompts

- From the Mac menu, install Chrome setup, confirm the native host reports ready, and complete Load unpacked from the managed folder. Preserve the extension ID and protected domains during migration from a source checkout.
- Open or switch to a locked site: no Touch ID prompt. Click, type, or scroll inside the page: one prompt appears and successful authentication navigates to the site. Browser shortcuts, Tab, Escape, pointer movement, and Manage protected sites stay quiet. Cancel during a trackpad scroll and verify momentum does not repeat the prompt. Switch tabs or navigate during authentication and verify the old response is rejected.
- Unlock a site, then relock it: its original title and cached site icon remain in the tab strip. Repeat after extension update/manual reload with duplicate destinations and different titles. Previously locked pages without saved titles use domain/path; a fresh site without a cached favicon may show Chrome’s default icon.
- Open a locked app: one Touch ID prompt appears with blur/input protection behind it. Cancel and verify a manual retry is available.
- Exercise an app update with and without protected apps; check the fingerprint confirmation when protected, relaunch, and saved settings. Exercise an extension-only update while the Mac app is running; it must not replace that app. Confirm offline/download/signature failures leave the existing installation and lock rules intact.
- Automated checks cover the focus-return regression, no-loop web prompts, metadata validation, unsigned/tampered DMG rejection, real signed staging, helper protocol, Chrome-only installs, bundled app setup, and signing identity continuity.

## Update continuity

- [ ] Keep two locked tabs with identical URLs, a pinned locked tab, and a window containing only locked tabs. Use the extension Update button: retain tab IDs, ordering, pinning, and destinations; keep protection and require Touch ID after reload.
- [ ] Repeat with Chrome’s manual Reload: missing lock pages/window return once, including duplicates. A tab deliberately closed before reloading must stay closed. Surviving unrelated tabs must stay untouched.
- [ ] Add and remove protected sites, then update/reload repeatedly. The latest list survives; removing every site remains an intentional empty list.
- [ ] Update the Mac app with a protected multi-window app open and unsaved sample text. Target processes/windows remain present. Only OpenLocker restarts; the protected list remains intact. Authentication is required again.
- [ ] Cancel or fail an update download: keep settings and locked tabs. Test missing windows, a tab closed during update, and a failed tab restoration without losing the recovery record.

Local automation includes `python3 tests/update_windows.py` for actual disposable AppKit windows; Chrome reload behavior is modeled in regression tests against the documented unload behavior. Live Chrome UI and physical fingerprints still require an interactive acceptance pass.
