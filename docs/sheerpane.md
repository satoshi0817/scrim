## TASK-OVERLAY-008 / v0.1.0-trial.6（現行ソース・出荷引き継ぎ）

現行製品は **Sheerpane 0.1.0 (6)**。`CFBundleShortVersionString=0.1.0`、`CFBundleVersion=6`、bundle ID は `com.satoshi0817.Sheerpane`。アイコンは変更しません。Designer の r12b Approve と Lead の GO を受け、trial.6 として出荷する実装です。trial.5 はベース commit `7f5277aba4d453516458b0c04b3105d33992f62d` として出荷済みです。この作業の commit 時点では、trial.6 の commit SHA、tag SHA、zip SHA-256、CDHash、Release URL は未確定であり、出荷後に記入します。trial.1–trial.5 の履歴は保持します。

- 保存キー: `sameLayoutOnAllDisplays`（既定 ON）、`panels`（既存の共有配置）、`sharedLayoutReferenceSize`、`layoutsByDisplay`。参照サイズは共有・画面別とも Codable な `width` / `height` オブジェクトで保存します。旧 `panels` の割合値は維持し、未設定の参照サイズは移行後の初回表示画面から採用します。OFF の未登録画面には現在表示中の配置、または共有配置をコピーし、その後の編集はその画面だけに保存します。切断された画面の保存配置は削除しません。Chira 移行元への書き込みはありません。
- 識別: 注入可能な `DisplayUUIDProviding` を通し、ColorSync の `CGDisplayCreateUUIDFromDisplayID` と `CFUUIDCreateString` で得た UUID 文字列を `uuid:` キーにします。数値の display ID が変わっても同じ UUID の配置を復元します。UUID 作成失敗時は画面ごとにランダムな `ephemeral:` キーを発行し、永続化せず、別画面へ再利用しません。切断後は破棄する保守的な fallback のため、この場合の再接続復元は保証しません。
- r12b 配置: フレームだけを縮め、通常サイズの文字・chrome・Web コンテンツを再レイアウトします。layer / affine の視覚的スケールは使いません。通常のフレーム寸法目安は元の 0.6 倍以上、240×160pt 下限。保存順に左→右、上→下へ 12pt 間隔で折り返します。縦に不足すれば 28pt のタイトルバー刻みでカスケードし、後のパネルを手前に描画して各タイトルをクリック可能にします。必要な場合はフレーム高さをさらに削って画面内に収めます。画面高さが枚数×28pt に満たない場合だけ露出幅を画面高さ÷枚数とし、完全なタイトルバーや本文が読めないリスクを残します。自由な重なり圧縮は行いません。
- 設定文言は「すべてのディスプレイで同じ配置」。
- r12b 保存: 同じ配置が ON で shrink / wrap / cascade を行った画面では、表示用の配置・小画面参照サイズを共有配置へ保存しません。並べ替えは ID 順序のみ反映し、既存 ID の割合値と参照サイズを保持します。URL・追加削除は反映できます。補正不要な画面での移動・リサイズは共有配置に保存可能。OFF は表示どおり画面別に保存します。
- r12b 設定: helper 行の下端から「診断」見出しの上端まで約20ptを確保し、追加した分だけウインドウを下へ伸ばします。r11b のログイン・Dock の可変配置を維持します。r12b-layout-wrap / r12b-layout-stack / r12b-layout-settings の light / dark fixture は LayoutFitter を通し、メモリ保存と偽ログインサービスを使います。
- 仕上げ（未実装）:
  - 重ねたパネルが左の1列に集まらないよう、横に空きがあるときは列ごとに分けて重ねる。
  - ずらす幅の下限を 20pt にする。

監督側の検証（出荷前、2026-11-16 JST）: `swift test` は 160 件すべて成功。`./scripts/build-sheerpane.sh` と `./scripts/build-sheerpane.sh --trial` は成功。r12b プレビュー（折り返し、タイトルバーカスケード、設定の間隔 × ライト／ダーク）を確認済み。

