# Privacy

OpenLocker makes no application network requests, has no accounts or analytics, and does not collect or transmit browsing history, page content, or fingerprints.

The extension stores a list of protected domains in `chrome.storage.local`. Temporary grants identify a tab and domain in `chrome.storage.session` and Chrome session rules. Rules are local to the Chrome profile. The original destination is carried in the local lock-page URL and can remain in browser history. Uninstalling the extension removes its Chrome storage and rules; browser history is controlled separately by Chrome.

The native helper receives only an operation, a fresh request ID, and the protected domain. macOS displays the system Touch ID prompt and returns an authentication result. Neither OpenLocker component receives fingerprint images or biometric templates. Any enrolled fingerprint for the active macOS user can authenticate.

Permissions:

| Permission | Purpose |
| --- | --- |
| `storage` | Remember protected domains and temporary tab grants locally. |
| `tabs` | Identify the current site and replace already-open protected pages. |
| `nativeMessaging` | Ask the locally installed Swift helper to authenticate using Touch ID. |
| `declarativeNetRequestWithHostAccess` | Install persistent domain redirects/blocks and temporary tab-scoped allowances. |
| HTTP/HTTPS host access | Apply blocking and a document-start guard across the sites the user chooses. |
| `webNavigation` | Recheck protected navigation, including cached documents. |
| `idle` | Relock when macOS reports that the screen is locked. |

The UI uses bundled assets and system fonts. GitHub links open only when clicked. Normal browsing after a successful unlock still contacts the website as usual. No claim is made about the privacy practices of those sites or Chrome itself.
