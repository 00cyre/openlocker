# OpenLocker demo

A 32-second illustrated walkthrough, authored in [HyperFrames](https://github.com/heygen-com/hyperframes). Shows website locking, automatic Touch ID, Mac window selection, input-blocking blur, and relocking when you leave.

The screens use sample content and OpenLocker's existing visual design. This is an animation, not a recording or a functional security demo. The macOS Touch ID prompt is simplified. It is deliberately silent for README playback.

## Edit and render

Requires Node.js 22+, FFmpeg, and the pinned HyperFrames CLI. The first run downloads the CLI and its render dependencies; fonts and GSAP are bundled locally.

```sh
cd docs/demo
npm run dev             # editable preview and timeline
npm run check           # lint, runtime, layout, motion, contrast, craft
npm run render          # 1080p, 30 fps MP4 in renders/
```

For a persistent preview, use `HYPERFRAMES_NO_TELEMETRY=1 npx --yes hyperframes@0.9.19 preview --background`. Stop it with the same command and `--stop` instead of `--background`.

`index.html` mounts four independent scenes. Edit UI and animation in `compositions/`, shared styling in `assets/demo.css`, and the brand colors/closing line in the root composition's variables. [SPEC.md](SPEC.md) defines the visual direction, [STORYBOARD.md](STORYBOARD.md) maps the scenes, and [REVIEW.md](REVIEW.md) records validation.

The README GIF is derived from the MP4 at 960px wide and 12 fps using FFmpeg's two-pass palette filter. Generated renders and HyperFrames caches are ignored by Git and excluded from source packages.

## Credits

- OpenLocker UI and fingerprint: this repository, MIT.
- Inter: bundled under the [SIL Open Font License](assets/fonts/OFL-inter.txt).
- GSAP 3.15.0: copyright GreenSock, under its [standard license](https://gsap.com/standard-license). The vendor file retains its license header.
- HyperFrames registry `browser-device-stage` and `oversized-cursor` were consulted as authoring references. The final scenes contain editable product-specific markup and an adapted cursor shape.
