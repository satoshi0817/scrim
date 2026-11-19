# 今の時間帯を既定表示・会議カウントダウン（2026-11-18）

- 次の予定を開き直すと進行中の時刻付き予定へ、なければ次の時刻付き予定へ移動。対象がないときは今日の先頭。既存agendaResetsScrollOnOpen（既定true）のスイッチ名を「開くたびに今の時間帯へ移動」に変更し、オフなら前回位置を保持。表示中の更新・peek→pinnedでは移動しない。
- 「今日」「今の時間帯」の手動移動ボタンを追加。終了済みを後ろへ回すソートを撤去し、終日優先・時刻順を維持。不透明度を45%へ。移動先の開始時刻が見切れないよう日付見出しの固定を外し、各カードにも日付・曜日を表示。
- 上部に次のMeet／Zoom会議名とカウントダウンを表示。表示対象の未来の時刻付き会議から選び、終日・開始済みは対象外。15分前からサマリーにも参加ボタン。分は切り上げ、時・日へ整形。既存の毎分タイマーで更新する。
- --verify-widgets成功。進行中優先／終了済み除外の移動先選択、会議リンクのある予定の選択、時刻順保持、残り時間整形、実際のNSScrollViewでの自動移動とオフ時の位置保持を確認。横長と340pt縦長の架空予定描画も確認。実際の会議リンクは開いていない。
- 通常版ビルド・署名検証成功。/Applications/Scrim.appへ更新・再起動し、署名requirement不変・バイナリ一致を確認。旧版はbuild/previous-install-20261118-235412.app。未commit・未push。

---

# 予定リンクの整理・再表示時のスクロール設定（2026-11-18）

- Meetは緑、Zoomは青の参加ボタンへ変更。ホバー時は指カーソル。会議リンクは複数あっても常時表示し、その他のWebリンクとメモは「リンクとメモ」に初期状態で折りたたむ。NotionはN、Docs／GitHub等はサービス別アイコンと名前を表示。外部opener成功時にScrimを閉じる既存経路を共用。
- EventLinksでHTTP(S)リンクの抽出・重複排除・HTMLアンカーのラベル取得。メモはHTMLを実行しないテキストとして表示。私的なURL／メモはメモリ内のみで、ログ・設定には保存しない。予定IDをカレンダーID＋イベントID＋開始時刻へ安定化し、定期更新で展開状態を保つ。
- 設定 → パネル → 次の予定に「開くたびに今日の予定の先頭へ戻す」スイッチを追加（既定オン）。hiddenからの再表示だけでScrollViewReaderを先頭へ移動し、表示中の更新・peekからpinnedへの切り替えでは位置を維持。オフ時は再表示でも位置保持。
- --verify-widgetsでリンク分類／抽出／外部opener／危険なスキームの拒否、既定設定、再表示・固定切替を確認。描画したNSScrollViewを実際にスクロールし、オン時の先頭復帰とオフ時の位置保持を確認。--verify-panel-behaviorと--verify-settingsも成功。架空予定の色付き参加ボタンと折りたたみ表示をPNGで確認。実際の会議は開いていない。
- 通常版のビルド・署名検証成功。/Applications/Scrim.appを更新・再起動し、署名requirement不変とバイナリ一致を確認。旧版はbuild/previous-install-20261118-111020.appに保持。未commit・未push。

---

# 予定と時計のビジュアル整理（2026-11-18）

- 予定カードの時刻を開始24pt（小さいカード21pt）＋小さい終了時刻へ分離。丸みのある等幅数字、開始前カウントはタイマー付きの小さいカプセル。1時間未満の赤い強調は開始時刻・バッジ・細い枠に絞る。
- カードは角丸16pt、カレンダー色の淡い背景＋ごく薄いグラデーション、細い枠、控えめな影へ。日付見出しは小さく、今日は赤いドット、件数は小さいピル。終了済みは65%で読みやすさを保持。
- 会議への参加ボタンを動画アイコン＋外部矢印のピル型に。アクションとクリック透過・ミーティング起動は既存経路を維持。
- デジタル時計を時分と小さい秒の一行表示へ変更。タイムゾーンと日付を控えめに添える。アナログ時計の日付も小さいピルに統一。
- --verify-widgets成功。予定／時計の新しい描画を確認し、通常版のビルド・署名検証成功。/Applications/Scrim.appを更新・再起動し、署名requirement不変・ビルド元とのバイナリ一致を確認。未commit・未push。

---

# 除外キーワード・短いダブルプレス編集・開始前強調（2026-11-18）

- 次の予定の背面設定に除外キーワード一覧を追加。複数追加、行内編集、ゴミ箱削除に対応。予定名の部分一致ORで除外。大小・全角半角を区別せず、空欄と重複は正規化。日本語の清音／濁音は区別。入力中は取得済み候補を再フィルタし、EventKitを毎文字再問い合わせしない。
- WidgetSpecのexclude queryに保存し、カレンダーIDと表示日数を維持。行はUUIDで管理し、入力中のフォーカスを保持。カードの設定内容全体を単一スクロールに変更し、キーワードが多くてもアカウント設定へ移動できる。
- 設定 → 操作 → ダブルプレスに「短く2回押すとレイアウト編集で開く」を追加。既定オフ。doublePressのpin効果時のみ設定を適用し、長押しpeekや通常ショートカットは維持。
- イベント時刻を大きい太字・等幅数字へ変更。時刻付き予定の開始まで0秒超かつ3600秒未満で、赤い時刻・枠・薄い赤の背景・あと○分バッジ。終日／進行中／終了済みは開始前強調から除外。既存のカレンダー色カードと進行中ラベルは保持。
- --verify-widgets、--verify-panel-behavior、--verify-settingsが成功。追加・複数除外・編集で旧結果復元・削除で復元、キーワード＋既存設定の保存往復、空欄／日本語濁点／リテラル一致、1時間境界／終日／進行中、設定の永続化と長押し時の非編集を検証。設定一覧と赤いカードの描画を確認。
- 通常版を証明書署名して/Applications/Scrim.appへ更新・再起動。署名requirement不変とバイナリ一致を確認。旧アプリは日時付きbuild/previous-installへ保持。未commit・未push。

