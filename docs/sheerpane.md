# Sheerpane

Independent macOS 14+ SwiftPM executable and Foundation/CoreGraphics logic library. Existing NotchBrowser targets remain separate. All UI text and visual treatment are original to this implementation.

## Sheerpane trial.3 naming review

This review changes product naming and settings migration only. Existing trial.2 entry, shortcut and hidden modifier-only controls remain unchanged. Command tap-then-hold belongs to a separate task and is not implemented here.

Designer revision: the Sheerpane bundle is version **0.1.0 (3)**; only CFBundleVersion changed. Trial.2 settings hide the modifier-only method dropdown, side picker and parenthesized permission hint without rewriting previously saved input-method preferences. The recording action button reserves at least 124 points (or its native fitted width plus padding), so 「キャンセル」 is shown in full. The field always shows the saved shortcut, including during retry. The error identifies the attempted shortcut and uses explicit sentence boundaries to avoid dangling Japanese fragments. A separate secondary line says 「<saved shortcut> のまま使えます」. The duplicate/generic light and dark failure fixtures deliberately retain ⌃⌥⌘F19 and attempt ⌃⌥P, making the distinction reviewable. No numeric error codes appear in these UI strings. The renderer preserves all light/dark states under the Sheerpane trial.3 filenames below; no real registration, ordered window or permission request is used.

The menu-bar entry loads the Designer PDF assets at 18×18 points with `isTemplate = true` and accessibility description Sheerpane. Success uses `MenuBarTemplate.pdf`; any registration failure uses `MenuBarWarningTemplate.pdf`. There is no system-symbol fallback or drawn warning badge. Review labels identify the selected resource name. Tooltip: Sheerpane. Menu order: 「開く (<current shortcut>)」, 「設定…」, optional actionable registration feedback, separator, 「Sheerpane を終了」. Open pins on the display containing the pointer without activating the app. Settings and app reopening activate only the settings window. The first-run guidance reads 「Sheerpane は画面上部のメニューバーにいます。」 followed by the configured shortcut instruction. Ice, a notch and macOS layout can still hide or displace a status item; this implementation cannot guarantee visibility.

Dock display defaults ON in DEBUG / TRIAL_DIAGNOSTICS builds and OFF in ordinary release builds. 「Dock に Sheerpane を表示」 saves an explicit preference that takes priority in either build. Reading the default does not persist it. The app applies regular/accessory activation policy without rewriting Info.plist or changing system preferences.

Press 「変更」 to start 「記録中」. The temporary local key-down monitor consumes only events in the key settings window during recording; Escape, Cancel, window closure or loss of key focus ends it. Only keycodes and supported modifier flags enter the pure recording model. No event characters, ordinary text, raw input logs or uploads are used. Control, Option or Command plus a regular key is required; shift-only, modifier keys, Escape and out-of-range keycodes are rejected. Labels use physical ANSI names and may differ from a non-ANSI keyboard layout. Other system/app shortcuts can be intercepted before the recorder; all conflicts cannot be detected. Secure-input behavior is unverified.

A candidate is registered before the old Carbon registration is removed. Only a successful registration commits the shortcut/method to settings. Failed registration and cancellation retain the saved binding; failed candidates can be retried. Choosing 「既定に戻す」 uses the same validated registration path, so a failed reset cannot overwrite the saved key. The already-active combination can be confirmed through its Carbon callback while recording. The F19 test-copy shortcut is unchanged; its override is now named `SHEERPANE_DEFAULT_SHORTCUT`. Registration feedback contains no numeric error codes or internal API identifiers. Only the SDK-verified duplicate result uses already-registered guidance; other failures ask the user to select another key and retry without asserting a collision.

In addition to the ten legacy fixtures, the renderer writes sixteen LIGHT/DARK review fixtures using the same icon generator, EntryState, settings and recording models:

```text
sheerpane-trial3-light-icon.png
sheerpane-trial3-light-menu.png
sheerpane-trial3-light-settings.png
sheerpane-trial3-light-hotkey-error.png
sheerpane-trial3-light-hotkey-generic-error.png
sheerpane-trial3-light-recording.png
sheerpane-trial3-light-first-run.png
sheerpane-trial3-light-dock.png
sheerpane-trial3-dark-icon.png
sheerpane-trial3-dark-menu.png
sheerpane-trial3-dark-settings.png
sheerpane-trial3-dark-hotkey-error.png
sheerpane-trial3-dark-hotkey-generic-error.png
sheerpane-trial3-dark-recording.png
sheerpane-trial3-dark-first-run.png
sheerpane-trial3-dark-dock.png
```

All fixtures are 1800×1169 points. They are explicitly labeled previews, not evidence of actual status-bar visibility. They use memory storage, no ordered windows, no real hotkey registration, no input monitor and no permission request. The Dock review preference is explicitly ON in memory for deterministic output. Diagnostics remain compiled only in diagnostic builds.

