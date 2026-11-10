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
        Text(text.scriptConverted)
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
        // 一个 GeometryReader 量整组宽度（原先每行一个，共 5 次布局）；行高定死 24，容器高由行数算出；
        // 整组光栅化一次（.drawingGroup）：滑动只是位移，不触发重绘
        let rows = min(KyV2.wuxingNames.count, percents.count)
        return GeometryReader { geo in
            let trackW = max(40, geo.size.width - 128)  // 24 名称＋38 百分比＋36 标签＋3×10 间距
            VStack(spacing: 9) {
                ForEach(0..<rows, id: \.self) { i in
                    let p = percents[i]
                    let st = stateLabel(p)
                    HStack(spacing: 10) {
                        Text(KyV2.wuxingNames[i])
                            .font(.system(size: 13, weight: .bold, design: .serif))
                            .foregroundStyle(KyV2.wuxingColors[i])
                            .frame(width: 24, height: 24)
                            .background(KyV2.wuxingColors[i].opacity(0.14))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 5).fill(Ky.line.opacity(0.45))
                            RoundedRectangle(cornerRadius: 5)
                                .fill(
                                    LinearGradient(
                                        colors: [KyV2.wuxingColors[i].opacity(0.85), KyV2.wuxingColors[i]],
                                        startPoint: .leading, endPoint: .trailing
                                    )
                                )
                                .frame(width: max(4, trackW * CGFloat(min(max(p, 0), 100)) / 100))
                        }
                        .frame(width: trackW, height: 10)
                        Text(String(format: "%.0f%%", p))
                            .font(KyV2.tabular(13, weight: .semibold)).foregroundStyle(Ky.ink)
                            .frame(width: 38, alignment: .trailing)
                        Text(st.0.scriptConverted)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(st.1)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(st.1.opacity(0.12))
                            .clipShape(Capsule())
                            .frame(width: 36, alignment: .leading)
                    }
                }
            }
        }
        .frame(height: CGFloat(rows) * 24 + CGFloat(max(0, rows - 1)) * 9)
        .drawingGroup()
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
                        withAnimation(KyMotion.toggle) { selection = i }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(levels[i].scriptConverted)
                            .font(.caption)
                            .fontWeight(isSelected ? .bold : .medium)
                        if !isEnabled {
                            Text("待开".scriptConverted).font(.system(size: 8)).foregroundStyle(Ky.sub)
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
/// 依据链文本繁体转换：典籍原文照录句不转（P5 口径），其余走 .scriptConverted。
/// 黑名单只收已逐条核实的原文照录句——InterpretModule dimensions() 内两处
/// （《滴天髓》何知章「何知其人贵，官星有理会」、《素问》「肝开窍于目」）
/// ＋一处存疑按保守口径不接（财富量级蓄水池「财有库，发则能存」未在《三命通会》查到原文照录）。
/// 其余 86 条 links 均为生成式盘面事实／现代规则转述／通说，全可接。
private func evidenceLinkText(_ text: String) -> String {
    let verbatim = ["何知其人贵，官星有理会", "肝开窍于目", "财有库，发则能存"]
    if verbatim.contains(where: { text.contains($0) }) { return text }
    return text.scriptConverted
}

struct EvidenceChainView: View {
    let conclusion: String
    let links: [(label: String, text: String)]  // 自上而下：盘面/法则/根据
    // G2 六段结构字段（全部可选，有值才显示，无值不占位；confidence 由 G5 填值）
    var mechanism: String? = nil
    var confidence: String? = nil
    var timeRange: String? = nil
    var advice: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(conclusion.scriptConverted)
                .font(.system(size: 15.5, weight: .regular))
                .foregroundStyle(Ky.ink)
                .lineSpacing(4.5)
                .fixedSize(horizontal: false, vertical: true)
            if !links.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(links.indices, id: \.self) { i in
                        HStack(alignment: .top, spacing: 8) {
                            Text(links[i].label.scriptConverted)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(links[i].label == "盘面" ? Ky.qingdai : Ky.gold)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background((links[i].label == "盘面" ? Ky.qingdai : Ky.gold).opacity(0.13))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            Text(evidenceLinkText(links[i].text))
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
            // 六段字段行（结论＋links 之下；机制走典籍原文黑名单同款处理，其余走简繁转换）
            if let mechanism = mechanism, !mechanism.isEmpty {
                fieldRow("作用机制", evidenceLinkText(mechanism))
            }
            if let timeRange = timeRange, !timeRange.isEmpty {
                fieldRow("时间范围", timeRange.scriptConverted)
            }
            if let advice = advice, !advice.isEmpty {
                fieldRow("现实建议", advice.scriptConverted)
            }
            if let confidence = confidence, !confidence.isEmpty {
                fieldRow("可信程度", confidence.scriptConverted)
            }
        }
    }
    private func fieldRow(_ label: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label.scriptConverted)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Ky.gold)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Ky.gold.opacity(0.13))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text(text)
                .font(.caption)
                .foregroundStyle(Ky.sub)
                .lineSpacing(2.5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - iOS 27 宋式章节眉题（强制单行不折行，左青黛圆角柱＋衬线标题＋发丝线＋右胶囊注）
struct KySectionTitle: View {
    let title: String
    var trailing: String = ""
    var body: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(Ky.qingdai)
                .frame(width: 4, height: 15)
            Text(title.scriptConverted)
                .font(.system(size: 16, weight: .bold, design: .serif))
                .foregroundStyle(Ky.ink)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Rectangle()
                .fill(Ky.line.opacity(0.85))
                .frame(height: 0.8)
            if !trailing.isEmpty {
                Text(trailing.scriptConverted)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(Ky.sub)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }
}

/// 朱砂印章小记：只用于「落判/落款」语义（回验落判、报告落款），不作普通按钮
struct KySeal: View {
    let text: String
    var body: some View {
        Text(text.scriptConverted)
            .font(.system(size: 13, design: .serif)).fontWeight(.bold)
            .foregroundStyle(Ky.cinnabar)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(Ky.cinnabar.opacity(0.06))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Ky.cinnabar, lineWidth: 1.3))
            .rotationEffect(.degrees(-3))
    }
}

