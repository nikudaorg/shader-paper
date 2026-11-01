# Patterns: desktop and lock-screen appearances

This fork adds independent appearances to [Shader Paper](https://github.com/shrekoverflow/shader-paper). It does not use WallpaperMachine, Wallpaper Engine assets, a Steam account, a video loop, or a browser renderer.

## Install

Use an Apple silicon Mac running macOS 26 or later. The current defaults target a 15-inch MacBook Air at 1440 × 932 logical points.

1. Disable WallpaperMachine's lock-screen feature and quit WallpaperMachine so it does not restore a competing provider after this app applies its selection.
2. Unzip the native distribution, move **Shader Paper.app** into `~/Applications` or `/Applications`, and keep only one installed copy of this fork. Its original Shader Paper provider identifiers are preserved. Do not run a separate upstream copy at the same time.
3. Open the app. This build is locally ad-hoc signed, not notarized; if macOS blocks it, use **System Settings → Privacy & Security → Open Anyway** for this app.
4. Leave **Desktop: Calm Sky / Animate off** and **Lock screen: Patterns / Animate on**, then choose **Apply appearances**. The app can be closed afterward.
5. Lock with Control–Command–Q. The actual wallpaper extension receives the explicit mode from WallpaperAgent; it does not simulate a lock screen or replace the password UI.

**Restore Previous Wallpaper** restores the selection backed up before activation. Applying a new configuration keeps the first backup and records timestamped intermediate backups, using Shader Paper's existing selection mechanism.

## Controls

The app holds all controls outside the lock screen: independent shader selection and animation switches for desktop/lock, pattern cell size, flow speed, subdivision, flow character, hue, color drift, pattern pause, and regeneration. Save/load settings transfers a full appearance configuration. Load settings also accepts the browser generator's settings JSON.

The initial pattern uses seed 3845275645, 19% cell size, speed 0.2, subdivision 0.26, restless flow and the slowly drifting purple palette from the user's earlier wallpaper. Its two recursive steps choose 2×2 or 3×3 splits, giving scales 1, 2, 3, 4, 6 and 9. The native CPU simulation preserves mixed-size neighbors and density contrast. Metal evaluates antialiased motifs, without subdivision crossfades.

**Calm Sky** is an original static blue abstract landscape rendered once by a time-independent Metal shader. It does not keep an animation timer running.

## Clock and login blur

The lock-only compositor applies a feathered, local nine-tap blur with a default radius of 6 logical points. Clock and login regions are centered horizontally, initially at Y=155 and Y=770 in the 1440×932 reference. Retina backing and adaptive resolution use the same normalized locations.

Under **Adjust protected regions**, adjust center Y, width and height to match the clock size and login UI chosen in macOS. These are configurable regions, not claims that macOS exposes widget rectangles. They do not draw or replace the OS clock, login field or password handling. Desktop output is unaffected.

## Presentation contract

WallpaperAgent's XPC request is inspected for its named `presentationMode` field, following Phosphene's Mirror-based implementation. Each surface owns its mode and activity state. Missing fields preserve that surface's state; unknown modes use the conservative desktop appearance. Clock speed, whether a timer runs, and screen animation are not inputs to appearance selection.

Every art shader can read a `UInt32` at **fragment buffer 2**:

- 0: unknown
- 1: desktop (`active`, `default`, `desktop`)
- 2: locked
- 3: idle
- 4: screen saver
- 5: picker preview

The default screen-saver and preview roles use the lock shader, while idle uses the desktop shader. Blur is enabled only for explicit mode 2. Animation policy remains separate from appearance. A mode-only change forces a full-resolution redraw even when the selected shader and saved clock are unchanged; unchanged updates do not redraw. Role-specific cached kernels and clocks preserve the lock simulation across desktop presentation.

Configuration is encoded into Shader Paper's existing wallpaper-choice data, so the sandboxed extension needs no unrestricted shared preferences directory or network. The app retains its editable copy at `~/Library/Application Support/Visual Meditation/Appearance.json`. Existing plain shader-name configurations and saved clock keys are migrated on read.

## Validation and limits

GitHub's Apple silicon macOS runner builds the app and renders every bundled shader. Tests cover native flow, topology and GPU buffer layout; explicit XPC field reflection; serialized appearance selection; the mode uniform and redraws at frozen time; static desktop output; lock-only blur, no blur outside the regions, and opaque output; plus upstream motion, resolution, daylight and restore behavior.

These tests do not drive the real macOS login UI or WallpaperAgent lock/wake cycle. Private wallpaper APIs can change; test a lock/unlock and sleep/wake on the target Mac. No SIP changes or recorded media are required.
