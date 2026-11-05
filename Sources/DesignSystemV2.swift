// 设计系统 v5（2026-11-05 UI/UX 全面升级版：对齐《模板规范-2026-10-29.md》「宋纸·青黛」与夜间「暗夜玄金」）
// 铁律：盘面永远是不透明的宋纸；玻璃只许出现在浮动控制层（导航/时间胶囊），且只用 regular；
// 颜色永不单独编码（干支五行色必配文字或属性小标）；数字一律等宽对齐；朱砂点缀全屏克制使用。
import SwiftUI
import LunarSwift

enum KyV2 {
    // 五行色（双编码：降饱和宋韵五色＋文字标签并行，正文对比 ≥4.5:1）
    static let wuxingNames = ["木", "火", "土", "金", "水"]
    static var wuxingColors: [Color] = [
        .kyDyn(0x4E7A51, 0x68A86C),  // 木：松石翠 / 竹青
        .kyDyn(0xB54932, 0xE06D53),  // 火：朱砂丹 / 暖绯
        .kyDyn(0x9A6E4B, 0xC89B73),  // 土：赭石暖棕
        .kyDyn(0x8C733E, 0xD4B46A),  // 金：古铜苍金
        .kyDyn(0x2F5C78, 0x6497B8),  // 水：青黛深蓝
    ]

    static func tabular(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }

    /// 干支单字对应的五行名称（木/火/土/金/水）
    static func element(ofChar ch: Character) -> String {
        switch ch {
        case "甲", "乙", "寅", "卯": return "木"
        case "丙", "丁", "巳", "午": return "火"
        case "戊", "己", "辰", "戌", "丑", "未": return "土"
        case "庚", "辛", "申", "酉": return "金"
        case "壬", "癸", "亥", "子": return "水"
        default: return ""
        }
    }

    /// 五行名称对应的索引
    static func elementIndex(_ el: String) -> Int? {
        wuxingNames.firstIndex(of: el)
    }

    /// 五行名称对应的主题色
    static func color(forElement el: String) -> Color {
        if let idx = elementIndex(el) { return wuxingColors[idx] }
        return Ky.ink
    }

    /// 干支单字对应的五行语义色
    static func color(forChar ch: Character) -> Color {
        color(forElement: element(ofChar: ch))
    }

    /// 干支单字对应的浅底色（用于柱卡或标签底纹）
    static func bgTint(forChar ch: Character) -> Color {
        color(forChar: ch).opacity(0.11)
    }

    /// 十神简称（用于紧凑盘面标签）
    static func shiShenShort(_ ss: String) -> String {
        switch ss {
        case "比肩": return "比"
        case "劫财": return "劫"
        case "食神": return "食"
        case "伤官": return "伤"
        case "偏财": return "才"
        case "正财": return "财"
        case "七杀": return "杀"
        case "正官": return "官"
        case "偏印": return "枭"
        case "正印": return "印"
        case "日主": return "日主"
        default: return ss
        }
    }
}

// 通用语义胶囊标签
struct KyBadge: View {
    let text: String
    var color: Color = Ky.qingdai
    var filled: Bool = false
    var body: some View {
        Text(text)
            .font(.caption2).fontWeight(.semibold)
            .padding(.horizontal, 8).padding(.vertical, 3.5)
            .background(filled ? color : color.opacity(0.13))
            .foregroundStyle(filled ? Color.white : color)
            .clipShape(Capsule())
    }
}

