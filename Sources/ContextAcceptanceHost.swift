import SwiftUI

/// A read-only environment receipt for the dedicated UI acceptance bundle.
/// No profile seeding, data reset, navigation shortcut or production launch mode.
struct ContextAcceptanceHost: ViewModifier {
    func body(content: Content) -> some View {
#if DEBUG
        if Bundle.main.bundleIdentifier == "com.kanyu.survey.contextqa",
           ProcessInfo.processInfo.arguments.contains("--context-acceptance") {
            content.overlay(alignment: .topLeading) {
                ContextAcceptanceReceipt()
            }
        } else {
            content
        }
#else
        content
#endif
    }
}

#if DEBUG
private struct ContextAcceptanceReceipt: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    private var sizeName: String {
        if typeSize == .accessibility5 { return "accessibility5" }
        if typeSize == .large { return "large" }
        return "other"
    }
    var body: some View {
        Text("QA环境 \(scheme == .dark ? "dark" : "light") \(sizeName)")
            .font(.system(size: 1))
            .frame(width: 1, height: 1).clipped().opacity(0.02)
            .allowsHitTesting(false)
            .accessibilityIdentifier("qa.context.environment")
    }
}
#endif
