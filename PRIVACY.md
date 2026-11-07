# Privacy

OpenLocker has no accounts or analytics and does not transmit browsing history, page content, protected app/domain lists, or fingerprints. Protection and recovery state are stored locally as described below. Update checks contact GitHub for public release metadata; clicking Update downloads the signed release from GitHub. These requests expose ordinary network information such as your IP address to GitHub. No protected site or app information is included.

The extension stores a protected-domain list and a recovery copy in `chrome.storage.local`. A local locked-tab journal stores original URLs (including paths, queries, and fragments), tab/window IDs, positions, saved page titles, pinned status, and selected-tab status so reloads can restore them. Entries are removed after unlocking, navigating away, removing protection, or deliberately closing the tab. This journal stays inside the same Chrome profile and is never sent to the helper or GitHub. Temporary grants identify a domain and its last-use timestamp in `chrome.storage.session`; Chrome session rules enforce access. Rules are local to the Chrome profile. The original destination is carried in the local lock-page URL and can remain in browser history. Uninstalling the extension removes its Chrome storage and rules; browser history is controlled separately by Chrome.

A separate local title record follows currently open protected tabs, including while unlocked, and is removed on closing the tab, navigating away from protected sites, or removing protection. Locked tab titles and site icons remain visible in the tab strip by design. Chrome’s favicon API supplies the site icon locally; OpenLocker does not request remote icon URLs while locked. Lock-page input is used only to start Touch ID. On normal web pages, a content script reports the occurrence of trusted input at most once a second, including inside frames. The worker verifies that the tab and Chrome window are active before renewing an existing protected-domain grant. Only the protected domain’s last-use timestamp is retained for the current browser session. No key contents, pointer coordinates, text, or input event details are recorded or transmitted.

The native helper receives an operation, a fresh request ID, the running extension version, and (for authentication) the protected domain. Local status checks store only the most recently reported version in `~/Library/Application Support/OpenLocker/extension-runtime.json` so the Mac app can show a reload reminder. No Chrome profile identifiers, URLs, or unlock grants are stored in this receipt. It is display-only state; with multiple profiles, each extension checks its own version and the Mac app shows the most recently reported one. An explicit update operation downloads and installs the verified Chrome components. macOS displays the system Touch ID prompt and returns an authentication result. Neither OpenLocker component receives fingerprint images or biometric templates. Any enrolled fingerprint for the active macOS user can authenticate.

Permissions:

| Permission | Purpose |
| --- | --- |
| `storage` | Remember protected domains, temporary domain grants, and cached update metadata locally. |
| `tabs` | Identify the current site, retain its title, and replace already-open protected pages. |
| `favicon` | Show Chrome’s stored site icon on the lock page. Covered by the existing `tabs` permission. |
| `nativeMessaging` | Ask the local Swift helper for Touch ID authentication or an explicit verified update. |
| `declarativeNetRequestWithHostAccess` | Install persistent domain redirects/blocks and temporary domain allowances across tabs. |
| HTTP/HTTPS host access | Apply blocking and a document-start guard across the sites the user chooses. |
| `webNavigation` | Recheck protected navigation, including cached documents. |
| `idle` | Revoke access when the Mac is locked or globally idle. |
| `alarms` | Expire each website’s grant and check locally for newly installed extension files. |

The UI uses bundled assets and system fonts. The Mac app checks for releases at launch and every six hours. The extension checks when its popup or settings opens, with results cached locally for an hour. A separate check asks the local helper about installed extension files every five minutes, on browser/extension startup, and when update UI opens. It does not contact GitHub or open Touch ID. These checks do not install anything automatically. A user-requested Mac update also installs the extension files; Chrome activation still requires Reload. Normal browsing after a successful unlock still contacts the website as usual. No claim is made about the privacy practices of those sites or Chrome itself.

## Mac menu-bar app

The native app stores protected app bundle IDs, display names, and installed paths in `~/Library/Application Support/OpenLocker/protected-apps.json`. Unlock grants exist only in process memory and are lost when OpenLocker exits. A local preference remembers whether the welcome message was shown. Optional Start at login registration uses macOS Service Management. During a Mac app update, a local `update-session.json` checkpoint records the running protected app IDs, paths, process IDs, hidden state, and locked state. It expires after five minutes and is consumed once during the update handoff. It does not contain biometric data or reusable authentication grants. Existing apps are left running; a missing protected app may be relaunched at its recorded, validated path.

Window selection reads on-screen window bounds and owning process IDs. Accessibility permission is used to observe window changes and restore a minimized window after authentication. The app reads elapsed time since system input and the foreground app ID to renew only that app’s in-memory timestamp. Each app expires after five minutes without use, regardless of activity in other apps. It does not inspect input contents. The blur uses the macOS compositor; OpenLocker does not capture screen pixels, record keystrokes, or send application/window metadata anywhere. The menu-bar app remains running to react to focus/window events; the Chrome helper runs on demand.

Accessibility is a broad OS permission. The app uses it for the behaviors above, and the full source is available in `macapp/`. Removing a protected app requires Touch ID through the UI. Deleting the local configuration or stopping the process remains possible for someone with control of the Mac.
