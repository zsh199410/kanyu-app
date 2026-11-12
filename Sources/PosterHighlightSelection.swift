import Foundation

/// Poster-only editorial selection. Full interpretations are not rewritten or
/// deleted: the source engine, interpretation screen and PDF remain unchanged.
enum PosterHighlightSelection {
    /// Returns a clearly abbreviated extract from the *existing* conclusion.
    /// It never adds new personal predictions or changes numeric chart fields.
    static func excerpt(_ original: String, maxCharacters: Int = 88) -> String {
        let compact = original.split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !compact.isEmpty else { return "" }
        let chars = Array(compact)
        let cap = max(24, maxCharacters)
        guard chars.count > cap else { return compact }
        let stops: Set<Character> = ["。", "！", "？", "；"]
        let sentenceEnd = chars.prefix(cap).enumerated()
            .first(where: { $0.offset >= 16 && stops.contains($0.element) })
            .map { $0.offset + 1 }
        let length = sentenceEnd ?? cap
        let text = String(chars.prefix(length)).trimmingCharacters(in: .whitespacesAndNewlines)
        // Ellipsis explicitly declares a partial extract, rather than
        // presenting the first sentence as the full interpretation.
        return length < chars.count ? text + "…" : text
    }

    private static let plainTitles: [String: String] = [
        "命局风景": "命盘整体",
        "喜忌（扶抑初判）": "五行喜忌（初判）",
        "岁运要点": "年份变化",
        "性格性情": "性格特点",
        "事业方向": "事业方向",
        "财运形态": "财务主题",
        "婚姻感情": "感情关系",
        "贵人与人际": "人际与助力",
        "天赋能力": "个人优势",
        "工作形态": "工作方式",
        "学业文书": "学习与考试",
        "置业田宅": "居住与房产",
        "健康倾向": "生活与健康提醒",
        "幸运颜色与数字": "传统颜色与数字",
        "适合方位": "传统方位"
    ]

    private static let coreTitles = [
        "命局风景", "喜忌（扶抑初判）", "岁运要点"
    ]
    private static let lifeTitles = [
        "性格性情", "事业方向", "财运形态", "婚姻感情", "贵人与人际"
    ]
    private static let premiumTitles = [
        "天赋能力", "工作形态", "学业文书", "置业田宅", "健康倾向"
    ]
    private static let cultureTitles = [
        "幸运颜色与数字", "适合方位"
    ]

    private static func selected(_ titles: [String], from items: [InterpretItem],
                                 group: String) -> PosterBoundSection? {
        let entries: [PosterBoundField] = titles.compactMap { title in
            guard let item = items.first(where: { $0.title == title }) else { return nil }
            let value = excerpt(item.conclusion)
            guard !value.isEmpty else { return nil }
            return .init(id: "highlight." + title, label: plainTitles[title] ?? title, value: value,
                         source: "InterpretEngine.interpret · " + title)
        }
        return entries.isEmpty ? nil
            : PosterBoundSection(id: "highlight." + group, title: group, fields: entries)
    }

    static func baziSections(chart: BaziChart, items: [InterpretItem],
                             pillars: [PosterBoundField],
                             elements: [PosterBoundField],
                             premium: Bool) -> [PosterBoundSection] {
        var result: [PosterBoundSection] = []
        if !pillars.isEmpty {
            result.append(.init(id: "pillars", title: "四柱命盘", fields: pillars))
        }
        if !elements.isEmpty {
            result.append(.init(id: "elements", title: "五行分布", fields: elements))
        }
        // Use the current decade and adjacent periods from the original
        // chart, rather than showing unrelated childhood periods as 'current'.
        if !chart.dayunGanZhi.isEmpty {
            let thisYear = Calendar(identifier: .gregorian).component(.year, from: Date())
            let starts = chart.dayunGanZhi.indices.map { chart.dayunStartYear($0) }
            let active = starts.lastIndex(where: { $0 <= thisYear }) ?? 0
            let lower = max(0, active - 1)
            let upper = min(chart.dayunGanZhi.count, lower + (premium ? 4 : 3))
            let fields: [PosterBoundField] = (lower..<upper).map { i in
                PosterBoundField(id: "dayun." + String(i),
                                 label: "\(chart.dayunStartYear(i)) 年起",
                                 value: chart.dayunGanZhi[i],
                                 source: "BaziChart.dayunGanZhi")
            }
            result.append(.init(id: "dayun", title: "大运节点", fields: fields))
        }
        if let core = selected(coreTitles, from: items, group: "这张盘的重点") { result.append(core) }
        if let life = selected(lifeTitles, from: items, group: "生活主题速览") { result.append(life) }
        if premium, let depth = selected(premiumTitles, from: items, group: "尊享补充重点") {
            result.append(depth)
        }
        if let culture = selected(cultureTitles, from: items, group: "传统颜色与方位") {
            result.append(culture)
        }
        return result
    }
}
