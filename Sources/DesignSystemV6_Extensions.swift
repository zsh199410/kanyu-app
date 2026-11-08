//
//  DesignSystemV6_Extensions.swift
//  Kanyu (UI 2.0)
//
//  《三术合参 UI 2.0》设计系统 V6 扩展规范（基线：build-128）
//  视觉方向：A（宋纸青黛为主 #F6F1E6 · 暗夜玄金为辅 #111317）
//  核心职责：在不破坏现有 DesignSystemV2 (v5) 任何语义色值与组件签名的前提下，
//  增量提供 UI 2.0 所需的 12 个前沿标准组件与 Apple 2026 Spatial Bento 排版规范。
//

import SwiftUI
import UIKit

// MARK: - 1. DesignSystemV6 尺寸与排版令牌 (Layout & Typography Tokens)

enum KyV6 {
    static let pageHorizontalMargin: CGFloat = 20
    static let cardCornerSmall: CGFloat = 12
    static let sectionSpacing: CGFloat = 15
    static let minTapTarget: CGFloat = 44

    /// 触感引擎（模拟机械罗盘微阻尼刻度感；与仓内内联写法同款，在调用线程执行，首击无 prepare 可能偏弱）
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        let gen = UIImpactFeedbackGenerator(style: style)
        gen.impactOccurred()
    }
}

// MARK: - 2. 首页 01 层：品牌导航与全局个人中心入口 (KyProfileHeader)

struct KyProfileHeader: View {
    let subtitle: String
    let activePersonName: String
    let onTapProfile: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AppLogoView(size: 40)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("浑天定盘 · 三术合参".scriptConverted)
                        .font(.system(size: 17, weight: .bold, design: .serif))
                        .foregroundStyle(Ky.ink)
                }
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Ky.sub)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            // 全局个人中心入口（恢复 MyView 可达性，保证 44x44pt 最小点击区域）
            Button {
                KyV6.impact(.light)
                onTapProfile()
            } label: {
                ZStack {
                    Circle()
                        .fill(Ky.card)
                        .frame(width: 40, height: 40)
                        .overlay(Circle().stroke(Ky.gold.opacity(0.45), lineWidth: 1))
                    if activePersonName.isEmpty {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Ky.qingdai)
                    } else {
                        Text(String(activePersonName.prefix(1)))
                            .font(.system(size: 15, weight: .bold, design: .serif))
                            .foregroundStyle(Ky.qingdai)
                    }
                }
                .frame(width: KyV6.minTapTarget, height: KyV6.minTapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("个人中心与全局设置")
        }
    }
}

// MARK: - 3. 首页 02 层：当前命主智能中枢卡 (KyPersonSwitcher)

struct KyPersonSwitcher: View {
    let person: Person?
    let baziSummary: String
    let dayMasterElement: String // 木/火/土/金/水
    let onSwitchPerson: () -> Void
    let onNewPerson: () -> Void
    let onOpenDetail: () -> Void

    // 日主五行色复用 KyV2.wuxingColors（土赭金／金苍金分色），不自立映射
    private var elementTint: Color {
        KyV2.color(forElement: dayMasterElement)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let p = person {
                HStack(alignment: .center, spacing: 12) {
                    // 命主五行徽章头像
                    Button(action: onOpenDetail) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(elementTint.opacity(0.14))
                                .frame(width: 50, height: 50)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(elementTint.opacity(0.45), lineWidth: 1)
                                )
                            Text(String(p.name.prefix(1)))
                                .font(.system(size: 21, weight: .bold, design: .serif))
                                .foregroundStyle(elementTint)
                        }
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(p.name)
                                .font(.system(size: 18, weight: .bold, design: .serif))
                                .foregroundStyle(Ky.ink)
                            if !p.relation.isEmpty {
                                KyBadge(text: p.relation, color: Ky.qingdai)
                            }
                            if p.gender == "M" {
                                KyBadge(text: "乾造", color: Ky.gold)
                            } else if p.gender == "F" {
                                KyBadge(text: "坤造", color: Ky.gold)
                            }
                            if !dayMasterElement.isEmpty {
                                KyBadge(text: "日主" + dayMasterElement, color: elementTint)
                            }
                        }
                        Text(baziSummary.scriptConverted)
                            .font(KyV2.tabular(12.5, weight: .medium))
                            .foregroundStyle(Ky.sub)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    // 切换命主与新建按钮
                    HStack(spacing: 6) {
                        Button {
                            KyV6.impact(.light)
                            onSwitchPerson()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.left.arrow.right")
                                Text("切换".scriptConverted)
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Ky.qingdai)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .frame(minHeight: KyV6.minTapTarget)
                            .background(Ky.elevated)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        Button {
                            KyV6.impact(.light)
                            onNewPerson()
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Ky.ink)
                                .frame(width: KyV6.minTapTarget, height: KyV6.minTapTarget)
                                .background(Ky.elevated)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("快速新建档案")
                    }
                }
            } else {
                // 空档案引导态
                HStack(spacing: 12) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 24))
                        .foregroundStyle(Ky.qingdai)
                        .frame(width: 48, height: 48)
                        .background(Ky.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("尚未建立命主档案")
                            .font(.system(size: 16, weight: .bold, design: .serif))
                            .foregroundStyle(Ky.ink)
                        Text("建档后，八字、紫微、合参及个人择吉将自动联动".scriptConverted)
                            .font(.system(size: 12))
                            .foregroundStyle(Ky.sub)
                    }
                    Spacer()
                    Button(action: onNewPerson) { Text("立即建档".scriptConverted) }
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Ky.qingdai)
                        .clipShape(Capsule())
                        .buttonStyle(.plain)
                }
            }
        }
        .kyCard()
    }
}

