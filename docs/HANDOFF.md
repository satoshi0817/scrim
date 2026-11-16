# Sheerpane 引き継ぎ（下書き）

> TASK-OVERLAY-014: 製品名は Sheerpane、バンドル ID は `com.satoshi0817.Sheerpane`、バージョンは **0.1.0 (3)**。リポジトリ名は `overlay-browser-trial` のままです。
> 今回は名称と設定移行のみ。下記の trial.3 ジェスチャー計画は別タスクで、今回実装・出荷しません。
> 現行のアイコン・メニュー・プレビュー仕様とコマンドは [sheerpane.md](sheerpane.md) を参照してください。下記の過去のレビュー記録には、その時点のソース説明も含まれます。
> この文書は下書きです。PM と Lead が確認するまで、コミット・push はしていません。
> 「確認済み」と書いたものは、記載した方法で確かめたものだけです。実機での操作確認は、ほとんどがまだです。

## 1. 目的と経緯

- Notch Browser を、Peek 型のアプリに作り変える話から始まりました。ショートカットで全画面のオーバーレイを出し、その上にウェブパネルを自由に配置するアプリです。
- さとしさんの決定:
  - ノッチは廃止してよい。
  - 公開情報の範囲で、機能と操作をできるだけ近づける。Peek のアプリの解析と逆アセンブルはしない。名前・ロゴ・画像・文言・コード・見た目は自前で作る。
  - Peek の利用規約（2026-10-20 施行）は、逆アセンブルを禁じ、名前とブランドを保護しています。
  - ショートカットは自由に変えられるようにする。
  - 押している間だけのぞく（押しっぱなし）。軽く押して離すと固定する。
- 置き場所は、Sheerpane 用の別の非公開リポジトリ（このリポジトリ）にする。試用版の Release もここに置く。公開の notch-browser には出さない。
- 製品名は Sheerpane に決定しました。旧仮称は Chira です。名称変更は商標についての新たな法的判断を示すものではありません。

## 2. 仕様（現在のソースの内容）

- 状態は 3 つです。
  - hidden: 隠れている。
  - peek: 押している間だけ表示。見るだけで、マウスは下のアプリに通ります。
    - マウスが下に通る点は、Designer の暫定の仮定です。元の Peek の実際の挙動は、画面録画などの実データが出るまで未確認です。
  - pinned: 固定中。パネルを操作でき、画面上部に「固定中」の表示が出ます。
- 押していた時間が 0.25 秒未満ならタップ（固定）、0.25 秒以上なら押しっぱなし（のぞき）です。ちょうど 0.25 秒は押しっぱなしとして扱います。
- 固定中は、Esc、背景のクリック、同じキーのいずれかで閉じます。
- パネルはウェブだけ（WKWebView）です。
  - 生きたパネルは、最近見た 4 枚までです。
  - それより古いパネルは休止させます。スナップショット画像にして WKWebView を解放します。
  - パネルの総数は最大 12 枚です。
- 休止中の表示: 画像を約 50% に暗くし、「休止中」のバッジと「クリックで再開」を出します。固定中にクリックすると、同じ URL で作り直します。
- 隠すときは `alphaValue = 0` と `ignoresMouseEvents = true` を使い、orderOut は使いません。オーバーレイ側は `NSApp.activate` を呼びません。
- のぞき中は、パネルの「…」メニューボタンを出しません（固定中だけ出します）。
- キー登録に失敗したときの表示:
  - 入力欄の直下にエラー文を出し、入力欄の枠をオレンジにします。
  - 起動時に失敗した場合は、設定画面を自動で開きます。
  - メニューバーの表示を「Sheerpane ⚠︎」にし、メニューにもエラー文の項目を出します。
  - 文言は「ショートカット <キー> を登録できませんでした（他のアプリと重複している可能性があります）。上の欄で別のキーを押してください。」です。
- 修飾キーだけで使うモードもあります（左右を区別）。
  - 方式は 2 つです。A は修飾キーの状態を約 10ms ごとに読み取る方式（`CGEventSource.flagsState`）、B は CGEventTap（listenOnly）で受け取る方式です。
  - 入力監視の許可が必要です。権限の案内は、修飾キーだけのモードを選んだときにだけ出します。文言は「修飾キーだけで使う場合は、入力監視の許可が必要です。」です。
  - 許可を求めるダイアログ（`CGRequestListenEventAccess`）は、方式 B を選んでボタンを押したときにだけ出します。
  - 離したことを検知できない場合は、押すたびに開閉する動作に切り替えます。
