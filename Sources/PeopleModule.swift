// 人物档案（P1，2026-10-30）：建一次，三术共用——八字盘面/解盘直接调人，
// 后续手相照片与风水案件关联同一人。数据只存本机 Documents/people.json，不出设备。
import SwiftUI
import UniformTypeIdentifiers

// 存储 schema 版本号（B-5，2026-11-02）：每份存档旁写 <名>.meta.json（含 schemaVersion 与条数），
// 导出包带 schemaVersion 字段；导入时带版本与无版本旧格式都接受（旧格式按 v0 计，字段只加不删）。
// v1 与 v0 的数据形状相同（只加了版本标记），故 v1 代码可直接读 v0 存档；将来改字段形状时按
// loadedSchemaVersion 分支做迁移，不得再靠“字段只加不删”硬扛。
enum StoreSchema {
    static let current = 1
    struct Meta: Codable { var schemaVersion: Int; var count: Int }
    static func metaURL(for fileURL: URL) -> URL {
        fileURL.deletingPathExtension().appendingPathExtension("meta.json")
    }
    static func writeMeta(for fileURL: URL, count: Int) {
        if let data = try? JSONEncoder().encode(Meta(schemaVersion: current, count: count)) {
            try? data.write(to: metaURL(for: fileURL), options: .atomic)
        }
    }
    static func readVersion(for fileURL: URL) -> Int {
        guard let data = try? Data(contentsOf: metaURL(for: fileURL)),
              let m = try? JSONDecoder().decode(Meta.self, from: data) else { return 0 }
        return m.schemaVersion
    }
}

struct PeopleExport: Codable { var schemaVersion: Int; var people: [Person] }

struct Person: Codable, Identifiable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String
    var relation: String = ""          // 关系备注：本人/丈夫/儿子/客户…
    var gender: String = "M"           // M/F
    var birthEpoch: Double             // 出生钟表时间（北京时间记录）
    var useLongitude: Bool = true
    var longitude: Double = 107.8
    var tags: String = ""              // 标签（逗号分隔，列表可搜可分组）
    var birthDate: Date { Date(timeIntervalSince1970: birthEpoch) }
}

