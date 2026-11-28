import SwiftUI
import ScrimCore

enum NativeSettingsPage: CaseIterable {
    case general, input, panels
    #if DEBUG || TRIAL_DIAGNOSTICS
    case diagnostics
    #endif
    var title: String {
        switch self {
        case .general: return "一般"
        case .input: return "操作"
        case .panels: return "パネル"
        #if DEBUG || TRIAL_DIAGNOSTICS
        case .diagnostics: return "診断"
        #endif
        }
    }
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .input: return "keyboard"
        case .panels: return "rectangle.3.group"
        #if DEBUG || TRIAL_DIAGNOSTICS
        case .diagnostics: return "waveform.path.ecg"
        #endif
        }
    }
}

private struct SettingsDisclosureStyle: DisclosureGroupStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                        .accessibilityHidden(true)
                    configuration.label
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isExpanded ? "展開中" : "折りたたみ")
            if configuration.isExpanded {
                VStack(alignment: .leading, spacing: 8) { configuration.content }
                    .padding(.leading, 18)
            }
        }
    }
}

struct NativeSettingsForm: View {
    @ObservedObject var controller: SettingsController
    let page: NativeSettingsPage
    @State private var notionTokenDraft = ""
    private var store: SettingsStore { controller.store }
    private func gesture<Value>(_ key: WritableKeyPath<GestureSettings, Value>) -> Binding<Value> {
        Binding(get: { store.gesture[keyPath: key] }, set: { value in controller.updateGesture { $0[keyPath: key] = value } })
    }
    var body: some View {
        Form {
            switch page {
            case .general: general
            case .input: input
            case .panels: panels
            #if DEBUG || TRIAL_DIAGNOSTICS
            case .diagnostics: diagnostics
            #endif
            }
        }
        .formStyle(.grouped)
        .disclosureGroupStyle(SettingsDisclosureStyle())
        .frame(minWidth: 600, idealWidth: 640, maxWidth: .infinity, minHeight: 480, idealHeight: 540, maxHeight: .infinity)
    }

    private var general: some View {
        Group {
            Section {
                Toggle("ログイン時に Scrim を開く", isOn: Binding(get: { controller.loginModel.isOn }, set: controller.setLoginEnabled))
                if controller.loginModel.showsApproval {
                    Text(LoginItemSettingsModel.approvalText).font(.callout).foregroundStyle(.secondary)
                }
                if let error = controller.loginModel.errorText {
                    Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(ScrimPalette.red)
                }
                if controller.loginModel.showsSettings {
                    Button(LoginItemSettingsModel.settingsTitle) { controller.loginModel.openSettings() }
                }
            } header: { Text("起動") }
            Section {
                Picker("外観", selection: Binding(get: { store.appearanceMode }, set: controller.setAppearanceMode)) {
                    Text("システム").tag(AppearanceMode.system)
                    Text("ライト").tag(AppearanceMode.light)
                    Text("ダーク").tag(AppearanceMode.dark)
                }.pickerStyle(.segmented)
                Toggle("Dock に表示", isOn: Binding(get: { store.dockVisible }, set: controller.setDockVisible))
                LabeledContent("アクション一覧", value: "⌘,")
                Toggle("Esc を2回押して Scrim を閉じる", isOn: Binding(get: { store.doubleEscapeToDismiss }, set: controller.setDoubleEscapeToDismiss))
            } header: { Text("表示") } footer: {
                Text("Scrimの固定表示中に ⌘ とカンマで一覧を開き、↑↓で選んでReturnで実行します。")
            }
            Section("パネルの配色") {
                PanelThemeSettingsView(store: store)
            }
            Section {
                Toggle("画面共有・スクリーンショットから除外", isOn: Binding(get: { store.hideFromScreenCapture }, set: controller.setCaptureExclusion))
            } header: { Text("画面キャプチャ") } footer: {
                Text("対応するキャプチャ方式でのみ有効です。現在のmacOSや共有アプリでは表示される場合があるため、共有先で事前に確認してください。撮影するときはオフにできます。")
            }
            Section {
                ReleaseSettings()
            } header: { Text("Scrim") }
        }
        .toggleStyle(.switch)
    }