struct KyWorkspaceHeading: View {
    let title: String
    let detail: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title.scriptConverted, systemImage: icon)
                .font(.system(.title2, design: .serif).weight(.bold))
                .foregroundStyle(Ky.ink)
            Text(detail.scriptConverted)
                .font(.subheadline)
                .foregroundStyle(Ky.sub)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    /// iOS 27 120Hz 零掉帧卡片：采用 continuous 连续曲率圆角（18pt）＋精细发丝描边，
    /// 剔除昂贵的动态离屏高斯阴影（.shadow），确保 ProMotion 滚动满帧丝滑。
    func kyCard() -> some View {
        self.padding(16)
            .background(Ky.card)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Ky.line, lineWidth: 1)
                    .allowsHitTesting(false)
            )
    }

    /// 浅染内嵌卡（用于卡片内部二级同心圆角区块，12pt continuous）
    func kySubCard() -> some View {
        self.padding(11)
            .background(Ky.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Ky.line.opacity(0.65), lineWidth: 0.6)
            )
    }
}

// MARK: - 排盘口径设置（对标文墨天机的安星参数页：口径成套可调，默认值＝现行金标准口径）
enum AppSettings {
    static var baziSect: Int { let v = UserDefaults.standard.integer(forKey: "baziSect"); return v == 1 ? 1 : 2 }
    static var ziweiLeapNext: Bool { UserDefaults.standard.object(forKey: "ziweiLeapNext") as? Bool ?? true }
    static var ziweiLateZiNext: Bool { UserDefaults.standard.bool(forKey: "ziweiLateZiNext") }
}

/// 中文图形日历选择器：内联整月日历＋中文年月标题，替代系统紧凑弹窗（弹窗月名曾跟随设备语言出英文）
struct KyChineseDatePicker: View {
    @Binding var date: Date
    private var title: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "yyyy年M月d日 EEEE"
        return f.string(from: date)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline).fontWeight(.semibold).foregroundStyle(Ky.ink)
            DatePicker("", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .environment(\.locale, Locale(identifier: "zh_CN"))
                .labelsHidden()
        }
    }
}

