// 报告中心（UI 2.0 P3 新建，2026-11-08）：已生成命书与海报的历史列表，按人物归档。
// 只读已生成文件：扫描临时目录与 Documents 下「命书-*.pdf」「poster-*.png」「ziwei-poster-*.png」
// 「hecan-poster-*.png」，按修改时间（即生成时间）倒序；不改 people.json／forecasts.json 等存储结构，
// 不新增存储键——命书或海报一经生成即落盘，中心自动出现，无需另记。
// 生成时间取文件修改时间；P0-4：条目按人物 UUID 归属分组（同名不同人分开），旧文件按姓名尽力迁移，
// 迁不上的孤儿只在「全部」下单列「未归属」组。
import SwiftUI

/// 报告中心一条历史记录（只读文件派生，不落库）
/// G1：命书条目另带档位（tierName：简洁／专业／完整；旧文件无档位后缀时按专业计，
/// 因旧版单格式输出即等同专业档）与版本哈希短码（hashShort：PDF 元数据 Keywords 内
/// contentHash 前 12 位，读不到时用文件名短码兜底，旧文件为 nil）。
/// P0-4：personID 为归属人物 UUID（命书读 PDF 元数据 personID、手相海报读文件名 -pid 后缀，
/// 其余旧文件按姓名尽力迁移）；nil 为孤儿（姓名无唯一匹配），只在「全部」下单列「未归属」组。
struct ReportHistoryEntry: Identifiable {
    let id: URL
    let url: URL
    let personID: UUID?
    let personName: String
    let kind: String
    let icon: String
    let generatedAt: Date
    let sizeKB: Int
    let tierName: String?
    let hashShort: String?
}

