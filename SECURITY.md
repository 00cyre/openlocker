# Security model

OpenLocker helps prevent casual viewing of selected websites in an enabled Chrome profile. It is not a substitute for locking macOS or for a separate OS account. Local administrator access, extension removal, alternate browsers/profiles, developer tools, malicious sites, and local file changes are outside its threat model.

## Authentication

- A new `LAContext` performs biometric-only authentication for each request. Authentication reuse is zero; password and Apple Watch fallback policies are not used.
- Failed, cancelled, timed-out, unavailable, or malformed native responses do not create a grant.
- The host accepts only its compiled extension origin, caps messages at 16 KiB, validates request IDs and domain names, and keeps stdout exclusively for protocol messages.
- Content scripts can request only a decision about their own top-level page. Mutating messages must originate from named extension pages. Native authentication is never forwarded from a content script.
- Grants are temporary and scoped to an authenticated domain across tabs in the current Chrome profile. They include its subdomains and resources requested from that domain. Five minutes without system input revokes every grant; activity resets the idle clock but never creates a new grant. Persistent network blocks remain in place during authentication. Concurrent relocking or navigation invalidates a pending unlock.

## Limits

Extension storage and source files are not tamper-resistant. The public manifest key provides a stable development ID, not authenticity or protection against a malicious replacement. Published binaries use a persistent self-signed certificate; they are not Apple-notarized. Source builds are ad-hoc signed unless a signing identity is configured.

Network interception does not cover every Chrome cache or protected surface. The document guard and navigation listener provide additional coverage, not an isolated trusted display against hostile website code. The guard also briefly covers unprotected HTTP(S) documents while asking the worker for a decision; if the extension stops responding, refresh after restoring/removing it.

Do not use this project as the sole protection for sensitive material on a shared or untrusted machine.

## Reporting

For a vulnerability, use GitHub's private vulnerability reporting if available. Otherwise contact the repository owner through their published GitHub contact details. Please do not post a working exploit or private browsing data in a public issue.

## Native Mac app locking

The menu-bar app places `NSVisualEffectView` blur/input-blocking panels above protected app windows, uses Accessibility to observe window changes, and reacts to workspace activation/focus events. The original app stays in place while a Touch ID modal owns keyboard focus. It never hides or minimizes an app as its locking action. It cannot block OS-level app launches or render a trusted lock before every frame. A protected window may appear briefly before the overlay is positioned; Mission Control, notifications, app-switcher thumbnails, and other system surfaces can expose app content. Unusual windows and full-screen/Spaces transitions may not be covered reliably. This is a visual/input guard within the normal desktop, not a system-wide prohibition on app input or data access.

Unlocks are bound to an app bundle ID and process ID and are never persisted. Focus changes, hiding, and minimizing preserve an unlocked session. Five minutes without system input locks all protected apps. Returning to the Mac requires fresh Touch ID; new input alone never restores grants. Locking, cancelling, changing the target, and process restarts invalidate grants or pending authentication as appropriate. Touch ID is required to remove a protected app or quit through OpenLocker's menu. Force quitting, killing the process, deleting its configuration, or changing the binary bypasses this convenience lock. Login launch is optional; protection starts only once OpenLocker is running.

The installer contains precompiled universal binaries signed with the persistent release identity, not a Developer ID certificate. Its checksums detect accidental corruption but are not independent proof of publisher identity. Gatekeeper is never disabled, and Accessibility must be approved by the user. Updates signed with the same identity should retain that approval; migration from an ad-hoc build needs one renewal.

## Updates and Chrome setup

The Mac app and extension request public release metadata from GitHub. Updates download only the expected asset from this repository. Before mounting an update, the updater verifies its disk-image signature against the bundled release certificate; it then verifies the installer signature and version before execution. A trusted initial installation is required: the public certificate pins subsequent updates but does not establish independent publisher trust for the first download.

Installation is serialized, rejects older helper versions, and preserves the protected app list. Chrome-only setup and updates replace only the extension and its helper. They never replace or restart the Mac app. A desktop update requires Touch ID when apps are protected and briefly stops protection while the app relaunches.

Chrome setup prepares a stable unpacked extension folder and registers its native host for the compiled extension ID. Chrome's initial extension approval remains a user action. Web pages cannot request updates, and repository-loaded extensions must switch to the managed folder once before their Update button can install releases.
