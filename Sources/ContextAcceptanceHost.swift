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
    private var clockReceipt: String {
        let solar = BirthInputView.solarOf(Date(timeIntervalSince1970: 946684800))
        let date = BirthClockInput.calendar.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: 8, minute: 0))
        let epoch = date.map { String(Int($0.timeIntervalSince1970)) } ?? "invalid"
        return "QA时钟 \(solar.year)-\(solar.month)-\(solar.day) \(solar.hour):\(solar.minute)|\(epoch)|\(TimeZone.current.identifier)"
    }
    var body: some View {
        VStack(spacing: 0) {
            Text("QA环境 \(scheme == .dark ? "dark" : "light") \(sizeName)")
                .font(.system(size: 1)).frame(width: 1, height: 1).clipped()
                .accessibilityIdentifier("qa.context.environment")
            Text(clockReceipt)
                .font(.system(size: 1)).frame(width: 1, height: 1).clipped()
                .accessibilityIdentifier("qa.context.clock")
        }
        .opacity(0.02).allowsHitTesting(false)
    }
}
#endif
