// 年度运势报告＋年度档案（G8，Insight 第 2 批，2026-11-09）
//
// 年度报告＝连续 12 个流年聚合＋年度 verdict：
//   逐年直断原文取自 YearEngine.report（复用，不改引擎、不新编口径）；
//   verdict 由 YearEngine.annualVerdict 纯函数推导，规则全文见 YearlyModule.swift
//   文件尾 G8 注释（含 3 组手工推演示例），Web 端实现同一规则表。
//   「12 个月」的口径说明：App 与 Web 两端均无按月引擎（只有按年四查），
//   故 12 条输入为连续 12 个流年报告（报告年份起一轮，Y…Y+11），
//   页内以「连续 12 个流年（本年起一轮）」明示，不冒充按月直断。
// 年度档案＝本机文件扫描（ReportCenter 同款做法）：只读 tmp 与 Documents 下
//   「年度报告-」前缀文件（pdf／png），按人物＋年份分组；不新增存储结构，
//   不写新数据文件。文件名约定：「年度报告-姓名-YYYY-…」。
// 口径：逐年直断原文一字不动，只聚合不改写；verdict 只写趋势与注意点。
import SwiftUI

struct AnnualReportView: View {
    let chart: BaziChart
    let name: String
    let initialYear: Int
    @State private var selectedYear: Int

    init(chart: BaziChart, name: String, initialYear: Int) {
        self.chart = chart
        self.name = name
        self.initialYear = initialYear
        _selectedYear = State(initialValue: initialYear)
    }

    private var nowYear: Int { Calendar.current.component(.year, from: Date()) }

    private func levelStyle(_ level: String) -> (Color, Bool) {
        switch level {
        case "关口级": return (Ky.cinnabar, true)
        case "主线": return (Ky.qingdai, false)
        case "参考": return (Ky.gold, false)
        default: return (Ky.sub, false)
        }
    }