---

# 天気の横スクロール廃止と会議リンクカード（2026-11-17）

- 天気の時間別予報から水平ScrollViewを撤去。利用幅で1〜8件を選び、等幅列に並べる。横長・縦長の既存表示を維持し、横スクロールバーは出さない。架空予報の横長描画で収まりを確認。
- 次の予定をカレンダー色12%の透過背景＋細い枠の角丸カードへ変更。縦の色線を撤去。日付別の見出し、時刻→タイトル→場所、進行中・終了済みの扱いは維持。
- EventKitの予定URL・場所・メモからGoogle Meet／ZoomのHTTPSリンクを検出。スキーム省略やHTMLの&amp;も処理。会議サービスの正確なホストを検証し、無関係・類似ドメインは参加ボタンにしない。
- 会議リンクがあるカードに参加ボタンを表示。NSWorkspaceで外部へ開き、成功時にScrimを閉じ、進行中のキー操作も既存onDismiss経路で取り消す。リンク（パスコード等を含む）は予定モデルのメモリ内だけで扱い、ログや設定には保存しない。
- --verify-widgetsでリンク抽出・クエリ保持・類似ホスト拒否・外部openerへのルーティングを架空URLで検証。実際の会議は開いていない。Google Meet／Zoomボタンを含む色付きカードの描画を確認。通常ビルドと署名検証に成功。
- /Applications/Scrim.appを更新・再起動。署名requirement不変とビルド元バイナリ一致を確認。旧版build/previous-installの日時付きバックアップを保持。未commit・未push。

---

# 日付別の予定・表示設定・天気予報（2026-11-17）

- 予定を「今日の予定」「明日の予定」「○月○日の予定」に区切り、日付／曜日の固定見出しと時刻→イベント名→場所の順で表示。進行中ラベル、終了済みは薄く後ろへ。今日の終了済みも取得し、前日からの継続は今日へまとめる。
- 予定の背面設定で今日を含む1〜31日を選択。WidgetSpecのdays queryに保存し、カレンダーIDフィルタと相互に保持。既存は7日。アカウント／カレンダーと設定画面のbool入力はスイッチ型へ変更。
- 設定 → パネル → WebパネルでPC／スマホ。スマホはiPhone用UAと中央寄せ最大390pt幅、PCはMac標準UAと全幅。ローカルファイル／ネイティブウィジェットは変更せず、休止画像の幅も合わせる。
- 前身NotchBrowserの公開GitHub mainを読み取り、hideFromScreenCapture既定trueとNSWindow.sharingType=.noneを確認（ソースは.tmp/notch-referenceに保存）。Notch自体は変更していない。同じ指定をScrimのオーバーレイ・設定・Web別窓へ追加。設定 → 一般 → 画面キャプチャで切り替え、初期オン。Apple公式は.noneを旧式としてキャプチャ防止への使用を推奨していないため、共有先で非表示を保証しないことをUIとdocsへ明記。共有中にScrim自体を閉じる代替モードは追加していない。
- 天気の3時間ごとの気温・天気・降雨確率を追加。気象庁の現在値／日別予報は維持。Open-Meteoはこの環境でタイムアウトしたため、取得できたwttr.in / WorldWeatherOnlineの東京の3時間データを使用し出典表示。設定 → パネル → 天気のスイッチでオン／オフ、初期オン。横長・低いカードでは左右に並べる。非表示中／オフは取得停止、エラー時は既存情報を保持する。
- --verify-widgets、--verify-panel-behavior、--verify-settingsが成功。日数境界、今日の終了済み、日付グループ、日数＋IDフィルタ保存、実際に取得したTokyo予報の解析、3時間スロット、表示切替、PC／スマホの幅とUA、キャプチャ指定の既定オンとオフ復元を検証。MacのWKWebViewはcustomUserAgent=nil設定後のgetterが空文字になるため、その両方を標準モードとして検証する。
- 架空予定・予報で新しい日付別UI、スイッチ型の設定面、横長天気を描画確認。会議相手側の画面共有除外は未検証であり保証しない。通常版を証明書署名し/Applications/Scrim.appへ更新・再起動。旧版build/previous-install-20261117-154141.app。署名requirement不変、バイナリ一致を確認。未commit・未push。

---

# 一時表示の操作・パネルメニュー・Webカレンダー（2026-11-17）

- 一時表示のクリック・スクロールを既定オンに変更。設定 → 操作 → 一時表示でオン／オフ可能。クリックがダブルプレスをキャンセルせず、キーを離すと閉じる。クリック時の⌘をScrim内だけ除外し、Command-clickによる別窓化を防止。WebViewは最初のクリックを受け付ける。ショートカット入力によるキャンセルは維持。
- 操作ボタンの「レイアウトを編集」の右側に「設定を開く」を追加。設定を開く／背景で閉じるときは進行中のジェスチャーを取り消し、短いキーリリースで再表示しない。
- クリックが難しかったインラインの時計切り替えと予定設定ボタンを撤去。編集時の右上をline.3.horizontal.circleアイコンにし、時計の「アナログ時計／デジタル時計」、予定の「表示するカレンダーを設定…」をメニューへ集約。予定の背面設定と回転は維持。設定面の内側だけ編集用hitTestを通す。
- 実設定でNotion Calendarの起動先に一時的な認証URLが残っていた。URLの値は文書に記録していない。起動先をルートURLへ正規化し、認証callbackや日付付きのURLを保存しないよう修正。既存の共有／画面別レコードも起動時に正規化する。パネルID・配置・ログインデータは維持。
- Notion Calendar表示時にページのToday／今日ボタンの描画を待ち、1回だけ押す。設定 → パネル → Webカレンダーで無効化可能。手動の「今日に戻す」も編集メニューへ追加。表示中の別日閲覧は維持し、非表示時は待機をキャンセルする。実サイト上で希望の期間になったかはユーザー確認が必要。
- --verify-panel-behavior、--verify-widgets、--verify-settings、--verify-input-monitoring、--verify-fadesに成功。実WebKitのネイティブクリック、設定導線、クリック継続とキーリリース、Todayボタンの遅延描画／1回だけの実行／非表示取消、URL正規化を検証。合成スクロールイベントはwindowNumber=0となるため自動テストには採用せず、隔離したScrimReviewの一時表示をCUAでクリック・スクロールし、ボタン成功とスクロールバー0→0.2942196を確認。実アカウントを使わない。テスト用アプリは停止済み。
- 通常版を証明書署名して/Applications/Scrim.appへ更新・再起動。署名requirement不変とビルド元とのバイナリ一致、保存されたカレンダー起動先の正規化を確認。未commit・未push。

