import SwiftUI

struct BasicCalculator {
    var display = "0"
    private var values: [Decimal] = []
    private var operators: [String] = []
    private(set) var awaiting = false
    private var finished = false
    private var repeatOp: String?
    private var repeatValue: Decimal?
    private var number: Decimal { Decimal(string: display, locale: Locale(identifier: "en_US_POSIX")) ?? 0 }
    private func evaluate(_ a: Decimal, _ op: String, _ b: Decimal) -> Decimal {
        switch op {
        case "+": return a + b
        case "−": return a - b
        case "×": return a * b
        default: return b == 0 ? .nan : a / b
        }
    }
    private func formatted(_ n: Decimal) -> String {
        var input = n, rounded = Decimal()
        NSDecimalRound(&rounded, &input, 14, .plain)
        return n.isNaN ? "エラー" : NSDecimalNumber(decimal: rounded).stringValue
    }
    private mutating func reduce() {
        let b = values.removeLast(), a = values.removeLast()
        values.append(evaluate(a, operators.removeLast(), b))
    }
    mutating func press(_ key: String) {
        if key == "AC" { self = Self(); return }
        if display == "エラー" { self = Self() }
        if key == "C" { display = "0"; awaiting = false; finished = false; repeatOp = nil; return }
        if key == "⌫" {
            if !awaiting && !finished { display = String(display.dropLast()); if display.isEmpty || display == "-" { display = "0" } }
            return
        }
        if key == "." || (key.count == 1 && key.first?.isNumber == true) {
            if finished { self = Self() }
            if awaiting { display = "0"; awaiting = false }
            if key == "." { if !display.contains(".") { display += "." } }
            else if display.count < 16 { display = display == "0" ? key : display + key }
            return
        }
        if key == "+/−" || key == "%" {
            let base = (operators.last == "+" || operators.last == "−") ? values.last ?? 1 : 1
            display = formatted(key == "%" ? number * base / 100 : -number)
            awaiting = false; return
        }
        if key == "=" {
            if finished, let op = repeatOp, let b = repeatValue { display = formatted(evaluate(number, op, b)); return }
            repeatOp = operators.last; repeatValue = number
            values.append(number)
            while !operators.isEmpty { reduce() }
            display = formatted(values.removeLast()); awaiting = false; finished = true
            return
        }
        guard ["+", "−", "×", "÷"].contains(key) else { return }
        if awaiting { operators.removeLast() } else { values.append(number) }
        while let last = operators.last, last == "×" || last == "÷" || key == "+" || key == "−" { reduce() }
        display = formatted(values.last ?? 0)
        operators.append(key); awaiting = true; finished = false
    }
}

struct CalculatorWidget: View {
    @State private var calc = BasicCalculator()
    @FocusState private var focused: Bool
    private let keys = [["AC", "+/−", "%", "÷"], ["7","8","9","×"], ["4","5","6","−"], ["1","2","3","+"], ["0",".","="]]
    var body: some View {
        GeometryReader { geometry in
            let gap: CGFloat = 5
            let w = max(1, (geometry.size.width - 3 * gap) / 4)
            VStack(spacing: gap) {
                Text(calc.display).font(.system(size: min(48, max(20,geometry.size.height * 0.18)), weight: .light))
                    .lineLimit(1).minimumScaleFactor(0.45).frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityLabel("計算結果 " + calc.display)
                ForEach(keys, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(row, id: \.self) { key in
                            let op = ["÷","×","−","+","="].contains(key)
                            Button { focused = true; calc.press(key) } label: {
                                Text(key).font(.system(size: min(22, max(12,geometry.size.height * 0.09)), weight: .medium))
                                    .foregroundStyle(op ? Color.white : .primary)
                                    .frame(width: key == "0" ? w*2+gap : w).frame(maxHeight: .infinity)
                                    .background(op ? Color.orange : Color.primary.opacity(row == keys[0] ? 0.21 : 0.11), in: Capsule())
                                    .contentShape(Capsule())
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }.focusable().focused($focused).focusEffectDisabled()
        .onKeyPress { press in
            let mapped = ["*":"×","/":"÷","-":"−",",":"."]
            let key = press.key == .return ? "=" : press.key == .delete ? "⌫" : mapped[press.characters] ?? press.characters
            guard press.modifiers.intersection([.command,.control,.option]).isEmpty, "0123456789.+−×÷=%⌫".contains(key), key.count == 1 else { return .ignored }
            calc.press(key); return .handled
        }
    }
}
