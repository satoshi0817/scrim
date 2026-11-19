# Scrim

[日本語](README.md)

Scrim is a macOS menu bar app that overlays your calendar, clocks, and web pages on the screen where you are working. Open it from the menu bar or by tapping Command twice.

## Getting started

1. Launch Scrim and select **レイアウトを編集…** (Edit Layout) from its menu bar menu.
2. Choose **パネルを追加** (Add Panel), pick a widget or page, and drag it into place. Drag its edges to resize it. Choose **完了** (Done) to return to normal viewing.
3. Double-tap Command to pin the overlay, or hold the second press for a temporary peek. The gesture requires macOS Input Monitoring permission. While pinned, use Command-comma to choose settings or layout editing, or Command-Shift-E to toggle editing directly. Press Escape in viewing mode or switch apps to dismiss Scrim.

## Panels

| Panel | What it shows |
| --- | --- |
| Upcoming events and monthly calendar | See events by day, time until the next event, attendance status, and links to join meetings. Choose calendars, the number of days to display, and keywords to exclude. Grant macOS Calendar access to read your events. No Google OAuth setup is required. |
| Clock and world clock | Switch between analog and digital displays, show several cities on the digital clock, or compare working hours across time zones. |
| Tokyo weather and calculator | Check the temperature and optional three-hour forecasts, or use the keyboard for basic arithmetic. |
| Web, Notion, and files | Add a website, a Notion database view, a PDF, a text note, or a local HTML page with its images and stylesheets. |

Settings control appearance, interaction during a peek, and per-display layouts. With an upcoming-events panel configured, supported Macs can show a countdown for accepted events beside the display notch.

## Build from source

Use macOS 14 or later and Xcode or Command Line Tools with the macOS 26 SDK. Packaging the app also requires a code-signing certificate in your keychain.

```sh
git clone https://github.com/satoshi0817/scrim.git
cd scrim
./scripts/build-scrim.sh
open build/Scrim.app
```

The script selects an Apple Development certificate automatically. To choose another certificate, set `SIGNING_IDENTITY`. For everyday use, copy the bundle to `/Applications` before granting permissions. Run `swift build` to compile the package, or `swift test` with an Xcode installation that includes XCTest.

[Settings and verification guide (Japanese)](docs/scrim.md) · [Development history (Japanese)](docs/HANDOFF.md)
