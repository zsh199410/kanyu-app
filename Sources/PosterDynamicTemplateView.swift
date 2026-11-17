import SwiftUI

// Read-only data binding for four poster types. Never parses sample JPEG text.
enum PosterDynamicKind: String {
    case palm, bazi, ziwei, premium
    var title: String {
        switch self {
        case .palm: return "手相个人指南"
        case .bazi: return "八字古风长卷"
        case .ziwei: return "紫微星曜图鉴"
        case .premium: return "尊享预测单"
        }
    }
    var ink: Color {
        switch self {
        case .palm: return Color(red: 0.14, green: 0.32, blue: 0.38)
        case .bazi: return Color(red: 0.39, green: 0.28, blue: 0.19)
        case .ziwei: return Color(red: 0.17, green: 0.27, blue: 0.43)
        case .premium: return Color(red: 0.55, green: 0.23, blue: 0.19)
        }
    }
    var paper: Color {
        switch self {
        case .palm: return Color(red: 0.974, green: 0.963, blue: 0.927)
        case .bazi: return Color(red: 0.974, green: 0.944, blue: 0.89)
        case .ziwei: return Color(red: 0.915, green: 0.933, blue: 0.949)
        case .premium: return Color(red: 0.965, green: 0.943, blue: 0.895)
        }
    }
}
struct PosterBoundField: Identifiable {
    let id: String
    let label: String
    let value: String
    let source: String
}
struct PosterBoundSection: Identifiable {
    let id: String
    let title: String
    let fields: [PosterBoundField]
}

// Batch 2 P0：快照图片资产。只记来源与校验摘要，不只存易失路径；
// 手相照片走本结构，八字/紫微/尊享为矢量渲染、imageAssets 为空。
struct PosterImageAsset: Identifiable {
    let id: String
    /// 资产种类：photo（原始照片）/ diagram（矢量图示）。
    let kind: String
    /// 稳定来源路径，如 PalmPhotos/<record-id>.jpg（相对 Documents，不含绝对路径）。
    let sourcePath: String
    /// 校验摘要（SHA256 前 12 位十六进制）；导出时计算，未计算为 nil。
    let checksum: String?
    /// 许可/来源说明，如“用户拍摄并授权本机使用”。
    let note: String
}

// Batch 2 P0：缺失字段。blocking 为真时禁止正式导出（见 canArchive）。
struct PosterMissingField: Identifiable {
    let id: String
    let label: String
    /// true＝正式导出必需、缺失即禁导出；false＝可选、缺失只显示缺失态。
    let blocking: Bool
}

// Batch 2 P0：异步导出隔离令牌。启动导出时固定 personID＋record IDs＋版本，
// 回调时用 matches 校验当前选中是否仍为同一人、同一批记录；不一致即丢弃结果，
// 防止快速切换人物后把上一人的导出写成当前人的。
struct PosterExportTask {
    let personID: UUID?
    let recordIDs: [String]
    let versions: [String: String]
    let createdAt: Date
    func matches(personID: UUID?, recordIDs: [String], versions: [String: String]) -> Bool {
        self.personID == personID && self.recordIDs == recordIDs && self.versions == versions
    }
}
struct PosterDynamicSnapshot {
    let kind: PosterDynamicKind
    let ownerID: UUID?
    let displayName: String
    let receipt: String
    let sections: [PosterBoundSection]
    let caution: String
    // Batch 2 P0：通用快照补齐的 5 个字段（规范建议 PosterSnapshot 的完整等价物）。
    /// 快照生成时刻（冻结快照的生成时间，与 receipt 里的出生钟表时间不同）。
    let generatedAt: Date
    /// 结构化来源记录 ID，如 ["Person:<uuid>", "BaziChart:<指纹>", "PalmRecord:<uuid>"]。
    let sourceRecordIDs: [String]
    /// 来源版本：键→不可变记录版本或内容指纹，如 ["baziSect": "1", "interpret": "30条"]。
    let sourceVersions: [String: String]
    /// 图片资产（手相照片；矢量渲染的三款为空）。
    let imageAssets: [PosterImageAsset]
    /// 缺失字段；blocking 为真时 canArchive 为 false。
    let missingFields: [PosterMissingField]
    /// 尊享幸运数字/颜色（单一权威：InterpretEngine.luckyNumbersColors）；仅 premium 有值。
    let lucky: PosterLucky?