    var body: some View {
        let summary = YearEngine.annualSummary(chart: chart, year: selectedYear)
        let first = summary.reports[0]
        let age = selectedYear - chart.birthYear
        let ageText = age >= 0 ? " · \(age) 岁" : ""
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(selectedYear) · \(first.gz)年\(ageText)".scriptConverted)
                            .font(.system(.headline, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
                        Text("连续 12 个流年（本年起一轮）".scriptConverted)
                            .font(.caption2).foregroundStyle(Ky.sub)
                    }
                    Spacer()
                    Stepper("", value: $selectedYear, in: (nowYear - 10)...(nowYear + 30))
                        .labelsHidden()
                }.kyCard()

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("年度 verdict".scriptConverted)
                            .font(.system(.subheadline, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
                        Spacer()
                        KyBadge(text: summary.verdict.title, color: summary.verdict.gateCount >= 3 ? Ky.cinnabar : Ky.qingdai, filled: summary.verdict.gateCount >= 3)
                    }
                    Text("关口级 \(summary.verdict.gateCount) · 主线 \(summary.verdict.mainCount) · 参考 \(summary.verdict.refCount) · 平年 \(summary.verdict.calmCount)（共 \(summary.reports.count) 年）".scriptConverted)
                        .font(.callout).foregroundStyle(Ky.ink)
                    Text("大运交接：\(summary.dayunChanged ? "本轮内有" : "本轮内无")；冲提纲：\(summary.chongTigang ? "有" : "无")".scriptConverted)
                        .font(.callout).foregroundStyle(Ky.ink)
                    ForEach(summary.verdict.notes.indices, id: \.self) { i in
                        HStack(alignment: .top, spacing: 6) {
                            Circle().fill(Ky.qingdai).frame(width: 5, height: 5).padding(.top, 7)
                            Text(summary.verdict.notes[i].scriptConverted)
                                .font(.callout).foregroundStyle(Ky.ink).lineSpacing(3)
                        }
                    }
                }.kyCard()

                KySectionTitle(title: "逐年直断（原文）", trailing: "\(summary.reports.count) 年")
                ForEach(summary.reports.indices, id: \.self) { i in
                    let r = summary.reports[i]
                    let st = levelStyle(r.level)
                    let rAge = r.year - chart.birthYear
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text("\(r.year) · \(r.gz)年")
                                .font(.system(.headline, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
                            if rAge >= 0 {
                                Text("\(rAge) 岁").font(KyV2.tabular(12)).foregroundStyle(Ky.sub)
                            }
                            if r.year == nowYear {
                                KyBadge(text: "今年", color: Ky.qingdai, filled: true)
                            }
                            Spacer()
                            KyBadge(text: r.level, color: st.0, filled: st.1)
                        }
                        ForEach(r.lines.indices, id: \.self) { j in
                            HStack(alignment: .top, spacing: 6) {
                                Circle().fill(st.0).frame(width: 5, height: 5).padding(.top, 7)
                                Text(r.lines[j].scriptConverted)
                                    .font(.callout).foregroundStyle(Ky.ink).lineSpacing(3)
                            }
                        }
                        if let xy = XiaoYun.ganzhi(chart: chart, year: r.year) {
                            HStack(alignment: .top, spacing: 6) {
                                Circle().fill(Ky.gold).frame(width: 5, height: 5).padding(.top, 7)
                                Text("小运（起运前）：\(xy) · \(r.year - chart.birthYear + 1) 岁（虚岁）· \(chart.qiyunDirection)——起运前以小运代大运，不展开断语。".scriptConverted)
                                    .font(.callout).foregroundStyle(Ky.ink).lineSpacing(3)
                            }
                        }
                    }
                    .padding(15)
                    .background(Ky.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(r.level == "关口级" ? Ky.cinnabar.opacity(0.55) : Ky.line, lineWidth: r.level == "关口级" ? 1.3 : 0.8)
                    )
                }
                Text("口径：逐年直断原文一字不动，只聚合不改写；年度 verdict 只按 12 个流年定级计数＋大运交接＋冲提纲两标志推导；趋势与注意点仅供参考。".scriptConverted)
                    .font(.caption2).foregroundStyle(Ky.sub)
            }.padding(16)
        }
        .background(Ky.bg)
        .navigationTitle(name.isEmpty ? "年度报告".scriptConverted : "年度报告 · ".scriptConverted + name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 年度档案（只读文件扫描，与 ReportCenterView 同款做法）

/// 年度档案一条历史记录（只读文件派生，不落库）
struct AnnualArchiveEntry: Identifiable {
    let id: URL
    let url: URL
    let personName: String
    let year: Int?
    let kind: String
    let generatedAt: Date
    let sizeKB: Int
}

enum AnnualArchive {
    static let filePrefix = "年度报告-"

    static var dateFmt: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        return f
    }

    /// 扫描已生成年度报告文件并按生成时间倒序返回
    static func scan() -> [AnnualArchiveEntry] {
        var urls: [URL] = []
        let fm = FileManager.default
        let dirs = [fm.temporaryDirectory, fm.urls(for: .documentDirectory, in: .userDomainMask)[0]]
        for dir in dirs {
            guard let list = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { continue }
            for u in list {
                let name = u.lastPathComponent
                if name.hasPrefix(filePrefix) && (u.pathExtension == "pdf" || u.pathExtension == "png") {
                    urls.append(u)
                }
            }
        }
        var seen: Set<URL> = []
        var out: [AnnualArchiveEntry] = []
        for u in urls {
            if seen.contains(u) { continue }
            seen.insert(u)
            if let e = entry(for: u) { out.append(e) }
        }
        return out.sorted { $0.generatedAt > $1.generatedAt }
    }

    private static func entry(for url: URL) -> AnnualArchiveEntry? {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: url.path) else { return nil }
        let date = (attrs[.modificationDate] as? Date) ?? Date()
        let size = (attrs[.size] as? Int) ?? 0
        let raw = url.deletingPathExtension().lastPathComponent
        let rest = String(raw.dropFirst(filePrefix.count))
        let parsed = parseFileName(rest)
        let kind = url.pathExtension == "pdf" ? "年度报告 PDF" : "年度报告图片"
        return AnnualArchiveEntry(id: url, url: url, personName: parsed.name, year: parsed.year, kind: kind, generatedAt: date, sizeKB: max(1, size / 1024))
    }

    /// 解析「姓名-YYYY-…」：姓名本身可含「-」，故从各段中找第一个 4 位纯数字段为年份，
    /// 其前各段拼回姓名；找不到年份时年份为空、姓名为整段。
    private static func parseFileName(_ rest: String) -> (name: String, year: Int?) {
        let parts = rest.split(separator: "-", omittingEmptySubsequences: false).map { String($0) }
        for (idx, part) in parts.enumerated() {
            if part.count == 4 && part.allSatisfy({ $0.isNumber }) {
                let name = parts[0..<idx].joined(separator: "-")
                return (name, Int(part))
            }
        }
        return (rest, nil)
    }
}

