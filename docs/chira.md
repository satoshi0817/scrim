# Chira (provisional)

Independent macOS 14+ SwiftPM executable and Foundation/CoreGraphics logic library. Existing NotchBrowser targets remain separate. All UI text and visual treatment are original to this implementation.

## Build and run

Use Swift 5.9 or newer on a Mac with the macOS 14 SDK or newer:

```sh
swift build --product Chira
swift test --filter ChiraTests
zsh scripts/build-chira.sh
open build/Chira.app
```

The new build script creates a local, ad-hoc signed app by default. Optional `SIGNING_IDENTITY` selects a signing identity. It does not notarize or publish. Distribution requires the repository's release signing and notarization procedure.

```sh
zsh scripts/build-chira.sh --trial
build/Chira.app/Contents/MacOS/Chira --render-previews build/chira-previews
```

`--trial` passes `-Xswiftc -DTRIAL_DIAGNOSTICS` to both executable and core. Debug builds also include diagnostics. Normal release builds exclude the diagnostic formatter, collection, labels and copy button. Preview mode emits ten `overlay-002-{empty,peek,pinned,dormant,menu,settings,hotkey-error,guide-no-permission,guide-permission,first-panel}.png` files, each 1800×1169 points (bitmap density follows AppKit). It uses cacheDisplay and an un-ordered host window, placeholder content, no web views and no hotkeys. The settings and hotkey-error previews show the default ⌃⌥Space shortcut; the latter injects a pure failure value without registering a hotkey. The guide previews reuse the real first-run view: default/Carbon has no permission text, while method B includes explanatory text and an inert permission button. No preview requests or preflights permissions. The first-panel preview shows one panel with pinned controls. Use a trial build for settings previews with diagnostics.

## Use

Default shortcut: Control–Option–Space (⌃⌥Space, Carbon keycode 49), separate from NotchBrowser's Control–Option–N. Previously saved shortcuts remain unchanged. Hold for a view-only overlay; release fades it over 0.15 seconds. A tap shorter than 0.25 seconds pins it; exactly 0.25 seconds is a hold. Pinned panels accept web input. Close with the shortcut, Escape or backdrop click. The menu-bar item opens settings. The shortcut recorder accepts a key with Control, Option or Command.

Registration failures appear immediately below the recorder with an orange recorder border and in a clickable status-menu item; the menu-bar title becomes `Chira ⚠︎`. A launch-time failure automatically opens only the settings window, even after the first run. Carbon handler/shortcut errors identify the shortcut and end with 「上の欄で別のキーを押してください。」; numeric system codes are omitted from user-facing text. Modifier B permission, creation, run-loop-source, enablement or disabled-tap failures explain the polling/toggle fallback. No error dialog is opened and NSApp.activate is never called. The key recorder remains available; recording a combination selects 「キーの組み合わせ」 and re-registers it. Successful registration restores the normal border and removes the warning. `HotkeyRegistrationStatus` is a pure value whose message contains no personal information. The left/right picker appears only for modifier-only methods; combination mode shows 「修飾キーだけで使う場合に選べます（権限が必要）」 instead. Modifier A uses Foundation's non-failable timer API; actual global device-flag availability still needs manual verification.

On a successful first launch, a minimal guide explains the shortcut and dismissal. `GuideContent(method:)` in ChiraCore owns the permission copy and display policy used by settings, the guide and its previews. The permission block is absent for Carbon and present for both modifier-only methods. Its wording is 「修飾キーだけで使う場合は、入力監視の許可が必要です。」. From method A, the permission button first selects method B and opens settings; only a subsequent explicit button press while B is selected requests access. The guide and settings use the same settings window, and the guide can open the full settings view. Other preview states retain their layout and content.

Only the display containing the mouse when opening is used, including its complete screen frame. Placement is stored as fractions of that full `NSScreen.frame`, in bottom-left coordinates local to that display (not visibleFrame, backing pixels or desktop-global coordinates). Frames are restored for the current display size, snapped to an 8-point grid/nearby edges (10-point threshold), minimum 240×160, and clamped to keep 40 points visible. Drag the header and resize using the seven-point edge/corner zones. The header menu is visible only while pinned and reloads, opens the current URL externally, duplicates or deletes. HTTP and HTTPS inputs are accepted; a missing scheme becomes HTTPS.