    static func bazi(person: Person, chart: BaziChart, premium: Bool) -> Self {
        let items = InterpretEngine.interpret(chart: chart)
        func item(_ title: String, _ key: String) -> PosterBoundField {
            let answer = items.first(where: { $0.title == title })?.conclusion ?? ""
            return .init(id: key, label: title,
                         value: answer.isEmpty ? "暂无结果" : answer,
                         source: "InterpretEngine.interpret: " + title)
        }
        let names = ["年柱", "月柱", "日柱", "时柱"]
        let pillars = names.enumerated().map { i, label in
            PosterBoundField(id: "pillar.\(i)", label: label,
                             value: chart.pillars.indices.contains(i) ? chart.pillars[i] : "暂无结果",
                             source: "BaziChart.pillars")
        }
        let elements = ["木", "火", "土", "金", "水"].enumerated().map { i, label in
            PosterBoundField(id: "element.\(i)", label: label,
                             value: chart.wuxingPercents.indices.contains(i)
                                 ? String(format: "%.1f%%", chart.wuxingPercents[i]) : "暂无结果",
                             source: "BaziChart.wuxingPercents")
        }
        let years = chart.dayunGanZhi.prefix(premium ? 8 : 6).enumerated().map { i, value in
            PosterBoundField(id: "dayun.\(i)",
                             label: "\(chart.dayunStartYear(i)) 年起",
                             value: value, source: "BaziChart.dayunGanZhi")
        }
        var sections = [
            PosterBoundSection(id: "pillars", title: "四柱命盘", fields: pillars),
            PosterBoundSection(id: "elements", title: "五行构成", fields: elements),
            PosterBoundSection(id: "dayun", title: "十年大运", fields: years),
            PosterBoundSection(id: "reading", title: "原局解释", fields: [
                item("命局风景", "interpret.overview"),
                item("月令格局（候选）", "interpret.pattern"),
                item("喜忌（扶抑初判）", "interpret.fuyi"),
                // Batch 2：补 interpret() 第 4 条总纲（此前模板未取用）。
                item("十神看点", "interpret.shishen"),
                item("岁运要点", "interpret.yun")]),
            // Batch 2：补 lunarText/节气（此前模板未用；原生预测单收据已有同款字段）。
            PosterBoundSection(id: "receipt", title: "排盘收据", fields: [
                PosterBoundField(id: "receipt.lunar", label: "农历", value: chart.lunarText.isEmpty ? "暂无结果" : chart.lunarText, source: "BaziChart.lunarText"),
                PosterBoundField(id: "receipt.prevJieQi", label: "上一节", value: chart.prevJieQiText.isEmpty ? "暂无结果" : chart.prevJieQiText, source: "BaziChart.prevJieQiText"),
                PosterBoundField(id: "receipt.nextJieQi", label: "下一节", value: chart.nextJieQiText.isEmpty ? "暂无结果" : chart.nextJieQiText, source: "BaziChart.nextJieQiText"),
                PosterBoundField(id: "receipt.xunKong", label: "旬空", value: chart.xunKong.isEmpty ? "暂无结果" : chart.xunKong, source: "BaziChart.xunKong")]),
            // Batch 2：补细盘字段组（取与海报信息架构相符的日主/命宫/身宫/纳音/四干十神）。
            PosterBoundSection(id: "detail", title: "细盘", fields: [
                PosterBoundField(id: "detail.rizhu", label: "日主", value: chart.rizhu.isEmpty ? "暂无结果" : chart.rizhu, source: "BaziChart.rizhu"),
                PosterBoundField(id: "detail.mingGong", label: "命宫", value: chart.mingGong.isEmpty ? "暂无结果" : chart.mingGong, source: "BaziChart.mingGong"),
                PosterBoundField(id: "detail.shenGong", label: "身宫", value: chart.shenGong.isEmpty ? "暂无结果" : chart.shenGong, source: "BaziChart.shenGong"),
                PosterBoundField(id: "detail.naYin", label: "纳音", value: chart.naYin.isEmpty ? "暂无结果" : chart.naYin.joined(separator: "、"), source: "BaziChart.naYin"),
                PosterBoundField(id: "detail.stemShiShen", label: "四干十神", value: chart.stemShiShen.isEmpty ? "暂无结果" : chart.stemShiShen.joined(separator: "、"), source: "BaziChart.stemShiShen")])
        ]
        // Batch 2 P0：尊享幸运数字/颜色的单一权威（InterpretEngine.luckyNumbersColors，
        // 取 interpret() 30 条内的“幸运颜色与数字”结论；原生预测单同调本函数，不再各用各的映射）。
        let lucky: PosterLucky? = premium ? InterpretEngine.luckyNumbersColors(items: items, chart: chart) : nil
        let luckyText: String = {
            guard let l = lucky, l.isVerified, !l.text.isEmpty else { return "来源待核对" }
            return l.text
        }()
        if premium {
            sections.append(.init(id: "deep", title: "尊享深读", fields: [
                item("事业方向", "interpret.career"),
                item("财运形态", "interpret.wealth"),
                item("婚姻感情", "interpret.relationship"),
                PosterBoundField(id: "interpret.lucky", label: "幸运颜色与数字",
                                 value: luckyText,
                                 source: "InterpretEngine.luckyNumbersColors"),
                item("注意事项", "interpret.caution")]))
        }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"
        df.locale = Locale(identifier: "zh_CN")
        df.timeZone = TimeZone(identifier: "Asia/Shanghai")
        // Batch 2 P0：通用快照 5 字段。盘面指纹＝四柱＋出生钟表时间（不可变内容标识）；
        // 版本含 baziSect（缓存键口径）与 interpret 条目数；八字为矢量渲染，imageAssets 为空。
        let chartFingerprint = "BaziChart:\(chart.pillars.joined())-\(Int(chart.birthDate.timeIntervalSince1970))"
        return .init(kind: premium ? .premium : .bazi,
                     ownerID: person.id, displayName: person.name,
                     receipt: "人物 UUID \(person.id.uuidString) · 生日钟表时间 \(df.string(from: person.birthDate))（北京口径）",
                     sections: sections,
                     caution: "仅展示既有引擎的字段和文字；传统命理解读不是已验证的现实预测。此预览不生成文件。",
                     generatedAt: Date(),
                     sourceRecordIDs: ["Person:\(person.id.uuidString)", chartFingerprint],
                     sourceVersions: ["baziSect": "\(AppSettings.baziSect)", "interpret": "30条"],
                     imageAssets: [],
                     missingFields: [],
                     lucky: lucky)
    }

