// 称骨独立工具 ＋ 小运（G8，2026-11-07）：
// 口径与 Web app/chenggu.py、app/wuyunliuqi.py 逐项同源（年／月／日／时四重称重表、
// 52 格歌诀七言四句正文、三源逐字核对与异文裁决见 Web 引擎注释；歌诀不含男女注解，
// 本工具不设寿元关口）。页面顶部固定按语「称骨仅 52 格、人人落格，粗疏不可据；
// 本工具不设寿元关口」。
// 小运：以时柱为起点，阳男阴女顺行、阴男阳女逆行（与大运同向，即 chart.qiyunDirection），
// 一岁一运，一岁为时柱顺／逆下一柱，虚岁计；只在起运前年份补一行，不展开断语。
// 任务初稿「男顺女逆」为简化说法，与典籍不符，以典籍为准（见 Web 引擎注释）。
import SwiftUI
import LunarSwift

enum ChengguEngine {
    // 年重：干支 → 钱（三源逐字核对；癸亥从两源六钱）
    static let yearWeight: [String: Int] = [
        "甲子": 12, "丙子": 16, "戊子": 15, "庚子": 7, "壬子": 5,
        "乙丑": 9, "丁丑": 8, "己丑": 7, "辛丑": 7, "癸丑": 7,
        "丙寅": 6, "戊寅": 8, "庚寅": 9, "壬寅": 9, "甲寅": 12,
        "丁卯": 7, "己卯": 19, "辛卯": 12, "癸卯": 12, "乙卯": 8,
        "戊辰": 12, "庚辰": 12, "壬辰": 10, "甲辰": 8, "丙辰": 8,
        "己巳": 5, "辛巳": 6, "癸巳": 7, "乙巳": 7, "丁巳": 6,
        "庚午": 9, "壬午": 8, "甲午": 15, "丙午": 13, "戊午": 19,
        "辛未": 8, "癸未": 7, "乙未": 6, "丁未": 5, "己未": 6,
        "壬申": 7, "甲申": 5, "丙申": 5, "戊申": 14, "庚申": 8,
        "癸酉": 8, "乙酉": 15, "丁酉": 14, "己酉": 5, "辛酉": 16,
        "甲戌": 15, "丙戌": 6, "戊戌": 14, "庚戌": 9, "壬戌": 10,
        "乙亥": 9, "丁亥": 16, "己亥": 9, "辛亥": 17, "癸亥": 6,
    ]
    // 月重：农历月 → 钱（正月＝1 … 冬月＝11、腊月＝12）
    static let monthWeight: [Int] = [6, 7, 18, 9, 5, 16, 9, 15, 18, 8, 9, 5]
    // 日重：农历日 → 钱
    static let dayWeight: [Int] = [5, 10, 8, 15, 16, 15, 8, 16, 8, 16, 9, 17, 8, 17, 10,
                                    8, 9, 18, 5, 15, 10, 9, 8, 9, 15, 18, 7, 8, 16, 6]
    // 时重：时支 → 钱
    static let hourWeight: [Character: Int] = [
        "子": 16, "丑": 6, "寅": 7, "卯": 10, "辰": 9, "巳": 16,
        "午": 10, "未": 8, "申": 8, "酉": 9, "戌": 6, "亥": 6,
    ]
    static let disclaimer = "称骨仅 52 格、人人落格，粗疏不可据；本工具不设寿元关口。"
    static let sourceNote = "歌诀为后世流传的袁天罡称骨歌通行原文（七言四句正文，不含男女注解）；年／月／日／时四重称重表经三源逐字核对，异文见 Web app/chenggu.py 注释。传为唐·袁天罡所作，正史无确证，仅作传统文化参考。"

