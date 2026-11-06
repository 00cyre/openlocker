# Real-Mac acceptance tests

Automated tests exercise policy logic with a Chrome API mock and native protocol framing against the compiled executable. They do **not** simulate a real fingerprint or constitute an end-to-end Chrome test.

Load the unpacked extension and install the helper on a Mac with enrolled Touch ID, then check:

- [ ] Settings reports “Touch ID is ready”. No errors appear on the extension card.
- [ ] Open `https://example.com`, click the toolbar icon, then **Lock this site**. The existing page is replaced with OpenLocker's lock screen.
- [ ] Open a second tab to the domain: it starts locked, with no protected page contents visible.
- [ ] Click **Unlock with Touch ID**. The macOS prompt names the domain; a valid fingerprint opens only that tab.
- [ ] Cancel the prompt: the page remains locked. No password/Apple Watch fallback unlocks it.
- [ ] Switch tabs, switch Chrome windows, leave the protected domain, and lock macOS. Each action relocks the protected document. Switching apps alone need not relock.
- [ ] Click **Lock all now** and verify every protected page is replaced, including background tabs.
- [ ] While an authentication prompt is pending, change tabs or request a lock. A late successful response must not unlock.
- [ ] Try a protected URL with query parameters and encoded characters. Confirm the destination after unlocking. Network redirect fragments are not guaranteed; do not promise POST replay.
- [ ] Try same-domain client-side navigation, reload, back/forward cache, and a service-worker/offline page. They must not expose a protected document while locked.
- [ ] Test a domain with subdomains, overlapping parent/child locks, and lookalikes such as `example.com.attacker.test`.
- [ ] Try a protected embedded frame/resource in another tab. It remains blocked; unrelated hosts work.
- [ ] Remove a domain in settings: fresh Touch ID is required. Cancelling preserves it.
- [ ] Restart Chrome with protected tabs restored: all start locked.
- [ ] Remove/unregister the helper: protected domains remain locked and the UI offers setup guidance.
- [ ] Uninstall the extension: Chrome rules disappear. Refresh any covered page and remove the helper with the uninstall script.

For meaningful testing, use disposable tabs with no unsaved work. Locking intentionally replaces the original document.

## Current validation

Initial development validation: Node policy/worker tests, manifest and syntax checks, Swift compilation/ad-hoc signing, native-host protocol tests, and visual review of the extension UI with a clearly isolated preview adapter. Physical fingerprint success/cancellation and installed Chrome integration require the manual checks above.