    private var input: some View {
        Group {
            Section("ページ移動") {
                HStack {
                    Text("←／→と組み合わせるキー")
                    Spacer()
                    Text(controller.pageKeyLabel).monospaced()
                    Button(controller.recordingPageKeys ? "キャンセル" : "記録…") {
                        if controller.recordingPageKeys { controller.cancelRecording() }
                        else { controller.beginPageKeyRecording() }
                    }.disabled(controller.isRecording)
                }
                if controller.recordingPageKeys {
                    Text("⌘・⌥・⌃・⇧を好きな組み合わせで押し、すべて離すと保存します。Escでキャンセルできます。")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }.onDisappear { if controller.recordingPageKeys { controller.cancelRecording() } }
            Section {
                HStack {
                    Text("ショートカット")
                    Spacer()
                    Text(controller.shortcutPresentation.recorderFieldText)
                        .font(.system(.body, design: .monospaced)).textSelection(.disabled)
                    Button(controller.isRecording ? "キャンセル" : "変更…") {
                        if controller.isRecording { controller.cancelRecording() } else { controller.beginRecording() }
                    }
                    Button("既定に戻す") { controller.resetShortcut() }.disabled(controller.isRecording)
                }
                .accessibilityElement(children: .contain)
                if controller.isRecording {
                    Text("キーの組み合わせを押してください。Esc でキャンセルできます。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if let feedback = controller.shortcutFeedback {
                    Label(feedback, systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            } header: { Text("呼び出し") } footer: {
                Text("押している間はのぞき見、短く押して離すと固定します。Esc・背景のクリック・同じショートカットで閉じます。")
            }

            Section {
                Toggle("一時表示中にクリック・スクロールを使う", isOn: Binding(get: { store.peekAllowsInteraction }, set: controller.setPeekInteraction))
            } header: { Text("一時表示") } footer: {
                Text("オンにすると、2回目のキーを押している間もパネル内を操作できます。離すと閉じます。")
            }.toggleStyle(.switch)

            Section {
                Toggle(GestureSettingsPresentation.checkboxTitle(fn: store.gesture.useFn), isOn: gesture(\.enabled))
                LabeledContent("表示中のレイアウト編集", value: "⌘⇧E")
                Picker("使用するキー", selection: gesture(\.command)) {
                    ForEach(CommandChoice.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.disabled(store.gesture.useFn || !store.gesture.enabled)
                LabeledContent("入力監視") {
                    Label(controller.monitoringStatus,
                          systemImage: controller.monitoringActive ? "checkmark.circle" : "info.circle")
                        .foregroundStyle(.secondary)
                    if !controller.permissionGranted {
                        Button("許可する…") { controller.presentGesturePermission() }
                    } else if !controller.monitoringActive && store.gesture.enabled {
                        Button("再接続") { controller.retryMonitoring() }
                    }
                }
            } header: { Text("ダブルプレス") } footer: {
                Text("2回目を押している間はのぞき見、短く2回押すと固定表示を開閉します。入力監視が未許可でも \(store.shortcut.displayString) を使えます。")
            }
            .toggleStyle(.switch)
            .disabled(controller.isRecording)

            Section {
                DisclosureGroup("詳細設定", isExpanded: Binding(get: { controller.advanced }, set: { controller.advanced = $0 })) {
                    timing("1回目の最長", key: \.firstTapMax)
                    timing("2回目までの間隔", key: \.gapMax)
                    timing("固定する境界", key: \.pinThreshold)
                    Toggle("fn / 地球儀キーを使う", isOn: gesture(\.useFn))
                    if store.gesture.useFn {
                        ForEach(GestureCopy.cautions, id: \.self) { Text($0).font(.callout).foregroundStyle(.secondary) }
                        Button("キーボード設定を開く…") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
                        }
                    }
                }
            }.disabled(controller.isRecording)
        }.toggleStyle(.switch)
    }
    private func timing(_ title: String, key: WritableKeyPath<GestureSettings, Double>) -> some View {
        LabeledContent(title) {
            let binding = Binding(get: { store.gesture[keyPath: key] }, set: { controller.updateTiming(key, value: $0) })
            TextField("秒", value: binding, format: .number.precision(.fractionLength(2)))
                .multilineTextAlignment(.trailing).frame(width: 64)
            Text("秒").foregroundStyle(.secondary)
            Stepper("秒数", value: binding, in: 0.01...2, step: 0.05).labelsHidden()
        }
    }
    private func saveNotionToken() {
        let token = notionTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        controller.saveNotionToken(token)
        notionTokenDraft = ""
    }
    private func notchBinding<T>(_ key: ReferenceWritableKeyPath<SettingsStore, T>) -> Binding<T> {
        Binding(get: { store[keyPath: key] }, set: { store[keyPath: key] = $0; controller.refresh(); NotificationCenter.default.post(name: .meetingBadgeChanged, object: nil) })
    }
    private var panels: some View {
        Group {
            Section {
                Toggle(DisplayLayoutCopy.checkboxTitle, isOn: Binding(get: { store.sameLayoutOnAllDisplays }, set: controller.setSameLayout))
            } header: { Text("ディスプレイ") } footer: {
                Text((store.sameLayoutOnAllDisplays ? DisplayLayoutCopy.sharedFooter : DisplayLayoutCopy.perDisplayFooter) + "\n" + DisplayLayoutCopy.switchFooter)
            }
            .toggleStyle(.switch)
            Section {
                ForEach(controller.displayChoices) { display in
                    Toggle(display.name, isOn: Binding(get: { store.showsOverlay(on: display.id) }, set: { controller.setShowsOverlay($0, on: display.id) }))
                        .disabled(display.id.hasPrefix("ephemeral:"))
                }
            } header: { Text(DisplayLayoutCopy.visibilityHeader) } footer: {
                Text(DisplayLayoutCopy.visibilityFooter)
            }
            .toggleStyle(.switch)
            Section {
                if controller.notionHasToken {
                    LabeledContent("トークン", value: "登録済み（キーチェーン）")
                    HStack {
                        Button("接続を確認") { controller.checkNotionToken() }.disabled(controller.notionChecking)
                        if controller.notionChecking { ProgressView().controlSize(.small) }
                        Spacer()
                        Button("トークンを削除", role: .destructive) { controller.removeNotionToken() }
                    }
                } else {
                    SecureField("トークン", text: $notionTokenDraft, prompt: Text("ntn_… または secret_…"))
                        .onSubmit { saveNotionToken() }
                    HStack {
                        Spacer()
                        Button("保存して確認") { saveNotionToken() }
                            .disabled(notionTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || controller.notionChecking)
                    }
                }
                if let status = controller.notionStatus {
                    Text(status.text).font(.callout).foregroundStyle(status.ok ? Color.secondary : ScrimPalette.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: { Text("Notion") } footer: {
                Text("「Notionタスク」パネルが使うトークンです。Notionの開発者ポータルで個人アクセストークンか内部接続のトークンを作り、ここに貼り付けてください。内部接続の場合は、使うデータベースや作成先のページの「•••」→「接続」から、その接続を追加してください。トークンはこのMacのキーチェーンだけに保存します。")
            }
            Section("文字サイズ") {
                PanelTextSizePicker(content: .notes, store: store)
                PanelTextSizePicker(content: .tasks, store: store)
            }
            Section {
                Toggle("開くたびに今の時間帯へ移動", isOn: Binding(get: { store.agendaResetsScrollOnOpen }, set: controller.setAgendaResetsScrollOnOpen))
            } header: { Text("次の予定") } footer: {
                Text("オフにすると、前回のスクロール位置を保ちます。")
            }.toggleStyle(.switch)
            Section {
                Toggle("ノッチ横に残り時間を表示", isOn: notchBinding(\.notchMeetingsEnabled))
                if store.notchMeetingsEnabled {
                    Stepper("開始の\(store.notchLeadMinutes)分前から", value: notchBinding(\.notchLeadMinutes), in: 1...120)
                    Stepper("\(store.notchLimitHours)時間以上の予定は表示しない", value: notchBinding(\.notchLimitHours), in: 1...24)
                    Toggle("Meet・Zoomリンクのある予定のみ", isOn: notchBinding(\.notchOnlineOnly))
                }
                NotchSettingsPreview()
            } header: { Text("ノッチの予定タイマー") } footer: {
                Text("「次の予定」に表示される時刻付きの予定が対象です。予定カードの右クリックで、その回だけ非表示にできます。")
            }.toggleStyle(.switch)
            Section {
                Toggle("3時間ごとの予報を表示", isOn: Binding(get: { store.weatherShowsHourly }, set: controller.setWeatherShowsHourly))
            } header: { Text("天気") } footer: {
                Text("時間ごとの気温・天気・降雨確率はwttr.in / WorldWeatherOnline、現在の観測値と日々の予報は気象庁を利用します。")
            }.toggleStyle(.switch)
            Section {
                Toggle("使っていないWebページを休止する", isOn: Binding(get: { store.releasesIdleWebPanels }, set: controller.setReleasesIdleWebPanels))
            } header: { Text("メモリ") } footer: {
                Text("Scrimを閉じたまま10分たつと、Webパネルを画像に置き換えてメモリを解放します。次に開いたときに読み込み直します。ログインは保たれますが、入力途中の内容やスクロール位置は戻りません。")
            }.toggleStyle(.switch)
            Section {
                Toggle("表示するときに今日へ戻す", isOn: Binding(get: { store.calendarReturnsToToday }, set: controller.setCalendarReturnsToToday))
            } header: { Text("Webカレンダー") } footer: {
                Text("Notion Calendarを開くたびに「今日」へ移動します。表示中に別の日へ移動する操作はそのまま使えます。")
            }.toggleStyle(.switch)
            Section {
                LabeledContent("グリッド", value: "横12列 × 縦8行")
                LabeledContent("表示", value: "編集中のみ・ドット")
                LabeledContent("余白", value: "画面端とパネル間に自動調整")
            } header: { Text("レイアウト") } footer: {
                Text("グリッドは画面のサイズに合わせて変わります。オーバーレイの「レイアウトを編集」から配置を変更できます。通常時は配置がロックされます。")
            }
        }
    }
    #if DEBUG || TRIAL_DIAGNOSTICS
    private var diagnostics: some View {
        Section {
            Text(controller.diagnostics).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
            Button("テキストをコピー") {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(controller.diagnostics, forType: .string)
            }
        } header: { Text("診断") } footer: { Text("試用・開発ビルドだけに表示されます。") }
    }
    #endif
}