enum ReportHistory {
    /// 扫描已生成文件并按生成时间倒序返回。
    /// documents 为可注入的 Documents 目录（默认真实 Documents），只为让单元测试能用临时目录；
    /// 临时目录部分不注入（系统 temp，测试用唯一文件名避免碰撞）。
    static func scan(documents: URL? = nil) -> [ReportHistoryEntry] {
        var urls: [URL] = []
        let fm = FileManager.default
        let docs = documents ?? fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dirs = [fm.temporaryDirectory, docs]
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
        var archived: [URL] = []
        // P0-4：归档目录直接由注入的 docs 拼 KanyuExports（与 ReportExportArchive.rootDirectory()
        // 同路径；生产 docs 即真实 Documents，结果一致；rootDirectory() 本身不接受注入参数）。
        let archiveDir = docs.appendingPathComponent("KanyuExports", isDirectory: true)
        if let walker = fm.enumerator(at: archiveDir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey], options: [.skipsHiddenFiles]) {
            for case let url as URL in walker {
                let kind = ExportManager.kind(of: url.lastPathComponent)
                if (kind == .report && url.pathExtension == "pdf") ||
                    ([.poster, .ziweiPoster, .hecanPoster, .palmPoster].contains(kind) && url.pathExtension == "png") {
                    archived.append(url)
                }
            }
        }
        // makePDF keeps its tested temporary URL; hide that duplicate when its durable copy exists.
        let archivedPDFNames = Set(archived.filter { $0.pathExtension == "pdf" }.map { $0.lastPathComponent })
        urls.removeAll { url in
            url.pathExtension == "pdf" && archivedPDFNames.contains(url.lastPathComponent) &&
                url.deletingLastPathComponent().standardizedFileURL == fm.temporaryDirectory.standardizedFileURL
        }
        urls.append(contentsOf: archived)
        // P0-4：旧文件按姓名尽力迁移——读一次人物列表，供 entry(for:people:) 逐条判定。
        let people = Person.loadPeopleForMigration(directory: docs)
        var seen: Set<URL> = []
        var out: [ReportHistoryEntry] = []
        for u in urls {
            if seen.contains(u) { continue }
            seen.insert(u)
            if let e = entry(for: u, people: people) { out.append(e) }
        }
        return out.sorted { $0.generatedAt > $1.generatedAt }
    }

    /// P0-4：逐条解析归属。命书优先读 PDF 元数据 personID，读不到再按姓名尽力迁移；
    /// 海报先剥文件名末尾的 -pid<32位hex>（有则得 UUID），没有再按姓名尽力迁移；
    /// 姓名精确匹配到唯一现有人物才挂 UUID，否则 personID 为 nil（孤儿）。
    private static func entry(for url: URL, people: [Person]) -> ReportHistoryEntry? {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: url.path) else { return nil }
        let date = (attrs[.modificationDate] as? Date) ?? Date()
        let size = (attrs[.size] as? Int) ?? 0
        let raw = url.deletingPathExtension().lastPathComponent
        let kind: String
        let icon: String
        let personName: String
        var personID: UUID? = nil
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
            personID = pdfPersonID(for: url) ?? Person.uniqueID(forName: personName, in: people)
        } else if raw.hasPrefix("ziwei-poster-") {
            kind = "紫微命盘海报"
            icon = "moon.stars.fill"
            let parsed = parsePosterName(String(raw.dropFirst("ziwei-poster-".count)))
            personName = parsed.name
            personID = parsed.personID ?? Person.uniqueID(forName: parsed.name, in: people)
        } else if raw.hasPrefix("hecan-poster-") {
            kind = "合参海报"
            icon = "sparkles"
            let parsed = parsePosterName(String(raw.dropFirst("hecan-poster-".count)))
            personName = parsed.name
            personID = parsed.personID ?? Person.uniqueID(forName: parsed.name, in: people)
        } else if raw.hasPrefix("palm-poster-") {
            kind = "手相面相鉴定海报"
            icon = "hand.raised.fill"
            let parsed = parsePosterName(String(raw.dropFirst("palm-poster-".count)))
            personName = parsed.name
            personID = parsed.personID ?? Person.uniqueID(forName: parsed.name, in: people)
        } else {
            if raw.contains("-yucedan") {
                kind = "尊享预测单长图"
                icon = "doc.richtext.fill"
            } else {
                kind = "八字命盘海报"
                icon = "photo.fill"
            }
            let parsed = parsePosterName(String(raw.dropFirst("poster-".count)))
            personName = parsed.name
            personID = parsed.personID ?? Person.uniqueID(forName: parsed.name, in: people)
        }
        return ReportHistoryEntry(id: url, url: url, personID: personID, personName: personName, kind: kind, icon: icon, generatedAt: date, sizeKB: max(1, size / 1024), tierName: tierName, hashShort: hashShort)
    }

    /// P0-4 级联删除：删掉该人的全部报告文件（personID 归属的必删；旧姓名文件只在
    /// 姓名唯一时才按名删，同名时留孤儿）。返回删除份数。documents 为可注入的 Documents 目录。
    @discardableResult
    static func deleteAll(for person: Person, nameIsShared: Bool, documents: URL? = nil) -> Int {
        let entries = scan(documents: documents)
        var count = 0
        for e in entries {
            let ownedByUUID = e.personID == person.id
            let ownedByName = e.personID == nil && !nameIsShared && e.personName == person.name
            if ownedByUUID || ownedByName {
                do {
                    try FileManager.default.removeItem(at: e.url)
                    count += 1
                } catch {
                    // 删不掉就留着（下次扫描仍可见），不阻塞删人流程。
                }
            }
        }
        return count
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

    /// P0-4：读 PDF 元数据 Keywords 中的 personID（makePDF 写入的 "personID=<uuid>"）；
    /// 旧文件无该键时返回 nil（调用方按姓名尽力迁移）。与 pdfHashShort 同读法，各管一键。
    static func pdfPersonID(for url: URL) -> UUID? {
        guard let doc = CGPDFDocument(url as CFURL) else { return nil }
        guard let info = doc.info else { return nil }
        var value: CGPDFStringRef?
        guard CGPDFDictionaryGetString(info, "Keywords", &value) else { return nil }
        guard let value = value else { return nil }
        guard let text = CGPDFStringCopyTextString(value) as String? else { return nil }
        for part in text.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1).map { String($0) }
            if kv.count == 2 && kv[0] == "personID" {
                return UUID(uuidString: kv[1])
            }
        }
        return nil
    }

    /// P0-4：剥掉文件名末尾的 -pid<32位小写hex> 段并还原为 UUID；没有该段（或不是合法 hex）
    /// 时原样返回、personID 为 nil。pid 段由 PalmPosterSheetView 在新海报文件名末尾追加。
    static func stripPersonIDSuffix(_ s: String) -> (name: String, personID: UUID?) {
        guard s.count > 36 else { return (name: s, personID: nil) }
        let suffix = String(s.suffix(36))
        guard suffix.hasPrefix("-pid") else { return (name: s, personID: nil) }
        let hex = String(suffix.dropFirst(4))
        guard hex.count == 32, hex.allSatisfy({ $0.isHexDigit }) else { return (name: s, personID: nil) }
        // 把 32 位 hex 还原为带连字符的 UUID 字符串（8-4-4-4-12）。
        let uuidString = "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20))"
        guard let id = UUID(uuidString: uuidString) else { return (name: s, personID: nil) }
        return (name: String(s.dropLast(36)), personID: id)
    }

    /// P0-4：解析海报文件名的命主部分——先剥末尾的 -pid 段（有则得 UUID），再剥款式后缀，余下即姓名。
    /// （pid 段在款式后缀之后追加，故先剥 pid 再剥款式；顺序反了会把款式后缀留在姓名里。）
    static func parsePosterName(_ s: String) -> (name: String, personID: UUID?) {
        let pid = stripPersonIDSuffix(s)
        return (name: stripStyleSuffix(pid.name), personID: pid.personID)
    }

    /// 去掉文件名末尾的款式后缀（-song／-yucedan 为现行款；-xuan／-ink 为已砍款式旧文件兼容），余下即命主姓名
    private static func stripStyleSuffix(_ s: String) -> String {
        for suffix in ["-yucedan", "-zhusha", "-xuanye", "-song", "-xuan", "-ink"] {
            if s.hasSuffix(suffix) { return String(s.dropLast(suffix.count)) }
        }
        return s
    }
}

