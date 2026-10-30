// 解盘 · 初断（规则层）：排盘之后的第一层解读，全部结论走依据链（结论←规则←盘面事实）。
// 定位写死：这是结构化初断——命局风景/月令格局候选/扶抑调候喜忌/十神分布/岁运要点；
// 工作室级的直断逐年（回测校准过的那套）仍以正式报告为准，App 内不冒充。
import SwiftUI
import AVFoundation

struct InterpretItem {
    let title: String
    let conclusion: String
    let links: [(label: String, text: String)]
}

enum InterpretEngine {
    private static let wxNames = ["木", "火", "土", "金", "水"]
    private static func wxIndex(of stem: Character) -> Int {
        switch stem { case "甲", "乙": return 0; case "丙", "丁": return 1
        case "戊", "己": return 2; case "庚", "辛": return 3; default: return 4 }
    }
    static func interpret(chart ch: BaziChart) -> [InterpretItem] {
        var items: [InterpretItem] = []
        let pct = ch.wuxingPercents
        let dayStem = ch.rizhu.first!
        let dayWx = wxIndex(of: dayStem)
        // 1 命局风景（五行分布直读）
        let order = pct.indices.sorted { pct[$0] > pct[$1] }
        let strong = order.first!; let weak = order.last!
        items.append(InterpretItem(
            title: "命局风景",
            conclusion: "五行里\(wxNames[strong])最重（\(Int(pct[strong].rounded()))%）、\(wxNames[weak])最轻（\(Int(pct[weak].rounded()))%）；日主\(ch.rizhu)属\(wxNames[dayWx])，力量排第 \(order.firstIndex(of: dayWx)! + 1)。",
            links: [("盘面", "五行占比 木\(Int(pct[0].rounded())) 火\(Int(pct[1].rounded())) 土\(Int(pct[2].rounded())) 金\(Int(pct[3].rounded())) 水\(Int(pct[4].rounded()))"),
                    ("口径", "占比为盘面计法（天干＋藏干加权），只说明分布，不直接等于强弱结论")]))
        // 2 月令格局候选（本气十神，透干校验）
        let monthBranch = ch.monthPillar.last!
        let benQi = BaziTables.cangGan[monthBranch]!.first!
        let benQiSS = BaziTables.shiShen(day: dayStem, stem: benQi)
        let touGan = ch.stemShiShen[1] == benQiSS
        items.append(InterpretItem(
            title: "月令格局（候选）",
            conclusion: "月令\(monthBranch)本气\(benQi)对日主为\(benQiSS)，先按\(benQiSS)格候选看。\(touGan ? "月干透出同气，格象较明。" : "本气未透干，格象要结合透藏与岁运再定，此处只作候选。")",
            links: [("盘面", "月柱 \(ch.monthPillar)，本气 \(benQi)；月干十神 \(ch.stemShiShen[1])"),
                    ("法则", "《子平真诠》：格以月令本气为纲，透干则格明")]))
        // 3 扶抑＋调候喜忌（初判）
        let shengWo = (dayWx + 4) % 5  // 生我者：木←水 火←木 土←火 金←土 水←金
        let tongDang = pct[dayWx] + pct[shengWo]
        let level = tongDang >= 55 ? "偏强" : (tongDang <= 40 ? "偏弱" : "中和")
        let xiText: String
        switch level {
        case "偏强": xiText = "扶抑上喜克、泄、耗——\(wxNames[(dayWx + 1) % 5])（食伤）\(wxNames[(dayWx + 2) % 5])（财）\(wxNames[(dayWx + 3) % 5])（官杀）方向可用，忌再添\(wxNames[shengWo])\(wxNames[dayWx])。"
        case "偏弱": xiText = "扶抑上喜生扶——\(wxNames[shengWo])（印）与\(wxNames[dayWx])（比劫）为援，忌克泄耗再压。"
        default: xiText = "同党异党接近，贵在流通：哪一行堵住就疏哪一行，不预设固定喜忌。"
        }
        var tiaoHou = ""
        if ["亥", "子", "丑"].contains(monthBranch) { tiaoHou = "生于寒月，调候另喜火暖局。" }
        if ["巳", "午", "未"].contains(monthBranch) { tiaoHou = "生于热月，调候另喜水润局。" }
        items.append(InterpretItem(
            title: "喜忌（扶抑初判）",
            conclusion: "日主\(level)：同党（\(wxNames[dayWx])＋印\(wxNames[shengWo])）约占 \(Int(tongDang.rounded()))%。\(xiText)\(tiaoHou)",
            links: [("盘面", "日主 \(ch.rizhu)（\(wxNames[dayWx])），月令 \(monthBranch)"),
                    ("法则", "扶抑取用为初判框架；《穷通宝鉴》调候优先于扶抑，两条冲突时以调候为先")]))
        // 4 十神分布看点
        let groups: [(String, [String], String)] = [
            ("官杀", ["正官", "七杀"], "规矩与压力成势：对秩序、名分、责任敏感，行事有框线感。"),
            ("印星", ["正印", "偏印"], "印星成势：重学习、凭靠与安全感，遇事先找依据和退路。"),
            ("财星", ["正财", "偏财"], "财星成势：对资源与结果敏感，行事重实效，钱与机会的嗅觉靠前。"),
            ("食伤", ["食神", "伤官"], "食伤成势：表达与手艺成势，靠输出吃饭，不喜被管束。"),
            ("比劫", ["比肩", "劫财"], "比劫成势：自我与同辈成势，主见强，合作与分账要先立规矩。"),
        ]
        var counts: [String: Int] = [:]
        for ss in ch.stemShiShen where ss != "日主" { counts[ss, default: 0] += 1 }
        for row in ch.hideShiShen { for ss in row { counts[ss, default: 0] += 1 } }
        let scored = groups.map { g -> (String, Int, String) in
            (g.0, g.1.reduce(0) { $0 + (counts[$1] ?? 0) }, g.2)
        }.sorted { $0.1 > $1.1 }
        if let top = scored.first, top.1 > 0 {
            items.append(InterpretItem(
                title: "十神看点",
                conclusion: top.2,
                links: [("盘面", "透干＋藏干合计：\(scored.map { "\($0.0) \($0.1)" }.joined(separator: " · "))"),
                        ("口径", "分布只定势的主次，具体事件要回到宫位与岁运引动，不单凭分布断事")]))
        }
        // 5 岁运要点（当前大运＋本年流年与日支关系）
        let nowYear = Calendar.current.component(.year, from: Date())
        var curIdx: Int? = nil
        for i in ch.dayunGanZhi.indices where nowYear >= ch.dayunStartYear(i) && nowYear <= ch.dayunStartYear(i) + 9 { curIdx = i }
        var yunText: String; var yunFacts: String
        if let i = curIdx {
            let gz = ch.dayunGanZhi[i]
            let ss = BaziTables.shiShen(day: dayStem, stem: gz.first!)
            yunText = "现行\(gz)大运（\(ch.dayunStartYear(i))–\(ch.dayunStartYear(i) + 9)），运干对日主为\(ss)——这十年的主课题先按\(ss)看。"
            yunFacts = "大运 \(gz)，起运 \(ch.qiyunDate)"
        } else {
            yunText = "尚未起运或已出已排大运范围，按童限与流年看。"
            yunFacts = "起运 \(ch.qiyunDate)"
        }
        let ln = BaziChart.yearGanZhi(nowYear)
        let dayBranch = ch.dayPillar.last!
        let lnBranch = ln.last!
        let chongPairs: [Character: Character] = ["子": "午", "午": "子", "丑": "未", "未": "丑", "寅": "申", "申": "寅",
                                                   "卯": "酉", "酉": "卯", "辰": "戌", "戌": "辰", "巳": "亥", "亥": "巳"]
        let hePairs: [Character: Character] = ["子": "丑", "丑": "子", "寅": "亥", "亥": "寅", "卯": "戌", "戌": "卯",
                                               "辰": "酉", "酉": "辰", "巳": "申", "申": "巳", "午": "未", "未": "午"]
        var relText = "与日支\(dayBranch)无直接冲合，属平流年。"
        if chongPairs[dayBranch] == lnBranch { relText = "流年\(lnBranch)冲日支\(dayBranch)：今年动象落在根基、居所与亲密关系一线，宜主动求变、忌被动挨冲。" }
        if hePairs[dayBranch] == lnBranch { relText = "流年\(lnBranch)合日支\(dayBranch)：今年牵合之象落在自身与亲密关系一线，合作、缔约、关系推进的信号强。" }
        items.append(InterpretItem(
            title: "岁运要点",
            conclusion: "\(yunText) \(nowYear) 年流年\(ln)：\(relText)",
            links: [("盘面", yunFacts), ("法则", "应期看引动：冲合落到哪一宫，哪一线的事先动")]))
        return items + dimensions(ch)
    }
}

