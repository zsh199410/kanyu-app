import SwiftUI

struct LearningTerm: Identifiable {
    let name: String
    let meaning: String
    var id: String { name }
}

struct LearningTopic: Identifiable {
    let id: String
    let title: String
    let summary: String
    let steps: [String]
    let terms: [LearningTerm]
}

enum SearchText {
    static func matches(_ query: String, in text: String) -> Bool {
        let locale = Locale(identifier: "zh_CN")
        let haystack = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: locale)
        let words = query.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: locale)
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        return words.allSatisfy { haystack.contains($0) }
    }
}

/// Original educational copy. Definitions explain the method; they are not additional chart predictions.
enum LearningContent {
    static let readingOrder = "先核对出生时间、地点和排盘口径，再读结论；展开盘面依据，查看它为什么这样判断；最后结合现实经历核验。不同术数意见不一致时保留分歧，不用条目数量投票。"
    static let topics: [LearningTopic] = [
        .init(id: "bazi", title: "八字：先认清自己，再看关系", summary: "四柱是一套时间与关系的传统表达。先看日主和月令，再看整体组合，最后叠加大运流年。", steps: [
            "核对输入：公历或农历、出生年月日时、出生地经度、是否启用真太阳时。时辰边界附近要比较校正前后，而不是只看最终盘。",
            "找日主：日柱上面的天干代表这套分析的参照点。十神描述其余干支与日主的关系，不是十种固定的人品标签。",
            "看整体：月令是季节背景，藏干说明地支内部的组成。五行百分比是算法摘要，不能只凭数量最多就认定最好，也不能把缺少某行直接当成需要补充。",
            "看时间：原局描述基础关系，大运看阶段，流年看年度叠加。把提到的年份与真实事件对照，记录符合与不符合的地方。"
        ], terms: [
            .init(name: "日主", meaning: "日柱的天干，是判定十神关系的参照点。例如甲日主与其他天干的生克关系，和丙日主的关系不同。"),
            .init(name: "月令", meaning: "出生月地支所代表的季节背景。相同五行在不同季节的表现不同，因此不能只数出现次数。"),
            .init(name: "十神", meaning: "以日主为中心，将同类、生我、我生、克我、我克分成阴阳不同的十种关系。它们是分析语言，不能单独等同职业、财富或品德。"),
            .init(name: "喜用", meaning: "某种取用方法下，认为有助于调节命局的因素。扶抑、调候、格局的出发点不同，结论可能不同，需要看明白采用的口径。"),
            .init(name: "大运", meaning: "传统排盘中通常按十年划分的阶段。具体起运时刻要看出生时间、性别和顺逆规则，不能统一按整数年龄起算。"),
            .init(name: "流年", meaning: "某一年的干支背景。应与原局和大运一起看，不能只凭单个字相冲，就认定一定发生某件事。")
        ]),
        .init(id: "ziwei", title: "紫微：从宫位读到组合", summary: "先认识十二宫讨论什么，再看主星、三方四正与四化；最后区分本命和阶段盘。", steps: [
            "核对农历日期、闰月归属和晚子时规则。与其他软件不同，先检查口径是否一致，再判断安星是否有误。",
            "先读命宫的基本结构，再选择事业、财帛、夫妻等具体主题。宫名是讨论范围，不是对人生某一方面的最终判决。",
            "把本宫与三方四正一起看；同一星曜落不同宫位、与不同星曜组合，解释会变化。不要把一颗星的通用说明当成完整解盘。",
            "区分生年四化、大限与流年四化；确认当前展示的时间层。遇到不同流派解释，保留来源与设置。"
        ], terms: [
            .init(name: "命宫", meaning: "紫微十二宫之一，常作为阅读本命整体倾向的起点。它仍需要结合其他宫位和星曜关系。"),
            .init(name: "三方四正", meaning: "以一个宫位为中心，连同三合位置和对宫一起观察的结构。用途是避免只看单宫、单星。"),
            .init(name: "四化", meaning: "禄、权、科、忌是传统分析的四种变化标记。化忌不等于必然灾祸，应区分由哪个天干引发、落在哪里及对应时间。"),
            .init(name: "大限", meaning: "紫微用于划分阶段的时间层，通常一个阶段十年；不要与本命盘、流年盘混为一张结论。")
        ]),
        .init(id: "qimen", title: "奇门：先明确问题和起局规则", summary: "奇门需要具体问题、明确时刻和可追踪的起局方法。盘面符号必须放回问题语境中解释。", steps: [
            "先写清想比较的事项、时间范围和已知条件。比如比较两个出行方案，比笼统地问未来好不好更容易回验。",
            "核对起局时刻、经度和真太阳时，记录拆补或置闰、阴阳遁、局数、中宫寄宫等设置。不同规则的盘不能直接逐格比较。",
            "先定位与问题相关的用神和落宫，再看星、门、神、天盘干与地盘干的关系；不要从一个好门或坏格局直接跳到成败。",
            "把推断、依据和不确定项分别写下，约定回验日期。后续出现新事实时更新判断，保留最初记录便于比较。"
        ], terms: [
            .init(name: "值符", meaning: "当局中领头的星及相关定位信息。阅读时要分清值符星、值符落宫和八神中的值符，不要混用字段。"),
            .init(name: "值使", meaning: "当局中领头的门。其落宫与推移方法取决于起局规则，需要与起局收据一起核对。"),
            .init(name: "拆补", meaning: "按节气和三元划分定局的一种方法，与置闰法存在口径差异；不能因为两种方法结果不同就断定其中一方计算错误。"),
            .init(name: "置闰", meaning: "通过闰奇等规则协调节气与符头的定局方法。对照案例时需要同时记录日期、节气、三元和局数。")
        ]),
        .init(id: "compass", title: "罗盘：先测可靠，再谈坐向", summary: "手机罗盘首先是一种传感器测量。记录读数、参照方向和误差，比多显示几层盘更重要。", steps: [
            "远离车辆、电器、磁吸壳与金属构件，允许定位；按提示校准设备，水平放置，等待读数稳定。",
            "分清磁北和真北：磁北跟随当地地磁，真北指向地理北极。磁偏角用于两者换算，记录采用设备校正还是模型校正。",
            "说明测量动作：站在哪、面向哪、读的是坐山还是朝向。大门外朝内与朝外通常应接近相差 180°，不能把同一个角度混作两种方向。",
            "连续多点复测，记录精度、倾斜和集中度。边界附近应保留误差范围并提示复测，不能为了显示山名就隐藏测量不确定性。"
        ], terms: [
            .init(name: "真北", meaning: "相对地理北极的北向，与地图的地理方位一致；设备未取得可靠真北时，应明确展示校正来源。"),
            .init(name: "磁偏角", meaning: "当地磁北相对真北的角度差，随位置和时间变化。东偏西偏的正负号需要与程序采用的换算公式一致。"),
            .init(name: "二十四山", meaning: "把一周分成二十四段、每段约十五度的传统方向分类。分界附近的小误差可能改变山名，必须结合测量精度阅读。"),
            .init(name: "坐向", meaning: "坐与向是相反的两个方向，相差 180°。本项目将大门外朝内的真北读数作为坐山输入，记录时应说明测量动作。")
        ]),
        .init(id: "fengshui", title: "堪舆：让现场事实与传统分析分开", summary: "先完成测量、照片和户型记录，再运行玄空或八宅分析。现场事实应当可复核。", steps: [
            "新建案件，记录建筑用途、建成年、入住年和重大装修年。元运取法存在差异，报告应说明实际采用的年份。",
            "多点定向后采集门口、明堂、房后及周边照片；需要 AR 或 RoomPlan 时，记录设备支持情况与扫描质量。",
            "户型图先核比例、方位与立极点。图纸叠加罗盘不会自动修正错误比例，也不能替代现场尺寸复核。",
            "解读时区分玄空飞星、八宅和形势记录。通风、采光、动线、消防和结构安全等现实条件应单独检查；传统象义不替代工程结论。"
        ], terms: [
            .init(name: "立极", meaning: "为户型或区域确定分析中心与方向参照。中心点或范围选择不同，压盘结果可能不同，应保留底图与操作记录。"),
            .init(name: "元运", meaning: "玄空等方法使用的时期划分。建筑以建成、入住还是大修时间立运，需要先确定取法，不能只为匹配结论而更换年份。"),
            .init(name: "飞星", meaning: "按照特定顺逆与宫位次序排列九星的方法。核对时须同时确认运盘、山盘、向盘及其顺逆依据。"),
            .init(name: "八宅", meaning: "以宅卦、命卦等建立方位关系的传统方法，与玄空使用不同规则；两者结论应分栏阅读，不直接相加评分。")
        ]),
        .init(id: "reading", title: "解盘：读懂结论为何成立", summary: "每一项都按结论、依据、解释、适用范围和回验来读。条目多不等于证据充分。", steps: [
            "先读该条在讨论什么，再看本盘实际有哪些干支、宫位或关系被引用。通用术语释义不等于针对本人的判断。",
            "展开作用机制与依据链，核对使用的是哪种取用或流派；多项依据若都来自同一条规则，不能当成多份独立证据。",
            "看时间范围：原局倾向、阶段变化和某年触发条件是不同层次。条件未满足或出生时刻不确定时，应保留判断。",
            "记录自己的经历与后续结果，也记录不符合的案例。个人勾选属于主观反馈，不能直接当成算法准确率或未来事件概率。"
        ], terms: [
            .init(name: "依据链", meaning: "把输入数据、计算出的盘面关系和解释规则连接起来的记录。可以帮助复核推理，但不等于证明预测一定实现。"),
            .init(name: "候选格局", meaning: "满足部分规则、仍需要结合其他条件复核的分析候选。候选一词表示尚不能直接定格。"),
            .init(name: "回验", meaning: "按事先约定的时间与标准，对照实际结果，记录符合、不符合以及信息不足的情况。先写判断再看结果，可以减少事后解释偏差。")
        ]),
        .init(id: "report", title: "报告：从输入核对到分享复核", summary: "简洁版抓重点，专业版保留完整结论，完整版增加逐项依据和术语解释。", steps: [
            "导出前核对人物、生辰、经度、时间校正和排盘口径。同名人物要再次核对，避免把别人的报告用于当前档案。",
            "按用途选档：简洁版用于快速阅读，专业版用于逐项理解，完整版用于复核依据与方法。内容哈希帮助比较内容，不表示预测正确。",
            "打开生成的 PDF 检查姓名、目录、页码、长段落和末页是否完整。分享前检查是否包含不希望公开的出生资料。",
            "临时文件可能被系统清理，重要报告请用系统分享保存到文件或另行备份。报告中心的历史列表不能代替独立备份。"
        ], terms: [
            .init(name: "排盘口径", meaning: "计算时采用的时间、历法与流派规则，例如晚子时换日、闰月归属和真太阳时。比较软件结果时，先把这些设置对齐。"),
            .init(name: "内容哈希", meaning: "对规范化报告内容计算的指纹，用于识别内容是否变化。哈希相同不代表预测有效，也不是身份认证。")
        ])
    ]