struct ReportCenterView: View {
    var person: Person? = nil
    @State private var entries: [ReportHistoryEntry] = []
    /// P0-4：分组标题用的人物列表（UUID → 姓名/关系），随扫描一起刷新。
    @State private var people: [Person] = []
    // UI 2.1 第6批：筛选范围跨启动保留（SceneStorage）
    @SceneStorage("reportCenter.scope") private var scope = 0   // 0：仅看此人（有指定人物时默认） 1：全部

    /// P0-4：刷新人物列表＋扫描报告（人物列表供分组标题按 UUID 查名）。
    private func reload() {
        people = Person.loadPeopleForMigration()
        entries = ReportHistory.scan()
    }

    private var shown: [ReportHistoryEntry] {
        if person == nil || scope == 1 { return entries }
        guard let p = person else { return entries }
        // P0-4：按人物 UUID 过滤（同名不同人互不可见；孤儿 personID 为空，不属于任何人）。
        return entries.filter { $0.personID == p.id }
    }

    private var grouped: [(id: String, title: String, entries: [ReportHistoryEntry])] {
        var order: [String] = []
        var map: [String: [ReportHistoryEntry]] = [:]
        for e in shown {
            let key = e.personID?.uuidString ?? "orphan"
            if map[key] == nil { order.append(key) }
            map[key, default: []].append(e)
        }
        // 组标题：按 UUID 找现有人物名；找不着（人已删但报告残留）用组内第一条的文件名姓名兜底；
        // 孤儿组叫「未归属」。同名多人时标题加关系备注区分。
        var titles: [String: String] = [:]
        for key in order {
            if key == "orphan" {
                titles[key] = "未归属"
            } else if let id = UUID(uuidString: key), let p = people.first(where: { $0.id == id }) {
                titles[key] = p.name.isEmpty ? "未命名" : p.name
            } else {
                let name = map[key]?.first?.personName ?? ""
                titles[key] = name.isEmpty ? "未命名" : name
            }
        }
        var nameCount: [String: Int] = [:]
        for key in order { nameCount[titles[key] ?? "", default: 0] += 1 }
        return order.map { key in
            // G1：组内按档位分组（简洁 → 专业 → 完整 → 无档位），同档内按生成时间倒序
            let sorted = (map[key] ?? []).sorted { a, b in
                let oa = a.tierName.flatMap { ReportTier(rawValue: $0)?.sortOrder } ?? 99
                let ob = b.tierName.flatMap { ReportTier(rawValue: $0)?.sortOrder } ?? 99
                if oa != ob { return oa < ob }
                return a.generatedAt > b.generatedAt
            }
            var title = titles[key] ?? "未命名"
            if nameCount[title, default: 0] > 1, key != "orphan",
               let id = UUID(uuidString: key), let p = people.first(where: { $0.id == id }) {
                title += p.relation.isEmpty ? "（\(id.uuidString.prefix(8))）" : "（\(p.relation)）"
            }
            return (id: key, title: title, entries: sorted)
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
                // G8：年度报告区段——有指定人物时链到该人当年年度报告页；无指定人物时只链档案。
                KyHomeSection(title: "年度报告", trailing: "") {
                    VStack(spacing: 8) {
                        if let p = person {
                            NavigationLink {
                                AnnualReportView(
                                    chart: BaziEngine.cachedPaipan(clock: p.birthDate, gender: p.gender, longitude: p.useLongitude ? p.longitude : nil),
                                    name: p.name,
                                    initialYear: Calendar.current.component(.year, from: Date())
                                )
                            } label: {
                                annualEntryRow(icon: "calendar.badge.clock", title: "年度报告 · ".scriptConverted + (p.name.isEmpty ? "此人" : p.name), subtitle: "连续 12 个流年聚合＋年度 verdict".scriptConverted)
                            }.buttonStyle(.plain)
                        }
                        NavigationLink {
                            AnnualArchiveView(person: person)
                        } label: {
                            annualEntryRow(icon: "archivebox", title: "年度档案".scriptConverted, subtitle: "按人物＋年份列出已生成的年度报告".scriptConverted)
                        }.buttonStyle(.plain)
                    }
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
                        ForEach(grouped, id: \.id) { g in
                            KyHomeSection(title: g.title, trailing: "共 \(g.entries.count) 份") {
                                VStack(spacing: 8) {
                                    ForEach(g.entries) { e in historyRow(e) }
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
        .task { reload() }
        .refreshable { reload() }
    }

    /// G8：年度报告区段入口行（与 historyRow 同款式，无分享按钮；标题与副标题由调用方一次转换）
    private func annualEntryRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Ky.qingdai)
                .frame(width: 36, height: 36)
                .background(Ky.qingdai.opacity(0.13))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline).fontWeight(.bold).foregroundStyle(Ky.ink)
                Text(subtitle)
                    .font(.caption2).foregroundStyle(Ky.sub)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Ky.sub)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Ky.elevated)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Ky.line.opacity(0.65), lineWidth: 0.6))
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