@MainActor
final class PeopleStore: ObservableObject {
    // 全局唯一单例：人物档案只读一次盘（people.json），各页共用同一份内存数据；
    // 旧写法每页 @StateObject 新建一个 PeopleStore，各读各的盘、改完还不同步
    static let shared = PeopleStore()
    @Published var people: [Person] = []
    // UI 2.0 全局当前命主（单点穿透数据源）：显式选择存 UserDefaults 键 "currentPersonId"（UUID 字符串）；
    // @AppStorage 不能与 @Published 叠加，故用 didSet 同键持久化。PersonDetailView 内的局部 currentPerson 只是详情页 @State，不可复用。
    @Published var currentPersonId: Person.ID? {
        didSet {
            if let id = currentPersonId {
                UserDefaults.standard.set(id.uuidString, forKey: "currentPersonId")
            } else {
                UserDefaults.standard.removeObject(forKey: "currentPersonId")
            }
        }
    }
    /// 全局当前命主：显式选择 → relation 本人 → 首位 → nil（沿用各页既有回落约定）
    var currentPerson: Person? {
        if let id = currentPersonId, let p = people.first(where: { $0.id == id }) { return p }
        return people.first(where: { $0.relation == "本人" }) ?? people.first
    }
    func setCurrentPerson(_ p: Person?) { currentPersonId = p?.id }
    private(set) var loadedSchemaVersion = 0   // 读档时 meta 的版本（无 meta 的旧档为 0）；将来改形状时按此分支迁移
    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("people.json")
    }
    init() {
        load()
        if let s = UserDefaults.standard.string(forKey: "currentPersonId"),
           let id = UUID(uuidString: s),
           people.contains(where: { $0.id == id }) {
            currentPersonId = id
        }
    }
    func load() {
        loadedSchemaVersion = StoreSchema.readVersion(for: fileURL)
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let list = try? JSONDecoder().decode([Person].self, from: data) { people = list }
        else { // 解码失败：先把坏档备份保全，绝不静默当空数据（备份文件勿删，交助手处理）
            try? FileManager.default.copyItem(at: fileURL, to: fileURL.deletingPathExtension().appendingPathExtension("corrupt.json"))
        }
    }
    func save() {
        do {
            let data = try JSONEncoder().encode(people)
            try data.write(to: fileURL, options: .atomic)
            DataProtection.applyComplete(to: fileURL)
            StoreSchema.writeMeta(for: fileURL, count: people.count)
        } catch {
            AppErrorCenter.shared.report("人物档案保存失败，刚才的改动可能没存入：请重试，仍失败请先导出备份再联系助手。")
        }
    }
    func upsert(_ p: Person) {
        if let i = people.firstIndex(where: { $0.id == p.id }) { people[i] = p } else { people.append(p) }
        save()
    }
    func remove(_ p: Person) {
        // Drop stale recent-person references before publishing the changed people array.
        let key = "recentTools.v1"
        if let recent = UserDefaults.standard.stringArray(forKey: key) {
            let deletedKey = "person:" + p.id.uuidString
            let kept = recent.filter { $0 != deletedKey }
            if kept.count != recent.count {
                UserDefaults.standard.set(kept, forKey: key)
            }
        }
        people.removeAll { $0.id == p.id }
        if currentPersonId == p.id { currentPersonId = nil }
        save()
    }
    func exportData() -> Data {
        (try? JSONEncoder().encode(PeopleExport(schemaVersion: StoreSchema.current, people: people))) ?? Data()
    }
    @discardableResult
    func importData(_ data: Data) -> Int {
        // 先按带版本导出包解，失败再按无版本旧格式（纯数组）解；版本高于当前也照收（v1 形状未变）
        let list: [Person]?
        if let wrapped = try? JSONDecoder().decode(PeopleExport.self, from: data) { list = wrapped.people }
        else { list = try? JSONDecoder().decode([Person].self, from: data) }
        guard let list = list else { return 0 }
        var n = 0
        for p in list where !people.contains(where: { $0.id == p.id }) { people.append(p); n += 1 }
        if n > 0 { save() }
        return n
    }
}