未確認: 2台目のディスプレイでの実機確認、抜き差ししたあとの並びの復元、ポインタのある画面に出ること、重なったタイトルバーをクリックして前に出す操作。trial.4 と trial.5 の未確認項目も引き続き未確認。

# Sheerpane

Independent macOS 14+ SwiftPM executable and Foundation/CoreGraphics logic library. Existing NotchBrowser targets remain separate. All UI text and visual treatment are original to this implementation.

## TASK-OVERLAY-006 + guided 修正 / v0.1.0-trial.5（現行ソース・出荷引き継ぎ）

現行製品は **Sheerpane 0.1.0 (5)**。`CFBundleShortVersionString=0.1.0`、`CFBundleVersion=5`、bundle ID は `com.satoshi0817.Sheerpane`。アイコンは変更しません。Designer の r11b Approve と Lead の GO を受け、trial.5 として出荷する実装です。trial.4 はベース commit `29f90e871b44ca8e343fc18ba82d44735acc70f9` として出荷済みです。この作業の commit 時点では、trial.5 の commit SHA、tag SHA、zip SHA-256、CDHash、Release URL は未確定であり、出荷後に記入します。trial.1–trial.4 の履歴は保持します。

- guided は Bool true、文字列 "true"、Data 内の JSON Bool true / JSON 文字列 "true" / UTF-8 "true" を true として読みます。それ以外と未設定は false。初回案内の開始時と設定ウインドウを閉じるときに JSON Bool true で保存し直します。移行元の Chira 設定は読み取り専用で、書き込み・削除しません。
- 設定では、ジェスチャー説明の約 20pt 下に「ログイン時に Sheerpane を開く」と「Dock に Sheerpane を表示」を1つのグループとして置きます。保存 bool は真実にせず、`SMAppService.mainApp` のライブ状態を表示します。起動や設定を開いただけでは登録しません。既定はオフです。
- `.requiresApproval` のときはチェックをオンとして表示し、チェック見出しの先頭に左揃えで、secondaryLabel の補助文「システム設定の『ログイン項目』で許可が必要です」と「システム設定を開く」を出します。承認待ち・エラー用の高さは事前に空けず、出たときだけ伸びます。
- 登録失敗の文言は「ログイン項目に登録できませんでした。システム設定の『ログイン項目』を確認してください。」、解除失敗は「ログイン項目から外せませんでした。システム設定の『ログイン項目』を確認してください。」です。色は systemRed、全文を折り返して表示し、内部のエラー理由は出しません。どちらのエラーの下にも「システム設定を開く」を付けます。失敗したらチェックを実際の登録状態に戻します。
- `LoginItemService` / `LoginItemSettingsModel` を通し、テストとプレビューには `FakeLoginItemService` を注入します。実機でのログイン項目の登録と、システム設定での許可は未確認です。
- 後続 polish（未実装）: 許可カードの「あとで」を左、「許可する」を右に入れ替え、カードの高さを内容に合わせて詰めます。

監督側の検証（出荷前、2026-11-16 JST）: `swift test` は 144 件すべて成功（既存 132 + 新規 12）。`./scripts/build-sheerpane.sh` と `./scripts/build-sheerpane.sh --trial` は成功。r11b プレビュー（オフ、承認待ち、登録失敗、解除失敗 × ライト／ダーク）を確認済み。

追加テスト（GuidedAndLoginItemTests）:

- `testGuidedBoolTrue`
- `testGuidedUTF8True`
- `testGuidedStringTrue`
- `testGuidedJSONBoolAndStringTrue`
- `testGuidedFalseMissingAndInvalid`
- `testTwoFreshLaunchesShowGuidanceOnlyOnceAndDismissalRewritesBool`
- `testTwoLaunchesWithMigratedDataNeverShowGuidance`
- `testLoginDefaultOffAndConstructionHasNoSideEffects`
- `testLoginReflectsLiveStatusChanges`
- `testLoginApprovalCopyAndButtonVisibility`
- `testLoginRegisterAndUnregisterErrorsSurfaceAndRetainLiveStatus`
- `testStoredBoolCannotOverrideLiveLoginStatus`