---

# 次の予定のアカウント選択と回転設定カード（2026-11-17）

- 次の予定の編集時に「設定」ボタンを追加。カードの前後を0.42秒の3D回転で切り替え、背面にアカウント／カレンダーのチェック一覧を表示。「動きを減らす」時はフェード。完了またはレイアウト編集終了で予定面へ戻る。
- 原因はEventKitの全カレンダー取得。カレンダーアプリ／Notion Calendar側の表示チェックとは独立している。EKSourceごとにまとめて一括選択、カレンダーごとの個別選択に対応。
- 選択はWidgetSpecのURLにfilter=selectedと複数calendar queryとしてパネルごとに保存。nilは全カレンダー、空集合は明示的に0件。選択済みがすべて消えた場合も別のカレンダーへフォールバックしない。予定の変更・アカウント設定の変更は行わない。
- --verify-widgets成功。架空の2アカウント／3カレンダーで絞り込み、全解除、全選択、URL特殊文字の往復、再読み込み、パネルへの永続化、編集状態とhitTest、編集終了時の表面復帰を確認。設定面と前後切替の描画も確認。XCTestのURL回帰テストも追加（このMacにはXCTestなし）。
- 通常版を証明書署名し/Applications/Scrim.appへ更新・再起動。署名requirement不変とビルド元のバイナリ一致を確認。未commit・未push。実際のアカウントの選択はユーザーが設定カードから行う。

---

# 編集時の時計と画面間の配置修正（2026-11-17）

- 時計のアナログ／デジタル切り替えを編集時だけ表示。PanelViewから編集状態を伝播し、編集時のドラッグ用hitTestが切り替え操作を奪わないようコントロール領域だけ通す。右上メニューとの重なりも回避。
- 実設定を読み取り、共有レイアウトが既定オン、画面別配置の保存なしを確認。スクリーンショットの違いは小さい画面でLayoutFitterが固定ptの縮小と保存順での再配置を行うため。保存順は前面化で変わるので並びも変わっていた。
- 共有時はrelativeFramesで画面に対する位置・サイズの比率を維持。共有時の自動再配置は廃止し、画面別配置モードの既存処理は維持。既存の保存配置は削除・リセットしていない。
- --verify-widgets成功。通常／編集の時計切り替え表示状態、編集時のhitTest通過、選択保存・復元を確認。2560x1440／1512x982／1920x1080で比率維持と前面化による順番変更への非依存を検証。XCTest用の回帰テストも追加（このMacにはXCTestなし）。
- 通常版を証明書署名し、/Applications/Scrim.appを更新・再起動。署名requirement不変、バイナリ一致を確認。未commit・未push。

---

# 予定の表示件数と時計の切り替え（2026-11-17）

- 次の予定：高さによる表示1〜4件の制限と取得8件の上限を撤去。7日間の予定をスクロールで全件確認可能。日付ヘッダーと余白を縮めて表示件数を増やし、右上に期間と総件数を表示。
- 時計：パネル内の標準セグメントでアナログ／デジタルを切り替え。デジタルは時分・秒・日付。scrim-widget://clock?style=digitalとしてパネルごとに保存し、再起動・複製時にも復元。旧URLはアナログのまま。
- --verify-widgetsに成功。12件の架空予定でスクロール表示を描画確認、時計の切り替えがメモリ設定のレコードに保存され再作成後に復元することを確認。デジタルの描画も確認。
- 証明書署名付き通常版を/Applications/Scrim.appへ更新・再起動し、署名requirement不変・バイナリ一致を確認。未commit・未push。

---

# フェードと実機確認の更新（2026-11-17）

- ユーザー実機でScrimが開き、ScreenNapとの干渉が解消したとの報告あり。ユーザー承認でScreenNapのsequenceEnabledをfalseに変更し、再起動・保存値を確認済み。
- 表示・非表示に0.25秒のease-in/ease-outを追加（最初の0.7秒案はユーザーが0.2〜0.3秒へ訂正）。peek→pinnedは進行中の表示フェードを継続。非表示途中の再表示は反転。入力監視取消などの緊急非表示は即時。
- --verify-fadesで実ウィンドウの途中の透過度、固定への移行、非表示途中の再表示、完全非表示とクリック透過、即時キャンセルを確認済み。
- 既存.buildのSwiftPM DBがdisk I/O errorを繰り返したため、一時scratch path /tmp/scrim-fade-buildでビルド。リポジトリのビルドスクリプト自体は変更していません。

---

# 追加更新（2026-11-17 14:12 JST）

