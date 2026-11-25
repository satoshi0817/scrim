import SwiftUI
import ScrimCore

@MainActor final class PanelTextAppearance: ObservableObject {
    static let shared = PanelTextAppearance()
    @Published private(set) var noteSize: PanelTextSize = .standard
    @Published private(set) var notionSize: PanelTextSize = .standard

    func load(from store: SettingsStore) {
        noteSize = store.noteTextSize
        notionSize = store.notionTextSize
    }

    func setNoteSize(_ size: PanelTextSize, in store: SettingsStore) {
        store.noteTextSize = size
        noteSize = size
    }

    func setNotionSize(_ size: PanelTextSize, in store: SettingsStore) {
        store.notionTextSize = size
        notionSize = size
    }
}

struct PanelTextSizePicker: View {
    enum Content { case notes, tasks }

    let content: Content
    let store: SettingsStore
    @ObservedObject private var appearance = PanelTextAppearance.shared

    private var selection: Binding<PanelTextSize> {
        switch content {
        case .notes:
            return Binding(get: { appearance.noteSize }, set: { appearance.setNoteSize($0, in: store) })
        case .tasks:
            return Binding(get: { appearance.notionSize }, set: { appearance.setNotionSize($0, in: store) })
        }
    }

    var body: some View {
        Picker(content == .notes ? "メモの文字サイズ" : "タスクの文字サイズ", selection: selection) {
            ForEach(PanelTextSize.allCases, id: \.self) { size in
                Text(size.title).tag(size)
            }
        }
        .pickerStyle(.segmented)
    }
}