// 五行横条（禁饼图：横条＋等宽数字＋气势强弱定性标签＋来源计法注脚）
struct WuxingBarsView: View {
    let percents: [Double]  // 木火土金水，合计 100
    private func stateLabel(_ p: Double) -> (String, Color) {
        if p >= 32 { return ("偏旺", Ky.cinnabar) }
        if p >= 22 { return ("得势", Ky.qingdai) }
        if p >= 12 { return ("中和", Ky.jade) }
        if p >= 3  { return ("偏弱", Ky.gold) }
        return ("缺显", Ky.sub)
    }
    var body: some View {
        VStack(spacing: 9) {
            ForEach(0..<min(KyV2.wuxingNames.count, percents.count), id: \.self) { i in
                let p = percents[i]
                let st = stateLabel(p)
                HStack(spacing: 10) {
                    Text(KyV2.wuxingNames[i])
                        .font(.system(size: 13, weight: .bold, design: .serif))
                        .foregroundStyle(KyV2.wuxingColors[i])
                        .frame(width: 24, height: 24)
                        .background(KyV2.wuxingColors[i].opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 5).fill(Ky.line.opacity(0.45))
                            RoundedRectangle(cornerRadius: 5)
                                .fill(
                                    LinearGradient(
                                        colors: [KyV2.wuxingColors[i].opacity(0.85), KyV2.wuxingColors[i]],
                                        startPoint: .leading, endPoint: .trailing
                                    )
                                )
                                .frame(width: max(4, geo.size.width * CGFloat(min(max(p, 0), 100)) / 100))
                        }
                    }.frame(height: 10)
                    Text(String(format: "%.0f%%", p))
                        .font(KyV2.tabular(13, weight: .semibold)).foregroundStyle(Ky.ink)
                        .frame(width: 38, alignment: .trailing)
                    Text(st.0)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(st.1)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(st.1.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
        }
    }
}

// 五级时间胶囊（学文墨天机底部时间转盘的单手逻辑，形态按 v5：青黛主色高对比切换）
struct TimeCapsuleBar: View {
    let levels: [String]
    let enabled: [Bool]
    @Binding var selection: Int
    var body: some View {
        HStack(spacing: 4) {
            ForEach(levels.indices, id: \.self) { i in
                let isEnabled = enabled.indices.contains(i) && enabled[i]
                let isSelected = selection == i
                Button {
                    if isEnabled {
                        withAnimation(.easeInOut(duration: 0.18)) { selection = i }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(levels[i])
                            .font(.caption)
                            .fontWeight(isSelected ? .bold : .medium)
                        if !isEnabled {
                            Text("待开").font(.system(size: 8)).foregroundStyle(Ky.sub)
                        }
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(isSelected ? Ky.qingdai : Color.clear)
                    .foregroundStyle(isSelected ? Color.white : (isEnabled ? Ky.ink : Ky.sub.opacity(0.6)))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
            }
        }
        .padding(4)
        .background(Ky.elevated)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Ky.line.opacity(0.8), lineWidth: 0.7))
    }
}

// 依据链组件 v5（白话结论高可读行距 ＋ 浅染底色盒装「盘面事实 / 典籍根据」三段式）
struct EvidenceChainView: View {
    let conclusion: String
    let links: [(label: String, text: String)]  // 自上而下：盘面/法则/根据
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(conclusion)
                .font(.system(size: 15.5, weight: .regular))
                .foregroundStyle(Ky.ink)
                .lineSpacing(4.5)
                .fixedSize(horizontal: false, vertical: true)
            if !links.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(links.indices, id: \.self) { i in
                        HStack(alignment: .top, spacing: 8) {
                            Text(links[i].label)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(links[i].label == "盘面" ? Ky.qingdai : Ky.gold)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background((links[i].label == "盘面" ? Ky.qingdai : Ky.gold).opacity(0.13))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            Text(links[i].text)
                                .font(.caption)
                                .foregroundStyle(Ky.sub)
                                .lineSpacing(2.5)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Ky.elevated.opacity(0.75))
                .clipShape(RoundedRectangle(cornerRadius: 9))
            }
        }
    }
}

// MARK: - 宋式章节眉题（左青黛竖线＋衬线标题＋金发丝线＋右小注）
struct KySectionTitle: View {
    let title: String
    var trailing: String = ""
    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Ky.qingdai)
                .frame(width: 3.5, height: 16)
            Text(title)
                .font(.system(.headline, design: .serif))
                .fontWeight(.bold)
                .foregroundStyle(Ky.ink)
            Rectangle()
                .fill(Ky.line)
                .frame(height: 0.8)
            if !trailing.isEmpty {
                Text(trailing)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(Ky.sub)
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
            .background(Ky.cinnabar.opacity(0.06))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Ky.cinnabar, lineWidth: 1.3))
            .rotationEffect(.degrees(-3))
    }
}

extension View {
    /// v5 标准宋纸卡：宣纸暖白卡面＋发丝描边＋柔和温润投影（内容层，永不玻璃）
    func kyCard() -> some View {
        self.padding(16)
            .background(Ky.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Ky.line.opacity(0.85), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.035), radius: 7, y: 3)
    }

    /// 浅染内嵌卡（用于卡片内部二级区块）
    func kySubCard() -> some View {
        self.padding(11)
            .background(Ky.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Ky.line.opacity(0.6), lineWidth: 0.6))
    }
}