- 既定のキー:
  - 現在のソースでは ⌃⌥P（Control+Option+P、Carbon keyCode 35）です。
  - 定数は SheerpaneCore の `Shortcut.default` の 1 か所で、表示の文字列はここから作ります。
  - すでに保存されている設定は上書きしません。既定値を読むだけでは保存もしません。
  - 変遷: ⌃⌥N → ⌃⌥Space → ⌃⌥P。
  - v0.1.0-trial.1 に入っている既定は ⌃⌥Space です。
- 初回起動と再度開いたとき（現在のソース、未出荷）:
  - 初回起動で設定画面を自動で開き、前面に出します。設定画面に限って `NSApp.activate(ignoringOtherApps: true)` を呼びます。
  - 先頭に「<キー> を押している間だけ表示します。」を出します。キーは設定に追従します。
  - アプリをもう一度開いたとき（`applicationShouldHandleReopen`）も、設定画面を開いて前面に出します。
- 診断は、試用版（`TRIAL_DIAGNOSTICS`）とデバッグビルドにだけ入ります（`#if DEBUG || TRIAL_DIAGNOSTICS`）。
  - 内容は、押してから離すまでの ms、離したことの検知経路、押していた時間、修飾キーの keyCode と左右、権限の状態、パネル数・生きている数・休止数、プロセスの RSS です。
  - URL、タイトル、ユーザー名、パスは含みません。
- メニューバーのメニューは「設定…」と「Sheerpane を終了」です（登録に失敗したときだけ、エラーの項目が加わります）。
- LSUIElement が true なので、Dock には出ません。
- 設定は `UserDefaults(suiteName: "com.satoshi0817.Sheerpane")` に保存します。初回に旧ドメインの不足キーのみコピーし、新側だけに移行済みフラグを保存します。旧側は変更しません。テストとプレビューは、メモリ上の保存（`MemorySettingsStorage`）を使います。
- 環境変数:
  - `SHEERPANE_DEFAULTS_SUITE`: 設定の保存先を切り替え、旧ドメインの移行をスキップします。
  - `SHEERPANE_DEFAULT_SHORTCUT=ctrl-opt-cmd-f19`: テスト用のコピーで使うキーです。

### 画面仕様（Designer のまとめ）

> 出典: Designer のデザイン引き継ぎ（2026-10-31 時点）。キーの記述は ⌃⌥P に直してあります。
> 上の仕様（現在のソース）と食い違う点は、消さずに「現在のソース」と「Designer の次版の要件」に分けて書いています。

#### 製品方向（さとしさんの決定）

- Notch Browser を Peek 型（peek.zone）に作り直す。ノッチは廃止する。
- 「完コピ」は、公開情報の範囲で機能と操作をできるだけ近づけること、という意味。Peek のアプリの解析と逆アセンブルはしない。名前・ロゴ・画像・文言・見た目・コードは自前で作る（1 章と同じ線引き）。
- 製品名は「Sheerpane」。
  - 試用版は、非公開リポジトリ satoshi0817/overlay-browser-trial に置く。
  - 公開リポジトリ satoshi0817/notch-browser には、Sheerpane のコードを入れない。
- 進め方: 作る → さとしさんが試して報告する。
  - リリースには、Designer の Approve、Lead の GO、さとしさんの承認が必要。
  - 商標の確認は人が行う。

#### 状態と操作

- 表示の状態は 3 つ。
  - peek: キーを押している間。見るだけ。
  - pinned: 軽く押して離す（0.25 秒未満）と固定する。移動・リサイズ・入力ができる。
  - hidden
- 閉じ方:
  - Designer のまとめ: Esc か同じキー。
  - 現在のソース: Esc、同じキー、背景のクリック。
- パネルの種類:
  - Designer のまとめ: Web、Notion タスク、Notion 議事録。
  - 現在のソース: Web だけ。Notion のパネルは段階計画の 004 で扱う予定です。
- 生きたパネルは、最大でおよそ 4 枚（暫定）。古いパネルは画像だけを残し、暗くして「休止中」バッジと「クリックで再開」を出す。現在のソースと一致しています。
- 既定のショートカットは Carbon のホットキー（権限は不要）。
  - 修飾キーだけで使うモードには入力監視の許可が必要で、許可の案内はそのモードのときだけ出す。
  - この点は現在のソースと一致しています。
