import SwiftUI

/// Readability overlay only. The traditional engine conclusion and evidence chain remain intact.
enum InterpretReadability {
    static let guides: [String: String] = [
        "命局风景": "先看整张命盘里的五行与十神是怎样组合的。它是传统规则中的概览，不是给人贴性格标签。",
        "月令格局（候选）": "看出生月份对传统格局分类有什么影响。这里是候选判断，不等于已确定格局。",
        "喜忌（扶抑初判）": "看传统扶抑法认为哪些五行偏需要、哪些可能过多。初判不是最终结论。",
        "十神看点": "把十神理解成不同生活主题的代号，例如责任、学习、表达与资源。",
        "岁运要点": "这里按传统历法讨论不同时间段的变化主题，不保证现实事件会发生。",
        "性格底色": "把这段当作传统性格象征解读，挑出可自我观察的部分即可。",
        "事业方向": "解读的是传统十神对应的工作方式，不是职业测评或录用预测。",
        "工作形态": "重点看独立工作、协作和规则环境等传统象征，实际仍以经验与能力为准。",
        "学业与文凭": "看传统规则里与学习有关的符号，不能预测具体成绩或证书。",
        "学业文书": "这里讨论学习、考试和文书事务的传统取象，不是考试结果保证。",
        "财运形态": "讲的是传统财星和收支风格的对应关系，不是收入或投资收益预测。",
        "置业田宅": "这里解释田宅相关的传统象征，不能代替预算、产权或房屋评估。",
        "名声声誉": "看传统命理对公众评价和职业口碑的象征，不是现实成名预测。",
        "行业赛道深断": "将传统十神组合翻译成几类工作场景，供了解术数思路使用。",
        "财富量级蓄水池": "财星、财库都是传统术语，不代表银行余额、财富级别或投资建议。",
        "婚姻感情": "解读传统关系符号，不能用来判断另一人的性格或关系是否成功。",
        "子女": "这里是传统子女主题的象征说法，不可预测生育结果。",
        "子女缘分": "与子女相关的命理语言是文化解释，不等于现实亲子关系判断。",
        "父母缘分": "侧重传统的家庭互动符号，不代表父母实际情况。",
        "兄弟同辈": "看同辈合作、竞争等传统取象，现实关系要以具体相处为准。",
        "兄弟姐妹": "不能依据命盘确定兄弟姐妹人数、健康或关系好坏。",
        "贵人与人际": "所谓贵人是传统帮助与机会的比喻，现实中仍要看具体的人和事。",
        "出行迁移": "把它理解成对移动、求学和搬迁的传统象征解释。",
        "六亲情境深读": "把家庭缘分分成相处情况和情感感受，不把命理符号当作事实。",
        "健康倾向": "传统五行与身体的对应不是医学诊断。身体问题请依据医学检查。",
        "中老年守年": "这里给出传统守年提醒，不代表寿命或疾病预测。",
        "晚年光景": "这是一种传统晚年象征解读，不等于实际生活质量判断。",
        "幸运颜色与数字": "颜色与数字属于民俗象征，可作个人审美选择，不会改变客观运气。",
        "适合方位": "方位与五行的关联属于传统体系，不替代工作、交通或房屋决策依据。",
        "注意事项": "将传统提醒理解为一般生活规划建议，不要凭命盘作医疗或财务决定。",
        "如何化解（破局调理）": "所谓化解不代表能改变客观命运；优先采用有现实依据的可执行行动。"
    ]

    static func guide(for title: String) -> String {
        guides[title] ?? "下面用简单语言介绍传统命理的这一主题，并保留完整盘面依据供核对。"
    }

    static func firstSentence(of original: String) -> String {
        let cleaned = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "本项暂无可展示的解读。" }
        let first = cleaned.components(separatedBy: CharacterSet(charactersIn: "。！？；\n")).first ?? cleaned
        let preview = String(first.prefix(100))
        return preview + (first.count > 100 ? "……" : "。")
    }

    static func narration(title: String, conclusion: String) -> String {
        "现在讲的是\(title)。先说这项是什么意思。\(guide(for: title))本盘原文提示：\(conclusion)"
    }
}

struct InterpretPlainIntro: View {
    let item: InterpretItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("一句话看懂", systemImage: "text.bubble")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Ky.qingdai)
            Text(InterpretReadability.guide(for: item.title))
                .font(.body)
                .foregroundStyle(Ky.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("本盘原文先看这一句：")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Ky.sub)
            Text(InterpretReadability.firstSentence(of: item.conclusion))
                .font(.body)
                .foregroundStyle(Ky.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("下方保留完整传统解读和依据；这不是已验证的现实预测。")
                .font(.caption)
                .foregroundStyle(Ky.sub)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ky.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