struct PeopleView: View {
    @EnvironmentObject var store: PeopleStore
    @State private var editing: Person?
    @State private var showingNew = false
    @State private var exportCache: URL?
    // UI 2.1 第6批：删除人物须确认（出生时间是唯一输入，无自动备份）
    @State private var pendingDeletePerson: Person? = nil
    @State private var showDeleteConfirm = false
    private static var fmt: DateFormatter {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = TimeZone(secondsFromGMT: 8 * 3600); return f
    }
    // UI 2.1 第6批：搜索跨启动保留（SceneStorage）
    @SceneStorage("people.query") private var query = ""
    @State private var importing = false
    @State private var importNote = ""
    private var filtered: [Person] {
        if query.isEmpty { return store.people }
        return store.people.filter { $0.name.contains(query) || $0.relation.contains(query) || $0.tags.contains(query) }
    }
    private var groups: [(String, [Person])] {
        var order: [String] = []; var map: [String: [Person]] = [:]
        for p in filtered {
            let g = p.relation.isEmpty ? "未分组" : p.relation
            if map[g] == nil { order.append(g) }
            map[g, default: []].append(p)
        }
        return order.map { ($0, map[$0]!) }
    }
    var body: some View {
        List {
            if store.people.isEmpty {
                Text("还没有人物。把家里人先建上：建一次，八字盘面、解盘直接调人，不用每次重输生日。".scriptConverted)
                    .font(.callout).foregroundStyle(Ky.sub)
            }
            if !importNote.isEmpty {
                Text(importNote.scriptConverted).font(.caption).foregroundStyle(Ky.jade)
            }
            ForEach(groups, id: \.0) { g in
                Section(g.0) {
                    ForEach(g.1) { p in personRow(p) }
                }
            }
        }
        .searchable(text: $query, prompt: "搜姓名、关系或标签")
        .navigationTitle("人物档案".scriptConverted)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 14) {
                    NavigationLink { BackupView() } label: { Image(systemName: "archivebox") }.accessibilityLabel("数据备份与恢复")
                    Menu {
                        if let u = exportCache {
                            ShareLink(item: u) { Label("导出命例（JSON）".scriptConverted, systemImage: "square.and.arrow.up") }
                        } else {
                            Button { exportCache = exportURL() } label: { Label("导出命例（JSON）".scriptConverted, systemImage: "square.and.arrow.up") }
                        }
                        Button { importing = true } label: { Label("导入命例".scriptConverted, systemImage: "square.and.arrow.down") }
                    } label: { Image(systemName: "arrow.up.arrow.down") }.accessibilityLabel("导入导出菜单")
                    Button { showingNew = true } label: { Image(systemName: "plus") }.accessibilityLabel("新增人物")
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { r in
            if case .success(let url) = r, url.startAccessingSecurityScopedResource(),
               let data = try? Data(contentsOf: url) {
                let n = store.importData(data)
                importNote = n > 0 ? "已导入 \(n) 位（同 ID 自动跳过）" : "没导入：文件格式不对或全是已有命例"
                url.stopAccessingSecurityScopedResource()
            }
        }
        .sheet(isPresented: $showingNew) {
            PersonFormView(store: store, person: Person(name: "", birthEpoch: Date().timeIntervalSince1970), onSaved: { showingNew = false })
        }
        .sheet(item: $editing) { p in PersonFormView(store: store, person: p, onSaved: { editing = nil }) }
        .confirmationDialog("删除人物？".scriptConverted, isPresented: $showDeleteConfirm) {
            Button("删除".scriptConverted, role: .destructive) {
                if let p = pendingDeletePerson { store.remove(p) }
                pendingDeletePerson = nil
            }
            Button("取消".scriptConverted, role: .cancel) { pendingDeletePerson = nil }
        } message: {
            if let p = pendingDeletePerson {
                Text("将删除「\(p.name)」的人物档案，出生时间只能凭记忆重建；恢复只依赖手动导出的备份包。".scriptConverted)
            }
        }
    }
    private func exportURL() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("people-export.json")
        try? store.exportData().write(to: url)
        return url
    }
    private func personRow(_ p: Person) -> some View {
        NavigationLink { PersonDetailView(person: p, store: store) } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(p.name).font(.system(.headline, design: .serif)).foregroundStyle(Ky.ink)
                    Text(p.gender == "M" ? "男" : "女").font(.caption2).foregroundStyle(Ky.sub)
                    if !p.tags.isEmpty {
                        Text(p.tags).font(.caption2).foregroundStyle(Ky.jade).lineLimit(1)
                    }
                }
                Text(Self.fmt.string(from: p.birthDate) + (p.useLongitude ? " · 经度 \(String(format: "%.1f", p.longitude))" : " · 钟表时间".scriptConverted))
                    .font(.caption).foregroundStyle(Ky.sub)
            }
        }
        .accessibilityLabel("人物档案：\(p.name)")
        .accessibilityValue("\(p.gender == "M" ? "男" : "女") · \(DisplayTimeReceipt.beijing(p.birthDate))")
        .accessibilityHint("打开人物详情；向左轻扫可编辑或删除")
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                pendingDeletePerson = p
                showDeleteConfirm = true
            } label: { Label("删除".scriptConverted, systemImage: "trash") }
            Button { editing = p } label: { Label("编辑".scriptConverted, systemImage: "pencil") }
        }
    }
}