// MARK: - 4. 通用分组容器与指标卡片 (KyHomeSection & KyMetricCard)

struct KyHomeSection<Content: View>: View {
    let title: String
    let trailing: String
    var onTrailingTap: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: KyV6.sectionSpacing) {
            HStack(alignment: .firstTextBaseline) {
                KySectionTitle(title: title, trailing: onTrailingTap == nil ? trailing : "")
                if let action = onTrailingTap, !trailing.isEmpty {
                    Button(action: action) {
                        HStack(spacing: 3) {
                            Text(trailing)
                            Image(systemName: "chevron.right")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Ky.qingdai)
                    }
                    .buttonStyle(.plain)
                }
            }
            content()
        }
    }
}

struct KyMetricCard: View {
    let label: String
    let value: String
    var badgeText: String = ""
    var tint: Color = Ky.qingdai

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Ky.sub)
                Spacer()
                if !badgeText.isEmpty {
                    KyBadge(text: badgeText, color: tint)
                }
            }
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .serif))
                .foregroundStyle(Ky.ink)
                .lineLimit(1)
        }
        .kySubCard()
    }
}

// MARK: - 5. 横向岁运时间轴与双编码图例 (KyTimeline & KyChartLegend)

struct KyTimelineItem: Identifiable {
    let id: String
    let topText: String     // 年份，如 "2020"（严禁千分位逗号）
    let mainText: String    // 干支，如 "壬申"
    let subText: String     // 十神或大限宫名，如 "七杀"
    let isCurrent: Bool
    let isFavorable: Bool?  // true: 喜, false: 忌, nil: 平
}