// MARK: - 排盘口径设置（对标文墨天机的安星参数页：口径成套可调，默认值＝现行金标准口径）
enum AppSettings {
    static var baziSect: Int { let v = UserDefaults.standard.integer(forKey: "baziSect"); return v == 1 ? 1 : 2 }
    static var ziweiLeapNext: Bool { UserDefaults.standard.object(forKey: "ziweiLeapNext") as? Bool ?? true }
    static var ziweiLateZiNext: Bool { UserDefaults.standard.bool(forKey: "ziweiLateZiNext") }
}

struct CaliberSettingsView: View {
    @AppStorage("signDateEpoch") private var signDateEpoch: Double = 0
    @AppStorage("signCertDays") private var signCertDays: Int = 365
    @AppStorage("baziSect") private var baziSect = 2
    @AppStorage("ziweiLeapNext") private var ziweiLeapNext = true
    @AppStorage("ziweiLateZiNext") private var ziweiLateZiNext = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    KySectionTitle(title: "八字口径", trailing: "子平正统")
                    Picker("晚子时归日", selection: $baziSect) {
                        Text("23 点后算次日（sect=1）").tag(1)
                        Text("23 点后算当日（sect=2）").tag(2)
                    }.pickerStyle(.segmented)
                    Text("现行金标准盘以 sect=2（23:00 后日柱不换、时干按次日五鼠遁推）对拍验证；改口径后盘面随之变化，属预期。")
                        .font(.caption).foregroundStyle(Ky.sub)
                }.kyCard()

                VStack(alignment: .leading, spacing: 10) {
                    KySectionTitle(title: "紫微口径", trailing: "天纪三合派")
                    Toggle("闰月整月归下月", isOn: $ziweiLeapNext)
                        .tint(Ky.qingdai)
                    Toggle("晚子时作次日", isOn: $ziweiLateZiNext)
                        .tint(Ky.qingdai)
                    Text("默认：闰月归下月、晚子时作当日，与紫微金标准盘（iztro 同源参照）一致。")
                        .font(.caption).foregroundStyle(Ky.sub)
                }.kyCard()

                VStack(alignment: .leading, spacing: 10) {
                    KySectionTitle(title: "签名信息", trailing: "侧载证书提醒")
                    DatePicker("签名日期", selection: Binding(
                        get: { signDateEpoch > 0 ? Date(timeIntervalSince1970: signDateEpoch) : Date() },
                        set: { signDateEpoch = $0.timeIntervalSince1970 }), displayedComponents: .date)
                    Picker("证书类型", selection: $signCertDays) {
                        Text("免费证书（7 天）").tag(7)
                        Text("付费证书（1 年）").tag(365)
                    }.pickerStyle(.segmented)
                    if signDateEpoch > 0 {
                        let expiry = Date(timeIntervalSince1970: signDateEpoch).addingTimeInterval(Double(signCertDays) * 86400)
                        let remain = Calendar.current.dateComponents([.day], from: Date(), to: expiry).day ?? 0
                        Text("到期日 \(expiry.formatted(date: .abbreviated, time: .omitted))，还剩 \(remain) 天。到期前 7 天起首页会亮提醒：到期后 App 打不开是证书问题、不是数据问题，续签覆盖安装即可，数据不丢。")
                            .font(.caption).foregroundStyle(remain <= 7 ? Ky.cinnabar : Ky.sub)
                    } else {
                        Text("装好 App 后在这里记下签名日期，临近到期首页会提醒续签。")
                            .font(.caption).foregroundStyle(Ky.sub)
                    }
                }.kyCard()

                VStack(alignment: .leading, spacing: 10) {
                    KySectionTitle(title: "紫微亮度表", trailing: "58星×12宫")
                    Text("现行：《斗数全书》派亮度（58 星×12 宫全量）。中州派亮度表数据源未核实，不编造，缺位标注在此——宁缺毋假。")
                        .font(.caption).foregroundStyle(Ky.sub)
                }.kyCard()
            }.padding(16)
        }
        .background(Ky.bg)
        .navigationTitle("排盘口径设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}