struct PersonFormView: View {
    @ObservedObject var store: PeopleStore
    @State var person: Person
    @State private var birth: Date
    @State private var longitudeText: String
    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFieldFocused: Bool
    var onSaved: (() -> Void)? = nil
    init(store: PeopleStore, person: Person, onSaved: (() -> Void)? = nil) {
        self.store = store
        self.onSaved = onSaved
        _person = State(initialValue: person)
        _birth = State(initialValue: person.birthDate)
        _longitudeText = State(initialValue: String(format: "%.1f", person.longitude))
    }
    /// 新建还是编辑：以 id 是否已在档案库为准，标题不再随姓名输入翻转
    private var isNew: Bool { !store.people.contains(where: { $0.id == person.id }) }
    var body: some View {
        NavigationStack {
            Form {
                TextField("姓名", text: $person.name)
                    .focused($nameFieldFocused)
                    .accessibilityIdentifier("person.form.name")
                TextField("关系（本人/丈夫/儿子/客户…，可空）", text: $person.relation)
                TextField("标签（逗号分隔，可搜）", text: $person.tags)
                Picker("性别".scriptConverted, selection: $person.gender) { Text("男").tag("M"); Text("女").tag("F") }
                    .pickerStyle(.segmented)
                Section {
                    BirthInputView(clock: $birth, useLongitude: $person.useLongitude, longitudeText: $longitudeText)
                }
            }
            .navigationTitle(isNew ? "新建人物".scriptConverted : "编辑人物".scriptConverted)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .keyboard) {
                    Button("收起键盘") { nameFieldFocused = false }
                        .accessibilityIdentifier("person.form.dismissKeyboard")
                }
                ToolbarItem(placement: .cancellationAction) { Button("取消".scriptConverted) { dismiss() }.accessibilityIdentifier("person.form.cancel") }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存".scriptConverted) {
                        guard !person.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                        var p = person
                        p.birthEpoch = birth.timeIntervalSince1970
                        p.longitude = Double(longitudeText) ?? p.longitude
                        store.upsert(p)
                        onSaved?()
                        dismiss()
                    }.disabled(person.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("person.form.save")
                }
            }
        }
    }
}

struct PersonDetailView: View {
    let person: Person
    @ObservedObject var store: PeopleStore
    @StateObject private var palmStore = PalmRecordStore()
    @StateObject private var forecastStore = ForecastStore()
    @State private var currentPerson: Person?
    @State private var sectionTab: Int = 0   // 0: 合参总览与八字  1: 紫微命盘  2: 30条详批  3: 逐年直断
    @State private var pdfURL: URL?
    @State private var generatingPDF = false

    private var activePerson: Person { currentPerson ?? person }

    var body: some View {
        let p = activePerson
        let ch = BaziEngine.cachedPaipan(clock: p.birthDate, gender: p.gender,
                                   longitude: p.useLongitude ? p.longitude : nil)
        let zw = ZiweiEngine.cachedChart(clock: p.birthDate, gender: p.gender,
                                   longitude: p.useLongitude ? p.longitude : nil)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                overviewCard(person: p, chart: ch, ziwei: zw)
                NavigationLink {
                    AstroHomeView(person: p, chart: ch)
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(Ky.gold)
                        Text("查看星命合参（东西双模本命盘） ›".scriptConverted)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Ky.ink)
                        Spacer()
                        Text("太阳 · 月亮 · 上升".scriptConverted)
                            .font(.caption2)
                            .foregroundStyle(Ky.sub)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Ky.card)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Ky.gold.opacity(0.4), lineWidth: 0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                actionToolbar(person: p, chart: ch, ziwei: zw)
                // P3：报告中心入口——命书与海报一经生成即落盘，中心按磁盘文件只读列出，无需另记，故生成后自动进历史
                NavigationLink {
                    ReportCenterView(person: p)
                } label: {
                    HStack {
                        Image(systemName: "doc.text.fill")
                            .foregroundStyle(Ky.qingdai)
                        Text("我的命书／报告中心 ›".scriptConverted)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Ky.ink)
                        Spacer()
                        Text(pdfURL == nil ? "生成后自动归档".scriptConverted : "已生成 · 可查看历史".scriptConverted)
                            .font(.caption2)
                            .foregroundStyle(Ky.sub)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Ky.card)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Ky.line, lineWidth: 0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                CrossCheckCard(bazi: ch, ziwei: zw)

                // 四合一分段控制器（无需反复进出子页面，一页切换八字、紫微、30条详批、逐年）
                Picker("合参视图".scriptConverted, selection: $sectionTab) {
                    Text("八字命盘".scriptConverted).tag(0)
                    Text("紫微斗数".scriptConverted).tag(1)
                    Text("30条详批".scriptConverted).tag(2)
                    Text("逐年四查".scriptConverted).tag(3)
                }
                .pickerStyle(.segmented)