- キー登録に失敗したとき: 入力欄の直下にエラー文とオレンジの枠、起動時に設定画面を自動で開く、メニューバーに「Sheerpane ⚠︎」。現在のソースと一致しています。
- 設定画面の「診断」ブロックは、試用版だけに出す。

#### 承認済みの画面（画面に出さずに描画したプレビューだけ）

- r3 の 10 枚は承認済みです（承認の条件は解消済み）。
  - 対象: dormant、empty、first-panel、guide-no-permission、guide-permission、hotkey-error、menu、peek、pinned、settings
  - Designer のレビュー用の置き場は `/workspace/notch-review/r3/` です（Mac ではなく、エージェントの作業用の環境にあります）。
  - 元の画像は、Runner の `.runner/real/evidence/TASK-OVERLAY-002/previews-r3/` にあります。
- first-panel は合成したプレビューで、実際に操作した結果ではありません。
- 承認はプレビュー画像に対するものです。実機の画面はまだ承認されていません。

#### 実機で未確認（Designer のまとめ）

- 全画面 Space の上での表示
- のぞきの速さ
- フォーカスの戻り
- 白いフラッシュ
- 移動・リサイズの手がかり
- 2 画面
- 既存の設定からの移行
- 設定画面の自動表示と、メニューバーの警告

#### 試用で見つかった問題

- メニューバーに入口が見えない。
  - 現状は文字の「Sheerpane」だけで、Ice やノッチで隠れることがある。
  - Dock にも出ない。

#### 次版の要件（Designer）と現在のソースの対比

- **入口のアイコン**
  - Designer の次版の要件: 常に見えるアイコンを置き、初回だけ場所を示す案内を出す。
  - 現在のソース: メニューバーは文字の「Sheerpane」だけで、アイコンも、場所を示す案内もありません。
- **メニュー**
  - Designer の次版の要件:「開く（現在のキー表記）」「設定…」「Sheerpane を終了」。「Sheerpane を終了」は区切り線の下に置く。
  - 現在のソース:「設定…」、区切り線、「Sheerpane を終了」の順で、「開く」はありません。登録に失敗したときだけ、先頭にエラー文の項目が出ます。
- **登録失敗の表示**
  - Designer の次版の要件: アイコンに警告印を付ける。先頭の行は「ショートカットを登録できませんでした」とし、押すと設定画面が開く。
  - 現在のソース:
    - メニューバーの文字を「Sheerpane ⚠︎」にします。
    - 先頭の項目には、エラー文の全文（「ショートカット <キー> を登録できませんでした（…）。上の欄で別のキーを押してください。」）を出し、押すと設定画面が開きます。
- **初回起動と、登録失敗時の自動表示**
  - Designer の次版の要件: どちらの場合も設定画面を自動で開く。Dock に出すかどうかを設定で選べる。
  - 現在のソース（msg-5、未出荷）:
    - 初回起動と、起動時の登録失敗のときに、設定画面を自動で開いて前面に出します。
    - Dock は出しません（LSUIElement）。Dock に出すかどうかを選ぶ設定はありません。
- **初回の案内の文言**
  - Designer の次版の要件: 初回だけ、メニューバーの中のアイコンの場所を示す。
  - 以前の指示にあった文例は「Sheerpane は画面上部のメニューバーにいます。<キー> を押している間だけ表示します。」で、キーは設定に追従します。
  - 現在のソース: 設定画面の先頭に「⌃⌥P を押している間だけ表示します。」（キーは設定に追従）だけを出し、場所の案内はありません。
- **再度開いたとき**
  - Designer の次版の要件: 設定画面を開く。
  - 現在のソース（msg-5、未出荷）: `applicationShouldHandleReopen` で設定画面を開いて前面に出します。実機では確認していません。
- **既定のキー**
  - Designer のまとめ: ⌃⌥Space は、macOS の「次の入力ソースを選択」（日本語入力の切り替え）と重なる可能性が高い。そのため既定を ⌃⌥P に変える（PM の決定。trial.2）。
  - 現在のソース: ⌃⌥P です（msg-5、未出荷）。出荷済みの v0.1.0-trial.1 は ⌃⌥Space のままです。
