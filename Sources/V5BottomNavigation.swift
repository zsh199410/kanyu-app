import SwiftUI
import UIKit

/// A visible native navigation control. The hidden system bar is replaced, not
/// duplicated for testing; real buttons retain tab semantics and selected state.
struct V5BottomNavigation: UIViewRepresentable {
    @Binding var selection: Int
    let theme: V5Theme
    func makeUIView(context: Context) -> V5BottomNavigationBar { V5BottomNavigationBar() }
    func updateUIView(_ view: V5BottomNavigationBar, context: Context) {
        view.update(selection: selection, theme: theme,
                    accessibilityLayout: context.environment.dynamicTypeSize.isAccessibilitySize) { selection = $0 }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: V5BottomNavigationBar, context: Context) -> CGSize? {
        // UITabBar's 60pt intrinsic size must not remain centered inside its
        // accessibility frame; the visible control fills its real slot.
        CGSize(width: proposal.width ?? uiView.bounds.width,
               height: proposal.height ?? (context.environment.dynamicTypeSize.isAccessibilitySize ? 80 : 60))
    }
}
final class V5BottomNavigationBar: UITabBar {
    private let titles = ["首页", "测算", "命书", "档案"]
    private let symbols = ["house", "safari", "book.closed", "person.crop.circle"]
    private let roles: [V5ArtworkRole] = [.navHome, .navMeasure, .navReports, .navProfiles]
    private var controls: [UIButton] = []
    private let separator = CALayer()
    private let selectionMark = CALayer()
    private var onSelect: ((Int) -> Void)?
    private var selectedIndex = 0
    override init(frame: CGRect) {
        super.init(frame: frame)
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear;appearance.shadowColor = .clear
        standardAppearance = appearance;scrollEdgeAppearance = appearance
        backgroundColor = .clear;isTranslucent = true;items = []
        isAccessibilityElement = false
        accessibilityLabel = "主要功能导航"
        for index in titles.indices {
            let button = UIButton(type: .system)
            button.accessibilityLabel = titles[index]
            button.accessibilityHint = "切换页面，保留当前命主"
            button.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                self.onSelect?(index)
            }, for: .touchUpInside)
            addSubview(button);controls.append(button)
        }
        // Explicit accessibility order describes the four actual visible controls.
        accessibilityElements = controls
        layer.addSublayer(separator);layer.addSublayer(selectionMark)
    }
    required init?(coder: NSCoder) { fatalError("Use programmatic navigation") }
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 60) }
    func update(selection: Int, theme: V5Theme, accessibilityLayout: Bool = false, onSelect: @escaping (Int) -> Void) {
        self.onSelect = onSelect;selectedIndex = selection
        let palette = theme.palette
        for (index, button) in controls.enumerated() {
            let selected = index == selection
            button.isSelected = selected
            button.accessibilityTraits = selected ? [.button, .selected] : [.button]
            var configuration = UIButton.Configuration.plain()
            configuration.title = titles[index]
            // At accessibility sizes retain the fully scaled, explicit title;
            // the redundant icon yields its space rather than clipping text.
            if accessibilityLayout {
                configuration.image = nil
            } else if let art = V5ArtworkRegistry.tabImage(roles[index]) {
                configuration.image = art.withRenderingMode(.alwaysOriginal)
            } else {
                configuration.image = UIImage(systemName: symbols[index], withConfiguration: UIImage.SymbolConfiguration(pointSize: 23, weight: .regular))
            }
            configuration.imagePlacement = .top;configuration.imagePadding = 3
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 2, bottom: 7, trailing: 2)
            configuration.baseForegroundColor = UIColor(V5Palette.color(selected ? palette.accent : palette.secondary))
            configuration.background.backgroundColor = .clear
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { original in
                var attributes = original
                attributes.font = UIFontMetrics(forTextStyle: .caption2).scaledFont(for: UIFont.systemFont(ofSize: 11, weight: selected ? .semibold : .regular))
                return attributes
            }
            button.configuration = configuration
            button.titleLabel?.adjustsFontForContentSizeCategory = true
        }
        separator.backgroundColor = UIColor(V5Palette.color(palette.ornament)).withAlphaComponent(0.25).cgColor
        selectionMark.backgroundColor = UIColor(V5Palette.color(palette.accent)).cgColor
        setNeedsLayout()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width / CGFloat(controls.count)
        for (index, button) in controls.enumerated() {
            button.frame = CGRect(x: CGFloat(index) * width, y: 0, width: width, height: bounds.height)
        }
        separator.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 0.5)
        selectionMark.frame = CGRect(x: CGFloat(selectedIndex) * width + (width - 18) / 2, y: 0, width: 18, height: 1.5)
    }
}