                switch sectionTab {
                case 0:
                    BaziResultView(chart: ch, name: p.name, verificationOwnerID: "person:\(p.id.uuidString)")
                case 1:
                    ZiweiBoardView(chart: zw, name: p.name)
                    ZiweiYearView(chart: zw)
                    ZiweiReadingView(chart: zw)
                case 2:
                    inlineInterpretSection(chart: ch)
                default:
                    inlineYearlySection(chart: ch)
                }
            }.padding(16).padding(.bottom, 100)
        }
        .background(Ky.bg)
        .navigationTitle(p.name.isEmpty ? "命主详情".scriptConverted : p.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if store.people.count > 1 {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(store.people) { candidate in
                            Button {
                                currentPerson = candidate
                                pdfURL = nil
                            } label: {
                                HStack {
                                    Text("\(candidate.name)（\(candidate.gender == "M" ? "男" : "女")）")
                                    if candidate.id == p.id { Image(systemName: "checkmark") }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.left.arrow.right.circle")
                            Text("换人".scriptConverted)
                        }
                        .font(.caption).fontWeight(.semibold).foregroundStyle(Ky.qingdai)
                    }
                    .accessibilityLabel("切换档案人物")
                }
            }
        }
    }

    private func actionToolbar(person p: Person, chart ch: BaziChart, ziwei zw: ZiweiChart) -> some View {
        HStack(spacing: 10) {
            if let url = pdfURL {
                ShareLink(item: url) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.richtext.fill").foregroundStyle(Ky.cinnabar)
                        Text("分享命书文件".scriptConverted).font(.caption).fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(Ky.card).clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Ky.line, lineWidth: 0.8))
                }.buttonStyle(.plain).foregroundStyle(Ky.ink)
            } else {
                Button {
                    generatingPDF = true
                    let target = p
                    DispatchQueue.global(qos: .userInitiated).async {
                        let u = ReportBuilder.makePDF(for: target)
                        DispatchQueue.main.async {
                            pdfURL = u
                            generatingPDF = false
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if generatingPDF {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "doc.badge.gearshape").foregroundStyle(Ky.qingdai)
                        }
                        Text(generatingPDF ? "生成文件中…".scriptConverted : "生成命书文件".scriptConverted).font(.caption).fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(Ky.card).clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Ky.line, lineWidth: 0.8))
                }.buttonStyle(.plain).foregroundStyle(Ky.ink)
            }

            ShareLink(item: aiPrompt(person: p, chart: ch, ziwei: zw)) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").foregroundStyle(Ky.gold)
                    Text("导出 AI 解读提示词".scriptConverted).font(.caption).fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(Ky.card).clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Ky.line, lineWidth: 0.8))
            }.buttonStyle(.plain).foregroundStyle(Ky.ink)
        }
    }

    // 三术合参总览：八字/紫微/手相面相/前瞻四路对齐
    private func overviewCard(person p: Person, chart ch: BaziChart, ziwei zw: ZiweiChart) -> some View {
        let now = Calendar.current.component(.year, from: Date())
        let yr = YearEngine.report(chart: ch, year: now)
        let di = YearEngine.dayunIndex(chart: ch, year: now)
        let ming = zw.palaces[zw.mingGong]
        let birthYear = Calendar.current.component(.year, from: p.birthDate)
        let age = now - birthYear + 1
        let curPalace = zw.palaces.first { ($0.decadal.first ?? 0) <= age && age <= ($0.decadal.last ?? 0) }
        let palms = palmStore.records(for: p.name)
        let fcs = forecastStore.entries.filter { $0.personName == p.name }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                KySectionTitle(title: "三术合参总览", trailing: "\(p.gender == "M" ? "乾造" : "坤造") · 日主\(ch.rizhu)")
                if !p.relation.isEmpty {
                    KyBadge(text: p.relation, color: Ky.qingdai)
                }
            }
            ovRow("子平八字", "四柱 \(ch.pillars.joined(separator: " "))；现行\(di.map { ch.dayunGanZhi[$0] } ?? "童限")运；\(now)年［\(yr.level)］——\(yr.lines.first ?? "")")
            ovRow("天纪紫微", "命宫坐\(ming.majors.isEmpty ? "无主星（借对宫）" : ming.majors.map { $0.star }.joined(separator: "、"))（\(zw.juName)）；当前大限走\(curPalace?.name ?? "—")")
            ovRow("手相面相", palms.isEmpty ? "暂未归档（可在首页『手相面相』测量后按姓名保存）"
                        : palms.prefix(2).map { "\($0.kind)：\($0.summary)" }.joined(separator: "；"))
            ovRow("前瞻账本", fcs.isEmpty ? "暂无封存断语"
                        : fcs.prefix(3).map { "\($0.targetYear)年［\($0.status)］\($0.text)" }.joined(separator: "；"))
            Text("合参分工纪律：阶段大象看紫微大限、应期年份与六亲细推以八字逐年消歧；两术冲突时按分工取主断。".scriptConverted)
                .font(.caption2).foregroundStyle(Ky.sub)
        }
        .kyCard()
    }

    private func ovRow(_ label: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            KyBadge(text: label, color: Ky.qingdai)
                .frame(width: 68, alignment: .leading)
            Text(text).font(.caption).foregroundStyle(Ky.ink).lineSpacing(2.5)
        }
    }

    private func inlineInterpretSection(chart ch: BaziChart) -> some View {
        let items = InterpretEngine.interpret(chart: ch)
        return VStack(alignment: .leading, spacing: 12) {
            ForEach(items.indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(i + 1). \(items[i].title)".scriptConverted)
                            .font(.system(.subheadline, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
                        Spacer()
                    }
                    EvidenceChainView(conclusion: items[i].conclusion, links: items[i].links)
                }.kyCard()
            }
        }
    }

    private func inlineYearlySection(chart ch: BaziChart) -> some View {
        let now = Calendar.current.component(.year, from: Date())
        let di = YearEngine.dayunIndex(chart: ch, year: now) ?? 0
        let start = ch.dayunStartYear(di)
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(start...(start + 9), id: \.self) { y in
                let r = YearEngine.report(chart: ch, year: y)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(y) · \(r.gz)年")
                            .font(.system(.headline, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
                        if y == now { KyBadge(text: "今年", color: Ky.qingdai, filled: true) }
                        Spacer()
                        KyBadge(text: r.level, color: r.level == "关口级" ? Ky.cinnabar : Ky.gold)
                    }
                    ForEach(r.lines, id: \.self) { ln in
                        Text(ln.scriptConverted).font(.callout).foregroundStyle(Ky.ink)
                    }
                }.kyCard()
            }
        }
    }
}

