import SwiftUI

/// Oriental Precision V6. Presentation-only; Ky palette, card and primary-button APIs bridge here.
enum KanyuV6 {
    enum Hex {
        static let paper: UInt32 = 0xF6F1E6
        static let ivory: UInt32 = 0xFCFBF7
        static let ink: UInt32 = 0x2B2723
        static let indigo: UInt32 = 0x1F4959
        static let cinnabar: UInt32 = 0x9A2A22
        static let bronze: UInt32 = 0x9E782F
        static let bronzeText: UInt32 = 0x80601F
        static let obsidian: UInt32 = 0x111317
        static let jadeCard: UInt32 = 0x1A1D23
        static let champagne: UInt32 = 0xD1AC53
        static let nightIndigo: UInt32 = 0x6CA2B8
        static let secondaryLight: UInt32 = 0x6D665D
        static let secondaryDark: UInt32 = 0xB5AEA2
        static let foregroundDark: UInt32 = 0xF2EBDD
        static let highlightLight: UInt32 = 0x2C5B6B
        static let highlightDark: UInt32 = 0xDABB76
        static let elevatedLight: UInt32 = 0xEFE9DA
        static let elevatedDark: UInt32 = 0x242830
        static let ruleLight: UInt32 = 0xE2D9C5
        static let ruleDark: UInt32 = 0x3B414B
    }
    enum Palette {
        static let paper = Color(rgb: Hex.paper)
        static let ivory = Color(rgb: Hex.ivory)
        static let ink = Color(rgb: Hex.ink)
        static let indigo = Color(rgb: Hex.indigo)
        static let cinnabar = Color(rgb: Hex.cinnabar)
        static let bronze = Color(rgb: Hex.bronze)
        static let bronzeText = Color(rgb: Hex.bronzeText)
        static let obsidian = Color(rgb: Hex.obsidian)
        static let jadeCard = Color(rgb: Hex.jadeCard)
        static let champagne = Color(rgb: Hex.champagne)
        static let nightIndigo = Color(rgb: Hex.nightIndigo)
    }
    enum Metric {
        static let pageInset: CGFloat = 20
        static let cardGap: CGFloat = 15
        static let cardInset: CGFloat = 16
        static let cardRadius: CGFloat = 18
        static let innerRadius: CGFloat = 12
        static let buttonRadius: CGFloat = 14
        static let buttonHeight: CGFloat = 52
        static let minimumHitTarget: CGFloat = 44
        static let hairline: CGFloat = 0.7
        static let pressScale: CGFloat = 0.985
        static let posterWidth: CGFloat = 540
        static let posterScale: CGFloat = 2
        static let posterTextInset: CGFloat = 32
    }
    enum Typography {
        // Semantic styles scale with Dynamic Type; 28/17/15/13 pt at the standard size.
        static let pageTitle = Font.system(.title, design: .serif).weight(.semibold)
        static let cardTitle = Font.system(.title3, design: .serif).weight(.semibold)
        static let body = Font.body
        static let detail = Font.subheadline
        static let evidence = Font.footnote
        static let numeric = Font.body.monospacedDigit()
    }
    enum Motion {
        static let press = Animation.easeOut(duration: 0.18)
        static let selection = Animation.spring(response: 0.28, dampingFraction: 0.88)
        static let disclosure = Animation.easeInOut(duration: 0.24)
        static let flyline = Animation.easeOut(duration: 0.45)
    }
    struct Theme {
        let background: Color
        let card: Color
        let foreground: Color
        let secondary: Color
        let action: Color
        let actionForeground: Color
        let actionHighlight: Color
        let ornament: Color
        let rule: Color
        static let light = Theme(background: Palette.paper, card: Palette.ivory,
            foreground: Palette.ink, secondary: Color(rgb: Hex.secondaryLight), action: Palette.indigo,
            actionForeground: .white, actionHighlight: Color(rgb: Hex.highlightLight),
            ornament: Palette.bronze, rule: Color(rgb: Hex.ruleLight))
        static let dark = Theme(background: Palette.obsidian, card: Palette.jadeCard,
            foreground: Color(rgb: Hex.foregroundDark), secondary: Color(rgb: Hex.secondaryDark), action: Palette.champagne,
            actionForeground: Palette.obsidian, actionHighlight: Color(rgb: Hex.highlightDark),
            ornament: Palette.champagne, rule: Color(rgb: Hex.ruleDark))
        static func resolved(_ scheme: ColorScheme) -> Theme { scheme == .dark ? .dark : .light }
    }
}

/// Opaque content surface used by the existing kyCard wrapper.
struct KanyuV6Card<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        let theme = KanyuV6.Theme.resolved(scheme)
        content
            .padding(KanyuV6.Metric.cardInset)
            .background(theme.card)
            .clipShape(RoundedRectangle(cornerRadius: KanyuV6.Metric.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: KanyuV6.Metric.cardRadius, style: .continuous)
                    .strokeBorder(contrast == .increased ? theme.foreground : theme.rule,
                                  lineWidth: contrast == .increased ? 1.4 : KanyuV6.Metric.hairline)
                    .allowsHitTesting(false)
            }
    }
}

struct KanyuV6PrimaryButton: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        let theme = KanyuV6.Theme.resolved(scheme)
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: KanyuV6.Metric.buttonHeight)
            .foregroundStyle(enabled ? theme.actionForeground : theme.secondary)
            .background {
                RoundedRectangle(cornerRadius: KanyuV6.Metric.buttonRadius, style: .continuous)
                    .fill(LinearGradient(colors: enabled ? [theme.actionHighlight, theme.action] : [theme.rule, theme.rule],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .scaleEffect(configuration.isPressed && !reduceMotion ? KanyuV6.Metric.pressScale : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(reduceMotion ? nil : KanyuV6.Motion.press, value: configuration.isPressed)
    }
}

/// Only for a floating control layer. Do not apply to scrolling content cards or exports.
struct KanyuV6FloatingSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @ViewBuilder func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        if reduceTransparency || contrast == .increased {
            content.background(KanyuV6.Theme.resolved(scheme).card, in: shape)
                .overlay(shape.strokeBorder(KanyuV6.Theme.resolved(scheme).foreground, lineWidth: 1).allowsHitTesting(false))
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }
}
