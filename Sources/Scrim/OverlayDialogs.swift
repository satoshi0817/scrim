import SwiftUI
import ScrimCore

enum OverlayAction: Int, CaseIterable {
    case edit, settings, quit

    var title: String {
        switch self {
        case .edit: return "レイアウトを編集"
        case .settings: return "設定を開く"
        case .quit: return "Scrim を終了"
        }
    }

    var symbol: String {
        switch self {
        case .edit: return "square.and.pencil"
        case .settings: return "gearshape"
        case .quit: return "power"
        }
    }
}

final class ActionSelection: ObservableObject {
    @Published var selected = OverlayAction.edit
    func move(_ delta: Int) {
        let actions = OverlayAction.allCases
        selected = actions[(selected.rawValue + delta + actions.count) % actions.count]
    }
}

struct OverlayActionList: View {
    @Environment(\.scrimAccent) private var accent
    @ObservedObject var selection: ActionSelection
    let editing: Bool
    let perform: (OverlayAction) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("アクション").font(.headline).padding(8)
            ForEach(OverlayAction.allCases, id: \.self) { action in
                Button { perform(action) } label: {
                    HStack {
                        Label(action == .edit && editing ? "レイアウト編集を完了" : action.title, systemImage: action.symbol)
                        Spacer()
                        if selection.selected == action { Image(systemName: "return") }
                    }.padding(10).contentShape(Rectangle())
                }.buttonStyle(.plain)
                .background(selection.selected == action ? accent.ink.opacity(0.24) : .clear, in: RoundedRectangle(cornerRadius: 8))
            }
        }.padding(12).frame(maxWidth: .infinity).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct OverlaySettingsForm: View {
    let controller: SettingsController
    let close: () -> Void
    @State private var page = NativeSettingsPage.general
    var body: some View {
        VStack(spacing: 8) {
            HStack { Text("Scrim 設定").font(.headline); Spacer(); Button("完了", action: close) }
            Picker("設定カテゴリ", selection: $page) {
                ForEach(NativeSettingsPage.allCases, id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).labelsHidden()
            NativeSettingsForm(controller: controller, page: page)
        }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

final class OverlayDialogBackdrop: NSView {
    var close: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    weak var dialogContent: NSView?
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let dialogContent, dialogContent.frame.contains(point) { return }
        close?()
    }
    override func scrollWheel(with event: NSEvent) {}
}

struct WebPanelSettings: View {
    @State var address: String
    @State var mode: WebDisplayMode
    let save: (URL, WebDisplayMode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TextField("URL", text: $address).textFieldStyle(.roundedBorder)
                    Picker("表示モード", selection: $mode) {
                        Text("PC表示").tag(WebDisplayMode.desktop)
                        Text("スマホ表示").tag(WebDisplayMode.mobile)
                    }.pickerStyle(.segmented)
                }.padding(.vertical, 6)
            }
            HStack {
                Spacer()
                Button("保存") {
                    if let url = SettingsStore.normalize(address) { save(url, mode) }
                }.keyboardShortcut(.defaultAction).disabled(SettingsStore.normalize(address) == nil)
            }
        }
    }
}

struct PanelSettingsSurface<Content: View>: View {
    let title: String
    var closeTitle = "完了"
    let close: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title).font(.title2.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(closeTitle, action: close).keyboardShortcut(.cancelAction)
            }
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(nsColor: .windowBackgroundColor))
                .strokeBorder(Color.primary.opacity(0.12))
                .shadow(color: .black.opacity(0.26), radius: 24, y: 8)
        }
    }
}
