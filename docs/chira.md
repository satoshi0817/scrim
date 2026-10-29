# Chira (provisional)

Independent macOS 14+ SwiftPM executable and Foundation/CoreGraphics logic library. All UI text and visual treatment are original to this implementation.

## Build and run

Use Swift 5.9 or newer on a Mac with the macOS 14 SDK or newer:

```sh
swift build --product Chira
swift test --filter ChiraTests
zsh scripts/build-chira.sh
open build/Chira.app
```

The new build script creates a local, ad-hoc signed app by default. Optional `SIGNING_IDENTITY` selects a signing identity. It does not notarize or publish. Distribution requires Developer ID signing and notarization.

```sh
zsh scripts/build-chira.sh --trial
build/Chira.app/Contents/MacOS/Chira --render-previews build/chira-previews
```

`--trial` passes `-Xswiftc -DTRIAL_DIAGNOSTICS` to both executable and core. Debug builds also include diagnostics. Normal release builds exclude the diagnostic formatter, collection, labels and copy button. Preview mode emits six `overlay-002-{empty,peek,pinned,dormant,menu,settings}.png` files, each 1800×1169 points (bitmap density follows AppKit). It uses cacheDisplay and an un-ordered host window, placeholder content, no web views and no hotkeys. Use a trial build for settings previews with diagnostics.

## Use

Default shortcut: Control–Option–N. Hold for a view-only overlay; release fades it over 0.15 seconds. A tap shorter than 0.25 seconds pins it; exactly 0.25 seconds is a hold. Pinned panels accept web input. Close with the shortcut, Escape or backdrop click. The menu-bar item opens settings. The shortcut recorder accepts a key with Control, Option or Command.

Only the display containing the mouse when opening is used, including its complete screen frame. Placement is stored as fractions of that full `NSScreen.frame`, in bottom-left coordinates local to that display (not visibleFrame, backing pixels or desktop-global coordinates). Frames are restored for the current display size, snapped to an 8-point grid/nearby edges (10-point threshold), minimum 240×160, and clamped to keep 40 points visible. Drag the header and resize using the seven-point edge/corner zones. The header menu reloads, opens the current URL externally, duplicates or deletes. HTTP and HTTPS inputs are accepted; a missing scheme becomes HTTPS.

The panel pool retains the four most recently viewed panels, up to twelve records. Hidden overlays keep web views alive using alpha=0 and ignore mouse input. Eviction asynchronously snapshots before releasing a web view; replacements wait for eviction to finish so at most four web views exist. Dormant panels show a dimmed snapshot and 休止中. Clicking recreates content at its URL with a spinner. A recreated site loses in-page state; navigation, authentication and site behavior follow WebKit. No external favicon downloads are performed.

## Input and permission

Carbon registers both press and release. Modifier A polls combined-session device flags every 10 ms only when selected. Modifier B uses a listen-only event tap and distinguishes modifier keycodes. The input-monitoring request is made only by the explicit settings button while B is selected; other paths only preflight. No Accessibility request is made. Without B permission, presses observed through flags polling toggle the overlay. A missing Carbon release is detected from physical key state and switches to toggle mode. A disabled event tap also falls back to polling/toggle. Re-selecting a method resets its input session.

Global physical input and Spaces behavior require manual validation on the target machine. No-permission polling behavior can vary by macOS version; if device flags are unavailable, choose the Carbon shortcut. Test permission behavior by launching the app bundle through LaunchServices, since command-line launching may inherit the terminal's permissions. The app never calls NSApp.activate. A pinned overlay calls makeKey each time it appears.

## Isolated test copies

Settings are injected into `SettingsStore` and only use a named UserDefaults suite. Production default is `com.satoshi0817.Chira`. `CHIRA_DEFAULTS_SUITE` overrides the suite; `CHIRA_DEFAULT_SHORTCUT=ctrl-opt-cmd-f19` overrides its shortcut at launch for test copies. Example:

```sh
CHIRA_DEFAULTS_SUITE=chira-test-manual CHIRA_DEFAULT_SHORTCUT=ctrl-opt-cmd-f19 build/Chira.app/Contents/MacOS/Chira
```

XCTest creates `chira-test-<UUID>` suites and removes their persistent domains in tearDown. Preview settings use a temporary suite removed immediately. Diagnostics contain only timing, source, modifier keycode, permission boolean, counts and this process's RSS; no URLs, page titles, usernames or paths.

## Supervisor verification

Run the commands above outside the task sandbox. Also build `swift build -c release --product Chira` and verify the resulting binary excludes `press→release:`, `process RSS:` and `テキストをコピー`. Manually exercise quick/long holds, repeated pinned key focus, WebKit input retention across hide/show, five-panel eviction/revival, all resize zones, background dismissal, both modifier sides, denied permission, missing release fallback, multiple displays and a third-party full-screen Space. Preview images do not validate global input or Spaces behavior.
