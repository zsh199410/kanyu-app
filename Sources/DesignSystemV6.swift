import SwiftUI

/// DesignSystem V6 — presentation tokens only. No engine or persisted model changes.
enum KanyuV6 {
    enum Palette {
        static let paper = Color(red: 246/255, green: 241/255, blue: 230/255)
        static let ivory = Color(red: 252/255, green: 251/255, blue: 247/255)
        static let ink = Color(red: 43/255, green: 39/255, blue: 35/255)
        static let indigo = Color(red: 31/255, green: 73/255, blue: 89/255)
        static let cinnabar = Color(red: 154/255, green: 42/255, blue: 34/255)
        static let bronze = Color(red: 158/255, green: 120/255, blue: 47/255)
        static let obsidian = Color(red: 17/255, green: 19/255, blue: 23/255)
        static let jadeCard = Color(red: 26/255, green: 29/255, blue: 35/255)
        static let champagne = Color(red: 209/255, green: 172/255, blue: 83/255)
        static let nightIndigo = Color(red: 108/255, green: 162/255, blue: 184/255)
    }
    enum Metric {
        static let pageInset: CGFloat = 20
        static let cardGap: CGFloat = 15
        static let cardInset: CGFloat = 16
        static let cardRadius: CGFloat = 18
        static let buttonRadius: CGFloat = 14
        static let buttonHeight: CGFloat = 52
        static let minimumHitTarget: CGFloat = 44
        static let pressScale: CGFloat = 0.985
    }
    enum Typography {
        static let pageTitle = Font.system(size: 28, weight: .semibold, design: .serif)
        static let cardTitle = Font.system(size: 19, weight: .semibold, design: .serif)
        static let body = Font.system(size: 16)
        static let detail = Font.system(size: 14)
        static let numeric = Font.system(size: 16, design: .rounded).monospacedDigit()
    }
    struct Theme {
        let background: Color
        let card: Color
        let foreground: Color
        let action: Color
        let ornament: Color
        static let light = Theme(background: Palette.paper, card: Palette.ivory, foreground: Palette.ink, action: Palette.indigo, ornament: Palette.bronze)
        static let dark = Theme(background: Palette.obsidian, card: Palette.jadeCard, foreground: Color(red: 242/255, green: 235/255, blue: 221/255), action: Palette.nightIndigo, ornament: Palette.champagne)
    }
}
