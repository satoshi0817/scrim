# Scrim

[日本語](README.md)

Scrim is a macOS menu bar app that overlays your calendar, clocks, and web pages on the screen where you are working. Open it from the menu bar or by tapping Command twice.

## Getting started

1. Launch Scrim and select **レイアウトを編集…** (Edit Layout) from its menu bar menu.
2. Choose **パネルを追加** (Add Panel), then click a card or drag it directly from the gallery onto the canvas. New panels start two columns wide and one row high. Nearby panels move or shrink during the drag to show where the new panel will fit. Drag an edge to resize and release to snap to the grid. Choose **完了** (Done) to return to normal viewing.
3. Double-tap Command to open or close the pinned overlay, or hold the second press for a temporary peek. The gesture requires macOS Input Monitoring permission. While pinned, use Command-comma to edit the layout, open settings, or quit Scrim. Command-Shift-E toggles layout editing. Press Escape in viewing mode or switch apps to dismiss Scrim.

In Edit Layout, use the **+** below the canvas to add an empty page. While pinned, switch pages with a two-finger horizontal scroll, Option-Command-Left/Right (customize modifiers in Settings → Input), or the dots at the bottom. Scrim remembers each layout and the last selected page.

In Edit Layout, hovering over a panel blurs it (shapes stay visible, text does not) and shows a centered hint to click for the menu or drag to move. Click a panel (or right-click it) to expand its settings into the center of the screen, or drag it to move it. The panel name appears at the top left, and tabs switch between settings and actions. Drag an edge or corner to resize the panel. To remove a panel, choose **パネルを削除** (Remove Panel) there. **完了** (Done) closes it. To remove a whole page, click its number below the canvas, choose the numbered delete action, and confirm. Drag a page number onto another to reorder pages.

### Multiple displays

Scrim opens on the display under the pointer. In Settings → Panels → Display, you can change the following:

- **すべてのディスプレイで同じ配置** (Same layout on all displays): When on (the default), every display shows the same panels at the same proportions of the screen. When off, Scrim remembers each panel's position, size, and stacking order for each display. Adding or removing panels and changing URLs still applies to every display. Switching keeps the most recent arrangement. Turning it back on shares the layout of the display where panels were most recently added, removed, or moved.
- **表示するディスプレイ** (Displays to show on): Turn Scrim on or off for each connected display. When the pointer is on a display that is turned off, the gesture and shortcut do nothing. Opening, editing the layout, or opening settings from the menu bar shows Scrim on a display that is turned on. The notch meeting timer works independently of this setting.

## Panels

| Panel | What it shows |
| --- | --- |
| Upcoming events and monthly calendar | See events by day, time until the next event, attendance status, and links to join meetings. Choose calendars, the number of days to display, and keywords to exclude. Grant macOS Calendar access to read your events. No Google OAuth setup is required. |
| Clock and world clock | Switch between analog and digital displays, show several cities on the digital clock, or compare working hours across time zones. |
| Tokyo weather and calculator | Check the temperature and optional three-hour forecasts, or use the keyboard for basic arithmetic. |
| Notion tasks | See the open tasks in a Notion database, with the nearest due dates first. Add tasks, complete them (with a few seconds to undo), and edit their names and due dates. |
| Text | Write notes directly in a panel and apply bold, underline, bullets, or numbered lists. Scrim saves the text and formatting automatically. |
| Web, Notion, and files | Add a website, a Notion database view, a PDF, a text file, or a local HTML page with its images and stylesheets. |

To change a web panel’s URL or switch between desktop and mobile viewing, click the panel in Edit Layout and use the **設定** (Settings) tab. Each panel saves its own choice. Web links in web panels, PDFs, notes, and Notion tasks open in your Mac’s default browser.

### Notes

Choose **パネルを追加** (Add Panel) → **テキスト** (Text) to create a note. Click the body in normal view to edit it, and use the toolbar to apply formatting. In a list, Return starts a new item. Press Return on an empty item to finish the list.

Choose Extra Small, Small, Medium, Large, or Extra Large for notes and Notion tasks independently in Settings → Panels → **文字サイズ** (Text Size). Medium is the default. In Edit Layout, click a panel and use **設定** (Settings) for notes or **文字サイズ** (Text Size) for Notion tasks. The choice applies to every panel of that type.

### Notion tasks

1. In the Notion developer portal, create a personal access token or an internal connection, and copy its token. A personal access token expires after the period you choose when creating it (one year by default). When it expires, register a new one.
2. In Scrim, open Settings → Panels → **Notion**, paste the token, and click **保存して確認** (Save and Check). Scrim stores the token only in this Mac's Keychain.
3. If you use an internal connection, add it to the database in Notion with **•••** → **Connections**. To create a new database, also add it to the page that will contain the database.
4. In Edit Layout, add **Notionタスク** (Notion Tasks). Finish editing, then click **データベースを設定…** (Set Up Database). Search for an existing database, paste its URL (from **Copy link**) or ID and click **開く** (Open), or open the **新規作成** (Create New) tab and pick the page that will contain it.
5. For an existing database, choose the column that marks completion (a checkbox or a status) and, optionally, a due date column. For a status column, choose the value to set when completing. All values in that value's group, such as Complete, count as done and are hidden.

Click a task to open it in the panel. There you can change its name, due date and status, and read and edit its page content. Click a paragraph, heading, bulleted or numbered item, to-do, quote, callout or code block to edit its text. To-dos can be checked off. The field at the bottom adds a paragraph, to-do or bulleted item at the end of the page. To delete a block, click **削除** (Delete) twice; it moves to Notion's Trash. Blocks with formatting such as bold or links, and images, tables and other blocks, are shown read-only (marked with a lock); edit those in Notion. The button at the top right opens the task in Notion.

Type in the field above the list to filter tasks by name. The filter button next to it narrows the list by due date (overdue, due today, due this week, no due date), by status or tags (select and multi-select columns), and by assignee. Each panel saves these three filters; the text filter is not saved. To filter by assignee, choose an assignee (people) column in the **列の対応付け** (Map Columns) tab.

The Notion task panel refreshes every minute while visible. To change its database or columns later, click the panel in Edit Layout.

Settings control appearance, interaction during a peek, and per-display layouts. With an upcoming-events panel configured, supported Macs can show a countdown for accepted events beside the display notch.

In Upcoming Events, a blue check marks accepted invitations and an amber question mark marks unanswered ones. The card background takes on a warm tint 30 minutes before an event and turns redder as the start approaches. A thin, translucent scrollbar overlays the cards while you scroll.

To preview the notch without a calendar event, open **Settings → Panels → ノッチの予定タイマー → 表示を試す** (Try Preview). Switch between upcoming and ongoing events and move the remaining-time slider to see the countdown colors change.

Settings → General shows the running version and can check GitHub for updates. Notifications and automatic installation are separate options. With either enabled, Scrim checks on launch and every six hours. An installed update takes effect on the next launch.

## Memory use

Web panels use the most memory, because each page runs in its own WebKit process. Scrim keeps that down as follows:

- When Scrim has been closed for 10 minutes, it frees the pages of web panels and reloads them the next time you open it. To turn this off, open Settings → Panels → **メモリ** (Memory). Sign-ins are kept, but text you were typing and scroll positions are not.
- When you switch pages, Scrim keeps the web sessions of only the previous page.
- When macOS runs low on memory while Scrim is closed, it frees web pages right away.

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
