# Developing OpenLocker

No npm dependencies. The Chrome extension is plain Manifest V3 HTML/CSS/JavaScript. The native pieces use system Swift frameworks and require Apple's Command Line Tools to build.

## Source install

```sh
git clone https://github.com/00cyre/openlocker.git
cd openlocker
npm run build:installer
```

Open `dist/OpenLocker-0.1.0-macOS.dmg` and run the installer, or build individual pieces:

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

The installer build cross-compiles `arm64` and `x86_64`, merges each executable with `lipo`, and ad-hoc signs the resulting bundles. The DMG and ZIP contain the compiled app, extension, and native helper; they do not download code at install time. Installer tests use temporary home-directory fixtures and do not install to the developer's account.

GitHub CI builds both the Chrome code and the universal macOS artifacts. Builds are ad-hoc signed, not notarized. A production distribution should use a Developer ID certificate, hardened runtime where appropriate, and Apple's notarization service before claiming a smooth Gatekeeper launch.

## Mac app flow

The menu-bar app persists a list of bundle IDs, names, and bundle paths. Window selection uses on-screen window metadata; it does not capture pixels. Accessibility observes minimization and restores minimized windows after authentication. Workspace notifications handle focus changes, hiding, launches, exits, sleep, and session changes.

`LockPolicy` owns process-scoped unlocks and generation-based authentication invalidation. A successful Touch ID response can create a grant only for the selected protected app and current process. Relocking, cancellation, or changing the target invalidates an old response. No grants are persisted. The application covers locked app windows with native behind-window blur panels that intercept input. A Touch ID modal appears in front when the user returns. It does not hide or minimize the protected app: doing so transfers focus and can dismiss the unlock modal. A deterministic activation-event replay guards this regression. macOS may display content before overlays are positioned.

## Chrome flow

Persistent `declarativeNetRequest` rules redirect protected top-level network requests to a local lock page and block matching subresources. The service worker accepts mutations only from named extension pages and sends a fresh request ID to the allowlisted native host. Swift uses `deviceOwnerAuthenticationWithBiometrics`, with fallback hidden and reuse disabled.

After a matching successful response, the worker checks that the tab and lock generation have not changed. A session allowance is scoped to the tab/domain. Switching tabs or Chrome windows, leaving the domain, restarting Chrome, and locking the screen revoke access. A document-start guard and navigation checks add coverage for cached pages.

## Release

Build the macOS artifacts on macOS, run all checks, and create a source ZIP. Publish a tag pointing to the tested commit with these assets:

- `OpenLocker-0.1.0-macOS.dmg`
- `OpenLocker-0.1.0-macOS.zip`
- `OpenLocker-0.1.0-source.zip`
- `SHA256SUMS.txt`

The [manual checklist](TESTING.md) covers the hardware and OS integration that automated checks cannot establish. Record unperformed checks in release notes.

Official references: [Chrome native messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging), [Chrome network rules](https://developer.chrome.com/docs/extensions/reference/api/declarativeNetRequest), [Apple biometric-only authentication](https://developer.apple.com/documentation/localauthentication/lapolicy/deviceownerauthenticationwithbiometrics), and [native behind-window blur](https://developer.apple.com/documentation/appkit/nsvisualeffectview/blendingmode-swift.enum/behindwindow).