- **確認の条件**: 実機のスクリーンショット 3 枚（アイコンの表示、メニューを開いたところ、登録失敗）。まだ撮っていません。

#### 次版に回す推奨項目（Designer）

- 空の状態に「キーを押している間だけ表示」のヒントの行を出す。
- 「クリックで再開」と、設定画面の注記の文字色を少し薄くする。
- 「…」ボタンを、もっと控えめにする。
- 削除の前に区切り線を入れ、赤で表示し、取り消しか確認を用意する。
- ラベルを「診断（試用版のみ）」にする。
- 修飾キーのモードで、案内の 1 行目を実際のキー名に合わせる。
- 「固定中」の表示のコントラストを上げる。
- 別のタスクとして扱うもの: Esc でメニューだけを閉じる件と、自動で選ばれた行にリングを出さない件。

## 3. 構成

- `Package.swift`: Sheerpane だけの SwiftPM パッケージです（swift-tools 5.9、macOS 14）。
- `Sources/SheerpaneCore/Core.swift`（ライブラリ。Foundation と CoreGraphics だけを使う、テストできるロジック）:
  - `OverlayState`、`VisibilityPlan`: 状態ごとの alpha、マウスの扱い、makeKey、固定中の表示、「…」ボタンの表示、フェードの時間。orderOut は使いません。
  - `HoldTapStateMachine`: タップと押しっぱなしの判定（0.25 秒）。
  - `ModifierSide`、`InputMethod`、`Shortcut`、`HotkeyRegistrationStatus`、`GuideContent`
  - `FractionalFrame`、`Placement`: 画面に対する割合での保存、8pt のグリッド、端への吸着、最小 240×160、画面に最低 40pt を残す制限。
  - `PanelRecord`、`PanelPool`: 生きたパネルの数の制限と休止。
  - `SettingsStorage`、`MemorySettingsStorage`、`SettingsStore`
  - `Diagnostics`: 診断の整形。試用版とデバッグビルドだけです。
- `Sources/Sheerpane`（アプリ本体。AppKit、WebKit、Carbon）:
  - `main.swift`: AppDelegate、メニューバーの項目、初回起動と再度開いたときの処理、`--render-previews`。
  - `Input.swift`: Carbon のホットキー（押した・離したの両方のイベント）、修飾キーの状態の読み取り、イベントタップ、キーの記録欄。
  - `Overlay.swift`: OverlayPanel（NSPanel）、背景、PanelView（WKWebView、ヘッダー、休止表示）、OverlayController。
  - `Settings.swift`: 設定画面、初回の案内、診断の表示欄。
  - `Previews.swift`: 画面に出さずに PNG を作るプレビュー（`Sheerpane --render-previews <dir>`）。
- `Resources/Sheerpane/Info.plist`: com.satoshi0817.Sheerpane、0.1.0（3）、LSUIElement。
- `scripts/build-sheerpane.sh`:
  - 通常は `build/Sheerpane.app` を作ります。
  - `--trial` を付けると `-Xswiftc -DTRIAL_DIAGNOSTICS` で診断入りになります。
  - `SIGNING_IDENTITY` を指定すると、その証明書で hardened runtime とタイムスタンプ付きの署名をします。指定しなければ ad-hoc 署名です。
- テスト: `Tests/SheerpaneTests/CoreTests.swift`。SheerpaneCore が対象で、49 件です（2026-10-31 JST に `swift test` で全件成功を確認）。テストは plist を作りません。
- 出荷の手順（v0.1.0-trial.1 で実際に行ったもの）:
  1. 通常版を build し、診断の文字列がないことを `strings` / `grep -a` で確認する。
  2. `SIGNING_IDENTITY="Developer ID Application: …" ./scripts/build-sheerpane.sh --trial`
  3. `.xcarchive` を手で作る（Products/Applications/Sheerpane.app と、ApplicationProperties を書いた Info.plist）。
  4. ExportOptions（method=developer-id、destination=upload）を使い、`xcodebuild -exportArchive` で公証に出す。Xcode に保存済みの開発者認証を使い、notarytool のプロファイルは使っていません。
  5. 受理されたら `xcodebuild -exportNotarizedApp` で書き出す。この時点で staple 済みです。
  6. `ditto -c -k --keepParent` で zip にし、`shasum -a 256` を控える。
  7. zip を展開し、`codesign --verify --deep --strict`、`xcrun stapler validate`、`spctl --assess --type execute` で確認する。
  8. 注釈付きのタグを付けて push し、`gh release create --prerelease` で非公開リポジトリに出す。
  9. ダウンロードし直して SHA-256 が一致することを確認する。

