// 人物档案（P1，2026-10-30）：建一次，三术共用——八字盘面/解盘直接调人，
// 后续手相照片与风水案件关联同一人。数据只存本机 Documents/people.json，不出设备。
import SwiftUI
import UniformTypeIdentifiers

struct Person: Codable, Identifiable, Equatable {
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
    @Published var people: [Person] = []
    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("people.json")
    }
    init() { load() }
    func load() {
        if let data = try? Data(contentsOf: fileURL),
           let list = try? JSONDecoder().decode([Person].self, from: data) { people = list }
    }
    func save() {
        if let data = try? JSONEncoder().encode(people) { try? data.write(to: fileURL) }
    }
    func upsert(_ p: Person) {
        if let i = people.firstIndex(where: { $0.id == p.id }) { people[i] = p } else { people.append(p) }
        save()
    }
    func remove(_ p: Person) { people.removeAll { $0.id == p.id }; save() }
    func exportData() -> Data { (try? JSONEncoder().encode(people)) ?? Data() }
    @discardableResult
    func importData(_ data: Data) -> Int {
        guard let list = try? JSONDecoder().decode([Person].self, from: data) else { return 0 }
        var n = 0
        for p in list where !people.contains(where: { $0.id == p.id }) { people.append(p); n += 1 }
        if n > 0 { save() }
        return n
    }
}

struct PeopleView: View {
    @StateObject private var store = PeopleStore()
    @State private var editing: Person?
    @State private var showingNew = false
    private static var fmt: DateFormatter {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = TimeZone(secondsFromGMT: 8 * 3600); return f
    }
    @State private var query = ""
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
                Text("还没有人物。把家里人先建上：建一次，八字盘面、解盘直接调人，不用每次重输生日。")
                    .font(.callout).foregroundStyle(Ky.sub)
            }
            if !importNote.isEmpty {
                Text(importNote).font(.caption).foregroundStyle(Ky.jade)
            }
            ForEach(groups, id: \.0) { g in
                Section(g.0) {
                    ForEach(g.1) { p in personRow(p) }
                }
            }
        }
        .searchable(text: $query, prompt: "搜姓名、关系或标签")
        .navigationTitle("人物档案")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 14) {
                    Menu {
                        ShareLink(item: exportURL()) { Label("导出命例（JSON）", systemImage: "square.and.arrow.up") }
                        Button { importing = true } label: { Label("导入命例", systemImage: "square.and.arrow.down") }
                    } label: { Image(systemName: "arrow.up.arrow.down") }
                    Button { showingNew = true } label: { Image(systemName: "plus") }
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
            PersonFormView(store: store, person: Person(name: "", birthEpoch: Date().timeIntervalSince1970))
        }
        .sheet(item: $editing) { p in PersonFormView(store: store, person: p) }
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
                Text(Self.fmt.string(from: p.birthDate) + (p.useLongitude ? " · 经度 \(String(format: "%.1f", p.longitude))" : " · 钟表时间"))
                    .font(.caption).foregroundStyle(Ky.sub)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { store.remove(p) } label: { Label("删除", systemImage: "trash") }
            Button { editing = p } label: { Label("编辑", systemImage: "pencil") }
        }
    }
}