### trial.4 から継続する 005 仕様

### ⌘ 2回押し peek の確定仕様

- 1回目の押下からリリースまで **≤0.30秒**、そのリリースから2回目の押下まで **≤0.40秒**。どちらも境界を含みます。2回目の key-down で直ちに peek を表示し、最低保持時間は設けません。
- 2回目のリリースが押下から **<0.25秒**なら pin、**≥0.25秒**なら hide。3つの数値は設定の「詳細」内だけで調整できます。
- 既定の「どちらの ⌘ でも」は左→右・右→左も成功。「左だけ」「右だけ」は反対側の押下で取り消し。両方の ⌘ の同時保持は常に取り消します。
- ⌘C、⌘Tab、⌘クリックを含む他キー・クリック、Shift / Option / Control など他修飾キーの出現・変化で取り消します。他修飾キーやマウスボタンが既に押されている場合は開始しません。
- 2回目を保持中の割り込みは `hideImmediately`：アニメーションなしで直ちに隠し、固定せず、元アプリのフォーカスを奪いません。peek は nonactivating・マウス透過で、`makeKey` / `NSApp.activate` を呼びません。実機では「⌘×2 → 2回目を保持したまま C」も確認します。
- Carbon の既定 **⌃⌥P** は独立した権限不要のフォールバックとして維持。入力監視なし・tap 作成失敗・無効化時も使用でき、tap を無限に自動再試行しません。

### 入力監視・許可カード

`DoublePressInput` は `.listenOnly` で監視し、イベントをそのまま返します。文字や非修飾キーコードを読まず、他キーは取り消しとして扱います。状態の記録は phase / cancel reason の閉じた値のみで、キー内容を記録・送信しません。カード本文は次のとおりです。

> Sheerpane は、押したキーの内容を記録・送信しません。⌘ を押したタイミングだけを使います。

- 自動表示は初回案内で一度、およびジェスチャーのチェックをオンにした直後（fn から有効な ⌘ ジェスチャーを再選択した場合を含む）だけ。未許可で設定を開いただけでは表示しません。「あとで」後は保存した deferred 状態で以降の自動表示を抑止し、再有効化時も手動の入口を使います。
- チェックの下に **「許可待ち（⌃⌥P で使用中）」＋「入力監視を許可…」** を表示。許可済みなら行全体を隠します。手動ボタンはカードを開くだけで OS の許可要求はしません。
- 未要求カードは主ボタン「許可する」と通常ボタン「あとで（⌃⌥P を使う）」。拒否時は「入力監視がオフになっています」と主ボタン「システム設定を開く」。主ボタンは Return の既定動作です。許可の自動検知後は「許可されました」を約2秒表示して閉じます。
- 入力監視の要求（`CGRequestListenEventAccess`）はカードの **「許可する」だけ**。`AppGesturePermission` の app-identity 検査を通る正規 app プロセスだけが実行可能です。preflight もその app 自身の identity で読み、シェルや helper の継承値を信用しません（実装は正しい bundle ID・.app・launchd 親 PID 1 を検査）。tap 開始には許可済み preflight も必要です。起動・設定を開く・テスト・プレビューから要求しません。
- 設定を開くボタンは該当ペインを開くだけで、許可やシステム設定を書き換えません。旧 trial.2 の権限ガイドは出荷 UI から到達できません。secure input 中はダイアログを出さず、「パスワード入力中は ⌘ の2回押しが使えません」というメニュー状態だけにします。

### fn / Globe（詳細だけの任意オプション）

`maskSecondaryFn` で検知。fn＋他キーは取り消し、listenOnly のため Fn-D 等のシステム操作を遮りません。fn 選択時はチェック名を「2回押しを使う」とし、recorder の下の Command 左右 picker は表示したまま無効化します。次の注意は fn 選択時かつ「詳細」を開いた場合だけ表示します。