## 4. 作業の流れの記録

- TASK-OVERLAY-001（使い捨ての試作。結果は「技術メモ」に）。macOS 15.7.9、MacBook Pro 内蔵ディスプレイ 1 枚、2026-10-28 JST に実施。
- TASK-OVERLAY-002+003（Local Codex Runner の 1 thread で実施）:
  - 初版: 新しい SwiftPM ターゲット（SheerpaneCore / Sheerpane / SheerpaneTests）、build-sheerpane.sh、docs/sheerpane.md。
  - 修正 1〜6（msg-1）: Carbon は離したイベントだけで判定、固定を解くときのフォーカスの戻し、診断の keyCode を実際に押されたキーに、VisibilityPlan、テストの追加、プレビューをメモリ保存に。
  - msg-2: 既定のキーを ⌃⌥Space に、ホットキー登録の失敗を画面に表示。
  - Designer の必須 4 点（msg-3）: 休止中の表示、登録失敗の表示、設定の語、のぞき中は「…」を隠す。あわせて、テストをメモリ保存に切り替え。
  - 文言の修正（msg-4）: 権限の案内の文言と、表示の条件。
  - msg-5（未出荷）: 既定のキーを ⌃⌥P に、初回起動と再度開いたときに設定画面を前面に出す。テストは 49 件。
- v0.1.0-trial.1（非公開リポジトリの pre-release）:
  - コミット: `83cb68ee36e0570364a5a9c31da8061e59a6edcd`
  - タグ: `v0.1.0-trial.1`
  - zip: `Chira-0.1.0-trial.1.zip`、SHA-256 `ed2eec52aff0c1d7aaa58dd1cfafb77e5db5d5ed242d251d1cca564a8ceaba59`
  - CDHash: `c0287c50d4646b015416c09857c7f3f361dec1ed`
  - codesign --strict は成功、stapler validate は成功、spctl は accepted（Notarized Developer ID）。ダウンロード後の SHA-256 も一致しました。
  - arm64 のみです。既定のキーは ⌃⌥Space です。

## 5. 技術メモ（試作 001 の結果）

- Carbon のホットキー:
  - `RegisterEventHotKey`（⌃⌥⌘F19）は、許可なしで install、register、unregister、remove がすべて OSStatus 0 でした。
  - 実際にキーを押したときの、押した・離した両方のイベントは未確認です。
- 修飾キーだけの検出と入力監視:
  - `CGEventSource.flagsState` の読み取りは許可なしでも取れました（約 11.5ms 間隔、何も押していないときの raw は 0x20000000）。
  - 注記: 修飾キーの値を読めただけです。他のアプリが最前面のときや、通常キーの検出は未確認です。二次情報では、入力監視が要るとされています。
  - 左右の判定には、デバイスごとのビットと keyCode（55/54、58/61、59/62、56/60）を使います。このロジックは単体テストで確認しました。
  - 許可の状態は、LaunchServices（`open`）で起動して確認する必要があります。Terminal から直接起動すると、Terminal の許可を引き継いでしまいます。
  - グローバルモニターとイベントタップは作っておらず、未確認です。
- 全画面 Space の上のオーバーレイ:
  - 別プロセスの全画面ウインドウの上に、次の設定の NSPanel を出しました: nonactivating、レベルは screenSaver、canJoinAllSpaces + fullScreenAuxiliary + stationary + ignoresCycle。
  - none / makeKey / activate のどの場合も、ホスト側の Space から追い出されませんでした。
  - makeKey: NSApp.isActive は true になりますが、最前面のアプリはホストのままでした。
  - activate: 最前面のアプリが試作に変わりました。
  - 再表示が CGWindowList に載るまで、p50 で 22.5ms でした。
  - 他社アプリの全画面、Space 切り替えのちらつき、Mission Control は未確認です。
