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
struct PosterDynamicSnapshot {
    let kind: PosterDynamicKind
    let ownerID: UUID?
    let displayName: String
    let receipt: String
    let sections: [PosterBoundSection]
    let caution: String

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
        // Poster-only selection: the complete interpretations remain available
        // in the app and existing full PDF. Only key chart facts and short
        // excerpts belong on the shareable image.
        let sections = PosterHighlightSelection.baziSections(
            chart: chart, items: items, pillars: pillars,
            elements: elements, premium: premium)
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"
        df.locale = Locale(identifier: "zh_CN")
        df.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return .init(kind: premium ? .premium : .bazi,
                     ownerID: person.id, displayName: person.name,
                     receipt: "人物 UUID \(person.id.uuidString) · 生日钟表时间 \(df.string(from: person.birthDate))（北京口径）",
                     sections: sections,
                     caution: "重点摘录仅用于快速阅读。完整解盘、规则和建议请在 App 或 PDF 中查看；传统命理不是已证实的现实预测。")
    }

    // Other domains require their actual record/chart and an explicit owner UUID.
    // Never match records by a person's name to infer identity.
    static func ziwei(chart: ZiweiChart, name: String, ownerID: UUID?) -> Self {
        let palaceFields = chart.palaces.enumerated().map { i, palace in
            PosterBoundField(id: "palace.\(i)", label: palace.name,
                             value: palace.majors.isEmpty ? "本宫无主星"
                                 : palace.majors.map { $0.star + ($0.mutagen.map { "化" + $0 } ?? "") }.joined(separator: "、"),
                             source: "ZiweiChart.palaces")
        }
        return .init(kind: .ziwei, ownerID: ownerID, displayName: name,
                     receipt: "ZiweiChart 农历: \(chart.lunarText)",
                     sections: [.init(id: "palaces", title: "十二宫主星", fields: palaceFields)],
                     caution: "来源为独立紫微命盘。未绑定稳定命主 UUID 时禁止保存为个人报告。")
    }
    static func palm(record: PalmRecord, ownerID: UUID?) -> Self {
        let fields = [
            PosterBoundField(id: "summary", label: "真实测量摘要", value: record.summary, source: "PalmRecord.summary"),
            PosterBoundField(id: "lineCount", label: "描线控制点组数",
                             value: "\(record.linesFlat.count / 2)", source: "PalmRecord.linesFlat")
        ]
        return .init(kind: .palm, ownerID: ownerID, displayName: record.personName,
                     receipt: "PalmRecord ID \(record.id.uuidString)",
                     sections: [.init(id: "measure", title: "已保存的测量记录", fields: fields)],
                     caution: "手相推断仅为民俗娱乐；旧记录只有姓名，禁止用同名自动推断人物 ID。")
    }
    var canArchive: Bool {
        guard ownerID != nil, !sections.isEmpty else { return false }
        return sections.allSatisfy { !$0.fields.isEmpty && $0.fields.allSatisfy { !$0.source.isEmpty } }
    }
}
struct PosterDynamicTemplateView: View {
    let snapshot: PosterDynamicSnapshot
    @State private var exporting = false
    @State private var archiveURL: URL?
    @State private var exportMessage: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("三术合参 · 动态结构预览").font(.caption.monospaced())
                    Text(snapshot.kind.title).font(.system(.largeTitle, design: .serif, weight: .bold))
                    Text(snapshot.displayName.isEmpty ? "未命名" : snapshot.displayName).font(.headline)
                    Text("重点速览 · 详细解读留在 App")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
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
                Text("本海报仅保留重要盘面数据和重点节选；完整版、解释依据及详细建议请在 App 或 PDF 中查看。")
                    .font(.caption)
                    .foregroundStyle(snapshot.kind.ink)
                if snapshot.canArchive {
                    Button {
                        guard !exporting else { return }
                        exporting = true
                        archiveURL = nil
                        exportMessage = nil
                        Task {
                            do {
                                archiveURL = try await PosterPagedArchive.export(snapshot)
                            } catch {
                                exportMessage = error.localizedDescription
                            }
                            exporting = false
                        }
                    } label: {
                        Label(exporting ? "正在生成完整分页图片……" : "生成全部海报（自动分张）",
                              systemImage: "square.stack.3d.up")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(snapshot.kind.ink)
                    .disabled(exporting)
                    .accessibilityIdentifier("poster.dynamic.exportAll")
                    if exporting {
                        ProgressView("正在渲染并校验所有 PNG 页面")
                            .accessibilityIdentifier("poster.dynamic.exportProgress")
                    }
                    if let archiveURL {
                        ShareLink(item: archiveURL) {
                            Label("保存或分享全部图片 ZIP", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.bordered)
                        .tint(snapshot.kind.ink)
                        .accessibilityIdentifier("poster.dynamic.shareZIP")
                    }
                    if let exportMessage {
                        Text("导出失败：" + exportMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("poster.dynamic.exportError")
                    }
                } else {
                    Label("尚未可靠关联人物身份，本报告不能保存或分享。",
                          systemImage: "person.crop.circle.badge.exclamationmark")
                        .font(.footnote)
                        .foregroundStyle(snapshot.kind.ink)
                }
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