    // Other domains require their actual record/chart and an explicit owner UUID.
    // Never match records by a person's name to infer identity.
    /// 兼容旧调用点（既有测试 testZiweiOrphanSnapshotCannotArchive 不改）：单 ownerID 转发为
    /// ownerIDs 单元素数组；nil 转发为空数组。新调用点一律用 ownerIDs: 版本。
    static func ziwei(chart: ZiweiChart, name: String, ownerID: UUID?) -> Self {
        ziwei(chart: chart, name: name, ownerIDs: ownerID.map { [$0] } ?? [])
    }
    // QA 导出验收 P0-B：收全部归属列表；ownerID 仅在唯一归属时推导，0 人或歧义（≥2 人）
    // 时为 nil 并记 blocking 缺失，正式导出禁用，歧义须由用户显式选人。
    static func ziwei(chart: ZiweiChart, name: String, ownerIDs: [UUID]) -> Self {
        let palaceFields = chart.palaces.enumerated().map { i, palace in
            PosterBoundField(id: "palace.\(i)", label: palace.name,
                             value: palace.majors.isEmpty ? "本宫无主星"
                                 : palace.majors.map { $0.star + ($0.mutagen.map { "化" + $0 } ?? "") }.joined(separator: "、"),
                             source: "ZiweiChart.palaces")
        }
        // QA 导出验收 P0-B：通用快照 5 字段。0 人记 ownerID blocking 缺失；
        // 歧义（≥2 人）记 ownerID-ambiguous blocking 缺失，canArchive 为 false。
        let ownerID: UUID? = ownerIDs.count == 1 ? ownerIDs[0] : nil
        var missing: [PosterMissingField] = []
        if ownerIDs.isEmpty {
            missing.append(.init(id: "ownerID", label: "未绑定人物 UUID", blocking: true))
        } else if ownerIDs.count > 1 {
            missing.append(.init(id: "ownerID-ambiguous", label: "多人共用同一盘面，请先明确选择导出人物", blocking: true))
        }
        return .init(kind: .ziwei, ownerID: ownerID, displayName: name,
                     receipt: "ZiweiChart 农历: \(chart.lunarText)",
                     sections: [.init(id: "palaces", title: "十二宫主星", fields: palaceFields)],
                     caution: "来源为独立紫微命盘。未绑定稳定命主 UUID 时禁止保存为个人报告。",
                     generatedAt: Date(),
                     sourceRecordIDs: ["ZiweiChart:\(chart.stableID)"],
                     sourceVersions: ["ziweiLeapNext": "\(AppSettings.ziweiLeapNext)", "ziweiLateZiNext": "\(AppSettings.ziweiLateZiNext)"],
                     imageAssets: [],
                     missingFields: missing,
                     lucky: nil)
    }
    static func palm(record: PalmRecord, ownerID: UUID?) -> Self {
        let fields = [
            PosterBoundField(id: "summary", label: "真实测量摘要", value: record.summary, source: "PalmRecord.summary"),
            PosterBoundField(id: "lineCount", label: "描线控制点组数",
                             value: "\(record.linesFlat.count / 2)", source: "PalmRecord.linesFlat")
        ]
        // Batch 2 P0：归属以记录自存的 personID 为准；调用方传入的 ownerID 为空时回落到记录值，
        // 两者皆空即为孤儿（blocking 缺失，canArchive 为 false）。绝不按姓名推断。
        let resolvedOwnerID = ownerID ?? record.personID
        var missing: [PosterMissingField] = []
        if resolvedOwnerID == nil {
            missing.append(.init(id: "ownerID", label: "未绑定人物 UUID", blocking: true))
        }
        if record.photoFile.isEmpty {
            missing.append(.init(id: "photo", label: "未附原始照片", blocking: false))
        }
        let assets: [PosterImageAsset] = record.photoFile.isEmpty ? [] : [
            .init(id: record.id.uuidString, kind: "photo",
                  sourcePath: "PalmPhotos/\(record.photoFile)", checksum: nil,
                  note: "原始照片；导出时计算 SHA256 摘要")
        ]
        var recordIDs = ["PalmRecord:\(record.id.uuidString)"]
        if let oid = resolvedOwnerID { recordIDs.append("Person:\(oid.uuidString)") }
        return .init(kind: .palm, ownerID: resolvedOwnerID, displayName: record.personName,
                     receipt: "PalmRecord ID \(record.id.uuidString)",
                     sections: [.init(id: "measure", title: "已保存的测量记录", fields: fields)],
                     caution: "手相推断仅为民俗娱乐；旧记录只有姓名，禁止用同名自动推断人物 ID。",
                     generatedAt: Date(),
                     sourceRecordIDs: recordIDs,
                     sourceVersions: ["storeSchema": "\(StoreSchema.current)"],
                     imageAssets: assets,
                     missingFields: missing,
                     lucky: nil)
    }
    var canArchive: Bool {
        guard ownerID != nil, !sections.isEmpty else { return false }
        // Batch 2 P0：blocking 缺失字段存在时禁止正式导出。
        guard !missingFields.contains(where: { $0.blocking }) else { return false }
        return sections.allSatisfy { !$0.fields.isEmpty && $0.fields.allSatisfy { !$0.source.isEmpty } }
    }
}
struct PosterDynamicTemplateView: View {
    let snapshot: PosterDynamicSnapshot
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("三术合参 · 动态结构预览").font(.caption.monospaced())
                    Text(snapshot.kind.title).font(.system(.largeTitle, design: .serif, weight: .bold))
                    Text(snapshot.displayName.isEmpty ? "未命名" : snapshot.displayName).font(.headline)
                    Text(snapshot.receipt).font(.caption).fixedSize(horizontal: false, vertical: true)
                    if !snapshot.canArchive {
                        Label("缺少稳定身份：禁止正式导出", systemImage: "exclamationmark.shield")
                            .font(.caption)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background(snapshot.kind.ink)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                ForEach(snapshot.sections) { section in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(section.title)
                            .font(.system(.title3, design: .serif, weight: .semibold))
                            .foregroundStyle(snapshot.kind.ink)
                        ForEach(section.fields) { field in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(field.label).font(.subheadline.weight(.semibold)).foregroundStyle(snapshot.kind.ink)
                                Text(field.value)
                                    .font(.body)
                                    .foregroundStyle(.black)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("来源：\(field.source)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(.white.opacity(0.87))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding(16)
                    .background(.white.opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                Text(snapshot.caution)
                    .font(.footnote)
                    .foregroundStyle(snapshot.kind.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Label("只读预览 · 不保存 · 不分享示例图", systemImage: "lock.doc")
                    .font(.caption)
            }
            .padding(18)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .background(snapshot.kind.paper.ignoresSafeArea())
        .navigationTitle(snapshot.kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("poster.dynamic.\(snapshot.kind.rawValue)")
    }
}