struct KyTimeline: View {
    let items: [KyTimelineItem]
    @Binding var selectedID: String
    var onSelect: ((KyTimelineItem) -> Void)? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    let isSel = item.id == selectedID
                    Button {
                        KyV6.impact(.light)
                        selectedID = item.id
                        onSelect?(item)
                    } label: {
                        VStack(spacing: 4) {
                            HStack(spacing: 3) {
                                Text(item.topText)
                                    .font(KyV2.tabular(11, weight: .medium))
                                    .foregroundStyle(isSel ? .white.opacity(0.9) : Ky.sub)
                                if item.isCurrent {
                                    Text("当运".scriptConverted)
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(isSel ? Color.white.opacity(0.25) : Ky.cinnabar.opacity(0.15))
                                        .foregroundStyle(isSel ? .white : Ky.cinnabar)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                            }
                            Text(item.mainText)
                                .font(.system(size: 17, weight: .bold, design: .serif))
                                .foregroundStyle(isSel ? .white : Ky.ink)
                            HStack(spacing: 3) {
                                Text(item.subText)
                                    .font(.system(size: 11))
                                    .foregroundStyle(isSel ? .white.opacity(0.9) : Ky.sub)
                                if let fav = item.isFavorable {
                                    Text(fav ? "✓" : "×")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(isSel ? .white : (fav ? Ky.cinnabar : Ky.sub))
                                }
                            }
                        }
                        .frame(width: 72, height: 68)
                        .background(isSel ? Ky.qingdai : Ky.card)
                        .clipShape(RoundedRectangle(cornerRadius: KyV6.cardCornerSmall, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: KyV6.cardCornerSmall, style: .continuous)
                                .stroke(item.isCurrent && !isSel ? Ky.cinnabar.opacity(0.6) : Ky.line, lineWidth: item.isCurrent ? 1.2 : 0.7)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

struct KyChartLegend: View {
    let items: [(symbol: String, name: String, color: Color, valueText: String)]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(items.indices, id: \.self) { idx in
                    let it = items[idx]
                    HStack(spacing: 4) {
                        Circle()
                            .fill(it.color)
                            .frame(width: 7, height: 7)
                        Text("\(it.symbol)\(it.name)")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Ky.ink)
                        if !it.valueText.isEmpty {
                            Text(it.valueText)
                                .font(KyV2.tabular(11, weight: .semibold))
                                .foregroundStyle(Ky.sub)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 6. 搜索栏、过滤胶囊、空状态、加载态与设置行

struct KySearchBar: View {
    @Binding var text: String
    var placeholder: String = "搜索命例、古籍条文或专项工具…"
    var onSubmit: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Ky.sub)
            TextField(placeholder, text: $text)
                .font(.system(size: 14))
                .foregroundStyle(Ky.ink)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .onSubmit { onSubmit?() }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Ky.sub)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(Ky.elevated)
        .clipShape(RoundedRectangle(cornerRadius: KyV6.cardCornerSmall, style: .continuous))
    }
}

struct KyFilterBar: View {
    let options: [(title: String, count: Int?)]
    @Binding var selectedIndex: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options.indices, id: \.self) { idx in
                    let active = selectedIndex == idx
                    let item = options[idx]
                    Button {
                        KyV6.impact(.light)
                        withAnimation(.easeInOut(duration: 0.16)) {
                            selectedIndex = idx
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(item.title)
                            if let c = item.count {
                                Text("\(c)")
                                    .font(KyV2.tabular(11, weight: .bold))
                                    .opacity(0.85)
                            }
                        }
                        .font(.system(size: 12.5, weight: active ? .bold : .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .frame(minHeight: KyV6.minTapTarget)
                        .background(active ? Ky.qingdai : Ky.elevated)
                        .foregroundStyle(active ? Color.white : Ky.ink)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct KyEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Ky.gold)
                .padding(.bottom, 2)
            Text(title.scriptConverted)
                .font(.system(size: 15, weight: .bold, design: .serif))
                .foregroundStyle(Ky.ink)
            Text(message.scriptConverted)
                .font(.system(size: 12.5))
                .foregroundStyle(Ky.sub)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            if let btn = actionTitle, let act = action {
                Button(action: act) { Text(btn.scriptConverted) }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Ky.qingdai)
                    .clipShape(Capsule())
                    .buttonStyle(.plain)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .kyCard()
    }
}

struct KyLoadingState: View {
    var title: String = "正在推演盘面与核对典籍…"

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(Ky.qingdai)
            Text(title.scriptConverted)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Ky.sub)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .kyCard()
    }
}

struct KySettingsRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color
    var trailingText: String = ""
    var onTap: (() -> Void)? = nil

    var body: some View {
        settingsRowContent
    }

    @ViewBuilder
    private var settingsRowContent: some View {
        if let tap = onTap {
            Button(action: tap) {
                rowBody
            }
            .buttonStyle(.plain)
        } else {
            rowBody
        }
    }

    private var rowBody: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.13))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title.scriptConverted)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Ky.ink)
                if !subtitle.isEmpty {
                    Text(subtitle.scriptConverted)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Ky.sub)
                        .lineLimit(1)
                }
            }

            Spacer()

            if !trailingText.isEmpty {
                Text(trailingText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Ky.sub)
            }
            if onTap != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Ky.sub)
            }
        }
        .frame(minHeight: KyV6.minTapTarget)
        .contentShape(Rectangle())
    }
}

// MARK: - 7. 底部抽屉（KyBottomSheet，第 12 个组件）

/// 底部抽屉：复用 BaziModule.swift:1207 的 .sheet＋.presentationDetents([.medium, .large]) 模式。
/// 用法：在调用方以 .sheet(isPresented:) 弹出 KyBottomSheet(title:) { 词条内容 }，
/// 或用 .kyBottomSheet(isPresented:title:) 修饰符。支撑「点击干支／十神弹词条释义」与 P1 详批抽屉；
/// 不新增 fullScreenCover，不加动态阴影。
struct KyBottomSheet<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                content()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            .background(Ky.bg)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }.foregroundStyle(Ky.qingdai)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

extension View {
    /// 以底部抽屉弹出任意内容（与 KyBottomSheet 同款 detents）。
    func kyBottomSheet<SheetContent: View>(isPresented: Binding<Bool>, title: String, @ViewBuilder content: @escaping () -> SheetContent) -> some View {
        self.sheet(isPresented: isPresented) {
            KyBottomSheet(title: title, content: content)
        }
    }
}