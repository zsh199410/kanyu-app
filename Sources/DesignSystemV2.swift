// 设计系统 v2（2026-10-30 UI 对标调研定版，规范全文见 UI-DESIGN.md v2 节）
// 铁律：盘面永远是不透明的纸；玻璃只许出现在浮动控制层（导航/时间胶囊），且只用 regular；
// 颜色永不单独编码（五行色必配文字）；数字一律等宽对齐；朱砂点缀全屏 ≤3 处。
import SwiftUI

enum KyV2 {
    // 五行色（双编码：色＋文字标签并行，正文对比 ≥4.5:1 取深值）
    static let wuxingNames = ["木", "火", "土", "金", "水"]
    static var wuxingColors: [Color] = [
        .kyDyn(0x2E7D4F, 0x4CAF7D),  // 木
        .kyDyn(0xB33727, 0xD95F43),  // 火
        .kyDyn(0x96690F, 0xC9973F),  // 土
        .kyDyn(0xA87F14, 0xC9A227),  // 金
        .kyDyn(0x2E5F8A, 0x5B8DB8),  // 水
    ]
    static func tabular(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }
}

// 五行横条（禁饼图：角度误读；横条＋等宽数字＋来源计法注脚）
struct WuxingBarsView: View {
    let percents: [Double]  // 木火土金水，合计 100
    var body: some View {
        VStack(spacing: 7) {
            ForEach(KyV2.wuxingNames.indices, id: \.self) { i in
                HStack(spacing: 8) {
                    Text(KyV2.wuxingNames[i])
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(KyV2.wuxingColors[i])
                        .frame(width: 16)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4).fill(Ky.line.opacity(0.5))
                            RoundedRectangle(cornerRadius: 4)
                                .fill(KyV2.wuxingColors[i])
                                .frame(width: max(3, geo.size.width * CGFloat(percents[i]) / 100))
                        }
                    }.frame(height: 10)
                    Text(String(format: "%.0f%%", percents[i]))
                        .font(KyV2.tabular(12)).foregroundStyle(Ky.ink)
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
    }
}

// 五级时间胶囊（学文墨天机底部时间转盘的单手逻辑，形态按 v2：唯一时间切换组件）
// 未开放级别灰置并标注阶段，不假装可用。
struct TimeCapsuleBar: View {
    let levels: [String]
    let enabled: [Bool]
    @Binding var selection: Int
    var body: some View {
        HStack(spacing: 2) {
            ForEach(levels.indices, id: \.self) { i in
                Button { if enabled[i] { selection = i } } label: {
                    HStack(spacing: 3) {
                        Text(levels[i]).font(.caption).fontWeight(selection == i ? .semibold : .regular)
                        if !enabled[i] {
                            Text("P2").font(.system(size: 8)).foregroundStyle(Ky.sub)
                        }
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 7)
                    .background(selection == i ? Ky.ink : Color.clear)
                    .foregroundStyle(selection == i ? Ky.bg : (enabled[i] ? Ky.ink : Ky.sub))
                    .clipShape(Capsule())
                }.buttonStyle(.plain).disabled(!enabled[i])
            }
        }
        .padding(3)
        .kyGlass(corner: 20)
    }
}

// 依据链组件（独门：结论 ← 规则 ← 盘面事实 ← 古籍原文；P2 断语层接入，先立形）
struct EvidenceChainView: View {
    let conclusion: String
    let links: [(label: String, text: String)]  // 自上而下：规则/盘面事实/原文
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "text.book.closed").foregroundStyle(Ky.cinnabar)
                Text(conclusion).font(.callout).fontWeight(.medium).foregroundStyle(Ky.ink)
            }
            ForEach(links.indices, id: \.self) { i in
                HStack(alignment: .top, spacing: 6) {
                    Text(links[i].label).font(.caption2).foregroundStyle(Ky.gold)
                        .frame(width: 34, alignment: .leading)
                    Text(links[i].text).font(.caption).foregroundStyle(Ky.sub)
                }.padding(.leading, 22)
            }
        }
    }
}

// MARK: - 设计系统 v3（2026-10-30 UI 对标调研七准则落地）
// 准则：盘面是纸不是玻璃 / 密度双层可关 / 时间轴主交互 / 专注模式其余淡化 /
// 首页是工作台 / 朱砂每屏一处·印章只作落款判定 / 大字号方盘变文字盘。
struct KySectionTitle: View {
    let title: String
    var trailing: String = ""
    var body: some View {
        HStack(spacing: 10) {
            Text(title).font(.system(.headline, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
            Rectangle().fill(Ky.gold.opacity(0.55)).frame(height: 1)
            if !trailing.isEmpty {
                Text(trailing).font(.caption2).foregroundStyle(Ky.sub)
            }
        }
    }
}

/// 朱砂印章小记：只用于「落判/落款」语义（回验落判、报告落款），不作普通按钮
struct KySeal: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13, design: .serif)).fontWeight(.bold)
            .foregroundStyle(Ky.cinnabar)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Ky.cinnabar, lineWidth: 1.4))
            .rotationEffect(.degrees(-4))
    }
}

extension View {
    /// v3 标准卡：纸面＋发丝描边＋极浅投影（内容层，永不玻璃）
    func kyCard() -> some View {
        self.padding(16)
            .background(Ky.card)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Ky.line.opacity(0.7), lineWidth: 0.7))
            .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }
}

// MARK: - 排盘口径设置（对标文墨天机的安星参数页：口径成套可调，默认值＝现行金标准口径）
enum AppSettings {
    static var baziSect: Int { let v = UserDefaults.standard.integer(forKey: "baziSect"); return v == 1 ? 1 : 2 }
    static var ziweiLeapNext: Bool { UserDefaults.standard.object(forKey: "ziweiLeapNext") as? Bool ?? true }
    static var ziweiLateZiNext: Bool { UserDefaults.standard.bool(forKey: "ziweiLateZiNext") }
}

struct CaliberSettingsView: View {
    @AppStorage("baziSect") private var baziSect = 2
    @AppStorage("ziweiLeapNext") private var ziweiLeapNext = true
    @AppStorage("ziweiLateZiNext") private var ziweiLateZiNext = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    KySectionTitle(title: "八字口径")
                    Picker("晚子时归日", selection: $baziSect) {
                        Text("23 点后算次日（sect=1）").tag(1)
                        Text("23 点后算当日（sect=2）").tag(2)
                    }.pickerStyle(.segmented)
                    Text("现行金标准盘以 sect=2 对拍验证；改口径后盘面随之变化，属预期。").font(.caption2).foregroundStyle(Ky.sub)
                }.kyCard()
                VStack(alignment: .leading, spacing: 10) {
                    KySectionTitle(title: "紫微口径（天纪三合派）")
                    Toggle("闰月整月归下月", isOn: $ziweiLeapNext)
                    Toggle("晚子时作次日", isOn: $ziweiLateZiNext)
                    Text("默认：闰月归下月、晚子时作当日，与紫微金标准盘（iztro 同源参照）一致。").font(.caption2).foregroundStyle(Ky.sub)
                }.kyCard()
                VStack(alignment: .leading, spacing: 10) {
                    KySectionTitle(title: "紫微亮度表")
                    Text("现行：《斗数全书》派亮度（58 星×12 宫全量）。中州派亮度表数据源未核实，不编造，缺位标注在此——宁缺毋假。").font(.caption).foregroundStyle(Ky.sub)
                }.kyCard()
            }.padding(16)
        }
        .background(Ky.bg)
        .navigationTitle("排盘口径设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}