- WKWebView の保持方式の比較（8 枚、5 サイクル、ローカルの軽い HTML）:
  - 保持（keep / alpha）: 表示まで p50 約 3ms、WebContent プロセスは 8 個、RSS は約 228MB。入力値は残りました。
  - スナップショット + 解放: 隠している間 WebContent は 0 個。再表示の JS 応答は p50 約 79ms でした。
  - 作り直し: 表示まで p50 約 76ms。入力とスクロールが失われました。
  - orderOut で隠すと、再表示時に visibilityState が hidden から visible に変わり、scrollY が 0 に戻りました。alpha 0 で隠せば保持されます。この結果から、本体では alpha 0 で隠し、生きたパネルを 4 枚までにしました。
  - 実サイトでの値は未確認です。
- 複数ディスプレイ: ディスプレイ 1 枚の環境だったため、未確認です。

## 6. 段階計画

- 002+003: Sheerpane の第 1 段階（このリポジトリ。試用版を出荷済み）。
- 004: Notion パネルと、Notch Browser からの移行。
  - Notion のタスクと議事録を、パネルの種類として加える。
  - Keychain の名前と値、固定ページ、設定を引き継ぐ。
  - 移行の方針:
    - 固定ページを 2×2 に並べる。
    - Notion が接続済みなら、Notion のパネルも出す。
    - ノッチが無くなったことを 1 回だけ知らせる。
- 005: ノッチの廃止と、新しい初回の案内。
  - ノッチ、タブバー、切り離しウインドウ、古い初回の案内を削除する。
  - 新しい初回の案内を作る。
- 第 2 段階（いまの候補。未決定）:
  - PDF
  - カレンダーとリマインダーのウィジェット（EventKit。別の許可が要る）
  - ディスプレイごとのレイアウト
  - 自動更新
  - 広告と要素の非表示（WKContentRuleList）
- パスキーは第 1 段階から外し、あとで決める。
  - 理由: Apple の審査つきの権限（`com.apple.developer.web-browser.public-key-credential`）が要るため。

### 次にやること（順番と担当）

担当の分け方: 実装は Engineer（Codex 経由）、仕様は PM、画面は Designer、割り振りと GO は Lead、承認はさとしさん、商標は Researcher。

1. trial.2（⌃⌥P、設定画面、メニューバーのアイコン）
   - 実装は Engineer、画面は Designer、GO は Lead、承認はさとしさん。
2. さとしさんの実機の結果を受け取る。
   - 受け取りと整理は Lead。画面の判断は Designer。
3. キーの範囲を確定する（さとしさんの実機の結果を受けて。普通の組み合わせか、修飾キーだけか）。
   - 仕様は PM、決定は PM と Lead、承認はさとしさん。
   - 補足: さとしさんの要望（2026-11-05）として、既定を「⌘を 1 回押してから、⌘を長押し」にしたい、いろんなキーストロークに対応したい、というものがあります。PM と Lead の現時点の決定は、下の「trial.3（⌘ の 2 回押し）の決定事項」にまとめています。
   - trial.3 は、この (3) とは別の task・別の thread で行います。着手も出荷も、Lead の GO のあとです。
4. 004（Notion パネルと移行）
   - 仕様は PM、画面は Designer、実装は Engineer、GO は Lead、承認はさとしさん。
5. 005（ノッチの廃止と新しい初回の案内）
   - 仕様は PM、画面は Designer、実装は Engineer、GO は Lead、承認はさとしさん。

- 商標の確認は、上の順番とは別に Researcher が進めます。名前を公開するのは、確認が済んでからです。

### trial.3（⌘ の 2 回押し）の決定事項（PM と Lead、2026-11-05 時点）

- 状態は未着手です。別の task・別の thread で行い、着手と出荷は Lead の GO のあとです。
- 操作の判定:
  - 1 回目は、押してから離すまでを 0.3 秒以内とする（0.25 秒の案は取り下げ）。
  - 1 回目を離してから 2 回目を押すまでは、0.4 秒以内とする。間隔の比較には、`NSEvent.doubleClickInterval` を使う案も試す。
  - 2 回目を押している間はのぞき、離すと隠れる。
  - 2 回目を 0.25 秒未満で離したら固定する。
  - 固定は、Esc、背景のクリック、同じ操作で閉じる。