Supervisor commands (not executed by the sandbox worker):

```sh
swift build --product Sheerpane
swift test --filter SheerpaneTests
./scripts/build-sheerpane.sh --trial
build/Sheerpane.app/Contents/MacOS/Sheerpane --render-previews build/sheerpane-trial3-previews
```

Real keys, actual menu-bar visibility, secure input, battery impact, Dock transitions and full-screen focus behavior require supervisor/manual verification. No such behavior is marked verified by source inspection or offscreen fixtures.

## Build and run

Use Swift 5.9 or newer on a Mac with the macOS 14 SDK or newer:

```sh
swift build --product Sheerpane
swift test --filter SheerpaneTests
zsh scripts/build-sheerpane.sh
open build/Sheerpane.app
```

The new build script creates a local, ad-hoc signed app by default. Optional `SIGNING_IDENTITY` selects a signing identity. It does not notarize or publish. Distribution requires the repository's release signing and notarization procedure.

```sh
zsh scripts/build-sheerpane.sh --trial
build/Sheerpane.app/Contents/MacOS/Sheerpane --render-previews build/sheerpane-previews
```

`--trial` passes `-Xswiftc -DTRIAL_DIAGNOSTICS` to both executable and core. Debug builds also include diagnostics. Normal release builds exclude the diagnostic formatter, collection, labels and copy button. Preview mode emits ten `overlay-002-{empty,peek,pinned,dormant,menu,settings,hotkey-error,guide-no-permission,guide-permission,first-panel}.png` files, each 1800×1169 points (bitmap density follows AppKit). It uses cacheDisplay and an un-ordered host window, placeholder content, no web views and no hotkeys. The settings preview shows the default ⌃⌥P shortcut. Failure previews retain ⌃⌥⌘F19 while injecting an attempted ⌃⌥P failure, without registering a hotkey. The two legacy guide previews are explicitly captioned as legacy validation fixtures, never current shipping first-run screens: default/Carbon has no permission text, while forced method B includes explanatory text and an inert permission button. The light/dark `first-run` reviews instead show the full settings view actually opened at first launch. No preview requests or preflights permissions. The first-panel preview shows one panel with pinned controls. Use a trial build for settings previews with diagnostics.

## Use

Default shortcut: Control–Option–P (⌃⌥P, Carbon keycode 35), separate from NotchBrowser's Control–Option–N. Previously saved shortcuts remain unchanged. Hold for a view-only overlay; release fades it over 0.15 seconds. A tap shorter than 0.25 seconds pins it; exactly 0.25 seconds is a hold. Pinned panels accept web input. Close with the shortcut, Escape or backdrop click. The window-shaped menu-bar icon opens a menu with Open, Settings and Quit. The explicit Change button starts ordinary combination recording.

Registration failures appear immediately below the recorder with the existing recorder feedback and the Designer warning template. The actionable menu indication opens settings. TRIAL.2 feedback distinguishes the SDK-verified duplicate result from generic failure, hides all numeric codes and internal identifiers, and does not promise complete conflict detection. A launch-time failure still opens settings. Recording failure preserves the saved binding and its existing active registration; retry or cancel remains available. Legacy modifier input settings remain supported, but modifier-only recording remains deferred to a separate task.

Error-copy verification used the installed header `/Library/Developer/CommandLineTools/SDKs/MacOSX14.5.sdk/System/Library/Frameworks/Carbon.framework/Versions/A/Frameworks/HIToolbox.framework/Versions/A/Headers/CarbonEventsCore.h`: `eventHotKeyExistsErr = -9878`, `eventHotKeyInvalidErr = -9879` (commented as currently unused), and `eventInternalErr = -9868`. The installed 15.5 and Xcode SDK headers agree. The duplicate comment includes registration within the current process and exclusive-registration conflicts across processes; it does not identify another app. Therefore the duplicate guidance says 「このキーはすでに登録されています。別のキーを選んでください。」, rather than asserting another app or the system owns it. Generic errors make no collision claim. Numeric status values are used internally for classification only and are not interpolated into settings, menu, recording feedback, guides or fixtures. No numeric registration diagnostics were added. The light/dark `hotkey-error` fixtures inject the verified duplicate value; `hotkey-generic-error` injects the verified internal-error value. No real registration occurs during rendering.

