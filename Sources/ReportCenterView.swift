// 报告中心（UI 2.0 P3 新建，2026-11-08）：已生成命书与海报的历史列表，按人物归档。
// 只读已生成文件：扫描临时目录与 Documents 下「命书-*.pdf」「poster-*.png」「ziwei-poster-*.png」
// 「hecan-poster-*.png」，按修改时间（即生成时间）倒序；不改 people.json／forecasts.json 等存储结构，
// 不新增存储键——命书或海报一经生成即落盘，中心自动出现，无需另记。
// 生成时间取文件修改时间；同名人物合并为一组（文件名只带姓名，不带 id）。
import SwiftUI

/// 报告中心一条历史记录（只读文件派生，不落库）
struct ReportHistoryEntry: Identifiable {
    let id: URL
    let url: URL
    let personName: String
    let kind: String
    let icon: String
    let generatedAt: Date
    let sizeKB: Int
}

enum ReportHistory {
    /// 扫描已生成文件并按生成时间倒序返回
    static func scan() -> [ReportHistoryEntry] {
        var urls: [URL] = []
        let fm = FileManager.default
        let dirs = [fm.temporaryDirectory, fm.urls(for: .documentDirectory, in: .userDomainMask)[0]]
        for dir in dirs {
            guard let list = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { continue }
            for u in list {
                let name = u.lastPathComponent
                if name.hasPrefix("命书-") && u.pathExtension == "pdf" { urls.append(u) }
                if name.hasPrefix("poster-") && u.pathExtension == "png" { urls.append(u) }
                if name.hasPrefix("ziwei-poster-") && u.pathExtension == "png" { urls.append(u) }
                if name.hasPrefix("hecan-poster-") && u.pathExtension == "png" { urls.append(u) }
            }
        }
        var seen: Set<URL> = []
        var out: [ReportHistoryEntry] = []
        for u in urls {
            if seen.contains(u) { continue }
            seen.insert(u)
            if let e = entry(for: u) { out.append(e) }
        }
        return out.sorted { $0.generatedAt > $1.generatedAt }
    }

    private static func entry(for url: URL) -> ReportHistoryEntry? {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: url.path) else { return nil }
        let date = (attrs[.modificationDate] as? Date) ?? Date()
        let size = (attrs[.size] as? Int) ?? 0
        let raw = url.deletingPathExtension().lastPathComponent
        let kind: String
        let icon: String
        let personName: String
        if raw.hasPrefix("命书-") {
            kind = "命书 PDF"
            icon = "doc.text.fill"
            personName = String(raw.dropFirst("命书-".count))
        } else if raw.hasPrefix("ziwei-poster-") {
            kind = "紫微命盘海报"
            icon = "moon.stars.fill"
            personName = stripStyleSuffix(String(raw.dropFirst("ziwei-poster-".count)))
        } else if raw.hasPrefix("hecan-poster-") {
            kind = "合参海报"
            icon = "sparkles"
            personName = stripStyleSuffix(String(raw.dropFirst("hecan-poster-".count)))
        } else {
            if raw.contains("-yucedan") {
                kind = "尊享预测单长图"
                icon = "doc.richtext.fill"
            } else {
                kind = "八字命盘海报"
                icon = "photo.fill"
            }
            personName = stripStyleSuffix(String(raw.dropFirst("poster-".count)))
        }
        return ReportHistoryEntry(id: url, url: url, personName: personName, kind: kind, icon: icon, generatedAt: date, sizeKB: max(1, size / 1024))
    }

    /// 去掉文件名末尾的款式后缀（-song／-yucedan／-xuan／-ink），余下即命主姓名
    private static func stripStyleSuffix(_ s: String) -> String {
        for suffix in ["-yucedan", "-song", "-xuan", "-ink"] {
            if s.hasSuffix(suffix) { return String(s.dropLast(suffix.count)) }
        }
        return s
    }
}

struct ReportCenterView: View {
    var person: Person? = nil
    @State private var entries: [ReportHistoryEntry] = []
    @State private var scope = 0   // 0：仅看此人（有指定人物时默认） 1：全部

    private var shown: [ReportHistoryEntry] {
        if person == nil || scope == 1 { return entries }
        guard let name = person?.name else { return entries }
        return entries.filter { $0.personName == name }
    }

    private var grouped: [(String, [ReportHistoryEntry])] {
        var order: [String] = []
        var map: [String: [ReportHistoryEntry]] = [:]
        for e in shown {
            let key = e.personName.isEmpty ? "未命名" : e.personName
            if map[key] == nil { order.append(key) }
            map[key, default: []].append(e)
        }
        return order.map { ($0, map[$0]!) }
    }

    private static var dateFmt: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        return f
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if let p = person {
                    Picker("范围", selection: $scope) {
                        Text("仅看 \(p.name.isEmpty ? "此人" : p.name)").tag(0)
                        Text("全部").tag(1)
                    }
                    .pickerStyle(.segmented)
                }
                if entries.isEmpty {
                    KyEmptyState(icon: "tray", title: "还没有已生成的报告", message: "在命主详情页点「生成命书文件」，或在各结果页导出海报，生成后会自动出现在这里。")
                } else {
                    HStack(spacing: 10) {
                        KyMetricCard(label: "命书 PDF", value: "\(entries.filter { $0.kind == "命书 PDF" }.count) 份")
                        KyMetricCard(label: "海报", value: "\(entries.filter { $0.kind != "命书 PDF" }.count) 张")
                    }
                    if shown.isEmpty {
                        KyEmptyState(icon: "person.crop.circle.badge.questionmark", title: "此人还没有报告", message: "切换到「全部」可看其他人的已生成报告。")
                    } else {
                        ForEach(grouped, id: \.0) { g in
                            KyHomeSection(title: g.0, trailing: "共 \(g.1.count) 份") {
                                VStack(spacing: 8) {
                                    ForEach(g.1) { e in historyRow(e) }
                                }
                            }
                        }
                    }
                }
                Text("只读历史：中心不存报告本身，只列出本机已生成的文件；删除文件后对应条目自动消失。")
                    .font(.caption2).foregroundStyle(Ky.sub).lineSpacing(2)
                    .padding(.horizontal, 2)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 100)
        }
        .background(Ky.bg)
        .navigationTitle("报告中心")
        .navigationBarTitleDisplayMode(.inline)
        .task { entries = ReportHistory.scan() }
        .refreshable { entries = ReportHistory.scan() }
    }

    private func historyRow(_ e: ReportHistoryEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: e.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Ky.qingdai)
                .frame(width: 36, height: 36)
                .background(Ky.qingdai.opacity(0.13))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(e.kind)
                    .font(.subheadline).fontWeight(.bold).foregroundStyle(Ky.ink)
                Text("\(Self.dateFmt.string(from: e.generatedAt)) · \(e.sizeKB) KB")
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