    // 歌诀：总重（钱）→（命格名，七言四句）。命格名为空者表示三源皆无别名，不虚构。
    // 三两六／三两九从黑曜石之家与百科知识两源（博客园一源互换）；二两二歌诀从博客园
    // 与黑曜石之家两源；七两二格四重最大值合计仅 7.1 两，现实不可达，歌诀列入备查。
    static let verses: [Int: (title: String, lines: [String])] = [
        21: ("终身行乞孤苦之命", ["短命非业谓大空", "平生灾难事重重", "凶祸频临陷逆境", "终世困苦事不成"]),
        22: ("一生劳碌之命", ["此命劳碌一生穷", "每逢困难事重重", "凶祸频临陷苦境", "终身大事谋不成"]),
        23: ("终身困苦之命", ["此命推来骨肉轻", "求谋做事事难成", "妻儿兄弟实难靠", "外出他乡做散人"]),
        24: ("一生薄福之命", ["此命推来福禄无", "门庭困苦总难荣", "六亲骨肉皆无靠", "流浪他乡作老翁"]),
        25: ("六亲无靠，自立更生之命", ["此命推来祖业微", "门庭营度似稀奇", "六亲骨肉如冰炭", "一世勤劳自把持"]),
        26: ("", ["平生衣禄苦中求", "独自营谋事不休", "离祖出门宜早计", "晚来衣禄自无休"]),
        27: ("一生多谋少成之命", ["一生作事少商量", "难靠祖宗作主张", "独马单枪空做去", "早年晚岁总无长"]),
        28: ("", ["一生行事似飘蓬", "祖宗产业在梦中", "若不过房改名姓", "也当移徒二三通"]),
        29: ("", ["初年运限未曾亨", "纵有功名在后成", "须过四旬才可立", "移居改姓始为良"]),
        30: ("", ["劳劳碌碌苦中求", "东奔西走何日休", "若使终身勤与俭", "老来稍可免忧愁"]),
        31: ("交友谨慎，老年衣食足用之命", ["忙忙碌碌苦中求", "何日云开见日头", "难得祖基家可立", "中年衣食渐无忧"]),
        32: ("", ["初年运蹇事难谋", "渐有财源如水流", "到得中年衣食旺", "那时名利一齐收"]),
        33: ("性直多情，交友带劫之命", ["早年作事事难成", "百计徒劳枉费心", "半世自如流水去", "后来运到得黄金"]),
        34: ("", ["此命福气果如何", "僧道门中衣禄多", "离祖出家方为妙", "朝晚拜佛念弥陀"]),
        35: ("", ["生平福量不周全", "祖业根基觉少传", "营事生涯宜守旧", "时来衣食胜从前"]),
        36: ("少年多波折，老来安逸之命", ["不须劳碌过平生", "独自成家福不轻", "早有福星常照命", "任君行去百般成"]),
        37: ("一生财来复去，难得大富之命", ["此命般般事不成", "弟兄少力自孤行", "虽然祖业须微有", "来得明时去不明"]),
        38: ("", ["一身骨肉最清高", "早入簧门姓氏标", "待到年将三十六", "蓝衫脱去换红袍"]),
        39: ("少年命运不通，老享清福之命", ["此命终身运不通", "劳劳作事尽皆空", "苦心竭力成家计", "到得那时在梦中"]),
        40: ("", ["平生衣禄是绵长", "件件心中自主张", "前面风霜多受过", "后来必定享安康"]),
        41: ("聪明超群，老来逍遥享福之命", ["此命推来事不同", "为人能干异凡庸", "中年还有逍遥福", "不比前时运未通"]),
        42: ("自力更生，老运名利双收之命", ["得宽怀处且宽怀", "何用双眉皱不开", "若使中年命运济", "那时名利一齐来"]),
        43: ("福禄厚重，白手成家之命", ["为人心性最聪明", "作事轩昂近贵人", "衣禄一生天数定", "不须劳碌过平生"]),
        44: ("初年无财，老年自得享福之命", ["万事由天莫苦求", "须知福禄命里收", "少壮名利难如意", "晚景欣然更不忧"]),
        45: ("少年辛苦，老来福禄双全之命", ["名利推来竟若何", "前番辛苦后奔波", "命中难养男与女", "骨肉扶持也不多"]),
        46: ("改姓移居，自得福寿双全之命", ["东西南北尽皆通", "出姓移居更觉隆", "衣禄无亏天数定", "中年晚景一般同"]),
        47: ("早年多波折，晚年享福之命", ["此命推为旺末年", "妻荣子贵自怡然", "平生原有滔滔福", "财源滚滚似水流"]),
        48: ("初年大志难伸，晚年发展之命", ["初年运道未曾亨", "若是蹉跎再不兴", "兄弟六亲皆无靠", "一身事业晚年成"]),
        49: ("交友多情有损，小心防之再发之命", ["此命推来福不轻", "自成自立显门庭", "从来富贵人钦敬", "使婢差奴过一生"]),
        50: ("衣食无亏，一生富贵之命", ["为利为名终日劳", "中年福禄也多遭", "老来是有财星照", "不比前番目下高"]),
        51: ("勤俭成家，老年自得福禄之命", ["一世荣华事事通", "不须劳碌自亨通", "弟兄叔侄皆如意", "家业成时福禄宏"]),
        52: ("聪明能干，老来财禄丰足之命", ["一世荣华事事能", "不须劳思自然宁", "宗族欣然心皆好", "家业丰亨自称心"]),
        53: ("自己兴家立业之命", ["此格推为气量真", "兴家发达在其中", "一生福禄安排定", "却是人间一富翁"]),
        54: ("一生清闲之命", ["此命推来厚且清", "诗书满腹看功成", "丰衣足食自然稳", "正是人间有福人"]),
        55: ("少年奋斗，晚年富贵之命", ["走马扬鞭争利名", "少年作事费筹论", "一朝福禄源源至", "富贵荣华显六亲"]),
        56: ("仁义之人，老来富贵之命", ["此格推来礼义通", "一身福禄用无穷", "甜酸苦辣皆尝过", "滚滚财源稳且丰"]),
        57: ("人人钦敬，离祖成家之命", ["福禄丰盈万事全", "一身荣耀乐天年", "名扬威震人争羡", "此世逍遥宛似仙"]),
        58: ("独创名利，晚年享福之命", ["平生福禄自然来", "名利兼全福寿偕", "雁塔题名为贵客", "紫袍金带走金阶"]),
        59: ("宜安分守己，福禄自足之命", ["细推此格妙且清", "必定才高礼义通", "甲第之中应有分", "扬鞭走马显威荣"]),
        60: ("鹤立鸡群，显祖扬宗之命", ["一朝金榜快题名", "显祖荣宗立大功", "衣禄定然原裕足", "田园财帛更丰盈"]),
        61: ("名利双收，一生富贵之命", ["不作朝中金榜客", "定为世上大财翁", "聪明天赋经书熟", "名显高科自是荣"]),
        62: ("读书聪明，特任高官，大振家风之命", ["此命生来福不穷", "读书必定显亲宗", "紫衣金带为卿相", "富贵荣华皆可同"]),
        63: ("长寿，高官显耀，上格之命", ["命主为官福禄长", "得来富贵实丰常", "名题金塔传金榜", "定中高科天下扬"]),
        64: ("权威大官，万古留名之富贵命", ["此格威权不可当", "紫袍金带尘高堂", "荣华富贵谁能及", "万古留名姓氏扬"]),
        65: ("", ["细推此命福非轻", "富贵荣华孰与争", "定国安邦人极品", "威声显赫震寰瀛"]),
        66: ("大富大贵，堆金积玉之福命", ["此格人间一福人", "堆金积玉满堂春", "从来富贵由天定", "正笏垂绅谒圣君"]),
        67: ("一世荣华，享福无边之命", ["此命生来福自宏", "田园家业最高隆", "平生衣禄盈丰足", "一世荣华万事通"]),
        68: ("享受天赐之福，近贵显达之命", ["富贵由天莫苦求", "万金家计不须谋", "如今不比前翻事", "祖业根基千古留"]),
        69: ("祖业虽多，若不紧守也会落空", ["君是人间衣禄星", "一生富贵众人钦", "纵然福禄由天定", "安享荣华过一生"]),
        70: ("一生清荣，富贵双全之命", ["此命推来福禄宏", "不须愁虑苦劳心", "一生天定衣与禄", "富贵荣华主一生"]),
        71: ("", ["此命生成大不同", "公侯卿相在其中", "一生自有逍遥福", "富贵荣华极品隆"]),
        72: ("", ["此格世界罕有生", "十代积善产此人", "天上紫微来照命", "统治万民乐太平"]),
    ]