// MARK: - AI 解读提示词
extension PersonDetailView {
    func aiPrompt(chart ch: BaziChart, ziwei zw: ZiweiChart) -> String {
        aiPrompt(person: activePerson, chart: ch, ziwei: zw)
    }
    func aiPrompt(person p: Person, chart ch: BaziChart, ziwei zw: ZiweiChart) -> String {
        let ming = zw.palaces[zw.mingGong]
        let wx = zip(["木", "火", "土", "金", "水"], ch.wuxingPercents).map { "\($0.0)\(Int($0.1))%" }.joined(separator: " ")
        return """
        你是一位严谨的子平命理师。请依据以下已校准的盘面（真太阳时排盘）解读，每条结论给出盘面依据，不说套话：
        命主：\(p.name)（\(p.gender == "M" ? "男" : "女")）
        四柱：\(ch.yearPillar) \(ch.monthPillar) \(ch.dayPillar) \(ch.timePillar)，日主\(ch.rizhu)，旬空\(ch.xunKong)
        十神：\(ch.stemShiShen.joined(separator: " "))
        五行：\(wx)
        人元司令：\(ch.siliText)；胎元\(ch.taiYuan)，命宫\(ch.mingGong)，身宫\(ch.shenGong)
        大运（\(ch.qiyunDirection)，\(ch.qiyunDate)起运）：\(ch.dayunGanZhi.joined(separator: " "))
        紫微：命宫\(ming.name)（\(ming.stem)\(ZiweiCore.DZ[ming.branch])），主星\(ming.majors.map { $0.star }.joined(separator: "、"))，\(zw.juName)
        请依次谈：格局与喜忌、事业形态、财运形态、婚姻、健康倾向、当前大运与近三年流年要点。
        """
    }
}