- 🌐キーの設定を「何もしない」にする必要があります。
- fn とほかのキーを一緒に押したときは、Sheerpane は開きません（Fn-D などのシステムの操作はそのまま使えます）
- Apple 以外の外付けキーボードでは動かないことがあります。
- 🌐キーで入力ソースを切り替えている場合は、fn は使えません。

全項目は system regular 12pt、`secondaryLabelColor`、行高20pt・項目間6pt。文中の 🌐 は文字表示形式で描画し、先頭の絵文字マーカーは追加しません。「キーボード設定を開く」は注意文の下に左寄せで置き、クリック時にペインを開くだけです。キーボード・システム設定は書き換えません。

### 検証とプレビューの引き継ぎ

005 の既存検証に guided / 006 の 12 件を加え、出荷前の `swift test` は **144 件すべて成功**しました。イベントと保存先は合成値・`MemorySettingsStorage` のみ。今回の版数検証は `testSheerpaneResourceVersionIsZeroOneZeroBuildFive`。通常版と診断版（`--trial`）のビルドも成功しています。実キー・Input Monitoring・secure input・focus・実機のログイン項目登録とシステム設定での許可の確認は、offscreen 画像とは別です。

現在のプレビュー名は `sheerpane-trial5-{light,dark}-{state}.png`。state は `icon, menu, settings, hotkey-error, hotkey-generic-error, recording, first-run, dock, gesture-default, gesture-advanced, permission-unasked, permission-denied, permission-granted, menu-permitted, menu-waiting, menu-secure`。旧 `overlay-002-*.png` も維持します。過去レビューの `sheerpane-trial3-*` は当時の画像名として保持します。プレビューは非表示ウィンドウ・メモリ保存で、実 tap / hotkey / 許可要求を作りません。006 の状態は light/dark の fake fixture を追加しています。

Offscreen preview command:

```sh
build/Sheerpane.app/Contents/MacOS/Sheerpane --render-previews preview-out/r11
```

## Historical: Sheerpane trial.3 naming review

This section records TASK-OVERLAY-014 at that time, including its then-planned release and historical preview filenames. Trial.3 subsequently shipped; the trial.5 development section above is the current source specification.

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

The default gesture in trial.4 is Command double-press, specified above. Carbon Control–Option–P (⌃⌥P, keycode 35) remains the independent permission-free fallback; saved combinations remain unchanged. Carbon press/release hold-tap behavior is unchanged. Registration retry, cancellation and reset retain the existing saved-binding safety. Legacy modifier A/B polling and polling/toggle fallback are no longer shipping input paths; InputController now registers Carbon only. DoublePressInput owns the new listen-only gesture path.

Error-copy verification used the installed header `/Library/Developer/CommandLineTools/SDKs/MacOSX14.5.sdk/System/Library/Frameworks/Carbon.framework/Versions/A/Frameworks/HIToolbox.framework/Versions/A/Headers/CarbonEventsCore.h`: `eventHotKeyExistsErr = -9878`, `eventHotKeyInvalidErr = -9879` (commented as currently unused), and `eventInternalErr = -9868`. The installed 15.5 and Xcode SDK headers agree. The duplicate comment includes registration within the current process and exclusive-registration conflicts across processes; it does not identify another app. Therefore the duplicate guidance says 「このキーはすでに登録されています。別のキーを選んでください。」, rather than asserting another app or the system owns it. Generic errors make no collision claim. Numeric status values are used internally for classification only and are not interpolated into settings, menu, recording feedback, guides or fixtures. No numeric registration diagnostics were added. The light/dark `hotkey-error` fixtures inject the verified duplicate value; `hotkey-generic-error` injects the verified internal-error value. No real registration occurs during rendering.

First launch and reopening still bring Settings forward; only first-run guidance can automatically add the permission card, subject to the policy above. Merely opening Settings while unauthorized does not show the card. The current large instruction comes from GestureCopy; Carbon combination recording remains available. The old showGuide() has no shipping callers and is retained for historical fixtures only.

