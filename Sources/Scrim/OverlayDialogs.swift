import SwiftUI

enum OverlayAction: Int, CaseIterable {
    case edit, settings
    var title: String { self == .edit ? "レイアウトを編集" : "設定を開く" }
    var symbol: String { self == .edit ? "square.and.pencil" : "gearshape" }
}

final class ActionSelection: ObservableObject {
    @Published var selected = OverlayAction.edit
    func move(_ delta: Int) {
        let actions = OverlayAction.allCases
        selected = actions[(selected.rawValue + delta + actions.count) % actions.count]
    }
}

struct OverlayActionList: View {
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
                .background(selection.selected == action ? ScrimPalette.blue.opacity(0.24) : .clear, in: RoundedRectangle(cornerRadius: 8))
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
    override func mouseDown(with event: NSEvent) { close?() }
    override func scrollWheel(with event: NSEvent) {}
}