- ウィジェット全体をApple純正風に変更。時計はアナログ文字盤、月間カレンダーは赤い月・今日の日付、天気は青いグラデーション。
- 「次の予定」を追加。EventKitでMacのカレンダーから今後7日間の予定を読み取り、予定名・時刻・場所・カレンダーの色を表示。初回は接続ボタンからのみ許可を要求。拒否・取消・予定なしの表示あり。表示中の1分更新／変更通知、非表示時の停止。予定の書き込みなし。
- カレンダーのusage descriptionと署名用entitlementを追加。通常ビルド・証明書署名・ウィジェット検証（4種類、WebView枠分離、非表示停止、検証モードで個人カレンダー取得・許可要求をしないこと）に成功。テスト用予定と4種類の実ウィンドウ描画を確認。実カレンダーの許可と予定取得はユーザー操作後の確認が必要。
- /Applications/Scrim.appを更新・再起動。旧版はbuild/previous-install-20261117-141203.app。designated requirement不変、署名検証、バイナリ一致を確認。未commit・未push。
- 暗転の調査：ScreenNapとScrimが同時起動中。ScreenNapのsequenceEnabled=true、保存シーケンスは⌘・⌘・⌘。14:09:45／50／53のログでキー一致→3画面のBlackout startedを確認。Scrimの繰り返し操作がScreenNapの3回押しに衝突していると考えられる。ScreenNapの設定は変更せず、ユーザーへ3回押し無効化の可否を質問中。

---

# ローカル実装の更新（2026-11-17 JST）

ユーザーの依頼により、Scrim 0.1.0 (8) をこの checkout に実装しました。未 commit・未 push・未公開です。最後の配布済みリリースは引き続き Sheerpane trial.7 です。以下の旧記録にある「改名未着手」は、このローカル実装については解消しています。

- ソース・SwiftPM ターゲット・製品・アプリ表示名を Scrim に改名。bundle ID は `com.satoshi0817.Scrim`。ビルドは `scripts/build-scrim.sh`。旧スクリプトは転送用に残しました。
- Sheerpane → Chira の順に設定を一度だけコピーし、Scrim の既存設定を優先。旧ドメインへの書き込みや Keychain の変更はありません。WebKit の旧ログインデータや入力監視の権限は移行しません。
- パネルの常時タイトルバーを撤去し、本文が全面を使用します。
- HTMLファイル／フォルダの取り込みを追加。画像・CSS・JSを専用フォルダへコピーし、元ファイルを移動・削除しても使えます。入れ子のエントリHTMLもパネル専用ルートから相対参照できます。
- ネイティブの「東京の天気」「時計」「月間カレンダー」を追加。天気は気象庁の予報とアメダス東京を使用。観測／発表時刻と出典を表示し、10分更新・キャッシュ・エラー表示を実装。位置情報／EventKitの許可は要求しません。
- ウィジェットはWebViewの枠を消費せず、非表示時は更新停止。新規パネルは空きグリッドを探して配置します。
- HUD（下部の操作ボタン）は初期状態では非表示。設定 → 一般から再表示可能で、メニューバーの「レイアウトを編集…」は常に使えます。
- グリッドに画面端16〜32pt／パネル間8〜16ptの余白を追加。編集開始時に表示配置を揃え、近接時の吸着も間隔を残します。
- HTML・テキストを直接入力／貼り付けしてパネル化。作成内容は Application Support/Scrim/PanelDocuments に分離保存し、編集モードで再編集できます。外部txt/text/md/markdown/logは読み取り専用のネイティブ表示に対応。
- 「レイアウトを編集」中だけ移動・サイズ変更・追加・複製・削除が可能。通常時は Web / PDF の操作が可能で、配置はロックします。Esc は編集を終了し、通常時はオーバーレイを閉じます。
- 固定 pt のグリッドを廃止。表示画面を横12列・縦8行に分割し、編集中だけ交点にドットを描きます。読み込みだけでは既存の保存配置を丸めません。
- 設定画面は標準 NSTabViewController の設定ツールバーと SwiftUI の grouped Form に刷新。「一般」「操作」「パネル」に分け、起動・Dock・ジェスチャー・ショートカット・画面別配置を標準のスイッチ／ピッカー／詳細開閉で編集します。診断は開発・試用ビルドだけ別タブです。
- 下部の操作ボタンは macOS 26 以降で標準 `NSButton` の `.glass` を使用。ボタン外側の共通背景と内側の二重枠を廃止し、ボタン自体を一層の Liquid Glass にしました。それ以前の OS は標準ボタンへフォールバック。
- 既存の WebKit 表示を継続し、`WKUIDelegate` で別窓、Cookie 共有、POST、window.opener、storage 通知、window.close、JS ダイアログに対応。認証の別窓がある間は元 WebView を破棄しません。
- 対象サイトは `calendar.notion.com`。公開コードでは別窓と storage イベントによる認証を確認。実際の日本語ログイン画面を隔離した WebKit で表示確認済み。実アカウントの認証完了は未確認です。
- Designer の `/workspace/notch-review/icons/scrim/` はこの Mac にないため、アイコン画像は以前のものを維持しています。

入力監視の修正（2026-11-17 11:13 JST）:

- macOS の TCC ログで旧 ad-hoc の cdhash `917911f...` と更新後 `d82ed0a...` の不一致を確認。旧アプリの実効監視は0件でした。
- ビルドスクリプトは証明書署名を必須にし、未指定時は Keychain の Apple Development 証明書を使用。ad-hoc への自動フォールバックを廃止。コード変更前後で designated requirement が一致することを確認しました。
- 監視を OS の enabled と実マスクで検証し、許可後や無効化・タイムアウト後に最大1秒間隔で再接続。自動の権限要求／TCCリセットはしません。
- 設定は「許可あり」だけを成功とせず「動作中」「監視を開始できません」を分け、再接続ボタンを追加。
- `--verify-input-monitoring` と `--verify-settings` は成功。回復ロジックのテストは偽の依存を使い、OS権限を変更しません。
- 修正版を停止後に入れ替え、旧版は `build/previous-install-20261117-111346.app` に保存。署名方式が変わるため、一度だけユーザーによる入力監視の旧項目削除／新アプリ再追加が必要です。その後、実行中アプリの監視が enabled=true、実マスク33559562（flagsChanged・keyDownほか必要イベントあり）となったことをOSの一覧で確認しました。物理キーの操作結果そのものはユーザーから未受領です。

検証:

