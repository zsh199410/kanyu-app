// 报告中心（UI 2.0 P3 新建，2026-11-08）：已生成命书与海报的历史列表，按人物归档。
// 只读已生成文件：扫描临时目录与 Documents 下「命书-*.pdf」「poster-*.png」「ziwei-poster-*.png」
// 「hecan-poster-*.png」，按修改时间（即生成时间）倒序；不改 people.json／forecasts.json 等存储结构，
// 不新增存储键——命书或海报一经生成即落盘，中心自动出现，无需另记。
// 生成时间取文件修改时间；同名人物合并为一组（文件名只带姓名，不带 id）。
import SwiftUI

/// 报告中心一条历史记录（只读文件派生，不落库）
/// G1：命书条目另带档位（tierName：简洁／专业／完整；旧文件无档位后缀时按专业计，
/// 因旧版单格式输出即等同专业档）与版本哈希短码（hashShort：PDF 元数据 Keywords 内
/// contentHash 前 12 位，读不到时用文件名短码兜底，旧文件为 nil）。
struct ReportHistoryEntry: Identifiable {
    let id: URL
    let url: URL
    let personName: String
    let kind: String
    let icon: String
    let generatedAt: Date
    let sizeKB: Int
    let tierName: String?
    let hashShort: String?
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
        var tierName: String? = nil
        var hashShort: String? = nil
        if raw.hasPrefix("命书-") {
            kind = "命书 PDF"
            icon = "doc.text.fill"
            let rest = String(raw.dropFirst("命书-".count))
            let parsed = parseReportFileName(rest)
            personName = parsed.name
            tierName = parsed.tier
            // 哈希优先读 PDF 元数据（权威来源），读不到时用文件名短码兜底
            hashShort = pdfHashShort(for: url) ?? parsed.hash
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
        return ReportHistoryEntry(id: url, url: url, personName: personName, kind: kind, icon: icon, generatedAt: date, sizeKB: max(1, size / 1024), tierName: tierName, hashShort: hashShort)
    }

    /// 解析 G1 命书文件名（不含扩展名、不含「命书-」前缀）：
    /// 新格式「姓名-档位-yyyyMMdd-HHmmss-哈希12位」，旧格式只有姓名。
    /// 姓名本身可含「-」，故从末尾倒推校验四段（档位／8 位日期／6 位时间／12 位 hex），
    /// 校验失败即按旧文件处理：姓名为整段、档位按专业计、哈希为空。
    private static func parseReportFileName(_ rest: String) -> (name: String, tier: String, hash: String?) {
        let parts = rest.split(separator: "-", omittingEmptySubsequences: false).map { String($0) }
        let tiers = ["简洁", "专业", "完整"]
        if parts.count >= 5 {
            let hash = parts[parts.count - 1]
            let time = parts[parts.count - 2]
            let day = parts[parts.count - 3]
            let tier = parts[parts.count - 4]
            let hashOK = hash.count == 12 && hash.allSatisfy { $0.isHexDigit }
            let timeOK = time.count == 6 && time.allSatisfy { $0.isNumber }
            let dayOK = day.count == 8 && day.allSatisfy { $0.isNumber }
            if hashOK && timeOK && dayOK && tiers.contains(tier) {
                let name = parts[0..<(parts.count - 4)].joined(separator: "-")
                return (name: name, tier: tier, hash: hash)
            }
        }
        return (name: rest, tier: "专业", hash: nil)
    }

    /// 读 PDF 元数据 Keywords 中的 contentHash（G1 版本锁定的权威来源），返回前 12 位短码；
    /// 元数据缺失或无 contentHash 时返回 nil（调用方用文件名短码兜底）。
    private static func pdfHashShort(for url: URL) -> String? {
        guard let doc = CGPDFDocument(url as CFURL) else { return nil }
        guard let info = doc.info else { return nil }
        var value: CGPDFStringRef?
        guard CGPDFDictionaryGetString(info, "Keywords", &value) else { return nil }
        guard let value = value else { return nil }
        guard let text = CGPDFStringCopyTextString(value) as String? else { return nil }
        for part in text.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1).map { String($0) }
            if kv.count == 2 && kv[0] == "contentHash" {
                return String(kv[1].prefix(12))
            }
        }
        return nil
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
    // UI 2.1 第6批：筛选范围跨启动保留（SceneStorage）
    @SceneStorage("reportCenter.scope") private var scope = 0   // 0：仅看此人（有指定人物时默认） 1：全部

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
        // G1：组内按档位分组（简洁 → 专业 → 完整 → 无档位），同档内按生成时间倒序
        return order.map { key in
            let sorted = (map[key] ?? []).sorted { a, b in
                let oa = a.tierName.flatMap { ReportTier(rawValue: $0)?.sortOrder } ?? 99
                let ob = b.tierName.flatMap { ReportTier(rawValue: $0)?.sortOrder } ?? 99
                if oa != ob { return oa < ob }
                return a.generatedAt > b.generatedAt
            }
            return (key, sorted)
        }
    }

    /// G1：命书档位计数行（只读扫描派生，不落库）
    private var tierSummary: String? {
        let books = entries.filter { $0.kind == "命书 PDF" }
        if books.isEmpty { return nil }
        var counts: [String: Int] = [:]
        for e in books {
            let t = e.tierName ?? "专业"
            counts[t, default: 0] += 1
        }
        let parts = ["简洁", "专业", "完整"].map { t in "\(t) \(counts[t] ?? 0)" }
        return "命书档位：" + parts.joined(separator: " · ") + " 份"
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
                    Picker("范围".scriptConverted, selection: $scope) {
                        Text("仅看 ".scriptConverted + (p.name.isEmpty ? "此人" : p.name)).tag(0)
                        Text("全部".scriptConverted).tag(1)
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
                    if let summary = tierSummary {
                        Text(summary.scriptConverted)
                            .font(.caption2).foregroundStyle(Ky.sub).lineSpacing(2)
                            .padding(.horizontal, 2)
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
                Text("只读历史：中心不存报告本身，只列出本机已生成的文件；删除文件后对应条目自动消失。".scriptConverted)
                    .font(.caption2).foregroundStyle(Ky.sub).lineSpacing(2)
                    .padding(.horizontal, 2)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 100)
        }
        .background(Ky.bg)
        .navigationTitle("报告中心".scriptConverted)
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
                HStack(spacing: 6) {
                    Text(e.kind.scriptConverted)
                        .font(.subheadline).fontWeight(.bold).foregroundStyle(Ky.ink)
                    if let tier = e.tierName {
                        Text(tier.scriptConverted)
                            .font(.caption2).fontWeight(.semibold).foregroundStyle(Ky.qingdai)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Ky.qingdai.opacity(0.13))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
                if let hash = e.hashShort {
                    Text("\(Self.dateFmt.string(from: e.generatedAt)) · \(e.sizeKB) KB · 哈希 \(hash)")
                        .font(.caption2).foregroundStyle(Ky.sub)
                } else {
                    Text("\(Self.dateFmt.string(from: e.generatedAt)) · \(e.sizeKB) KB")
                        .font(.caption2).foregroundStyle(Ky.sub)
                }
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