The first launch automatically opens the full settings window and brings it to the front. Reopening the running app through Finder, Launchpad or `open -a Sheerpane` also opens settings, regardless of whether another window is visible. Only settings activation uses NSApp.activate(ignoringOtherApps: true), followed by makeKeyAndOrderFront. The top instruction is built by `GuideContent.shortcutSentence(shortcut:)` from the currently configured shortcut's displayString. `Shortcut.default` is the single default definition; reading the fallback does not write settings, and saved shortcuts take priority. `GuideContent(method:)` in SheerpaneCore owns the permission copy and display policy used by settings, the guide and its previews. The legacy guide model still describes permission blocks for modifier-only methods, but trial.2 settings hide the modifier method dropdown, side picker and permission controls. Its wording is 「修飾キーだけで使う場合は、入力監視の許可が必要です。」. The retained `showGuide()` method has no callers. If invoked by future code with a non-Carbon method, it would construct the legacy permission guide; this is not an entry path in the current app. The legacy handler can select B from A and can request access from B, but all current settings permission affordances are hidden. No permission handler is executed by tests or previews.

Only the display containing the mouse when opening is used, including its complete screen frame. Placement is stored as fractions of that full `NSScreen.frame`, in bottom-left coordinates local to that display (not visibleFrame, backing pixels or desktop-global coordinates). Frames are restored for the current display size, snapped to an 8-point grid/nearby edges (10-point threshold), minimum 240×160, and clamped to keep 40 points visible. Drag the header and resize using the seven-point edge/corner zones. The header menu is visible only while pinned and reloads, opens the current URL externally, duplicates or deletes. HTTP and HTTPS inputs are accepted; a missing scheme becomes HTTPS.

The panel pool retains the four most recently viewed panels, up to twelve records. Hidden overlays keep web views alive using alpha=0 and ignore mouse input. Eviction asynchronously snapshots before releasing a web view; replacements wait for eviction to finish so at most four web views exist. Dormant panels show a snapshot at 50% alpha, a rounded 「休止中」 badge and a secondary 「クリックで再開」 line. The same rendering is used in previews. Clicking recreates content at its URL with a spinner. A recreated site loses in-page state; navigation, authentication and site behavior follow WebKit. No external favicon downloads are performed.

## Input and permission

Carbon registers both press and release and relies exclusively on those events, without polling physical key state or switching to toggle mode. Modifier A polls combined-session device flags every 10 ms only when selected. Modifier B uses a listen-only event tap and distinguishes modifier keycodes. The retained request handler could request input monitoring only if explicitly invoked while B is selected; its settings button is always hidden and `showGuide()` has no callers. Current shipping entry paths expose no request affordance. Other paths only preflight. No Accessibility request is made. Without B permission, presses observed through flags polling toggle the overlay. A disabled or unavailable event tap also falls back to polling/toggle. The 10 ms timer exists only for modifier A or modifier B fallback. Re-selecting a method resets its input session.

Global physical input and Spaces behavior require manual validation on the target machine. No-permission polling behavior can vary by macOS version; if device flags are unavailable, choose the Carbon shortcut. Test permission behavior by launching the app bundle through LaunchServices, since command-line launching may inherit the terminal's permissions. The overlay never calls NSApp.activate; settings alone uses NSApp.activate(ignoringOtherApps: true) before makeKeyAndOrderFront. A pinned overlay calls makeKey each time it appears; peek never calls makeKey. After hiding finishes, if the overlay remains key and settings is not key, NSApp.deactivate returns keyboard focus to the previous application. A revision guard prevents stale fade completions from deactivating a re-shown overlay. VisibilityPlan defines alpha, mouse handling, key acquisition, pinned pill and fade duration; all visibility plans prohibit orderOut.

## Isolated test copies

Settings storage is injected into `SettingsStore` through `SettingsStorage`. The running app tries its named UserDefaults suite and falls back to standard defaults only when no suite override is present; previews and SettingsStore tests use `MemorySettingsStorage`, a dictionary of JSON data with no disk writes. Migration tests use an injected memory domain that also preserves arbitrary property-list values. Production default is `com.satoshi0817.Sheerpane`. `SHEERPANE_DEFAULTS_SUITE` overrides the suite; `SHEERPANE_DEFAULT_SHORTCUT=ctrl-opt-cmd-f19` overrides its shortcut at launch for test copies. Example:

```sh
SHEERPANE_DEFAULTS_SUITE="sheerpane-test-$(uuidgen)" SHEERPANE_DEFAULT_SHORTCUT=ctrl-opt-cmd-f19 build/Sheerpane.app/Contents/MacOS/Sheerpane
```

No Sheerpane test or preview creates a UserDefaults suite, so the Sheerpane test suite creates no `sheerpane-test-*.plist`. Persistence coverage writes JSON through the storage protocol and reads it through a fresh SettingsStore sharing the same memory storage. Previously created preference files are not deleted by these tests. Settings previews include diagnostics only in DEBUG/TRIAL_DIAGNOSTICS builds. Diagnostics contain only timing, source, observed physical modifier keycode and left/right name, permission boolean, counts and this process's RSS; no URLs, page titles, usernames or paths. The observed modifier comes from flagsChanged keycodes or transitions in polled device bits, never the configured side. Before any observation (including Carbon mode) it reads none. Observation state and formatting are compiled only in diagnostic builds.