- `swift build`、通常版および `--trial` の app ビルドと ad-hoc 署名検証は成功。
- メモリ設定・非永続 WebKit・ローカルの架空ログインによる `--verify-interactions` は成功。通常時の配置ロック、編集時の移動・追加・削除、画面比率グリッド、タイトルバーなし、別窓、Cookie、POST / redirect、opener + storage callback、window.close、WebView 再作成後のセッションを確認。
- `swift test` はこの Mac に XCTest を含む Xcode がないため `no such module 'XCTest'` で実行不可。既存テストの import / リソースパス / 名前 / 期待値を更新し、設定移行の優先順位と画面別グリッドの回帰テストを追加しています。Xcode がある環境で全件の実行が必要です。
- `--verify-widgets` は成功。東京予報、観測値の品質、URL保存、ネイティブ表示、重なり回避、WebView枠の分離、非表示時の停止、オフライン時のキャッシュ保持を確認。
- `--verify-content` は成功。取り込み元フォルダ削除後に相対参照の画像・CSS・JSが表示されることも確認。テキスト／HTMLの作成、Unicode、再編集・再読み込み、休止復帰、外部ファイルへの書き込み拒否、HTMLのフォルダ分離、閉じる操作での元ファイル保持を確認。
- `--verify-settings` は成功。メモリ設定と偽ログインサービスで、Dock・ログイン・画面別配置・ジェスチャー・タイミング検証・ショートカット登録の成功／失敗／取消を確認。
- 実画面で単層のガラスボタン、追加メニューの種類選択、テキスト入力シートと取消を確認。最新版を /Applications/Scrim.app に再配置し、署名・ビルド元とのバイナリ一致と再起動を確認。
- 実画面でも通常／編集の切替、操作メニューの表示条件、ログイン別窓の生成、標準設定ツールバーのタブ切替とスイッチ操作、Esc によるショートカット記録の取消を確認。

通常版を `/Applications/Scrim.app` に配置済み（0.1.0 build 8、Apple Development 証明書署名、Developer ID 公証なし）。設置後の署名検証とビルド元バイナリの一致を確認しています。

HTML取り込みと3種類のウィジェットを含む最新版を再配置済み。旧版は `build/previous-install-20261117-115140.app` に保存。証明書の designated requirement が旧版と一致すること、ビルド元と設置先のバイナリ一致、実際の気象庁データの表示を確認しました。

詳細と検証手順は [scrim.md](scrim.md)。以下は過去の出荷・開発履歴です。

---

# 現状と残作業（2026-11-17 JST）

現行の main は **Sheerpane 0.1.0 (7)** です。commit は `80592fbccc6e76ab216ffb9caafd53386cf6b5f8`、tag は `v0.1.0-trial.7`、bundle ID は `com.satoshi0817.Sheerpane` です。この記録を書いた時点では、main は origin/main と一致していました。Sheerpane から Scrim への改名（TASK-OVERLAY-016 / trial.8）のソース差分は、まだありません。

## リリース済み一覧

いずれも非公開リポジトリ `satoshi0817/overlay-browser-trial` のプレリリースです。一般公開用ではありません。Apple Silicon（arm64）のみ、macOS 14 以降、Developer ID 署名・公証・staple 済みです。

- **v0.1.0-trial.1**（Chira 0.1.0 (1)、2026-10-29）
  - commit `83cb68e`、tag `v0.1.0-trial.1`
  - zip `Chira-0.1.0-trial.1.zip`、SHA-256 `ed2eec52aff0c1d7aaa58dd1cfafb77e5db5d5ed242d251d1cca564a8ceaba59`、CDHash `c0287c50d4646b015416c09857c7f3f361dec1ed`
  - https://github.com/satoshi0817/overlay-browser-trial/releases/tag/v0.1.0-trial.1
  - 診断付きの試作。既定キーは ⌃⌥Space。登録失敗の表示、休止中パネル、権限案内。名前は仮で、商標は未確認。
- **v0.1.0-trial.2**（Chira 0.1.0 (2)、2026-11-16）
  - commit `1ac1f4f`、tag `v0.1.0-trial.2`
  - zip `Chira-0.1.0-trial.2.zip`、SHA-256 `79207e4d15cef03ef022c6d69941dc6de065a70590a83480fc6b34f3fdbae32c`
  - https://github.com/satoshi0817/overlay-browser-trial/releases/tag/v0.1.0-trial.2
  - 既定キーを ⌃⌥P に変更。メニューバーアイコン、通常キーの記録、Dock 表示、初回案内。Designer 指摘の表示修正。
- **v0.1.0-trial.3**（Sheerpane 0.1.0 (3)、2026-11-16）
  - commit `b7b80fc`、tag `v0.1.0-trial.3`
  - zip `Sheerpane-0.1.0-trial.3.zip`、SHA-256 `a1114ac20748cc56c2490c92821ca1ad5236cb5a74bb874b7bc3570ef23d392c`、公証後 CDHash `be4b40ea24f5137959128d3ecbababadb98ba07d`
  - https://github.com/satoshi0817/overlay-browser-trial/releases/tag/v0.1.0-trial.3
  - Chira から Sheerpane へ改名（bundle ID `com.satoshi0817.Sheerpane`）。アイコン、旧設定の一度だけのコピー、起動時の UserDefaults フォールバック、登録失敗時の中立な枠。
- **v0.1.0-trial.4**（Sheerpane 0.1.0 (4)、2026-11-16）
  - commit `29f90e8`、tag `v0.1.0-trial.4`
  - zip `Sheerpane-0.1.0-trial.4.zip`、SHA-256 `e261e30806759dc8a9dee23964090c669f1ef6719015d3e0c51dc3e09928137c`、公証後 CDHash `5bee4bd3af8d73d4027206f6365ae4810888191a`
  - https://github.com/satoshi0817/overlay-browser-trial/releases/tag/v0.1.0-trial.4
  - ⌘ の2回押し、許可カード、fn / 🌐 の上級オプション。許可がなくても ⌃⌥P は使える。