    static var terms: [LearningTerm] { topics.flatMap { $0.terms } }
    static func terms(in text: String) -> [LearningTerm] { terms.filter { text.contains($0.name) } }
    static func search(_ query: String) -> [LearningTopic] {
        topics.filter { SearchText.matches(query, in: ([$0.title, $0.summary] + $0.steps + $0.terms.map { $0.name + $0.meaning }).joined(separator: " ")) }
    }
}

struct LearningCenterView: View {
    @State private var query = ""
    private var matchingTools: [ToolItem] {
        AllToolsData.allItems.filter { item in
            SearchText.matches(query, in: item.title + " " + item.desc + " " + (ToolHelpContent.entries[item.id] ?? []).joined(separator: " "))
        }
    }
    var body: some View {
        List {
            Section {
                Text(LearningContent.readingOrder.scriptConverted)
                    .font(.body).lineSpacing(5).textSelection(.enabled)
            } header: { Text("先读懂，再判断") }
            ForEach(LearningContent.search(query)) { topic in
                Section {
                    Text(topic.summary.scriptConverted).font(.body).lineSpacing(4)
                    ForEach(Array(topic.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)").font(.body.monospacedDigit().weight(.semibold)).foregroundStyle(Ky.qingdai)
                            Text(step.scriptConverted).font(.body).lineSpacing(5).textSelection(.enabled)
                        }.padding(.vertical, 4)
                    }
                    DisclosureGroup("术语白话解释（\(topic.terms.count) 项）") {
                        ForEach(topic.terms) { term in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(term.name.scriptConverted).font(.headline)
                                Text(term.meaning.scriptConverted).font(.body).lineSpacing(4).textSelection(.enabled)
                            }.padding(.vertical, 6)
                        }
                    }
                } header: { Text(topic.title.scriptConverted).font(.headline) }
            }
            Section("全部工具的使用说明") {
                ForEach(matchingTools) { item in
                    NavigationLink { ToolHelpView(item: item) } label: {
                        Label(item.title.scriptConverted, systemImage: item.icon)
                            .font(.body).padding(.vertical, 4)
                    }
                }
            }
            if LearningContent.search(query).isEmpty && matchingTools.isEmpty {
                Text("没有找到相关内容，试试“真北”“四化”或“大运”。")
                    .foregroundStyle(.secondary)
            }
        }
        .searchable(text: $query, prompt: "搜功能、术语或问题")
        .navigationTitle("白话使用指南")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("learning.center")
    }
}

struct ReadingHelpView: View {
    let text: String
    var body: some View {
        let terms = LearningContent.terms(in: text)
        if !terms.isEmpty {
            DisclosureGroup("读懂术语（\(terms.count) 项）") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(terms) { term in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(term.name.scriptConverted).font(.headline)
                            Text(term.meaning.scriptConverted).font(.body).lineSpacing(4).textSelection(.enabled)
                        }
                    }
                }.padding(.top, 8)
            }
        }
    }
}
