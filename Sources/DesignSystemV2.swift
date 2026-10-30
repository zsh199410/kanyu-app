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
