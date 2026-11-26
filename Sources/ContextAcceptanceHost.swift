import SwiftUI
import UIKit

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
    private var environmentReceipt: String {
        "QA环境 \(scheme == .dark ? "dark" : "light") \(sizeName)"
    }
    var body: some View {
        VStack(spacing: 0) {
            NativeContextEnvironmentReceipt(swiftUIReceipt: environmentReceipt)
                .fixedSize()
            Text(clockReceipt)
                .font(.system(size: 1)).fixedSize()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(clockReceipt)
                .accessibilityIdentifier("qa.context.clock")
        }
        // Keep real intrinsic glyph bounds: a clipped 1x1 Text has no stable
        // rendered label for AX snapshots at accessibility Dynamic Type sizes.
        .opacity(0.02).allowsHitTesting(false)
        .onAppear { NSLog("[ContextReceipt] %@ | %@", environmentReceipt, clockReceipt) }
        .onChange(of: environmentReceipt) { _, label in
            NSLog("[ContextReceipt] environment changed: %@", label)
        }
    }
}
/// Read the traits of the attached receipt view, not a preferred scheme from a
/// different SwiftUI modifier scope. Never substitute the requested test case.
private struct NativeContextEnvironmentReceipt: UIViewRepresentable {
    let swiftUIReceipt: String
    func makeUIView(context: Context) -> ContextEnvironmentLabel { ContextEnvironmentLabel() }
    func updateUIView(_ view: ContextEnvironmentLabel, context: Context) {
        view.swiftUIReceipt = swiftUIReceipt
        view.refreshReceipt()
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ContextEnvironmentLabel,
                     context: Context) -> CGSize? { uiView.intrinsicContentSize }
}

private final class ContextEnvironmentLabel: UILabel {
    var swiftUIReceipt = ""
    override init(frame: CGRect) {
        super.init(frame: frame)
        font = .systemFont(ofSize: 1)
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        accessibilityIdentifier = "qa.context.environment"
        refreshReceipt()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        refreshReceipt()
    }
    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        refreshReceipt()
    }
    func refreshReceipt() {
        let category = traitCollection.preferredContentSizeCategory
        let size = category == .large ? "large"
            : category == .accessibilityExtraExtraExtraLarge ? "accessibility5" : "other"
        let scheme = traitCollection.userInterfaceStyle == .dark ? "dark" : "light"
        let receipt = "QA环境 \(scheme) \(size)"
        text = receipt
        accessibilityLabel = receipt
        guard window != nil else { return }
        let values: [String: String] = ["label": receipt, "swiftUIReceipt": swiftUIReceipt,
            "contentSizeCategory": category.rawValue,
            "interfaceStyle": String(traitCollection.userInterfaceStyle.rawValue)]
        if let data = try? JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: FileManager.default.temporaryDirectory
                .appendingPathComponent("context-environment-receipt.json"), options: .atomic)
        }
        NSLog("[ContextReceipt UIKit] %@ | SwiftUI=%@", receipt, swiftUIReceipt)
    }
}

#endif
