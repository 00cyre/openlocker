# Demo review

The v0.1.5 walkthrough shows protection, automatic authentication, continued access while switching tabs/apps, and a labeled five-minute idle time jump before relocking. It uses OpenLocker's palette, fingerprint graphic, controls, and lock-page wording with generic sample content. The illustrated Touch ID sheet is simplified. No real browser tabs, documents, or biometric information appear.

Protecting Notes immediately blurs the app and opens Touch ID. After authentication, changing focus leaves Notes clear; the blur returns only after the explicit idle time jump. Window geometry stays fixed throughout. Chrome's protected page disappears while locked and reappears after authentication; changing tabs preserves the domain's unlock.

Validation:

- HyperFrames 0.9.19 `check --json`: passed with zero lint, runtime, layout, motion, or contrast errors.
- Inspected the changed moments at 9.8, 13.3, 27.5, 30.5, and 33.5 seconds, full-film beat sheets, all three scene-cut strips, and 360px phone sheets. No clipping or unintended overlap appeared in these samples. Sheets do not establish smoothness between samples.
- Opened and played the 35-second composition through to its final frame in the local HyperFrames browser preview.
- Rendered with `--quality delivery --fps 30 --workers 2 --strict`. FFprobe verified H.264 at 1920 × 1080, 30 fps, 1050 frames, exactly 35 seconds (2,072,027 bytes); the looping 960 × 540 GIF has 420 frames (2,262,577 bytes). Inspected the final idle-relock frame after encoding.
- Repository checks and source-package verification run before publication; generated caches, renders, and dependencies remain excluded.

Deliberate warnings:

- Silent film: intended for an autoplaying, looping README GIF. There is no audio to assess.
- Small incidental UI labels and brief secondary helper copy: the large captions carry the instructions; the product controls remain recognizable. The full-resolution MP4 is provided for closer viewing.
- Two composition files exceed the suggested line count. Each remains one self-contained, named scene; splitting its synchronized UI states would make this small walkthrough harder to edit.

The weakest view is the small browser popup on a phone. A dedicated portrait cut with a closer crop would improve it; the landscape version is composed for the GitHub README and desktop video.
