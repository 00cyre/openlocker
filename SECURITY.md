# Security model

OpenLocker helps prevent casual viewing of selected websites in an enabled Chrome profile. It is not a substitute for locking macOS or for a separate OS account. Local administrator access, extension removal, alternate browsers/profiles, developer tools, malicious sites, and local file changes are outside its threat model.

## Authentication

- A new `LAContext` performs biometric-only authentication for each request. Authentication reuse is zero; password and Apple Watch fallback policies are not used.
- Failed, cancelled, timed-out, unavailable, or malformed native responses do not create a grant.
- The host accepts only its compiled extension origin, caps messages at 16 KiB, validates request IDs and domain names, and keeps stdout exclusively for protocol messages.
- Content scripts can request only a decision about their own top-level page. Mutating messages must originate from named extension pages. Native authentication is never forwarded from a content script.
- Grants are temporary and scoped to one tab/domain. Persistent network blocks remain in place during authentication. Concurrent relocking or navigation invalidates a pending unlock.

## Limits

Extension storage and source files are not tamper-resistant. The public manifest key provides a stable development ID, not authenticity or protection against a malicious replacement. The local helper is ad-hoc signed and is not distributed as a notarized binary.

Network interception does not cover every Chrome cache or protected surface. The document guard and navigation listener provide additional coverage, not an isolated trusted display against hostile website code. The guard also briefly covers unprotected HTTP(S) documents while asking the worker for a decision; if the extension stops responding, refresh after restoring/removing it.

Do not use this project as the sole protection for sensitive material on a shared or untrusted machine.

## Reporting

For a vulnerability, use GitHub's private vulnerability reporting if available. Otherwise contact the repository owner through their published GitHub contact details. Please do not post a working exploit or private browsing data in a public issue.

## Native Mac app locking

The menu-bar app places `NSVisualEffectView` blur/input-blocking panels above protected app windows, uses Accessibility to detect minimization, and reacts to workspace activation/focus events. The original app stays in place while a Touch ID modal owns keyboard focus. It never hides or minimizes an app as its locking action. It cannot block OS-level app launches or render a trusted lock before every frame. A protected window may appear briefly before the overlay is positioned; Mission Control, notifications, app-switcher thumbnails, and other system surfaces can expose app content. Unusual windows and full-screen/Spaces transitions may not be covered reliably. This is a visual/input guard within the normal desktop, not a system-wide prohibition on app input or data access.

Unlocks are bound to an app bundle ID and process ID and are never persisted. Locking, cancelling, changing the target, and process restarts invalidate grants or pending authentication as appropriate. Touch ID is required to remove a protected app or quit through OpenLocker's menu. Force quitting, killing the process, deleting its configuration, or changing the binary bypasses this convenience lock. Login launch is optional; protection starts only once OpenLocker is running.

The installer contains precompiled universal binaries and is ad-hoc signed, not Developer ID signed or notarized. Its checksums detect accidental corruption but are not independent proof of publisher identity. Gatekeeper is never disabled, and Accessibility must be approved by the user. Granting permission to one installed build may need to be repeated after an update.