Only the display containing the mouse when opening is used, including its complete screen frame. Placement is stored as fractions of that full `NSScreen.frame`, in bottom-left coordinates local to that display (not visibleFrame, backing pixels or desktop-global coordinates). Frames are restored for the current display size, snapped to an 8-point grid/nearby edges (10-point threshold), minimum 240×160, and clamped to keep 40 points visible. Drag the header and resize using the seven-point edge/corner zones. The header menu is visible only while pinned and reloads, opens the current URL externally, duplicates or deletes. HTTP and HTTPS inputs are accepted; a missing scheme becomes HTTPS.

The panel pool retains the four most recently viewed panels, up to twelve records. Hidden overlays keep web views alive using alpha=0 and ignore mouse input. Eviction asynchronously snapshots before releasing a web view; replacements wait for eviction to finish so at most four web views exist. Dormant panels show a snapshot at 50% alpha, a rounded 「休止中」 badge and a secondary 「クリックで再開」 line. The same rendering is used in previews. Clicking recreates content at its URL with a spinner. A recreated site loses in-page state; navigation, authentication and site behavior follow WebKit. No external favicon downloads are performed.

## Input and permission

See the trial.4 permission specification above. Carbon registers press and release independently of Input Monitoring. DoublePressInput uses a listen-only tap for flags and cancellation events; it never stores or sends key contents. Host-inherited preflight is not trusted. Only the explicit card Allow action can request permission. Tap failure/disable falls back to Carbon without silent tap retries. Secure input updates menu status only.

The overlay never calls NSApp.activate; settings alone may activate. Peek never calls makeKey. Normal hiding retains the existing guarded fade/focus-return path, while second-hold interruption uses hideImmediately without animation or focus movement. Real input, Spaces and focus still require manual verification.

## Isolated test copies

Settings storage is injected into `SettingsStore` through `SettingsStorage`. The running app tries its named UserDefaults suite and falls back to standard defaults only when no suite override is present; previews and SettingsStore tests use `MemorySettingsStorage`, a dictionary of JSON data with no disk writes. Migration tests use an injected memory domain that also preserves arbitrary property-list values. Production default is `com.satoshi0817.Sheerpane`. `SHEERPANE_DEFAULTS_SUITE` overrides the suite; `SHEERPANE_DEFAULT_SHORTCUT=ctrl-opt-cmd-f19` overrides its shortcut at launch for test copies. Example:

```sh
SHEERPANE_DEFAULTS_SUITE="sheerpane-test-$(uuidgen)" SHEERPANE_DEFAULT_SHORTCUT=ctrl-opt-cmd-f19 build/Sheerpane.app/Contents/MacOS/Sheerpane
```

No Sheerpane test or preview creates a UserDefaults suite, so the Sheerpane test suite creates no `sheerpane-test-*.plist`. Persistence coverage writes JSON through the storage protocol and reads it through a fresh SettingsStore sharing the same memory storage. Previously created preference files are not deleted by these tests. Settings previews include diagnostics only in DEBUG/TRIAL_DIAGNOSTICS builds. Diagnostics contain only timing, source, observed physical modifier keycode and left/right name, permission boolean, counts and this process's RSS; no URLs, page titles, usernames or paths. The legacy observed-modifier diagnostic remains none in the Carbon-only InputController; the new gesture adapter does not collect keycodes. Observation state and formatting are compiled only in diagnostic builds.

## Settings migration

On an ordinary first launch, `SettingsMigration` reads a persistent snapshot of the former provisional bundle domain, copies each missing key verbatim to `com.satoshi0817.Sheerpane`, then sets `sheerpaneSettingsMigrated` on the new side only. Existing destination values, including false and empty data, win. The old domain is never written or deleted. A later launch with the flag reads no old settings. An explicit `SHEERPANE_DEFAULTS_SUITE` override skips migration entirely. Preview rendering exits before opening any defaults suite. The migration storage protocol permits memory-only tests; no test opens either real domain.

Historical TASK-OVERLAY-014 plan (trial.3 has since shipped): tag `v0.1.0-trial.3`, zip `Sheerpane-0.1.0-trial.3.zip`. These are not trial.4 artifact identifiers. The repository name remains `overlay-browser-trial`.

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
