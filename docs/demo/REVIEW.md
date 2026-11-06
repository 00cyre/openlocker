# Demo review

The film follows one direct walkthrough: protect, authenticate, continue, leave, relock. It uses OpenLocker's real palette, fingerprint graphic, controls, and lock-page wording with generic sample content. The illustrated Touch ID sheet is simplified. No real browser tabs, documents, or biometric information appear.

The Mac sequence was corrected during review to show the immediate lock and automatic prompt after selecting a newly protected app. Window geometry stays fixed through blur, authentication, and relocking. The Chrome page disappears while locked and reappears after authentication.

Validation:

- HyperFrames 0.9.19 `check --json`: passed. No lint errors, runtime errors, layout errors, motion assertion failures, or contrast warnings.
- Inspected full-size popup, menu, blur, and authentication frames; beat sheets; all three scene-cut strips; 360px phone sheets; and eight frames around the Mac unlock transition.
- A separate visual review found no P0/P1 issues in the storyboard and review sheets. Sheets do not establish animation smoothness between samples.
- Opened and played the composition through to its final frame in HyperFrames' browser preview.
- Rendered with `--quality delivery --fps 30 --workers 2 --strict`. FFprobe verified H.264, 1920 × 1080, 30 fps, 960 frames, and exactly 32 seconds (1,995,438 bytes). Inspected decoded MP4 frames, including the Touch ID prompt, and the derived 960px GIF (2,199,441 bytes).
- Repository checks passed; built a source ZIP and verified that the demo sources/assets were included while render caches, generated renders, and dependencies were excluded.

Deliberate warnings:

- Silent film: intended for an autoplaying, looping README GIF. There is no audio to assess.
- Small incidental UI labels and brief secondary helper copy: the large captions carry the instructions; the product controls remain recognizable. The full-resolution MP4 is provided for closer viewing.
- Two composition files exceed the suggested line count after formatting. Each remains one self-contained, named scene; splitting its synchronized UI states would make this small walkthrough harder to edit.

The weakest view is the small browser popup on a phone. A dedicated portrait cut with a closer crop would improve it; the landscape version is composed for the GitHub README and desktop video.