struct InterpretView: View {
    let chart: BaziChart
    let name: String
    @StateObject private var speaker = Speaker()
    var body: some View {
        let items = InterpretEngine.interpret(chart: chart)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Button {
                    speaker.read(items.map { "\($0.title)。\($0.conclusion)" }.joined(separator: "。"))
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: speaker.speaking ? "stop.circle.fill" : "play.circle.fill")
                        Text(speaker.speaking ? "停止朗读" : "朗读全文（听书）").font(.subheadline).fontWeight(.medium)
                    }.foregroundStyle(Ky.gold)
                }.buttonStyle(.plain)
                ForEach(items.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(items[i].title)
                            .font(.system(.subheadline, design: .serif)).fontWeight(.semibold).foregroundStyle(Ky.ink)
                        EvidenceChainView(conclusion: items[i].conclusion, links: items[i].links)
                    }
                    .kyCard()
                }
                Text("解盘说明：以上每一项都是按盘面数据逐项算出，结论下附「盘面＋根据」可复核；所据为五典与流派通说，标注在每条根据里。健康与寿元只给倾向与关口年，不落病名、不预言寿数。正式命书（回测校准的直断）以工作室报告为更深一层。")
                    .font(.caption2).foregroundStyle(Ky.sub)
            }.padding(16)
        }
        .background(Ky.bg)
        .onDisappear { speaker.stop() }
        .navigationTitle(name.isEmpty ? "解盘" : "解盘 · \(name)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 朗读（对标问真「听书」：解盘可听，系统语音离线合成）
final class Speaker: ObservableObject {
    private let synth = AVSpeechSynthesizer()
    @Published var speaking = false
    func read(_ text: String) {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate); speaking = false; return }
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        u.rate = 0.48
        speaking = true
        synth.speak(u)
    }
    func stop() { synth.stopSpeaking(at: .immediate); speaking = false }
}

