# WallpaperNoDim

Keep your wallpaper bright when using native macOS Fill / Maximize and window tiling.

[Chinese (Simplified)](README.zh-CN.md)

I built this small desktop app with help from GPT-6 in Codex after macOS started dimming my wallpaper when I filled or tiled windows. The desktop-overlay workaround worked on my Mac running **macOS 27.0, build 26A428**. Other versions have not been tested.

## How it works

The app reads the wallpaper image for each connected screen and displays a static copy in a borderless window, just above the desktop window level. These windows ignore mouse clicks and join all Spaces. For dynamic HEIC files, it reads the embedded light/dark image mapping instead of always displaying the primary frame. Automatic selection follows the system appearance; recognized wallpaper-specific Light/Dark settings take precedence.

On my setup, the copies remain bright while I use native Fill / Maximize. The system's dimming behavior still exists underneath: this app provides a visual workaround. It does not resize app windows, modify system files, or require disabling System Integrity Protection (SIP).

## Run and quit

Open `WallpaperNoDimTest.app`, or run this command from the project directory:

```sh
open WallpaperNoDimTest.app
```

The menu-bar item uses a warning-light icon (`warninglight`). **Launch at Login** is enabled on first launch; uncheck it to disable automatic startup. If macOS requires approval, use **Open Login Items Settings…**. Subsequent launches respect changes made in System Settings. Choose **Refresh Wallpaper** after changing your wallpaper to reload the images for all connected screens. Choose **Quit and restore wallpaper** to remove the overlay immediately. System light/dark appearance changes and screen-layout changes also trigger a refresh automatically.

## Build

Install Xcode or Command Line Tools with a macOS SDK, then run:

```sh
./build.sh
```

The script builds the app and applies a local ad-hoc signature. Sources: [`WallpaperNoDimTest.m`](WallpaperNoDimTest.m) for the app and [`WallpaperImage.m`](WallpaperImage.m) for image decoding.

## Limitations

- The overlay is a static image. Light/dark HEIC variants are supported; video playback and exact solar/time-of-day transitions are not reproduced.
- Use **Refresh Wallpaper** after changing the wallpaper or its options. System appearance and screen-layout changes refresh automatically.
- Wallpaper-specific appearance overrides are read on a best-effort basis from the macOS wallpaper configuration. If the format is unrecognized, the app follows system appearance.
- No launch-at-login behavior is installed.
- This is an experimental workaround verified on one Mac, not a system-wide fix tested across macOS versions.

## Experimental alternative: WindowManager patching — NOT TESTED

During investigation, we located `TiledWallpaperDimComponent` in Apple's WindowManager. In build **26A428**, its update path selects a hard-coded dimming value of `0.5` or `0`. A patched copy was prepared that changes the `0.5` instruction to `0` in both binary slices. The copied app passed local signature verification, but **it was never installed or tested at runtime**. A debugger attach attempt to the system process was denied while SIP was enabled; the exact enforcement mechanism was not confirmed.

The candidate instruction locations and source hash are recorded in [`experimental/patch-details.json`](experimental/patch-details.json). They apply only to the exact inspected binary. Runtime addresses also require accounting for ASLR. This metadata is a research record, not an installer or a complete patching procedure.

### SIP commands for further research

**I have not tested the SIP-disabled patching route.** Disabling SIP weakens macOS protections and is unnecessary for the working overlay app. Disabling it alone does not establish that debugger access, modified binaries, or a replacement system service will work.

For researchers who choose to investigate, Apple's documented procedure is:

1. Start in macOS Recovery. On Apple silicon, shut down, hold the power button until startup options appear, then choose Options → Continue. On Intel, start up while holding Command-R. See [Apple's Recovery guide](https://support.apple.com/en-us/102518).
2. Open Utilities → Terminal, run `csrutil disable`, follow the prompts, then restart.
3. In normal macOS, inspect the state with `csrutil status`.
4. After research, return to Recovery, run `csrutil enable`, and restart to restore SIP.

See [Apple's SIP documentation](https://developer.apple.com/documentation/security/disabling-and-enabling-system-integrity-protection). These are SIP configuration steps, not instructions to replace WindowManager. No system-volume modification or persistent patch installer is provided here.

I'd love feedback from anyone who can validate the patch route, find a real dimming preference, or improve the overlay. Please include your macOS version/build, hardware, relevant protection settings, and whether native Fill / Maximize stays functional.

## Thanks

Thanks to **GPT-6 in Codex** for helping investigate the behavior and build this workaround.

## Dynamic wallpaper references

[Apple: desktopImageURL(for:)](https://developer.apple.com/documentation/appkit/nsworkspace/desktopimageurl(for:)) returns the wallpaper file URL, not a rendered frame for the current appearance. The HEIC light/dark mapping is documented in [the original dynamic-wallpaper metadata investigation](https://gist.github.com/leptos-null/c88e8c3c0f9f6860c7500826031c8551).