- 左右の ⌘ は、どちらを押しても反応する。左右の選択は、設定に残しておくだけにする。
- 入力の方式:
  - 入力監視の許可を使う方式で作る。`CGEventTap` の listenOnly で、flagsChanged・keyDown・mouseDown を受け取る。
  - 「A と B を比べる試作」は取りやめる。
  - ただし、この方式について次を測って報告する。
    - 電池の消費
    - 押している間の取りこぼし
    - ⌘C、⌘Tab、⌘クリックでの誤反応
    - 他のアプリが最前面のときの動き
    - 許可したあとに再起動が要るかどうか
- 許可のカードの名前は、実際に使う方式に合わせて「入力監視」とする。
- trial.3 の task に入れるもの:
  - 許可したあとに tap が作れないときの、再起動ボタン
  - セキュア入力中は反応しないことを、メニューバーで知らせる表示
  - Developer ID 署名の確認
- Designer の暫定案:
  - 許可が切れたことを検知したら、許可のカードをもう一度出す。
  - パスワード欄などのセキュア入力中は、「安全な入力中のため、⌘ の2回押しは一時的に使えません。⌃⌥P を使えます」と出す。
- 実機の確認項目に入れるもの:
  - Researcher の 7 点（中身は Researcher のまとめを参照。この文書には書き写していません）
  - 日本語配列の「英数」「かな」キーと ⌘ キーの組み合わせ
  - Karabiner との干渉。さとしさんが Karabiner を使っているかは未確認なので、確認の前に聞く。

## 7. 決定の記録

- パスキーは第 1 段階に入れない（理由は 6 章）。
- Notion のトークンと Keychain の名前は変えない（値にも触らない）。
- Peek の名前、資産、文言はコピーしない。解析もしない。
- 既定のキーは、PM が ⌃⌥P に決定しました。さとしさんは「他のキーに」とだけ希望しました。キーは設定でいつでも変えられます。

## 8. 既知の問題と未確認

- さとしさんが試したところ、メニューバーに Sheerpane の項目が見えませんでした。
  - Ice を使っていて、ノッチ付きの MacBook です。
  - 原因はまだ確定していません。Ice の隠しセクションにあるか、ノッチの裏に隠れている可能性があります。
  - v0.1.0-trial.1 の案内ウインドウは NSApp.activate を呼ばないため、前面に出ていない可能性があります。
- 参考（このとき確認した事実）: この Mac の macOS のキーボードショートカットでは、⌃⌥Space が「入力ソースを切り替え」系（symbolic hotkey ID 61、有効）に割り当てられています。trial.1 の既定のキーと重なっていました。
- Designer が出した、次の版の必須要件:
  - メニューバーに常に見えるアイコン（文字ではなく小さなアイコン）。現在のソースは、まだ文字の「Sheerpane」です。
  - メニューは「開く（現在のキー表記）」「設定…」「Sheerpane を終了」（終了は区切り線の下）。現在のソースは「設定…」と「Sheerpane を終了」です（詳しくは「2. 仕様」の「画面仕様（Designer のまとめ）」）。
  - 初回の案内:「Sheerpane は画面上部のメニューバーにいます。<キー> を押している間だけ表示します。」（キーは設定に追従）。現在のソースは後半の 1 文だけです。
  - 登録失敗の表示。
  - アプリを再度開いたら、設定画面を開く（現在のソースで実装済み、実機では未確認）。
  - Dock に出すかどうかを、設定で選べるようにする（未実装）。
  - Approve の条件は、実機のスクリーンショット 3 枚（アイコン、メニュー、登録失敗）です。
- trial.2 の最小案: 初回に設定画面を自動で開いて前面に出すことと、再度開いたときに設定を表示すること。どちらも現在のソースに入っていますが、未出荷で、実機でも未確認です。
- 実機で未確認の項目:
  - 実際のキーでの押す・離す
  - 全画面 Space の上での見え方
  - のぞきの速さ
  - 固定を解いたあとのフォーカスの戻り
  - 複数ディスプレイ（2 枚のディスプレイを含む）
  - 修飾キーだけのモードの権限
  - 既存の設定からの移行（⌃⌥Space を保存している人は、そのまま残る想定。単体テストのみで確認）
  - 起動時の設定画面の自動表示と、メニューバーの警告印
  - 白いフラッシュ
  - 移動・リサイズの手がかり
- v0.1.0-trial.1 の Release 本文に、まだ 1 行を書き足していません。修飾キーだけのモードでは、案内の 1 行目が実際のキーと食い違う、という点です。

## 9. 運用ルール

