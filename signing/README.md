# Release identity

`release.cer` is OpenLocker's **public** self-signed code-signing certificate. The private key is not in this repository. Release builds pin this certificate, use hardened runtime, and let `codesign` synthesize a certificate-bound designated requirement. They refuse ad-hoc signing.

This gives successive releases the same code identity without a paid Apple Developer account. It does **not** make the app Apple-trusted or notarized: Gatekeeper may still require first-launch approval. Never weaken the requirement to just a bundle identifier, add a trusted root to users' Macs, disable Gatekeeper, or strip quarantine to work around this.

The encrypted signing identity is backed up as the repository Actions secrets `OPENLOCKER_SIGNING_P12` (base64 PKCS#12) and `OPENLOCKER_SIGNING_PASSWORD`. They are available only to the release workflow, not pull-request checks. Keep the private key; regenerating it changes the identity and requires users to approve Accessibility again. Certificate changes must be treated as an explicit migration. The installer detects this through Security.framework's code-requirement validation.

## Local release

Import the existing identity into a dedicated keychain. Set `OPENLOCKER_SIGNING_IDENTITY` to its fingerprint and `OPENLOCKER_SIGNING_KEYCHAIN` to that keychain, then run `npm run build:release`. Do not create a new key for each build. Normal `build:installer` without these variables produces a development build only.

The regression test in `test:installer` modifies a release bundle, re-signs it with the same identity, and verifies it against the **previous** bundle's designated requirement. It also checks that a different ad-hoc identity triggers renewal. This exercises macOS signature validation; the physical Accessibility and Touch ID flow still needs the manual checks in `docs/TESTING.md`.

[Apple's code-signing guidance](https://developer.apple.com/library/archive/technotes/tn2206/_index.html) describes how designated requirements identify updates and how persistent self-signed identities work. A future Developer ID migration could add Apple notarization, but it also needs a one-time permission migration from this identity.