struct PersonFormView: View {
    @ObservedObject var store: PeopleStore
    @State var person: Person
    @State private var birth: Date
    @State private var longitudeText: String
    @Environment(\.dismiss) private var dismiss
    init(store: PeopleStore, person: Person) {
        self.store = store
        _person = State(initialValue: person)
        _birth = State(initialValue: person.birthDate)
        _longitudeText = State(initialValue: String(format: "%.1f", person.longitude))
    }
    var body: some View {
        NavigationStack {
            Form {
                TextField("姓名", text: $person.name)
                TextField("关系（本人/丈夫/儿子/客户…，可空）", text: $person.relation)
                TextField("标签（逗号分隔，可搜）", text: $person.tags)
                Picker("性别", selection: $person.gender) { Text("男").tag("M"); Text("女").tag("F") }
                    .pickerStyle(.segmented)
                DatePicker("出生钟表时间", selection: $birth, displayedComponents: [.date, .hourAndMinute])
                Toggle("真太阳时校正（按经度）", isOn: $person.useLongitude)
                if person.useLongitude {
                    HStack { Text("出生地经度"); Spacer()
                        TextField("107.8", text: $longitudeText)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90) }
                }
            }
            .navigationTitle(person.name.isEmpty ? "新建人物" : "编辑人物")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var p = person
                        p.birthEpoch = birth.timeIntervalSince1970
                        p.longitude = Double(longitudeText) ?? p.longitude
                        store.upsert(p); dismiss()
                    }.disabled(person.name.trimmingCharacters(in: .whitespaces).isEmpty)
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
    @State private var pdfURL: URL?
    var body: some View {
        let ch = BaziEngine.paipan(clock: person.birthDate, gender: person.gender,
                                   longitude: person.useLongitude ? person.longitude : nil)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                overviewCard(chart: ch)
                if let url = pdfURL {
                    ShareLink(item: url) {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.richtext").foregroundStyle(Ky.gold)
                            Text("分享命书 PDF").font(.subheadline).fontWeight(.medium)
                            Spacer()
                            Image(systemName: "square.and.arrow.up").font(.caption).foregroundStyle(Ky.sub)
                        }
                        .kyCard()
                    }.buttonStyle(.plain).foregroundStyle(Ky.ink)
                }
                ShareLink(item: aiPrompt(chart: ch)) {
                    HStack(spacing: 8) {
                        Image(systemName: "text.badge.star").foregroundStyle(Ky.gold)
                        Text("AI 解读提示词（复制盘面去问 AI）").font(.subheadline).fontWeight(.medium)
                        Spacer()
                        Image(systemName: "square.and.arrow.up").font(.caption).foregroundStyle(Ky.sub)
                    }
                    .kyCard()
                }.buttonStyle(.plain).foregroundStyle(Ky.ink)
                BaziResultView(chart: ch, name: person.name)
                Text("风水案件在堪舆模块按案件管理；建案时以人物姓名命名，即可对人查阅。")
                    .font(.caption2).foregroundStyle(Ky.sub)
            }.padding(16)
        }
        .background(Ky.bg)
        .navigationTitle(person.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { pdfURL = ReportBuilder.makePDF(for: person) }
    }

    // 三术合参总览：八字/紫微/手相面相/前瞻四路对齐，冲突按分工明标，不和稀泥
    private func overviewCard(chart ch: BaziChart) -> some View {
        let now = Calendar.current.component(.year, from: Date())
        let yr = YearEngine.report(chart: ch, year: now)
        let di = YearEngine.dayunIndex(chart: ch, year: now)
        let zw = ZiweiEngine.chart(clock: person.birthDate, gender: person.gender,
                                   longitude: person.useLongitude ? person.longitude : nil)
        let ming = zw.palaces[zw.mingGong]
        let birthYear = Calendar.current.component(.year, from: person.birthDate)
        let age = now - birthYear + 1
        let curPalace = zw.palaces.first { ($0.decadal.first ?? 0) <= age && age <= ($0.decadal.last ?? 0) }
        let palms = palmStore.records(for: person.name)
        let fcs = forecastStore.entries.filter { $0.personName == person.name }
        return VStack(alignment: .leading, spacing: 10) {
            Text("三术合参总览").font(.system(.headline, design: .serif)).foregroundStyle(Ky.ink)
            ovRow("八字", "现行\(di.map { ch.dayunGanZhi[$0] } ?? "童限")运；\(now) 年逐年等级［\(yr.level)］——\(yr.lines.first ?? "")")
            ovRow("紫微", "命宫\(ming.majors.map { $0.star }.joined(separator: "、"))（\(zw.juName)）；当前大限走\(curPalace?.name ?? "—")\(curPalace.map { "（\($0.majors.map { $0.star }.joined(separator: "、"))）" } ?? "")")
            ovRow("手相面相", palms.isEmpty ? "未记录（去手相面相页测量并保存）"
                        : palms.prefix(2).map { "\($0.kind)：\($0.summary)" }.joined(separator: "；"))
            ovRow("前瞻登记", fcs.isEmpty ? "无登记"
                        : fcs.prefix(3).map { "\($0.targetYear) 年［\($0.status)］\($0.text)" }.joined(separator: "；"))
            Text("对读规矩：阶段主题看紫微大限、应期年份以八字逐年消歧；两边信号冲突时按此分工取主断，另一边记异议。")
                .font(.caption2).foregroundStyle(Ky.sub)
        }
        .kyCard()
    }

    private func ovRow(_ label: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label).font(.caption).fontWeight(.bold).foregroundStyle(Ky.gold)
                .frame(width: 56, alignment: .leading)
            Text(text).font(.callout).foregroundStyle(Ky.ink)
        }
    }
}

// MARK: - AI 解读提示词（对标问真「AI 提示词」：盘面结构化文本，粘到任意 AI 即得解读）
extension PersonDetailView {
    func aiPrompt(chart ch: BaziChart) -> String {
        let zw = ZiweiEngine.chart(clock: person.birthDate, gender: person.gender,
                                   longitude: person.useLongitude ? person.longitude : nil)
        let ming = zw.palaces[zw.mingGong]
        let wx = zip(["木", "火", "土", "金", "水"], ch.wuxingPercents).map { "\($0.0)\(Int($0.1))%" }.joined(separator: " ")
        return """
        你是一位严谨的子平命理师。请依据以下已校准的盘面（真太阳时排盘）解读，每条结论给出盘面依据，不说套话：
        命主：\(person.name)（\(person.gender == "M" ? "男" : "女")）
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