    struct Result {
        let rows: [(part: String, key: String, qian: Int)]
        let total: Int
        let title: String
        let lines: [String]
    }

    static func cnDigit(_ n: Int) -> String {
        let digits = ["", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
        if n >= 0 && n < digits.count {
            return digits[n]
        }
        return String(n)
    }

    static func fmtWeight(_ qian: Int) -> String {
        let liang = qian / 10
        let q = qian % 10
        if liang == 0 {
            return cnDigit(q) + "钱"
        }
        if q == 0 {
            return cnDigit(liang) + "两"
        }
        return cnDigit(liang) + "两" + cnDigit(q) + "钱"
    }

    // 闰月归属（通行注）：闰月上半月算本月，下半月算下月。
    static func monthForChenggu(month: Int, isLeap: Bool, day: Int) -> Int {
        if isLeap && day > 15 {
            return min(month + 1, 12)
        }
        return month
    }

    // 农历月／日取自与 BaziEngine.paipan 相同的真太阳时校正后时间
    // （chart.trueSolarDate，未给经度时为出生钟表时间）；LunarSwift month 为负表示闰月。
    static func lunarMonthDay(for chart: BaziChart) -> (month: Int, day: Int, isLeap: Bool) {
        let date = chart.trueSolarDate ?? chart.birthDate
        var cal = Calendar(identifier: .gregorian)
        if let tz = TimeZone(secondsFromGMT: 8 * 3600) {
            cal.timeZone = tz
        }
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let y = min(max(c.year ?? 2026, 1901), 2099)
        let m = min(max(c.month ?? 1, 1), 12)
        let d = min(max(c.day ?? 1, 1), 31)
        let h = min(max(c.hour ?? 12, 0), 23)
        let lunar = Solar.fromYmdHms(year: y, month: m, day: d, hour: h, minute: c.minute ?? 0).lunar
        let rawMonth = lunar.month
        return (abs(rawMonth), lunar.day, rawMonth < 0)
    }

    static func from(chart: BaziChart) -> Result? {
        let yearGz = chart.yearPillar
        let hourBranch = chart.timePillar.last ?? "?"
        let yw = yearWeight[yearGz] ?? -1
        let hw = hourWeight[hourBranch] ?? -1
        if yw < 0 || hw < 0 {
            return nil
        }
        let lm = lunarMonthDay(for: chart)
        let usedMonth = monthForChenggu(month: lm.month, isLeap: lm.isLeap, day: lm.day)
        if usedMonth < 1 || usedMonth > 12 || lm.day < 1 || lm.day > 30 {
            return nil
        }
        let mw = monthWeight[usedMonth - 1]
        let dw = dayWeight[lm.day - 1]
        let total = yw + mw + dw + hw
        let v = verses[total]
        let rows: [(part: String, key: String, qian: Int)] = [
            (part: "年", key: yearGz, qian: yw),
            (part: "月", key: "农历" + String(usedMonth) + "月", qian: mw),
            (part: "日", key: "农历" + String(lm.day) + "日", qian: dw),
            (part: "时", key: String(hourBranch) + "时", qian: hw),
        ]
        return Result(rows: rows, total: total, title: v?.title ?? "", lines: v?.lines ?? [])
    }
}

// MARK: - 小运（起运前补一行，与 Web app/wuyunliuqi.py 同口径）
enum XiaoYun {
    // 指定年份的小运干支；起运后或出生年前返回 nil。
    static func ganzhi(chart: BaziChart, year: Int) -> String? {
        if year < chart.birthYear {
            return nil
        }
        if year >= chart.qiyunYear {
            return nil
        }
        let age = year - chart.birthYear + 1
        let forward = chart.qiyunDirection == "顺行"
        let delta = forward ? age : -age
        return shift(chart.timePillar, by: delta)
    }

