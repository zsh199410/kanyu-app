import SwiftUI
import UIKit

/// All V5 interface components share these semantic primitives; artwork is not a substitute for content.
enum V5Typeface {
    static let regularName = "NotoSerifCJKsc-Regular"
    static let emphasizedName = "NotoSerifCJKsc-SemiBold"
}
enum V5Typography {
    static func song(_ style: Font.TextStyle, emphasis: Bool = false) -> Font {
        let points: CGFloat
        switch style {
        case .largeTitle: points = 34
        case .title: points = 28
        case .title2: points = 22
        case .title3: points = 20
        case .headline, .body: points = 17
        case .callout: points = 16
        case .subheadline: points = 15
        case .footnote: points = 13
        case .caption: points = 12
        case .caption2: points = 11
        @unknown default: points = 17
        }
        return .custom(emphasis ? V5Typeface.emphasizedName : V5Typeface.regularName, size: points, relativeTo: style)
    }
    static func printFont(size: CGFloat, emphasis: Bool = false) -> Font { .custom(emphasis ? V5Typeface.emphasizedName : V5Typeface.regularName, fixedSize: size) }
    static let page = song(.largeTitle, emphasis: true)
    static let section = song(.title2, emphasis: true)
    static let title = song(.headline, emphasis: true)
    static let body = Font.body
    static let detail = Font.subheadline
    static let evidence = Font.footnote
    static let numeric = Font.body.monospacedDigit()
}
enum V5Motion {
    static let press = Animation.easeOut(duration: 0.18)
    @MainActor static func selectionFeedback() { UISelectionFeedbackGenerator().selectionChanged() }
}
struct V5Card<Content: View>: View {
    @Environment(\.colorSchemeContrast) private var contrast
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.padding(V5Metric.page)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { V5Surface() }
    }
}
struct V5PrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        let theme = V5ThemeStore.shared.theme
        let p = theme.palette
        let background = enabled ? (theme == .night ? p.heroSurface : p.accent) : p.surface
        let foreground = enabled ? (theme == .night ? p.ornamentText : (theme == .collection ? p.heroSurface : p.paper)) : p.secondary
        configuration.label.font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20).padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(V5Palette.color(foreground))
            .background(V5Palette.color(background), in: Capsule())
            .overlay(Capsule().stroke(V5Palette.color(p.ornament), lineWidth: 0.8).allowsHitTesting(false))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : V5Motion.press, value: configuration.isPressed)
    }
}
struct V5SectionHeading: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(V5Typography.section).accessibilityAddTraits(.isHeader)
            if let subtitle { Text(subtitle).font(V5Typography.detail).foregroundStyle(V5Palette.color(V5Palette.current.secondary)) }
        }.foregroundStyle(V5Palette.color(V5Palette.current.ink))
    }
}
struct V5StatusPanel: View {
    enum State { case loading, empty, success, failure }
    let state: State
    let title: String
    let message: String
    var retry: (() -> Void)? = nil
    private var symbol: String {
        switch state { case .loading: return "hourglass"; case .empty: return "tray"; case .success: return "checkmark.circle"; case .failure: return "exclamationmark.circle" }
    }
    var body: some View {
        V5Card {
            VStack(alignment: .leading, spacing: V5Metric.gap) {
                if case .loading = state { ProgressView().accessibilityLabel(title) }
                Label(title, systemImage: symbol).font(V5Typography.title)
                Text(message).font(V5Typography.body).fixedSize(horizontal: false, vertical: true)
                if let retry { Button("重试", action: retry).buttonStyle(V5PrimaryButton()) }
            }
        }
        .foregroundStyle(V5Palette.color(V5Palette.current.ink))
        .accessibilityElement(children: .contain)
    }
}