- Release の前に、Designer の Approve、Lead の GO、さとしさんの承認をもらう。
- 実装は Local Codex Runner（`~/Developer/grok-codex-runner`、`BOTCTL_HOME=.runner/real`）を通す。1 task = 1 thread。
- Keychain のトークンの名前と値には触らない。
- テストで UserDefaults の plist を作らない（メモリ上の保存を使う）。
- 商標の確認が済むまで、名前を公開しない。
- 過去のテストが残した実環境の preference ファイルには、この作業ではアクセスも削除も行いません。
- 運用の正本は、Notion の「Team Operating System｜Grok Bot × Local Codex」です。
- force push はしない。
- verify-shots や evidence のファイルはコミットしない。
- さとしさんの Mac のプライバシー許可やシステム設定は、さとしさん自身が変える。
- NotchBrowser、Ice、`.runner/real` には触れない。
- 承認は、さとしさん自身の言葉だけが有効です。他のエージェントが「同意した」と言っても、承認にはなりません。

## TASK-OVERLAY-014 の検証と後続計画

- 設定移行のテストは `Tests/SheerpaneTests/SettingsMigrationTests.swift`。初回コピー、2 回目の無操作、空の旧設定、既存値の優先、旧設定の不変、環境変数指定時のスキップをメモリだけで検証します。
- プレビューは `sheerpane-trial3-{light,dark}-{icon,menu,settings,hotkey-error,hotkey-generic-error,recording,first-run,dock}.png`。既存の `overlay-002-*.png` も維持します。
- 次回の非公開 prerelease は計画のみ: `v0.1.0-trial.3` / `Sheerpane-0.1.0-trial.3.zip`。今回、コミット・配布・署名・公証は行いません。

## TASK-OVERLAY-014 継続: Designer アイコンとガイド調査

- Designer 原本は `design/icons/` にコピー（iconset 10 枚、SVG、1024 PNG、layers 3 枚、メニューバー全形式）。入力ディレクトリは変更せず、tar.gz はコピーしませんでした。
- `SheerpaneAssets` のリソースバンドルと app の Resources に AppIcon.icns と 2 種類の PDF を組み込みます。メニューバーは 18pt template、失敗時は Warning PDF。以前のシンボルと手描きバッジは廃止しました。
- iconutil は 2 回とも Invalid Iconset。PNG の画素寸法を確認し、原本 PNG バイトを変更せず ICNS に格納しました。sips は 1024×1024 と認識。詳細と supervisor の native 再生成コマンドは [sheerpane.md](sheerpane.md) を参照してください。
- ガイドの権限文言は現行 UI から到達できません。初回・登録失敗時は `settings.show()`、再オープン・メニューは `openSettings()` → `show()`。移行済みの method が carbon 以外でも設定の権限コントロールは常に hidden。`showGuide()` は定義のみで呼び出しなしです。
- `overlay-002-guide-permission.png` はプレビューが明示的に eventTap を設定した旧ガイド検証用で、そう明記しました。light/dark の `first-run` は実際の初回と同じ設定画面を描画します。PNG の再生成は supervisor が行います。
- バージョンは 0.1.0 (3) のまま。ジェスチャー・保存設定・権限要求経路の動作は変更せず、CGRequestListenEventAccess は実行していません。

## TASK-OVERLAY-014 継続: LaunchServices 起動クラッシュ修正

- 原因: Foundation は現在の bundle identifier を `initWithSuiteName:` に渡すことをエラーと定義しています。app と同じ名前の suite が nil を返し、従来の guard が fatalError に到達しました。
- `SettingsDefaultsPolicy` は override が未指定の場合だけ、shipping suite が nil なら `UserDefaults.standard` にフォールバックします。明示的な override は suite のみを使い、失敗しても standard へ切り替えません。
- 移行条件・旧ドメインの読取り方法・既存値の優先・新側だけのフラグ保存は維持。メモリ factory のみのポリシーテストを 4 件追加（既存 89 件は維持）。
- CLI/swift-run で bundle が app ではない場合、standard の保存先が Sheerpane 以外になり得ます。必ず固有の throwaway suite override を指定してください。詳細は [sheerpane.md](sheerpane.md) を参照。
- supervisor が検証した native AppIcon.icns（169624 bytes）をそのまま維持。0.1.0 (3) のまま。実アプリ起動・実 defaults 操作・権限要求は worker では行いません。