    static func shift(_ gz: String, by delta: Int) -> String {
        let tg = BaziTables.TG
        let dz = BaziTables.DZ
        guard let first = gz.first, let last = gz.last else {
            return gz
        }
        var idx = -1
        for n in 0..<60 {
            if tg[n % 10] == first && dz[n % 12] == last {
                idx = n
                break
            }
        }
        if idx < 0 {
            return gz
        }
        let n2 = ((idx + delta) % 60 + 60) % 60
        return String(tg[n2 % 10]) + String(dz[n2 % 12])
    }
}

// MARK: - 称骨独立小工具页
struct ChengguView: View {
    let person: Person
    let chart: BaziChart

    var body: some View {
        let result = ChengguEngine.from(chart: chart)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                Text(ChengguEngine.disclaimer)
                    .font(.callout).fontWeight(.semibold).foregroundStyle(Ky.cinnabar)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Ky.cinnabar.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                if let r = result {
                    VStack(alignment: .leading, spacing: 8) {
                        KySectionTitle(title: "四重称重明细", trailing: "年／月／日／时")
                        ForEach(r.rows.indices, id: \.self) { i in
                            HStack(spacing: 10) {
                                Text(r.rows[i].part).font(.caption).fontWeight(.semibold)
                                    .foregroundStyle(Ky.gold).frame(width: 20, alignment: .leading)
                                Text(r.rows[i].key).font(.callout).foregroundStyle(Ky.ink)
                                Spacer()
                                Text(ChengguEngine.fmtWeight(r.rows[i].qian))
                                    .font(KyV2.tabular(14, weight: .bold)).foregroundStyle(Ky.ink)
                            }
                        }
                        Divider()
                        HStack(spacing: 10) {
                            Text("总骨重").font(.callout).fontWeight(.bold).foregroundStyle(Ky.ink)
                            Spacer()
                            Text(ChengguEngine.fmtWeight(r.total))
                                .font(.system(.title3, design: .serif)).fontWeight(.bold)
                                .foregroundStyle(Ky.qingdai)
                        }
                        if r.title.isEmpty == false {
                            Text(r.title).font(.callout).foregroundStyle(Ky.sub)
                        }
                        if r.total == 72 {
                            Text("七两二格四重最大值合计仅 7.1 两，现实不可达；歌诀列入备查。")
                                .font(.caption2).foregroundStyle(Ky.sub)
                        }
                    }.kyCard()
                    VStack(alignment: .leading, spacing: 6) {
                        KySectionTitle(title: "称骨歌诀", trailing: ChengguEngine.fmtWeight(r.total))
                        ForEach(r.lines.indices, id: \.self) { i in
                            Text(r.lines[i] + "，")
                                .font(.system(.body, design: .serif)).foregroundStyle(Ky.ink)
                                .lineSpacing(3)
                        }
                        Text(ChengguEngine.sourceNote)
                            .font(.caption2).foregroundStyle(Ky.sub)
                    }.kyCard()
                } else {
                    Text("称骨无法计算：四柱或农历月日缺失，请检查档案出生时间。")
                        .font(.callout).foregroundStyle(Ky.sub)
                }
                Text("依据与金标准：四重称重表与 52 格歌诀经三源逐字核对，异文裁决见 Web app/chenggu.py 注释；金标准见 Web tools/tests/test_chenggu.py（合成四柱 10 例＋实盘 4 例逐项复算）。")
                    .font(.caption2).foregroundStyle(Ky.sub)
            }.padding(16)
        }
        .background(Ky.bg)
        .navigationTitle(person.name.isEmpty ? "称骨" : "称骨 · \(person.name)")
        .navigationBarTitleDisplayMode(.inline)
    }
}