- **v0.1.0-trial.5**（Sheerpane 0.1.0 (5)、2026-11-16）
  - commit `7f5277a`、tag `v0.1.0-trial.5`
  - zip `Sheerpane-0.1.0-trial.5.zip`、SHA-256 `26eababd843a1e0a8c0f25f2c7f3727c8feba158ff18b44a3e89f25096d6baf9`（再ダウンロード一致）
  - https://github.com/satoshi0817/overlay-browser-trial/releases/tag/v0.1.0-trial.5
  - ログイン時の起動（006）。`guided` の初回案内が繰り返し出る問題の修正。
- **v0.1.0-trial.6**（Sheerpane 0.1.0 (6)、2026-11-16）
  - commit `74d0658`、tag `v0.1.0-trial.6`
  - zip `Sheerpane-0.1.0-trial.6.zip`、SHA-256 `b48be87d0c2285d0d86752b324a864d15003f9377f82d32f131b23c0ca436b3c`（再ダウンロード一致）
  - https://github.com/satoshi0817/overlay-browser-trial/releases/tag/v0.1.0-trial.6
  - ディスプレイごとの配置（008）。「すべてのディスプレイで同じ配置」は既定でオン。小さい画面では縮めて折り返し、縦に収まらないときは 28pt ずつずらして重ねる。
- **v0.1.0-trial.7**（Sheerpane 0.1.0 (7)、2026-11-16 23:31 JST）
  - commit `80592fb`、tag `v0.1.0-trial.7`
  - zip `Sheerpane-0.1.0-trial.7.zip`、SHA-256 `31071db87227846bb6dfbb1bde7f5489bf017b56f515e9305cb0a208324e0f2d`（再ダウンロード一致）、公証後 CDHash `aa21ff489cf70b6012b26762fabd518b6260c9e7`
  - https://github.com/satoshi0817/overlay-browser-trial/releases/tag/v0.1.0-trial.7
  - PDF / HTML をパネルで開く（Finder の「このアプリケーションで開く」、ドロップ、「ファイルを開く…」⌘O）。拡張子のない PDF の判定。ファイルパネルの「…」メニューと、読めないときの理由行。「削除」の表記を「パネルを閉じる」に変更（パネルを消すだけで、元のファイルには触れない）。監督側の `swift test` は 171 件すべて成功。

## TASK-OVERLAY-016 / trial.8（Scrim への改名）の状態

- 2026-11-16 23:31 JST ごろ、trial.7 出荷のあとに着手する予定でした。新しい Codex thread、base は main `80592fb`、bundle ID は `com.satoshi0817.Scrim`、バージョンは 0.1.0 (8)、アイコンは `/workspace/notch-review/icons/scrim/`、プレビューは `/workspace/notch-review/r14/`、アプリ内の文言はすべて Scrim にする、という方針です。
- その直後に Grok Bot の利用枠が尽きたため、監督側の作業が途中で止まっています。Local Codex Runner を確認したところ、TASK-OVERLAY-016 の job / thread / worktree は作られていません。最後の job は TASK-OVERLAY-007 の継続 `f3ec869c-71dd-4ac5-b649-f80f84e585cb`（thread `01a1e4a5-176b-7ce2-b67e-00eeb92ff9f1`、worktree `66ca5a9f10746c4b442c954b`）で、2026-11-16 23:22 JST に成功しています。
- 改名のソース差分はないため、ブランチ `task/overlay-016-scrim-rename` は作っていません。016 のテストとビルドも、差分がないので実行していません。
- 改名は、利用枠が回復したあと、新しい Codex thread でやり直します。公開名の最終判断は、下の「公開前に決めること」に従います。非公開の試用版で Scrim を使うこと自体は、Lead の条件では止まっていません。

## 次のタスク（Lead の一覧）

1. **改名（trial.8 / TASK-OVERLAY-016）**: Sheerpane を Scrim にする。アイコンは Designer の `icons/scrim/`。アプリ内の文言（メニュー、設定、fn の注意書き、許可カード、エラー）をすべて Scrim にする。「このアプリについて」画面は、今のアプリにはまだないので、完全版の仕上げで最初から Scrim の名前で設計する。
2. **009 自動更新**
3. **010 ブラウザ／既定のアプリで開く**
4. **011 閲覧データの消去**
5. **012 カレンダー・リマインダー・時計（読み取りのみ）**
6. **013 広告やトラッカーのブロック**

## 仕上げのメモ

- 診断なしの通常版（試用版の `--trial` / `TRIAL_DIAGNOSTICS` を外した配布）。
- 「このアプリについて」画面とライセンス表記。
- アップデートの仕組み。
- Designer の細かい直し:
  - 許可カードのボタン順と高さ
  - 「システム設定を開く」の左端
  - 列ごとのカスケードと最小オフセット 20pt
  - ライトでファイルパネルの「…」が白く浮いて見えるので、ダークと同じ控えめな塗りに揃える（trial.7 は止めない仕上げ）
  - タイトルバーのアイコンがファイル名より少し上にずれているので、縦の中心を揃える（同上）
  - 設定画面の余白

## Designer の仕事

- trial.8（Scrim 改名）のプレビュー確認
- 009〜013 のデザイン確認
- ウィジェットの仕様書き

## さとしさんの実機確認（trial.4〜7）

まだ実機では確認できていません。戻ったら、次を順に見てください。

**trial.4（手順 1〜8）**

