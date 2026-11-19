import SwiftUI

struct PanelGallery: View {
    let choose: (Int) -> Void
    let close: () -> Void
    private struct Entry: Identifiable {
        let id: Int
        let title: String
        let description: String
        let symbol: String
        let color: Color
        init(_ id: Int, _ title: String, _ description: String, _ symbol: String, _ color: Color) {
            self.id = id; self.title = title; self.description = description; self.symbol = symbol; self.color = color
        }
    }
    private let widgets = [
        Entry(15,"電卓","四則演算・符号変更・パーセント","plus.forwardslash.minus",.orange),
        Entry(13,"次の予定","予定一覧と開始までの残り時間","calendar.badge.clock",.red),
        Entry(10,"東京の天気","気温と3時間ごとの予報","cloud.sun.fill",.blue),
        Entry(11,"時計","アナログまたはデジタルの時計","clock.fill",.indigo),
        Entry(14,"世界時計","都市ごとの時刻と勤務時間","globe",.teal),
        Entry(12,"月間カレンダー","今月の日付と曜日をひと目で確認","calendar",.pink)
    ]
    private let content = [
        Entry(0,"ウェブページ","URLを指定してサイトを表示","safari.fill",.blue),
        Entry(5,"Notionビュー","データベースのビューを表示","tablecells.fill",.secondary),
        Entry(1,"テキスト","入力したメモや文章を表示","text.alignleft",.mint),
        Entry(2,"HTML","入力したHTMLをページとして表示","chevron.left.forwardslash.chevron.right",.purple),
        Entry(3,"ファイル","PDF・テキスト・HTMLを開く","doc.fill",.cyan),
        Entry(4,"HTMLを取り込む","画像やCSSを含むページを保存","folder.fill",.orange)
    ]
    private func previewText(for entry: Entry) -> String? {
        switch entry.id {
        case 15: return "24 × 5 = 120"
        case 13: return "10:00  チーム定例"
        case 10: return "18°  晴れ"
        case 11: return "10:09"
        case 14: return "東京 17:00   ロンドン 08:00"
        case 12: return "月   火   水   木   金   土   日"
        default: return nil
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack { Text("パネルを追加").font(.title2.bold()); Spacer(); Button(action: close) { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel("閉じる") }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    section("ウィジェット", widgets)
                    section("ページとファイル", content)
                }
            }
        }.padding(22).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
    private func section(_ title: String, _ entries: [Entry]) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.headline).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 185))], spacing: 8) {
                ForEach(entries) { entry in
                    Button { choose(entry.id) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 8) {
                                Image(systemName: entry.symbol).font(.title2)
                                if let sample = previewText(for: entry) {
                                    Text(sample).font(.caption.weight(.semibold)).monospacedDigit()
                                }
                            }.foregroundStyle(.white).accessibilityHidden(true)
                                .frame(maxWidth: .infinity).frame(height: 44)
                                .background(entry.color.gradient, in: RoundedRectangle(cornerRadius: 8))
                            Text(entry.title).font(.headline)
                            Text(entry.description).font(.caption).foregroundStyle(.secondary)
                        }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}