## Settings migration

On an ordinary first launch, `SettingsMigration` reads a persistent snapshot of the former provisional bundle domain, copies each missing key verbatim to `com.satoshi0817.Sheerpane`, then sets `sheerpaneSettingsMigrated` on the new side only. Existing destination values, including false and empty data, win. The old domain is never written or deleted. A later launch with the flag reads no old settings. An explicit `SHEERPANE_DEFAULTS_SUITE` override skips migration entirely. Preview rendering exits before opening any defaults suite. The migration storage protocol permits memory-only tests; no test opens either real domain.

The private prerelease is planned only: tag `v0.1.0-trial.3`, zip `Sheerpane-0.1.0-trial.3.zip`. This task does not publish it. The repository name remains `overlay-browser-trial`.

## Supervisor verification

Run the commands above outside the task sandbox. Also build `swift build -c release --product Sheerpane` and verify the resulting binary excludes `press→release:`, `process RSS:` and `テキストをコピー`. Manually exercise quick/long Carbon holds without input-monitoring permission, repeated pinned key focus and focus return after hide, settings retaining key focus during hide, rapid hide/re-show during a fade, WebKit input retention across hide/show, five-panel eviction/revival, all resize zones, background dismissal, both modifier sides, denied permission and disabled-tap fallback, multiple displays and a third-party full-screen Space. Preview images do not validate global input or Spaces behavior.

## Designer icon assets (TASK-OVERLAY-014 continuation)

Original Designer inputs are preserved under `design/icons/`: all ten `AppIcon.iconset/*.png`, `sheerpane-icon.svg`, `sheerpane-icon-small.svg`, `sheerpane-icon-1024.png`, all three `layers/*.svg`, and both menu-bar templates in PDF/PNG/SVG/2x PNG formats. The archive was not copied. Layers are kept for future Icon Composer work.

Runtime resources are `Sources/SheerpaneAssets/Resources/{AppIcon.icns,MenuBarTemplate.pdf,MenuBarWarningTemplate.pdf}`. SwiftPM processes them in the `SheerpaneAssets` resource bundle. The build script copies that bundle plus the three resources into `Sheerpane.app/Contents/Resources`; the loader prefers app resources, then the SwiftPM bundle. `CFBundleIconFile` points to `AppIcon.icns`. Both icon and dock reviews include the app icon alongside the template/settings review.

Native `iconutil` was attempted twice here and returned “Invalid Iconset”, including with a workspace-local temporary directory. All ten PNG dimensions were checked. The checked-in ICNS packages the original PNG bytes, unchanged, as standard ICNS elements; `file` recognizes it as an icon and `sips` reports 1024×1024. Supervisor should verify native regeneration outside this sandbox before distribution:

```sh
iconutil -c icns design/icons/AppIcon.iconset -o build/AppIcon-native.icns
```

The four added `IconResourceTests` check loadable SwiftPM resources, 18-point accessible template loading, failure/recovery selection, and app resource lookup using an isolated fixture bundle without launching it. The existing entry recovery test now asserts the Designer resource names instead of the retired symbol identity. All existing tests remain; Swift tests, builds and PNG rendering are reserved for supervisor execution.

## Bundled launch defaults fallback (TASK-OVERLAY-014)

Foundation documents `initWithSuiteName:` with the current application bundle identifier as an error (installed `Foundation.framework/Headers/NSUserDefaults.h`, line 67). Under LaunchServices, the requested shipping suite matches the app identifier, so it can return nil; the former unconditional guard then trapped. This does not require an existing preferences file.

`SettingsDefaultsPolicy.open` now tries the shipping suite and lazily falls back to `UserDefaults.standard` if it fails. In the bundled app, standard defaults use the Sheerpane application domain. Any explicit `SHEERPANE_DEFAULTS_SUITE` is opened only with `suiteName:`; failure still terminates, without touching standard defaults or enabling migration. Tests inject memory factories rather than opening preferences.

Migration still uses the selected destination object to read the old persistent domain, copies missing keys only, and sets the new-side flag. It never opens or modifies the legacy suite. Preview rendering still exits before preferences setup.

For CLI or swift-run launches, always set a unique throwaway suite override. If it is unset and opening the shipping suite fails, `UserDefaults.standard` can belong to a different process domain when `Bundle.main` is not the Sheerpane app. Settings and migration writes could then reach that other domain, while migration snapshots still name the Sheerpane domain. This fallback is intended for the correctly identified bundled app.

The supervisor-provided native AppIcon.icns (169624 bytes) is retained unchanged; it supersedes the earlier handmade ICNS discussed above. No icon or permission-guide behavior changes are part of this fix. Supervisor will rerun tests/builds and retry LaunchServices launch; this worker does not launch the app or read real preferences.