1. 出てきたカードの「許可する」を押します。
2. システム設定の「入力監視」で Sheerpane をオンにします。カードに「許可されました」と出て閉じれば完了です。
3. ⌘ を短く1回押して離し、すぐにもう1回押したままにします。押している間だけパネルが出れば OK です。
4. 3 と同じ操作で、2回目を一瞬で離します。パネルが出たまま残れば OK です。もう一度呼び出すか Esc で閉じてください。
5. 左の ⌘ と右の ⌘ を1回ずつ押しても、3 と同じようにパネルが出れば OK です。
6. ⌘C、⌘Tab、⌘クリックをそれぞれ試します。どれでもパネルが出なければ OK です。
7. ⌘ を2回押し、2回目を押したまま C を押します。パネルがすぐ消えて（出ないこともあります）、元のアプリでコピーができていれば OK です。
8. パスワード欄に入力しながら ⌘ を2回押します。パネルが出ず、メニューの先頭が「パスワード入力中は…」になっていれば OK です。

**trial.5**

- ログイン項目の実登録と、システム設定での許可。「ログイン時に Sheerpane を開く」をオンにし、ログアウトしてログインし直し、自動で起動するか見る。2回起動して、初回案内が出ないことを確かめる。

**trial.6**

- 2台目のディスプレイでの実機確認、抜き差ししたあとの並びの復元、ポインタのある画面に出ること、重なったタイトルバーをクリックして前に出す操作。

**trial.2 から継続**

- 実メニューバーのアイコン（メニューバー管理ツールで隠れていると見えません）。
- Chira からの設定移行。配布済みの Chira trial.1 と trial.2 は、自分の bundle ID を `UserDefaults(suiteName:)` に渡すため、Finder や `open` での起動時に落ち得ます。

**trial.7**

- Finder の「このアプリケーションで開く」、ドロップ、⌘O、実パネルでの PDF 表示、開くときのちらつき。

## 公開前に決めること

さとしさん自身の判断が必要です。非公開の試用版を Scrim で進めることと、一般公開の名前は分けて考えます。

- **公開名**: Scrim のままか、「Scrim for Mac」のように言葉を足すか、別の名前にするか。
- **商標の最終確認**: 同じ用途（押してのぞくブラウザ）の Scrim は見当たりませんでした。ただし、画面に重ねる系統の Mac アプリが2つ（ScrimApp、TryScrim）すでに「Scrim」と名乗っています。アメリカには同じつづりの SCRIM が 9類・42類にあり、日本には読み方が同じ「ＳＱＲＩＭ」の登録があります。scrim.com / .app / .dev / .io / .ai は登録済みです。公開時の重なりは Sheerpane より大きくなります。法的な判断ではなく、一次的な調べです。
- **ライセンスの最終確認**。

## ほかの worktree に残っている差分（参考・未 push）

016 以外の worktree は、勝手には push していません。

- TASK-OVERLAY-007（`66ca5a9f`）: HEAD は main と同じ `80592fb`。追跡ファイルの差分なし。未追跡の `preview-out/` のみ（commit しない）。
- TASK-OVERLAY-008（`077ef8b3`）、006（`f129930e`）、005（`17b426bd`）: 追跡ファイルの差分なし。各 worktree の HEAD は、それぞれの出荷 commit（trial.6 / trial.5 / trial.4）のままです。
- TASK-OVERLAY-014（`f6cda73a`、HEAD `521aca9`）: Chira から Sheerpane への改名差分が未 commit で残っています。この内容は trial.3（`b7b80fc`）として main に入済みです。
- TASK-OVERLAY-003（`39144f2d`、HEAD `1ac1f4f`）: 登録失敗時の中立な枠と、補助文をエラーのすぐ下へ置く変更（4 ファイル、+38 / -3）が未 commit で残っています。この内容は `521aca9` として main に入済みです。

---

## TASK-OVERLAY-007 / v0.1.0-trial.7（現行ソース・出荷引き継ぎ）

現行製品は **Sheerpane 0.1.0 (7)**。`CFBundleShortVersionString=0.1.0`、`CFBundleVersion=7`、bundle ID は `com.satoshi0817.Sheerpane`。アイコンは変更しません。Designer の r13b Approve と Lead の GO を受け、trial.7 として出荷する実装です。trial.6 はベース commit `74d0658465ae279926e6306334e8ac46f70c7af1` として出荷済みです。出荷結果（2026-11-16 23:31 JST）: commit `80592fbccc6e76ab216ffb9caafd53386cf6b5f8`、tag `v0.1.0-trial.7`（`3b17293`）、zip `Sheerpane-0.1.0-trial.7.zip`、SHA-256 `31071db87227846bb6dfbb1bde7f5489bf017b56f515e9305cb0a208324e0f2d`（再ダウンロード一致）、公証後 CDHash `aa21ff489cf70b6012b26762fabd518b6260c9e7`、Release https://github.com/satoshi0817/overlay-browser-trial/releases/tag/v0.1.0-trial.7 。trial.1–trial.6 の履歴は保持します。

- ローカル PDF / HTML / HTM / XHTML を新規パネルで開く。Finder の「このアプリケーションで開く」、ドロップ、「ファイルを開く…」⌘O。
- 公式ビルドスクリプトは entitlements を渡さず、App Sandbox は未導入。本作業でも変更なし。既存 PanelRecord の URL フィールドに plain file:// URL を保存して復元する（security-scoped bookmark は使用しない）。既存 http(s) JSON は変更なし。
- HTML は WKWebView.loadFileURL で当該ファイルのディレクトリだけを許可。PDF は PDFKit。欠落・非対応・読み込み失敗はパネル内中央に「このファイルは表示できません」。ダイアログは表示しない。
- 拡張子のない PDF はシグネチャで判定する。
- ファイルパネルとウェブパネルの「…」メニュー。読めないときの理由行。
- 「削除」の表記を「パネルを閉じる」に変更。パネルを消すだけで、元のファイルには触れない。
- r13-file-{pdf,html,unreadable}-{light,dark}.png のオフスクリーンプレビューを実装。合成 fixture は SheerpaneAssets/Resources/r13-local.*。実ファイルや実設定は使用しない。

監督側の検証（出荷前、2026-11-16 JST）: `swift test` は 171 件すべて成功。

未確認: 実機での Finder の「このアプリケーションで開く」、ドロップ、⌘O、実パネルでの PDF 表示、開くときのちらつき。

