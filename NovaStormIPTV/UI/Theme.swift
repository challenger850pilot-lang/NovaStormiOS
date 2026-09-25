import SwiftUI

/// The NovaStorm palette (mirrors the TV app).
enum Theme {
    static let accent = Color(red: 0x35 / 255.0, green: 0xA8 / 255.0, blue: 0xFF / 255.0)
    static let accentDeep = Color(red: 0x6A / 255.0, green: 0x5C / 255.0, blue: 0xFF / 255.0)
    static let bg = Color(red: 0x0A / 255.0, green: 0x10 / 255.0, blue: 0x24 / 255.0)
    static let bg2 = Color(red: 0x14 / 255.0, green: 0x1E / 255.0, blue: 0x3E / 255.0)
    static let surface = Color.white.opacity(0.08)
    static let muted = Color.white.opacity(0.6)
    static let badge = Color(red: 0x10 / 255.0, green: 0x1A / 255.0, blue: 0x38 / 255.0)
}

struct ScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.background(
            LinearGradient(colors: [Theme.bg, Theme.bg2], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea())
    }
}

extension View {
    func screenBackground() -> some View { modifier(ScreenBackground()) }
}