struct CaliberSettingsView: View {
    @AppStorage("signDateEpoch") private var signDateEpoch: Double = 0
    @AppStorage("signCertDays") private var signCertDays: Int = 365
    @AppStorage("baziSect") private var baziSect = 2
    @AppStorage("ziweiLeapNext") private var ziweiLeapNext = true
    @AppStorage("ziweiLateZiNext") private var ziweiLateZiNext = false
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    KySectionTitle(title: "八字口径", trailing: "子平正统")
                    Picker("晚子时归日", selection: $baziSect) {
                        Text("23 点后算次日".scriptConverted).tag(1)
                        Text("23 点后算当日".scriptConverted).tag(2)
                    }.pickerStyle(.segmented)
                    Text("现行金标准盘以晚子时算当日（23:00 后日柱不换、时干按次日五鼠遁推）对拍验证；改口径后盘面随之变化，属预期。".scriptConverted)
                        .font(.caption).foregroundStyle(Ky.sub)
                }.kyCard()

                VStack(alignment: .leading, spacing: 10) {
                    KySectionTitle(title: "紫微口径", trailing: "天纪三合派")
                    Toggle("闰月整月归下月", isOn: $ziweiLeapNext)
                        .tint(Ky.qingdai)
                    Toggle("晚子时作次日", isOn: $ziweiLateZiNext)
                        .tint(Ky.qingdai)
                    Text("默认：闰月归下月、晚子时作当日，与紫微金标准盘（同源参照）一致。".scriptConverted)
                        .font(.caption).foregroundStyle(Ky.sub)
                }.kyCard()

                VStack(alignment: .leading, spacing: 10) {
                    KySectionTitle(title: "签名信息", trailing: "侧载证书提醒")
                    Text("签名日期").font(.subheadline).fontWeight(.medium).foregroundStyle(Ky.ink)
                    KyChineseDatePicker(date: Binding(
                        get: { signDateEpoch > 0 ? Date(timeIntervalSince1970: signDateEpoch) : Date() },
                        set: { signDateEpoch = $0.timeIntervalSince1970 }))
                    Picker("证书类型", selection: $signCertDays) {
                        Text("免费证书（7 天）".scriptConverted).tag(7)
                        Text("付费证书（1 年）".scriptConverted).tag(365)
                    }.pickerStyle(.segmented)
                    if signDateEpoch > 0 {
                        let expiry = Date(timeIntervalSince1970: signDateEpoch).addingTimeInterval(Double(signCertDays) * 86400)
                        let remain = Calendar.current.dateComponents([.day], from: Date(), to: expiry).day ?? 0
                        Text("到期日 \(expiry.formatted(date: .abbreviated, time: .omitted))，还剩 \(remain) 天。到期前 7 天起首页会亮提醒：到期后应用打不开是证书问题、不是数据问题，续签覆盖安装即可，数据不丢。".scriptConverted)
                            .font(.caption).foregroundStyle(remain <= 7 ? Ky.cinnabar : Ky.sub)
                    } else {
                        Text("装好应用后在这里记下签名日期，临近到期首页会提醒续签。".scriptConverted)
                            .font(.caption).foregroundStyle(Ky.sub)
                    }
                }.kyCard()

                VStack(alignment: .leading, spacing: 10) {
                    KySectionTitle(title: "紫微亮度表", trailing: "58星×12宫")
                    Text("现行：《斗数全书》派亮度（58 星×12 宫全量）。中州派亮度表数据源未核实，不编造，缺位标注在此——宁缺毋假。".scriptConverted)
                        .font(.caption).foregroundStyle(Ky.sub)
                }.kyCard()
            }.padding(16).padding(.bottom, 100)
        }
        .background(Ky.bg)
        .navigationTitle(Text("排盘口径设置".scriptConverted))
        .navigationBarTitleDisplayMode(.inline)
    }
}