## TASK-OVERLAY-008 / v0.1.0-trial.6（現行ソース・出荷引き継ぎ）

現行製品は **Sheerpane 0.1.0 (6)**。`CFBundleShortVersionString=0.1.0`、`CFBundleVersion=6`、bundle ID は `com.satoshi0817.Sheerpane`。アイコンは変更しません。Designer の r12b Approve と Lead の GO を受け、trial.6 として出荷する実装です。trial.5 はベース commit `7f5277aba4d453516458b0c04b3105d33992f62d` として出荷済みです。出荷結果（2026-11-16 22:53 JST）: commit `74d0658465ae279926e6306334e8ac46f70c7af1`、tag `v0.1.0-trial.6`（`b4a0a5f`）、zip `Sheerpane-0.1.0-trial.6.zip`、SHA-256 `b48be87d0c2285d0d86752b324a864d15003f9377f82d32f131b23c0ca436b3c`（再ダウンロード一致）、Release https://github.com/satoshi0817/overlay-browser-trial/releases/tag/v0.1.0-trial.6 。trial.1–trial.5 の履歴は保持します。

- 保存キーは `sameLayoutOnAllDisplays`（既定 ON）、`panels`（共有配置）、`sharedLayoutReferenceSize`、`layoutsByDisplay`。共有・画面別の参照サイズは Codable な `width` / `height` オブジェクト。旧配置の割合値は書き換えず、初回表示画面を参照サイズに採用します。OFF の初回表示では現在の表示配置、または共有配置をコピーし、以後は画面別に編集・保存します。切断した画面の配置は保持し、Chira 移行元には書き込みません。
- 安定 ID は注入可能な `DisplayUUIDProviding` 経由で、ColorSync の `CGDisplayCreateUUIDFromDisplayID` → `CFUUIDCreateString` により生成する `uuid:` キー。数値 display ID の変更には依存しません。UUID が得られなければ画面ごとのランダムな `ephemeral:` キーを使い、永続化せず、別画面へ再利用しません。切断時に破棄するため、この fallback では再接続復元を保証しません。
- r12b 配置: フレームだけを縮め、通常サイズの文字・chrome・Web コンテンツを再レイアウトします。layer / affine の視覚的スケールは使いません。通常のフレーム寸法目安は元の 0.6 倍以上、240×160pt 下限。保存順に左→右、上→下へ 12pt 間隔で折り返します。縦に不足すれば 28pt のタイトルバー刻みでカスケードし、後のパネルを手前に描画して各タイトルをクリック可能にします。必要な場合はフレーム高さをさらに削って画面内に収めます。画面高さが枚数×28pt に満たない場合だけ露出幅を画面高さ÷枚数とし、完全なタイトルバーや本文が読めないリスクを残します。自由な重なり圧縮は行いません。
- チェックボックスは「すべてのディスプレイで同じ配置」。
- r12b 保存: 同じ配置が ON で shrink / wrap / cascade を行った画面では、表示用の配置・小画面参照サイズを共有配置へ保存しません。並べ替えは ID 順序のみ反映し、既存 ID の割合値と参照サイズを保持します。URL・追加削除は反映できます。補正不要な画面での移動・リサイズは共有配置に保存可能。OFF は表示どおり画面別に保存します。
- r12b 設定: helper 行の下端から「診断」見出しの上端まで約20ptを確保し、追加した分だけウインドウを下へ伸ばします。r11b のログイン・Dock の可変配置を維持します。r12b-layout-wrap / r12b-layout-stack / r12b-layout-settings の light / dark fixture は LayoutFitter を通し、メモリ保存と偽ログインサービスを使います。
- 仕上げ（未実装）:
  - 重ねたパネルが左の1列に集まらないよう、横に空きがあるときは列ごとに分けて重ねる。
  - ずらす幅の下限を 20pt にする。

監督側の検証（出荷前、2026-11-16 JST）: `swift test` は 160 件すべて成功。`./scripts/build-sheerpane.sh` と `./scripts/build-sheerpane.sh --trial` は成功。r12b プレビュー（折り返し、タイトルバーカスケード、設定の間隔 × ライト／ダーク）を確認済み。

未確認: 2台目のディスプレイでの実機確認、抜き差ししたあとの並びの復元、ポインタのある画面に出ること、重なったタイトルバーをクリックして前に出す操作。trial.4 と trial.5 の未確認項目も引き続き未確認。

# Sheerpane 引き継ぎ

## TASK-OVERLAY-006 + guided 修正 / v0.1.0-trial.5（現行ソース・出荷引き継ぎ）

現行製品は **Sheerpane 0.1.0 (5)**。`CFBundleShortVersionString=0.1.0`、`CFBundleVersion=5`、bundle ID は `com.satoshi0817.Sheerpane`。アイコンは変更しません。Designer の r11b Approve と Lead の GO を受け、trial.5 として出荷する実装です。trial.4 はベース commit `29f90e871b44ca8e343fc18ba82d44735acc70f9` として出荷済みです。出荷結果（2026-11-16 22:17 JST）: commit `7f5277aba4d453516458b0c04b3105d33992f62d`、tag `v0.1.0-trial.5`（`856a400`）、zip `Sheerpane-0.1.0-trial.5.zip`、SHA-256 `26eababd843a1e0a8c0f25f2c7f3727c8feba158ff18b44a3e89f25096d6baf9`（再ダウンロード一致）、Release https://github.com/satoshi0817/overlay-browser-trial/releases/tag/v0.1.0-trial.5 。trial.1–trial.4 の履歴は保持します。

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

## 過去の引き継ぎ記録（trial.1 / trial.2 / trial.3）

以下の「現在のソース」「未着手」「未出荷」「計画のみ」は各記録を作成した当時の状態です。現行の版数・005 の操作・許可・出荷状況には、冒頭の trial.5 開発版と継続する 005 仕様を使ってください。古いジェスチャー暫定案や polling/toggle の説明は現行仕様ではありません。

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
