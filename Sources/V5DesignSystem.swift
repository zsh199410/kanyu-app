import SwiftUI
import UIKit

/// All V5 interface components share these semantic primitives; artwork is not a substitute for content.
enum V5Typography {
    static let page = Font.system(.largeTitle, design: .serif).weight(.semibold)
    static let section = Font.system(.title2, design: .serif).weight(.semibold)
    static let title = Font.system(.headline, design: .serif)
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
            .background(V5Palette.color(V5Palette.current.surface), in: RoundedRectangle(cornerRadius: V5Metric.corner))
            .overlay {
                RoundedRectangle(cornerRadius: V5Metric.corner)
                    .stroke(V5Palette.color(contrast == .increased ? V5Palette.current.ink : V5Palette.current.ornament), lineWidth: contrast == .increased ? 1.4 : 0.7)
                    .allowsHitTesting(false)
            }
    }
}
struct V5PrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        let p = V5Palette.current
        configuration.label.font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20).padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(V5Palette.color(enabled ? p.paper : p.secondary))
            .background(V5Palette.color(enabled ? p.accent : p.surface), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(V5Palette.color(p.ornament), lineWidth: 0.7).allowsHitTesting(false))
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