The panel pool retains the four most recently viewed panels, up to twelve records. Hidden overlays keep web views alive using alpha=0 and ignore mouse input. Eviction asynchronously snapshots before releasing a web view; replacements wait for eviction to finish so at most four web views exist. Dormant panels show a snapshot at 50% alpha, a rounded 「休止中」 badge and a secondary 「クリックで再開」 line. The same rendering is used in previews. Clicking recreates content at its URL with a spinner. A recreated site loses in-page state; navigation, authentication and site behavior follow WebKit. No external favicon downloads are performed.

## Input and permission

Carbon registers both press and release and relies exclusively on those events, without polling physical key state or switching to toggle mode. Modifier A polls combined-session device flags every 10 ms only when selected. Modifier B uses a listen-only event tap and distinguishes modifier keycodes. The input-monitoring request is made only by the explicit settings button while B is selected; other paths only preflight. No Accessibility request is made. Without B permission, presses observed through flags polling toggle the overlay. A disabled or unavailable event tap also falls back to polling/toggle. The 10 ms timer exists only for modifier A or modifier B fallback. Re-selecting a method resets its input session.

Global physical input and Spaces behavior require manual validation on the target machine. No-permission polling behavior can vary by macOS version; if device flags are unavailable, choose the Carbon shortcut. Test permission behavior by launching the app bundle through LaunchServices, since command-line launching may inherit the terminal's permissions. The app never calls NSApp.activate. A pinned overlay calls makeKey each time it appears; peek never calls makeKey. After hiding finishes, if the overlay remains key and settings is not key, NSApp.deactivate returns keyboard focus to the previous application. A revision guard prevents stale fade completions from deactivating a re-shown overlay. VisibilityPlan defines alpha, mouse handling, key acquisition, pinned pill and fade duration; all visibility plans prohibit orderOut.

## Isolated test copies

Settings storage is injected into `SettingsStore` through `SettingsStorage`. The running app uses a named UserDefaults suite; previews and all Chira tests use `MemorySettingsStorage`, a dictionary of JSON data with no disk writes. Production default is `com.satoshi0817.Chira`. `CHIRA_DEFAULTS_SUITE` overrides the suite; `CHIRA_DEFAULT_SHORTCUT=ctrl-opt-cmd-f19` overrides its shortcut at launch for test copies. Example:

```sh
CHIRA_DEFAULTS_SUITE=chira-test-manual CHIRA_DEFAULT_SHORTCUT=ctrl-opt-cmd-f19 build/Chira.app/Contents/MacOS/Chira
```

No Chira test or preview creates a UserDefaults suite, so the Chira test suite creates no `chira-test-*.plist`. Persistence coverage writes JSON through the storage protocol and reads it through a fresh SettingsStore sharing the same memory storage. Previously created preference files are not deleted by these tests. Settings previews include diagnostics only in DEBUG/TRIAL_DIAGNOSTICS builds. Diagnostics contain only timing, source, observed physical modifier keycode and left/right name, permission boolean, counts and this process's RSS; no URLs, page titles, usernames or paths. The observed modifier comes from flagsChanged keycodes or transitions in polled device bits, never the configured side. Before any observation (including Carbon mode) it reads none. Observation state and formatting are compiled only in diagnostic builds.

## Supervisor verification

Run the commands above outside the task sandbox. Also build `swift build -c release --product Chira` and verify the resulting binary excludes `press→release:`, `process RSS:` and `テキストをコピー`. Manually exercise quick/long Carbon holds without input-monitoring permission, repeated pinned key focus and focus return after hide, settings retaining key focus during hide, rapid hide/re-show during a fade, WebKit input retention across hide/show, five-panel eviction/revival, all resize zones, background dismissal, both modifier sides, denied permission and disabled-tap fallback, multiple displays and a third-party full-screen Space. Preview images do not validate global input or Spaces behavior.