struct AnnualArchiveView: View {
    var person: Person? = nil
    @State private var entries: [AnnualArchiveEntry] = []
    @SceneStorage("annualArchive.scope") private var scope = 0   // 0：仅看此人（有指定人物时默认） 1：全部

    private var shown: [AnnualArchiveEntry] {
        if person == nil || scope == 1 { return entries }
        guard let name = person?.name else { return entries }
        return entries.filter { $0.personName == name }
    }

    private var grouped: [(String, [AnnualArchiveEntry])] {
        var order: [String] = []
        var map: [String: [AnnualArchiveEntry]] = [:]
        for e in shown {
            let key = e.personName.isEmpty ? "未命名" : e.personName
            if map[key] == nil { order.append(key) }
            map[key, default: []].append(e)
        }
        return order.map { key in
            let sorted = (map[key] ?? []).sorted { a, b in
                let ya = a.year ?? -1
                let yb = b.year ?? -1
                if ya != yb { return ya > yb }
                return a.generatedAt > b.generatedAt
            }
            return (key, sorted)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if let p = person {
                    Picker("范围".scriptConverted, selection: $scope) {
                        Text("仅看 ".scriptConverted + (p.name.isEmpty ? "此人" : p.name)).tag(0)
                        Text("全部".scriptConverted).tag(1)
                    }
                    .pickerStyle(.segmented)
                }
                if entries.isEmpty {
                    KyEmptyState(icon: "calendar", title: "还没有已生成的年度报告", message: "年度报告文件以「年度报告-姓名-年份」命名落盘后，会自动出现在这里。")
                } else if shown.isEmpty {
                    KyEmptyState(icon: "person.crop.circle.badge.questionmark", title: "此人还没有年度报告", message: "切换到「全部」可看其他人的已生成年度报告。")
                } else {
                    ForEach(grouped, id: \.0) { g in
                        KyHomeSection(title: g.0, trailing: "共 \(g.1.count) 份") {
                            VStack(spacing: 8) {
                                ForEach(g.1) { e in archiveRow(e) }
                            }
                        }
                    }
                }
                Text("只读历史：档案不存报告本身，只列出本机已生成的文件；删除文件后对应条目自动消失。".scriptConverted)
                    .font(.caption2).foregroundStyle(Ky.sub).lineSpacing(2)
                    .padding(.horizontal, 2)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 100)
        }
        .background(Ky.bg)
        .navigationTitle("年度档案".scriptConverted)
        .navigationBarTitleDisplayMode(.inline)
        .task { entries = AnnualArchive.scan() }
        .refreshable { entries = AnnualArchive.scan() }
    }

    private func archiveRow(_ e: AnnualArchiveEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Ky.qingdai)
                .frame(width: 36, height: 36)
                .background(Ky.qingdai.opacity(0.13))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(e.kind.scriptConverted)
                        .font(.subheadline).fontWeight(.bold).foregroundStyle(Ky.ink)
                    if let y = e.year {
                        Text("\(y) 年".scriptConverted)
                            .font(.caption2).fontWeight(.semibold).foregroundStyle(Ky.qingdai)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Ky.qingdai.opacity(0.13))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
                Text("\(AnnualArchive.dateFmt.string(from: e.generatedAt)) · \(e.sizeKB) KB")
                    .font(.caption2).foregroundStyle(Ky.sub)
            }
            Spacer()
            ShareLink(item: e.url) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Ky.qingdai)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Ky.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Ky.line.opacity(0.65), lineWidth: 0.6))
    }
}
