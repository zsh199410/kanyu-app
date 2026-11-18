#if DEBUG
import SwiftUI

/// iOS-native visual acceptance gallery; not linked into production navigation.
struct KanyuV6ComponentGallery: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedState = 0
    @State private var detailsOpen = false

    private var theme: KanyuV6.Theme { .resolved(colorScheme) }
    private let states = ["默认", "加载中", "已成功", "出错", "不可操作"]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: KanyuV6.Metric.cardGap) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ORIENTAL PRECISION")
                            .font(.caption.monospaced().weight(.semibold))
                            .tracking(2)
                            .foregroundStyle(theme.ornament)
                        Text("宋纸 · 青黛 · 金石")
                            .font(KanyuV6.Typography.pageTitle)
                            .foregroundStyle(theme.foreground)
                        Text("仅预览原生视觉组件；示例数据不是测算结果。")
                            .font(.subheadline)
                            .foregroundStyle(theme.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    KanyuV6Card {
                        VStack(alignment: .leading, spacing: 10) {
                            sectionTitle("01 / 字级层级")
                            Text("八字命盘")
                                .font(KanyuV6.Typography.cardTitle)
                                .foregroundStyle(theme.foreground)
                            Text("先看结论，再看盘面事实和依据。")
                                .font(KanyuV6.Typography.body)
                                .foregroundStyle(theme.foreground)
                            Text("传统解盘不是已验证的现实预测。")
                                .font(KanyuV6.Typography.evidence)
                                .foregroundStyle(theme.secondary)
                            Text("2000-01-01 08:00 · 北京时间")
                                .font(KanyuV6.Typography.numeric)
                                .foregroundStyle(theme.foreground)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    KanyuV6Card {
                        VStack(alignment: .leading, spacing: 12) {
                            sectionTitle("02 / 按钮五态")
                            Picker("演示状态", selection: $selectedState) {
                                ForEach(states.indices, id: \.self) { index in
                                    Text(states[index]).tag(index)
                                }
                            }
                            .pickerStyle(.menu)
                            Button {
                                selectedState = selectedState == 3 ? 1 : 2
                            } label: {
                                Label(states[selectedState], systemImage: selectedState == 2 ? "checkmark.circle" : "arrow.right.circle")
                            }
                            .buttonStyle(KanyuV6PrimaryButton())
                            .disabled(selectedState == 4)
                            if selectedState == 1 {
                                ProgressView("示例处理中")
                            } else if selectedState == 3 {
                                Label("失败，可重试", systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(theme.foreground)
                            } else if selectedState == 2 {
                                Label("成功（本地状态演示）", systemImage: "checkmark.circle")
                                    .foregroundStyle(theme.foreground)
                            }
                        }
                    }

                    KanyuV6Card {
                        VStack(alignment: .leading, spacing: 10) {
                            sectionTitle("03 / 可信来源")
                            ForEach(["盘面事实：来自计算字段", "传统法则：注明流派和口径", "古籍相关：未核逐字不标原文", "个人回验：不代表准确率"], id: \.self) { item in
                                Label(item, systemImage: "seal")
                                    .font(.subheadline)
                                    .foregroundStyle(theme.foreground)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    KanyuV6Card {
                        VStack(alignment: .leading, spacing: 10) {
                            sectionTitle("04 / 无障碍")
                            Text(dynamicTypeSize.isAccessibilitySize ? "最大辅助字号：优先单列" : "标准字号：适应系统宽度")
                                .foregroundStyle(theme.foreground)
                            Text(reduceMotion ? "已尊重系统减少动态效果" : "使用系统动态效果设置")
                                .font(.footnote)
                                .foregroundStyle(theme.secondary)
                            Button("查看验收说明") { detailsOpen.toggle() }
                                .frame(minHeight: KanyuV6.Metric.minimumHitTarget)
                                .accessibilityIdentifier("gallery.accessibility.details")
                            if detailsOpen {
                                Text("核验读屏焦点、按钮热区、深浅色对比度与失败恢复。")
                                    .font(.subheadline)
                                    .foregroundStyle(theme.foreground)
                            }
                        }
                    }
                }
                .padding(KanyuV6.Metric.pageInset)
            }
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("V6 组件预览")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(theme.ornament)
    }
}

#Preview("宋纸浅色") {
    KanyuV6ComponentGallery().preferredColorScheme(.light)
}

#Preview("玄夜深色") {
    KanyuV6ComponentGallery().preferredColorScheme(.dark)
}
#endif