// MARK: - 解盘全维度（每条：大白话结论＋依据链；标注所据法则与出处层级）
extension InterpretEngine {
    static func dimensions(_ ch: BaziChart) -> [InterpretItem] {
        var out: [InterpretItem] = []
        let dayStem = ch.rizhu.first!
        let pct = ch.wuxingPercents
        let wxN = ["木", "火", "土", "金", "水"]
        func wxIdx(_ c: Character) -> Int { ["甲", "乙"].contains(c) ? 0 : ["丙", "丁"].contains(c) ? 1 : ["戊", "己"].contains(c) ? 2 : ["庚", "辛"].contains(c) ? 3 : 4 }
        let dayWx = wxIdx(dayStem)
        // 十神计数（透＋藏）
        var cnt: [String: Int] = [:]
        for ss in ch.stemShiShen where ss != "日主" { cnt[ss, default: 0] += 1 }
        for row in ch.hideShiShen { for ss in row { cnt[ss, default: 0] += 1 } }
        func g(_ names: [String]) -> Int { names.reduce(0) { $0 + (cnt[$1] ?? 0) } }
        let guan = g(["正官", "七杀"]), yin = g(["正印", "偏印"]), cai = g(["正财", "偏财"])
        let shi = g(["食神", "伤官"]), bi = g(["比肩", "劫财"])
        let sha = Set(BaziTables.shenSha(ch).flatMap { $0 })
        let shengWo = (dayWx + 4) % 5
        let tong = pct[dayWx] + pct[shengWo]
        let level = tong >= 55 ? "偏强" : (tong <= 40 ? "偏弱" : "中和")
        let cntText = "官杀 \(guan) · 印 \(yin) · 财 \(cai) · 食伤 \(shi) · 比劫 \(bi)（透干＋藏干合计）"
        func item(_ t: String, _ c: String, _ fact: String, _ rule: String) -> InterpretItem {
            InterpretItem(title: t, conclusion: c, links: [("盘面", fact), ("根据", rule)])
        }

        // 性格性情
        let natureWx = ["木": "仁厚向上、要生长空间，最烦被堵死", "火": "热情外放、反应快，最烦冷场和慢节奏", "土": "稳重务实、重承诺，最烦反复无常", "金": "利落果断、讲规矩，最烦拖泥带水", "水": "灵活善变通、想得多，最烦被框死"][wxN[dayWx]]!
        let dom = [("官杀", guan, "骨子里自带一根弦：对规则和评价敏感，越有压力越成形"), ("印星", yin, "先想后动，安全感来自有依据、有退路"), ("财星", cai, "结果导向，凡事先问值不值、有没有用"), ("食伤", shi, "表达欲和主见都强，服理不服管"), ("比劫", bi, "自我驱动力强，认定的事别人很难拉回")].max { $0.1 < $1.1 }!
        out.append(item("性格性情",
            "日主属\(wxN[dayWx])：\(natureWx)。再叠上盘里最重的\(dom.0)——\(dom.2)。",
            "日主 \(ch.rizhu)（\(wxN[dayWx])）；\(cntText)",
            "日主五行定性情底色（《滴天髓》干象）；主导十神定行为模式（类象通说）"))

        // 学业文书
        var xue = ""
        if yin >= 3 { xue = "印星成势，读书缘厚：吸收慢但扎实，适合需要长期积累的专业，文凭、证书这类凭靠对你加分明显。" }
        else if yin >= 1 && shi >= 2 { xue = "印与食伤兼见：理解力与表达力都在线，学东西偏向学以致用，考试型与应用型都能走。" }
        else if yin == 0 { xue = "原局印星不现，读书这条路不靠天赋靠方法：别拼记忆拼体系，选应用型、技能型方向比纯学术更顺。" }
        else { xue = "印星有根不多：学习靠兴趣和压力驱动，遇到对味的领域钻得进去。" }
        if sha.contains("文昌贵人") { xue += "盘带文昌，考试与文字关口有额外助力。" }
        out.append(item("学业文书", xue,
            "印星合计 \(yin)，食伤 \(shi)；文昌\(sha.contains("文昌贵人") ? "见" : "不见")",
            "印为文书学业之星（《三命通会》印绶论）；文昌主聪敏临场（神煞通说）"))

        // 事业方向
        let hangYe = ["木": "教育、文创、医药、园林纺织", "火": "能源、电子、餐饮、传媒娱乐", "土": "地产、建筑、农业、仓储", "金": "金融、机械、五金、法务军警", "水": "物流、贸易、旅游、水产航运"]
        let xiWx = level == "偏弱" ? wxN[shengWo] : wxN[(dayWx + 2) % 5]
        var career = ""
        if guan >= 3 { career = "官杀成势，事业主线在平台与秩序里：体制、大机构、纪律性强的行业，越规范的舞台越出成绩。" }
        else if shi >= 3 && cai >= 1 { career = "食伤生财，靠本事吃饭：技术、手艺、表达、产品——能把输出变成钱的路子最合你，自由度越高越强。" }
        else if cai >= 3 { career = "财星成势，事业围绕资源与经营转：生意、运营、客户与钱打交道的岗位是主场。" }
        else if yin >= 3 { career = "印星成势，事业靠专业与凭靠立身：研究、教育、医疗、技术权威路线，资历越老越值钱。" }
        else { career = "事业没有单一主星压场，走的是复合路：平台给框、手艺给底、机会给跳板，三样里至少占两样才稳。" }
        career += "行业象上多往喜用\(xiWx)靠：\(hangYe[xiWx]!)一类。"
        out.append(item("事业方向", career,
            cntText + "；身\(level)，喜用先取\(xiWx)",
            "十神定事业形态（类象通说）；行业以喜用五行取象（《穷通宝鉴》调候＋五行类象）"))

        // 工作形态
        var form = ""
        if guan >= 2 && yin >= 2 { form = "官印相生型：适合在体系内一级级往上走，名分、职级、编制这类东西对你不是束缚，是台阶。" }
        else if shi >= 2 && cai >= 2 { form = "自营手艺型：给人打工容易憋屈，自己接活、做产品、开工作室反而顺；早期可以先借平台练手。" }
        else if bi >= 3 { form = "合伙须谨慎型：同辈与合伙人是你的变量，合作可以，但账目、分工、退出机制必须白纸黑字在先。" }
        else { form = "灵活就业型：不挑体制内外，挑的是事情本身对不对味；对味时爆发力强，不对味时耗损明显。" }
        out.append(item("工作形态", form, cntText,
            "官印相生主体系进阶；食伤生财主自营；比劫重主合伙变量（《子平真诠》格局应用）"))

        // 财运
        var wealth = ""
        if cai == 0 { wealth = "财星不入局：不是没财，是钱不主动找你——财要靠食伤去生、靠岁运去引，年轻时先攒本事，财路后开。" }
        else if level == "偏弱" && cai >= 3 { wealth = "财多身弱：机会和钱的动静都不小，但自己兜不住——求财忌贪大，先练承载（身体、团队、现金流），能守住的才是你的财。" }
        else if level == "偏强" && cai >= 2 { wealth = "身强财旺：能扛财、能聚财，求财路子正大光明地走就行；偏财机会来时手要快，但只取看得懂的那份。" }
        else { wealth = "财星有根有度：正业收入是主干，偏财是点缀；钱的进出节奏平稳，败在人情与冲动，不败在没机会。" }
        let ku = ch.pillars.filter { ["辰", "戌", "丑", "未"].contains($0.last!) }.count
        wealth += ku > 0 ? "盘里见财库之地（辰戌丑未共 \(ku) 处），攒钱要靠制度：自动储蓄、不动产、定期，靠意志攒不住。" : "盘里无财库，钱来钱去偏活，攒钱全靠规则外置（单独账户、固定转存）。"
        out.append(item("财运形态", wealth,
            "财星合计 \(cai)，日主\(level)；四支中辰戌丑未 \(ku) 处",
            "财为我克之物，身能任财才聚（《滴天髓》何知章）；财库在辰戌丑未（通说）"))

        // 婚姻感情
        let spouseNames = ch.gender == "M" ? ["正财", "偏财"] : ["正官", "七杀"]
        let spouse = g(spouseNames)
        var love = ""
        if spouse == 0 { love = "配偶星不入原局：感情不是没有，是不按常规时间表来——多半要靠岁运把配偶星引出来才成事，晚一点反而稳。" }
        else if spouse >= 3 { love = "配偶星成势：异性缘与婚缘信号都强，选择多，难的不是遇不到，是定下来——定性比开始更重要。" }
        else { love = "配偶星有根：婚缘信号清晰，节奏正常，遇到对的人推进即可，不必自我怀疑。" }
        let db = ch.dayPillar.last!
        var dayRels: [String] = []
        for (i, p) in ch.pillars.enumerated() where i != 2 {
            if let r = BaziTables.relationFull(p.last!, db) { dayRels.append("\(["年", "月", "日", "时"][i])支\(p.last!)与日支\(r.0)") }
        }
        love += dayRels.isEmpty ? "夫妻宫（日支）安静无冲合：婚姻主打一个稳，波动多来自外部节奏而非结构本身。" : "夫妻宫有牵动：\(dayRels.joined(separator: "、"))——关系里有动象，相处要留沟通的余地，忌冷战积压。"
        if sha.contains("桃花") { love += "带桃花，人缘魅力在线，已婚后更要立边界。" }
        out.append(item("婚姻感情", love,
            "\(ch.gender == "M" ? "男命以财为配偶星" : "女命以官杀为配偶星")，合计 \(spouse)；日支 \(db)",
            "配偶星定位（《三命通会》六亲论）；夫妻宫看日支冲合（通说）"))

        // 子女
        let childStar = shi
        var child = ""
        if childStar == 0 { child = "子女星（食伤）不现：与子女的缘分偏「后发型」——要么得子偏晚，要么孩子独立早、聚少离多；缘分不在数量在质量。" }
        else if childStar >= 4 { child = "子女星成势：子女缘厚，孩子多半不止一个的信息强（时代生育政策另计）；孩子个性也强，管教要立规矩在前、讲感情在后。" }
        else { child = "子女星有根：子女缘分正常，多半一到两个的信息（时代政策另计），亲子关系以陪伴质量取胜。" }
        let timeSS = ch.stemShiShen[3]
        child += "时柱为\(ch.timePillar)（时干十神\(timeSS)），晚年与子女的相处模式先按\(timeSS)看：\(["食神": "子女孝顺贴心，晚景有口福与陪伴", "伤官": "子女有主见成就心强，你要学会放手", "正财": "子女务实顾家，晚年经济上得力", "偏财": "子女路子活、离家发展者多，得力在关键时刻", "正官": "子女守规矩有出息，是门面担当", "七杀": "子女个性硬、有冲劲，关系要靠尊重维系", "正印": "子女体贴，晚景照护有靠", "偏印": "子女有专长怪才，沟通要找对频道", "比肩": "子女独立性强，像朋友多过像下属", "劫财": "子女花钱手松或竞争心强，早立财务规矩"][timeSS] ?? "平常相处")。"
        out.append(item("子女缘分", child,
            "食伤（子女星）合计 \(childStar)；时柱 \(ch.timePillar)",
            "食伤为子女星、时柱为子女宫（《三命通会》六亲论）；个数为传统口径，须叠加时代基线"))

        // 父母
        let father = g(["偏财"]), mother = yin
        var par = ""
        par += father == 0 ? "父星（偏财）不现：父亲这一线缘分偏淡或助力偏间接——多半是聚少离多、或父亲不善表达，不是情薄，是形式如此。" : "父星有根：父亲对你的影响与助力看得见，方式多半实在（给资源、给出路）。"
        par += mother == 0 ? "母星（印）不现：母亲这一线要么缺位感强、要么母亲角色由他人代行；自己成家后，安全感要靠自己建。" : "母星有根：母亲是你的靠山之一，学业与人生关键处多有她的托举。"
        out.append(item("父母缘分", par,
            "偏财（父星）\(father)，印星（母星）\(mother)；年月柱 \(ch.yearPillar) \(ch.monthPillar)",
            "偏财看父、正印看母、年月为父母宫（六亲通说）；只断助力与缘分形态，不及生死"))

        // 兄弟姐妹
        var sib = ""
        if bi == 0 { sib = "比劫不现：手足缘薄，独生或与兄弟姐妹疏远的信息强；人生路上同辈助力少，靠自己。" }
        else if bi >= 4 { sib = "比劫成势：兄弟姐妹多或同辈圈子重——助力大，分账与边界也要清；手足是你一生的重要变量。" }
        else { sib = "比劫有根：手足缘分正常，一两个兄弟姐妹的信息，同辈之间守望相助型。" }
        out.append(item("兄弟姐妹", sib, "比劫合计 \(bi)；月柱 \(ch.monthPillar)",
            "比劫为手足星、月柱为兄弟宫（六亲通说）；个数为传统口径参考"))

        // 健康
        let organ = ["木": "肝胆与筋骨", "火": "心脑血管与眼睛", "土": "脾胃与肌肉", "金": "肺与呼吸道、皮肤", "水": "肾与泌尿、耳朵"]
        let orderW = pct.indices.sorted { pct[$0] < pct[$1] }
        let weakest = wxN[orderW.first!], strongest = wxN[orderW.last!]
        var health = "五行最弱的是\(weakest)，先天短板在\(organ[weakest]!)一线，平时的保养重点放这里；最旺的是\(strongest)，过旺也会压人，\(organ[strongest]!)的负担同样要留意。"
        if shi >= 3 && cai >= 3 && level == "偏弱" { health += "另有食伤财连环泄身之象：代谢与内分泌的慢性消耗要早防，作息比补品重要。" }
        out.append(item("健康倾向", health,
            "五行占比 " + (0..<5).map { "\(wxN[$0])\(Int(pct[$0].rounded()))" }.joined(separator: " ") + "；日主\(level)",
            "五行配脏腑（《素问》＋命理通说）；只给部位倾向，不落病名"))

        // 寿元关口（守年）
        var gates: [String] = []
        let startY = max(ch.birthYear + 40, Calendar.current.component(.year, from: Date()))
        for y in startY...(ch.birthYear + 92) {
            let r = YearEngine.report(chart: ch, year: y)
            if r.level == "关口级" { gates.append("\(y) 年（\(r.gz)，\(y - ch.birthYear) 岁上下）") }
            if gates.count >= 4 { break }
        }
        let gateText = gates.isEmpty
            ? "从中年往后逐年扫到九十余岁，没有出现双重强引动叠在要害宫位的年份——寿元这条线盘面给的是平稳信号，守成即可。"
            : "逐年扫下来，这些年份引动最重，是传统说的关口年：\(gates.joined(separator: "；"))。关口年的过法就三条：当年不冒进、不做不可逆的大决定、体检与作息提前安排。能扫出来，就是为了避开，不是为了吓人。"
        out.append(item("寿元关口", gateText,
            "逐年四查（流年×大运×原局引动），关口级＝两项以上强引动同现",
            "应期引动法（纪律：冲提纲、动日柱、岁运并临同凶才列关口）；只列年份不预言寿数"))

        // 贵人人际
        var noble = sha.contains("天乙贵人")
            ? "带天乙贵人：这是命理里第一贵人星——你一生不缺关键时刻拉一把的人，贵人多来自长辈与体制内的人脉，平时要经营、要惜福。"
            : "不带天乙贵人：贵人运不靠天给，靠事后口碑攒——把每件小事做漂亮，就是你的贵人制造机。"
        if yin >= 2 { noble += "印星又有根，长辈缘与师长缘双在线，遇事多问一句长辈不吃亏。" }
        out.append(item("贵人与人际", noble,
            "神煞：\(sha.isEmpty ? "常见贵人星不见" : sha.sorted().joined(separator: "、"))；印星 \(yin)",
            "天乙贵人为贵人总星（《三命通会》神煞论）"))

        // 出行迁移
        var move = sha.contains("驿马")
            ? "带驿马：一生动象足——求学、工作、定居多有迁移变动，越动越活；适合把发展半径放大，不必困守出生地。"
            : "不带驿马：根基型命局，动不如守——在本土深耕的收益大于频繁迁徙，真要动，选岁运冲动之年顺势而动。"
        out.append(item("出行迁移", move,
            "驿马\(sha.contains("驿马") ? "见" : "不见")（按年支/日支三合查）",
            "驿马主走动迁移（神煞通说）"))

        // 置业田宅
        var home = ""
        if pct[2] >= 25 { home = "土气足，田宅缘厚：置业欲强、也置得下，不动产是你最稳的资产形态，买房宜早不宜迟、宜自住兼保值。" }
        else if yin >= 2 { home = "印星主房产凭靠：置业多得长辈助力或政策红利，买房看文书与产权，手续齐全比价格更重要。" }
        else { home = "田宅不是你的强项宫：置业顺其自然，有闲钱再置，不必为买房压垮现金流；租房与置业的福气差不大。" }
        out.append(item("置业田宅", home,
            "土占比 \(Int(pct[2].rounded()))%，印星 \(yin)，财库之地 \(ch.pillars.filter { ["辰", "戌", "丑", "未"].contains($0.last!) }.count) 处",
            "土为田宅之象、印为房产文书（类象通说）"))

        // 名声
        var fame = ""
        if yin >= 2 && shi >= 2 { fame = "印与食伤俱全：这是著书立说、靠专业名声吃饭的配置——作品、口碑、职称就是你的名片，越老越响。" }
        else if guan >= 2 { fame = "名声来自职位与口碑：官星给名分，你的名气和平台绑定，平台越高名越大。" }
        else { fame = "名声不是主打项：你的福气在实利不在虚名，不必追流量与头衔，把事做成就是最好的名声。" }
        out.append(item("名声声誉", fame, cntText,
            "印主名誉凭靠、食伤主表达传播、官主名分（类象通说）"))

        // 晚年
        let timeDiShi = ch.diShi[3]
        var old = ""
        if ["帝旺", "临官", "长生", "冠带"].contains(timeDiShi) { old = "时柱得旺地（\(timeDiShi)）：晚景有靠——子女得力、老本够用、精神有寄托，是越老越稳的盘。" }
        else if ["墓", "绝", "胎"].contains(timeDiShi) { old = "时柱落\(timeDiShi)：晚年要提前布局——钱、房、健康、陪伴四样在中年就要安排好，不指望临时抱佛脚。" }
        else { old = "时柱落\(timeDiShi)：晚景平稳，无大起大落；保持手边有事做、有老友来往，就是最好的晚年。" }
        out.append(item("晚年光景", old,
            "时柱 \(ch.timePillar)，日主在时支处\(timeDiShi)地",
            "时柱为晚景宫，长生十二宫定地势（《三命通会》）"))

        // —— 本轮扩项：颜色数字/方位/注意事项/化解（层级标注从严）——
        let xiIdx: [Int]
        let jiIdx: Int
        switch level {
        case "偏弱": xiIdx = [shengWo, dayWx]; jiIdx = (dayWx + 2) % 5
        case "偏强": xiIdx = [(dayWx + 1) % 5, (dayWx + 2) % 5]; jiIdx = shengWo
        default: xiIdx = [orderW.first!]; jiIdx = orderW.last!
        }
        let xiNames = xiIdx.map { wxN[$0] }.joined(separator: "、")
        let colorMap = ["木": "青、绿", "火": "红、紫、粉", "土": "黄、棕、米", "金": "白、银、浅金", "水": "黑、蓝、深灰"]
        let numMap = ["木": "3、8", "火": "2、7", "土": "5、0（即 10）", "金": "4、9", "水": "1、6"]
        let dirMap = ["木": "东方", "火": "南方", "土": "中宫一带（及西南、东北）", "金": "西方", "水": "北方"]
        let xiColors = xiIdx.map { "\(wxN[$0])主\(colorMap[wxN[$0]]!)" }.joined(separator: "；")
        let xiNums = xiIdx.map { "\(wxN[$0])数 \(numMap[wxN[$0]]!)" }.joined(separator: "；")
        out.append(item("幸运颜色与数字",
            "日常多用这几色最合你：\(xiColors)。穿衣、手机壳、车色、家居点缀都可用，不必全身只穿一色，点缀到位即可。数字上 \(xiNums) 与你相合，选号、楼层、车牌尾数遇上可优先。反过来，\(wxN[jiIdx])色（\(colorMap[wxN[jiIdx]]!)）是你的忌向，大面积长期使用少一些。先把层级说清：这条是民间象征层的用法——图的是提醒与心安，不是典籍断法，别为它花高价买『开运物』。",
            "喜用五行 \(xiNames)；忌向 \(wxN[jiIdx])（身\(level)口径，与喜忌条同源）",
            "数字出《周易·系辞》河图五行数（一六水、二七火、三八木、四九金、五十土）；颜色为五行配色通说；取用属民间象征层，标注使用"))

        // 适合方位
        let xiDirs = xiIdx.map { "\(wxN[$0])主\(dirMap[wxN[$0]]!)" }.joined(separator: "；")
        out.append(item("适合方位",
            "你的喜用方位：\(xiDirs)。落到生活里：求学、求职、定居选城市，先看出生地往哪个喜用方向走；书桌与办公位朝向、床头方向，也优先朝喜用方位。忌向是\(wxN[jiIdx])主\(dirMap[wxN[jiIdx]]!)，长期定居与重大发展尽量避开纯忌向。这条属流派应用层——取方位之势帮扶喜用；屋内具体的门床灶吉凶另有八宅与飞星法，在风水模块里按宅盘算，不拿这一条代替。",
            "喜用五行 \(xiNames)；日主 \(ch.rizhu)，身\(level)",
            "五行配方位（木东、火南、土中、金西、水北）为《尚书·洪范》以降通说；以喜用定方位属流派应用层"))

        // 注意事项
        var notes: [String] = []
        let groupVals = [("官杀", guan), ("印星", yin), ("财星", cai), ("食伤", shi), ("比劫", bi)]
        let topGroup = groupVals.max { $0.1 < $1.1 }!.0
        let excessText = ["官杀": "注意一：压力与评价是你的暗耗——忌在高压下硬扛到透支，该分出去的责任要分。",
                          "印星": "注意一：想得多、做得少是你的暗耗——忌无限准备，方案定了七成就先动起来。",
                          "财星": "注意一：钱与机会是你的暗耗——忌贪多求快、忌为人情破财，账要算在前面。",
                          "食伤": "注意一：嘴与锋芒是你的暗耗——忌话说太满、得罪人不自知，重要的话先过夜再说。",
                          "比劫": "注意一：合伙与冲动是你的暗耗——忌担保、忌共同账户，钱的事一律白纸黑字。"][topGroup]!
        notes.append(excessText)
        notes.append("注意二：\(weakest)弱是先天短板（\(organ[weakest]!)一线），这一项写进每年的固定体检单，别等有感觉了才查。")
        let nowY = Calendar.current.component(.year, from: Date())
        var nearGate: String? = nil
        for y in nowY...(nowY + 5) {
            let r = YearEngine.report(chart: ch, year: y)
            if r.level == "关口级" { nearGate = "\(y) 年（\(r.gz)）"; break }
        }
        if let ng = nearGate { notes.append("注意三：最近的关口年是 \(ng)，那年按守年过——不冒进、不做不可逆的大决定、体检提前安排。") }
        else { notes.append("注意三：近六年逐年扫下来没有关口级年份，节奏平稳，可以按主线年放心推进大事。") }
        if sha.contains("桃花") { notes.append("注意四：带桃花，人缘是双刃——已婚或有伴后，异性往来的边界要立在明处。") }
        if sha.contains("驿马") { notes.append("注意四：带驿马，一生动象多——出行与交通安全是常年课题，忌疲劳驾驶、忌赶夜路。") }
        out.append(item("注意事项", notes.joined(separator: ""),
            "主导十神组 \(topGroup)；最弱五行 \(weakest)；近六年关口扫描 \(nearGate ?? "无")；神煞 \(sha.sorted().joined(separator: "、"))",
            "过用之弊按主导十神取象（类象通说）；关口年按逐年四查定级；健康只给体检提醒、不落病名"))

        // 如何化解（破局五层，工作室定版口径）
        let branchWx: [Character: Int] = ["子": 4, "丑": 2, "寅": 0, "卯": 0, "辰": 2, "巳": 1, "午": 1, "未": 2, "申": 3, "酉": 3, "戌": 2, "亥": 4]
        let xiSet = Set(xiIdx)
        var buYun: [String] = []
        for i in ch.dayunGanZhi.indices {
            let gz = ch.dayunGanZhi[i]
            if xiSet.contains(wxIdx(gz.first!)) || xiSet.contains(branchWx[gz.last!]!) {
                buYun.append("\(gz)运（\(ch.dayunStartYear(i))–\(ch.dayunStartYear(i) + 9)）")
            }
        }
        var buText: String
        if !buYun.isEmpty { buText = "补得到喜用\(xiNames)的大运是 \(buYun.prefix(2).joined(separator: "、"))——那是你命里的回血期，升学、创业、婚嫁、置业这类大事，优先压到这些十年里办。" }
        else {
            var yrs: [String] = []
            for y in nowY...(nowY + 10) {
                let gz = BaziChart.yearGanZhi(y)
                if xiSet.contains(wxIdx(gz.first!)) { yrs.append("\(y)（\(gz)）") }
                if yrs.count >= 3 { break }
            }
            buText = "大运里没有整步直补喜用\(xiNames)的，靠流年小补：\(yrs.isEmpty ? "近十年流年天干亦少见直补，以守势积累为主" : yrs.joined(separator: "、") + " 这几年天干带喜用，是借势推进的窗口")。"
        }
        var realRules: [String] = ["把\(organ[weakest]!)一线写进年度体检固定项"]
        if bi >= 3 { realRules.append("合伙与借贷一律先立字据再谈感情") }
        if level == "偏弱" && cai >= 3 { realRules.append("钱不贪大、杠杆不上，先练承载再谈扩张") }
        if shi >= 3 { realRules.append("重要表态与决定先过夜，次日再发") }
        realRules.append("关口年守三条：不冒进、不做不可逆决定、体检提前")
        let hua = "先说典籍的实话：命里的『病』，典籍只负责断出来，『药』不靠摆件求、靠岁运带来——人能用的典籍手段只有择时进退。【时间表】\(buText)【修身路】《了凡四训》的路子：改过、积善、谦德——命数之外，日用行为能改的那一半在这条路上，与任何物品无关。【借势路】行业、城市、方位往喜用\(xiNames)靠（见事业方向、适合方位），取其势帮扶。【象征路】颜色、数字、佩饰按喜用取（见幸运颜色与数字），这是民间象征层，图提醒与心安，别花高价买『开运物』。【现实路】真正落地的是这几条：\(realRules.joined(separator: "；"))。"
        out.append(item("如何化解（破局调理）", hua,
            "喜用 \(xiNames)；大运序列 \(ch.dayunGanZhi.joined(separator: " "))；最弱 \(weakest)；十神计数 \(cntText)",
            "破局五层法（工作室 2026-10-30 调研定版）：五典病药是诊断学不是治疗学，药靠原局与岁运；典籍伦理层出《了凡四训》；方位行业为流派应用层；颜色数字佩饰为民间象征层——五层分开标注，不混卖"))
        return out
    }
}
