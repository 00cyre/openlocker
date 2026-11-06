# OpenLocker

**A little privacy, at your fingertips.** A Chrome extension that locks websites behind your MacBook's Touch ID.

Open a website → click **OpenLocker** → **Lock this site**. When you return, click **Unlock with Touch ID** and touch the sensor. No accounts, cloud service, subscriptions, or passwords to remember.

## How it feels

- **One click to protect a domain.** Includes its subdomains; `www.example.com` becomes `example.com`. Other subdomains stay specific: locking `mail.example.com` does not lock all of `example.com`.
- **One fingerprint to get back in.** macOS performs biometric-only authentication. A cancelled or failed prompt leaves the site locked. No password or Apple Watch fallback inside OpenLocker.
- **Automatic relocking.** The unlock belongs to one tab. Switching tabs or Chrome windows, leaving the domain, restarting Chrome, or locking your Mac relocks it. Switching to another app alone does not relock it.
- **Simple management.** Add domains, lock everything now, or remove a domain after Touch ID verification.
- **Local by design.** Your fingerprint never reaches the extension or the helper.

## Install on your Mac

Requirements: **macOS 13+**, Google Chrome **120+**, and enrolled Touch ID. The local helper build needs Apple's Command Line Tools (`xcode-select --install` if missing). Node is only needed for development tests.

This is a source release, not a Chrome Web Store listing or a notarized installer. Review the code before loading it.

1. Clone or download this repository:

   ```sh
   git clone https://github.com/00cyre/openlocker.git
   cd openlocker
   ```

2. Open `chrome://extensions`, turn on **Developer mode**, click **Load unpacked**, and select the repository's **extension** folder. Its ID should be `hnbakoefkkiblpegjcefcilkdplphmbg`.

3. Install the Touch ID helper once, from the repository folder:

   ```sh
   ./scripts/install-macos.sh
   ```

   Return to OpenLocker settings and click **Check again**. Pin OpenLocker in Chrome's Extensions menu.

That's it. Visit a website, click the toolbar icon, then **Lock this site**.

The installer compiles the Swift source locally, ad-hoc signs the resulting app, and registers it for your user only. It does not need `sudo`, download a helper executable, start a server, or create a background daemon. Chrome launches the helper only when checking availability or requesting authentication. The manifest includes a public development key to keep the unpacked extension ID stable across folders and machines. No signing private key is included.

## Privacy & scope

OpenLocker is a **privacy convenience inside one Chrome profile**, not an OS security boundary. Anyone able to disable/uninstall extensions, modify local files, use another profile/browser, or control your Mac can bypass it. It does not encrypt website data, erase history, hide titles in Chrome history, or log you out of websites. All fingerprints enrolled for the current macOS user can authenticate.

- Locking navigates matching open tabs to a local lock screen. **Save drafts first**: unsaved forms and in-memory app state can be lost. Normal URL paths and queries are restored after unlocking; URL fragments may not survive Chrome's network-level redirects. POST requests cannot be replayed.
- Protected domains are also blocked as embedded resources in other tabs. This can affect embeds or shared services. Unlocking a tab permits that domain and its subdomains only in that tab.
- Chrome's internal pages, the Chrome Web Store, other profiles, incognito, native apps, downloaded files, and browser UI are outside the scope. IPv6 literal addresses are not supported. Up to 500 domains can be configured.
- Persistent Chrome network rules perform the main blocking. A document-start guard and navigation checks also cover cached/service-worker pages. Browser-protected surfaces, developer tools, malicious page scripts, and extension tampering are not security boundaries this project can enforce.
- Local storage contains your protected domain list. Temporary tab grants stay in session storage and session rules. The locked tab URL includes its original destination. There is no analytics, remote code, or account connection.

See [PRIVACY.md](PRIVACY.md) and [SECURITY.md](SECURITY.md).

## Development

There are no npm dependencies or extension build steps.

```sh
npm test                 # Domain logic and service-worker behavior with a mocked Chrome API
npm run check            # Manifest, syntax, page assets, and native origin consistency
npm run build:native     # Compile and ad-hoc sign the macOS helper
npm run test:native      # Native protocol validation; never prompts for a fingerprint
npm run package          # Source distribution in dist/
```

The automated tests cover domain boundaries, spoofed messages, missing/cancelled authentication, request-ID mismatch, concurrent updates, relocking, and successful authentication arriving after a tab change or explicit lock. Mocked Chrome tests do not prove Chrome API integration. Follow [the manual test checklist](docs/TESTING.md) on a real Mac before releasing. A physical fingerprint test cannot be completed by automation.

```text
extension/   Manifest V3 extension; plain HTML, CSS, and JavaScript
native/      Swift LocalAuthentication helper
scripts/     Local build, install, uninstall, validation, and packaging
tests/      Node behavior tests and Python native-protocol tests
```

### How it works

1. Persistent `declarativeNetRequest` rules redirect locked main-frame requests to the extension and block protected subresources. Domain patterns use Chrome's domain matching rather than unsafe substring matches.
2. An unlock request is accepted only from the extension's own top-level lock page. The service worker sends a fresh request ID and domain to the allowlisted native host.
3. Swift calls `LAContext.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics)`, with fallback hidden and reuse disabled. The host validates its caller origin and bounds incoming messages.
4. After a matching successful response, the worker rechecks the tab and lock generation. It installs a session allow rule scoped to that tab/domain and navigates back.
5. Relocking removes the session allowance and replaces any exposed protected pages. Mutating operations are serialized to avoid dropping simultaneous domain edits.

Official references: [Chrome native messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging), [Chrome declarative network rules](https://developer.chrome.com/docs/extensions/reference/api/declarativeNetRequest), and [Apple biometric-only authentication](https://developer.apple.com/documentation/localauthentication/lapolicy/deviceownerauthenticationwithbiometrics).

### Troubleshooting

- **Helper not found:** run the installer and click **Check again**. It registers Google Chrome's default macOS user-data location; custom `--user-data-dir` locations and other Chromium browsers need their own native-host registration.
- **Unexpected extension ID:** select `extension/` directly, preserve `manifest.json`'s public key, and reload. A different Chrome Web Store identity requires updating the key, `extension-id.txt`, and `native/Config.swift` together.
- **Touch ID unavailable:** enroll a fingerprint, open the MacBook lid, or use an eligible Touch ID keyboard. If macOS has locked biometry after failed attempts/restart, unlock your Mac with its password before trying Touch ID again. OpenLocker itself never falls back to a password.
- **A page stays covered:** restore/reload the extension and refresh the tab. The guard keeps pages covered if the worker cannot answer.
- **Updating:** pull changes, rerun the helper installer if native code changed, and click **Reload** on the extension card.

### Uninstall

Remove OpenLocker in `chrome://extensions` to remove domain rules, then run:

```sh
./scripts/uninstall-macos.sh
```

Removing only the helper leaves the extension's sites locked. Refresh any previously covered tabs after removing the extension.

## License

MIT. Built for people who want a little more privacy on their own Mac.
