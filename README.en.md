# Scrim

[日本語](README.md)

Scrim is a macOS menu bar app that overlays your calendar, clocks, and web pages on the screen where you are working. Open it from the menu bar or by tapping Command twice.

## Getting started

1. Launch Scrim and select **レイアウトを編集…** (Edit Layout) from its menu bar menu.
2. Choose **パネルを追加** (Add Panel), then click a card or drag it directly from the gallery onto the canvas. New panels start two columns wide and one row high. Nearby panels move or shrink during the drag to show where the new panel will fit. Drag an edge to resize and release to snap to the grid. Choose **完了** (Done) to return to normal viewing.
3. Double-tap Command to open or close the pinned overlay, or hold the second press for a temporary peek. The gesture requires macOS Input Monitoring permission. While pinned, use Command-comma to choose settings or layout editing, or Command-Shift-E to toggle editing directly. Press Escape in viewing mode or switch apps to dismiss Scrim.

In Edit Layout, use the **+** below the canvas to add an empty page. While pinned, switch pages with a two-finger horizontal scroll, Option-Command-Left/Right (customize modifiers in Settings → Input), or the dots at the bottom. Scrim remembers each layout and the last selected page.

In Edit Layout, use the panel’s top-right menu and choose **パネルを削除** (Remove Panel). To remove a whole page, click its number below the canvas, choose the numbered delete action, and confirm. Drag a page number onto another to reorder pages.

## Panels

| Panel | What it shows |
| --- | --- |
| Upcoming events and monthly calendar | See events by day, time until the next event, attendance status, and links to join meetings. Choose calendars, the number of days to display, and keywords to exclude. Grant macOS Calendar access to read your events. No Google OAuth setup is required. |
| Clock and world clock | Switch between analog and digital displays, show several cities on the digital clock, or compare working hours across time zones. |
| Tokyo weather and calculator | Check the temperature and optional three-hour forecasts, or use the keyboard for basic arithmetic. |
| Web, Notion, and files | Add a website, a Notion database view, a PDF, a text note, or a local HTML page with its images and stylesheets. |

To change a web panel’s URL or switch between desktop and mobile viewing, open its top-right menu in Edit Layout and choose **Webパネル設定…** (Web Panel Settings). Each panel saves its own choice.

Settings control appearance, interaction during a peek, and per-display layouts. With an upcoming-events panel configured, supported Macs can show a countdown for accepted events beside the display notch.

In Upcoming Events, a blue check marks accepted invitations and an amber question mark marks unanswered ones. The card background takes on a warm tint 30 minutes before an event and turns redder as the start approaches. A thin, translucent scrollbar overlays the cards while you scroll.

To preview the notch without a calendar event, open **Settings → Panels → ノッチの予定タイマー → 表示を試す** (Try Preview). Switch between upcoming and ongoing events and move the remaining-time slider to see the countdown colors change.

Settings → General shows the running version and can check GitHub for updates. Notifications and automatic installation are separate options. With either enabled, Scrim checks on launch and every six hours. An installed update takes effect on the next launch.

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
