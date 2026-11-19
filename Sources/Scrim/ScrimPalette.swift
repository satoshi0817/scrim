import AppKit
import SwiftUI

enum ScrimPalette {
    static let nativeBlue = NSColor(srgbRed: 0, green: 129/255, blue: 243/255, alpha: 1)
    static let nativeAmber = NSColor(srgbRed: 1, green: 175/255, blue: 0, alpha: 1)
    static let nativeRed = NSColor(srgbRed: 1, green: 50/255, blue: 26/255, alpha: 1)
    static let blue = Color(nsColor: nativeBlue)
    static let amber = Color(nsColor: nativeAmber)
    static let red = Color(nsColor: nativeRed)
    static let button = mix(nativeBlue, .black, 0.25)

    static func mix(_ from: NSColor, _ to: NSColor, _ fraction: CGFloat) -> Color {
        Color(nsColor: from.blended(withFraction: min(1, max(0, fraction)), of: to) ?? from)
    }

    static func badge(accepted: Bool, dark: Bool) -> Color {
        if accepted { return dark ? mix(nativeBlue, .white, 0.45) : button }
        return dark ? amber : mix(nativeAmber, .black, 0.52)
    }
}
