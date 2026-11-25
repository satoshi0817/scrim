import SwiftUI

struct PanelGallery: View {
    let choose: (Int) -> Void
    let drag: (Int, Bool) -> Void
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
        Entry(15,"電卓","四則演算・符号変更・パーセント","plus.forwardslash.minus",ScrimPalette.amber),
        Entry(13,"次の予定","予定一覧と開始までの残り時間","calendar.badge.clock",ScrimPalette.red),
        Entry(16,"Notionタスク","未完了タスクの一覧・追加・完了","checklist",ScrimPalette.blue),
        Entry(10,"東京の天気","気温と3時間ごとの予報","cloud.sun.fill",ScrimPalette.blue),
        Entry(11,"時計","アナログまたはデジタルの時計","clock.fill",ScrimPalette.button),
        Entry(14,"世界時計","都市ごとの時刻と勤務時間","globe",ScrimPalette.button),
        Entry(12,"月間カレンダー","今月の日付と曜日をひと目で確認","calendar",ScrimPalette.red)
    ]
    private let content = [
        Entry(0,"ウェブページ","URLを指定してサイトを表示","safari.fill",ScrimPalette.blue),
        Entry(5,"Notionビュー","データベースのビューを表示","tablecells.fill",.secondary),
        Entry(1,"テキスト","箇条書きや番号付きのメモを書く","text.alignleft",ScrimPalette.amber),
        Entry(2,"HTML","入力したHTMLをページとして表示","chevron.left.forwardslash.chevron.right",ScrimPalette.button),
        Entry(3,"ファイル","PDF・テキスト・HTMLを開く","doc.fill",ScrimPalette.blue),
        Entry(4,"HTMLを取り込む","画像やCSSを含むページを保存","folder.fill",ScrimPalette.amber)
    ]
    @ViewBuilder private func artwork(_ entry: Entry) -> some View {
        switch entry.id {
        case 15:
            VStack(alignment: .trailing, spacing: 3) {
                Text("120").font(.system(size: 25, weight: .light)).monospacedDigit()
                ForEach(["789÷", "456×", "123−"], id: \.self) { row in
                    HStack(spacing: 4) {
                        ForEach(Array(row), id: \.self) { key in
                            Text(String(key)).font(.system(size: 10, weight: .medium))
                                .frame(width: 25, height: 15)
                                .background(key.isNumber ? Color.white.opacity(0.18) : ScrimPalette.amber, in: Capsule())
                                .foregroundStyle(key.isNumber ? Color.white : .black)
                        }
                    }
                }
            }.padding(9).foregroundStyle(.white).background(.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 12))
        case 13:
            VStack(alignment: .leading, spacing: 6) {
                Text("今日の予定").font(.caption.bold())
                ForEach(["10:00   チーム定例", "13:30   デザインレビュー"], id: \.self) { title in
                    Text(title).font(.system(size: 12, weight: .medium)).padding(7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(entry.color.opacity(0.13), in: RoundedRectangle(cornerRadius: 6))
                }
            }.frame(maxWidth: 184)
        case 16:
            VStack(alignment: .leading, spacing: 7) {
                ForEach([("checkmark.circle.fill", "資料を共有"), ("circle", "見積もりを確認"), ("circle", "週次レポート")], id: \.1) { symbol, title in
                    HStack(spacing: 7) {
                        Image(systemName: symbol).foregroundStyle(symbol == "circle" ? Color.secondary : entry.color)
                        Text(title).font(.system(size: 12, weight: .medium)).strikethrough(symbol != "circle")
                    }
                }
            }.frame(maxWidth: 184, alignment: .leading)
        case 10:
            HStack(spacing: 18) {
                VStack(alignment: .leading) {
                    Text("東京").font(.headline)
                    Text("18°").font(.system(size: 45, weight: .light))
                }
                Image(systemName: "cloud.sun.fill").symbolRenderingMode(.palette)
                    .foregroundStyle(.white, ScrimPalette.amber).font(.system(size: 43))
            }.foregroundStyle(.white)
        case 11:
            ZStack {
                Circle().fill(.background)
                ForEach(0..<12) { tick in
                    Capsule().fill(.secondary).frame(width: 2, height: tick % 3 == 0 ? 7 : 4)
                        .offset(y: -36).rotationEffect(.degrees(Double(tick) * 30))
                }
                Capsule().frame(width: 4, height: 23).offset(y: -11).rotationEffect(.degrees(305))
                Capsule().frame(width: 3, height: 31).offset(y: -15).rotationEffect(.degrees(60))
                Circle().fill(ScrimPalette.amber).frame(width: 6, height: 6)
            }.frame(width: 86, height: 86)
        case 14:
            HStack(spacing: 15) {
                ForEach(["東京|17:00", "ロンドン|08:00"], id: \.self) { sample in
                    let parts = sample.components(separatedBy: "|")
                    VStack(spacing: 5) {
                        Text(parts[0]).font(.caption)
                        Text(parts[1]).font(.system(size: 23, weight: .medium, design: .rounded)).monospacedDigit()
                    }
                }
            }
        case 12:
            VStack(alignment: .leading, spacing: 5) {
                Text("11月").font(.headline).foregroundStyle(entry.color)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                    ForEach(1...21, id: \.self) { day in
                        Text(String(day)).font(.system(size: 10)).frame(width: 17, height: 17)
                            .foregroundStyle(day == 20 ? Color.white : .primary)
                            .background(day == 20 ? entry.color : .clear, in: Circle())
                    }
                }
            }.frame(width: 148)
        default:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: entry.symbol).foregroundStyle(entry.color)
                    Text([0:"example.com", 5:"プロジェクト", 1:"打ち合わせメモ", 2:"index.html", 3:"資料.pdf", 4:"website/"][entry.id] ?? "")
                        .font(.system(size: 12, weight: .semibold))
                }
                Divider()
                switch entry.id {
                case 0: RoundedRectangle(cornerRadius: 4).fill(ScrimPalette.blue.gradient).frame(height: 17)
                case 5: Text("タスク名　　　　　担当").font(.caption.bold())
                case 1: Text("・ 来週の予定を確認").font(.caption)
                case 2: Text("<main>Hello</main>").font(.system(size: 11, design: .monospaced))
                case 4: Text("├ index.html   └ assets/").font(.system(size: 11, design: .monospaced))
                default: Text("四半期レポート").font(.headline)
                }
                Capsule().fill(.secondary.opacity(0.25)).frame(width: 90, height: 3)
            }.padding(12).frame(width: 170, alignment: .leading)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack { Text("パネルを追加").font(.title2.bold()); Spacer(); Button(action: close) { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel("閉じる") }
            Text("クリックして追加、または配置したい場所にドラッグ").font(.callout).foregroundStyle(.secondary)
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
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 235, maximum: 400))], spacing: 14) {
                ForEach(entries) { entry in
                    Button { choose(entry.id) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            artwork(entry)
                                .frame(maxWidth: .infinity).frame(height: 120)
                                .background(entry.id == 10 ? ScrimPalette.button : entry.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                                .accessibilityHidden(true)
                            Text(entry.title).font(.headline)
                            Text(entry.description).font(.callout).foregroundStyle(.secondary)
                        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    .highPriorityGesture(DragGesture(minimumDistance: 5, coordinateSpace: .global)
                        .onChanged { _ in drag(entry.id, false) }
                        .onEnded { _ in drag(entry.id, true) })
                }
            }
        }
    }
}
