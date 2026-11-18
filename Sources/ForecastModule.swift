// 前瞻登记（独门，2026-10-30）：断语先落盘冻结、到期回验——同类 App 无此功能。
// 与八字线《前瞻断语登记簿》同规矩：原文不许改，只许到期标状态（待验/命中/部分/未中）。
import SwiftUI

struct ForecastExport: Codable { var schemaVersion: Int; var entries: [ForecastEntry] }

struct ForecastEntry: Codable, Identifiable {
    var id: UUID = UUID()
    /// P0-4：归属人物 UUID（可选，兼容旧档；旧档 personID 为空，读档时按姓名尽力迁移）。
    var personID: UUID? = nil
    var personName: String
    var text: String
    var targetYear: Int
    var status: String = "待验"   // 待验/命中/部分/未中
    var createdEpoch: Double = Date().timeIntervalSince1970
}

@MainActor
final class ForecastStore: ObservableObject {
    @Published var entries: [ForecastEntry] = []
    /// P0-4：可注入目录（默认仍为真实 Documents），只为让单元测试能用临时目录；默认行为不变。
    private let directory: URL
    private var fileURL: URL { directory.appendingPathComponent("forecasts.json") }
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if let data = try? Data(contentsOf: fileURL) {
            if let list = try? JSONDecoder().decode([ForecastEntry].self, from: data) {
                entries = list
                migratePersonIDs()
            }
            else { try? FileManager.default.copyItem(at: fileURL, to: fileURL.deletingPathExtension().appendingPathExtension("corrupt.json")) }
        }
    }
    /// P0-4 尽力迁移：personID 为空且 personName 精确匹配到唯一现有人物时挂上该人 UUID；
    /// 匹配到零个或多个时留作孤儿（personID 保持空）。改动过才回写，幂等。
    private func migratePersonIDs() {
        let people = Person.loadPeopleForMigration(directory: directory)
        var changed = false
        for i in entries.indices {
            if entries[i].personID == nil, let id = Person.uniqueID(forName: entries[i].personName, in: people) {
                entries[i].personID = id
                changed = true
            }
        }
        if changed { save() }
    }
    /// P0-4：按人物 UUID 取登记（同名不同人互不可见；孤儿 personID 为空，不属于任何人）。
    func entries(for person: Person) -> [ForecastEntry] { entries.filter { $0.personID == person.id } }
    /// P0-4 级联删除：删掉该人的全部登记（personID 归属的必删；旧姓名键记录只在
    /// 姓名唯一时才按名删，同名时留孤儿）。
    func removeAll(for person: Person, nameIsShared: Bool) {
        let before = entries.count
        entries.removeAll {
            $0.personID == person.id || (!nameIsShared && $0.personID == nil && $0.personName == person.name)
        }
        if entries.count != before { save() }
    }
    /// 供 PeopleStore.remove() 级联调用（用一次性实例，不碰任何共享 store 的内存状态）。
    static func removeAll(for person: Person, nameIsShared: Bool, in directory: URL) {
        ForecastStore(directory: directory).removeAll(for: person, nameIsShared: nameIsShared)
    }
    func save() {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: .atomic)
            DataProtection.applyComplete(to: fileURL)
            StoreSchema.writeMeta(for: fileURL, count: entries.count)
        } catch {
            AppErrorCenter.shared.report("前瞻登记保存失败，刚才的改动可能没存入：请重试，仍失败请先导出备份再联系助手。")
        }
    }
    func add(_ e: ForecastEntry) { entries.insert(e, at: 0); save() }
    func setStatus(_ e: ForecastEntry, _ s: String) {
        if let i = entries.firstIndex(where: { $0.id == e.id }) { entries[i].status = s; save() }
    }
    func remove(_ e: ForecastEntry) { entries.removeAll { $0.id == e.id }; save() }
    func exportData() -> Data {
        (try? JSONEncoder().encode(ForecastExport(schemaVersion: StoreSchema.current, entries: entries))) ?? Data()
    }
    @discardableResult
    func importData(_ data: Data) -> Int {
        let list: [ForecastEntry]?
        if let wrapped = try? JSONDecoder().decode(ForecastExport.self, from: data) { list = wrapped.entries }
        else { list = try? JSONDecoder().decode([ForecastEntry].self, from: data) }
        guard let list = list else { return 0 }
        var n = 0
        for e in list where !entries.contains(where: { $0.id == e.id }) { entries.append(e); n += 1 }
        if n > 0 { save() }
        return n
    }
}

struct ForecastView: View {
    @StateObject private var store = ForecastStore()
    @State private var showingNew = false
    @State private var exportCache: URL?
    // UI 2.1 第6批：删除前瞻登记须确认（冻结断语原文是唯一输入，引擎无法重算用户原话）
    @State private var pendingDeleteEntry: ForecastEntry? = nil
    @State private var showDeleteConfirm = false
    static func writeExport(_ data: Data, _ name: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? data.write(to: url, options: .atomic)
        return url
    }
    var body: some View {
        List {
            if store.entries.isEmpty {
                Text("还没有登记。规矩：断语写下就冻结，到期只标命中与否、不许改原文——这是咱们断得准不准的账本。".scriptConverted)
                    .font(.callout).foregroundStyle(Ky.sub)
            }
            ForEach(store.entries) { e in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(e.personName).font(.subheadline).fontWeight(.semibold).foregroundStyle(Ky.ink)
                        Text("\(String(e.targetYear)) 年").font(.caption).foregroundStyle(Ky.gold)
                        Spacer()
                        Menu {
                            ForEach(["待验", "命中", "部分", "未中"], id: \.self) { s in
                                Button(s) { store.setStatus(e, s) }
                            }
                        } label: {
                            Text(e.status.scriptConverted).font(.caption2).fontWeight(.semibold)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(e.status == "命中" ? Ky.jade.opacity(0.18)
                                            : e.status == "未中" ? Ky.cinnabar.opacity(0.14) : Ky.bg)
                                .clipShape(Capsule()).foregroundStyle(Ky.ink)
                        }
                    }
                    Text(e.text).font(.callout).foregroundStyle(Ky.ink)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        pendingDeleteEntry = e
                        showDeleteConfirm = true
                    } label: { Label("删除".scriptConverted, systemImage: "trash") }
                }
            }
        }
        .confirmationDialog("删除前瞻登记？".scriptConverted, isPresented: $showDeleteConfirm) {
            Button("删除".scriptConverted, role: .destructive) {
                if let e = pendingDeleteEntry { store.remove(e) }
                pendingDeleteEntry = nil
            }
            Button("取消".scriptConverted, role: .cancel) { pendingDeleteEntry = nil }
        } message: {
            if let e = pendingDeleteEntry {
                Text("将删除「\(e.personName)」\(e.targetYear) 年的冻结断语，原文删后无法从引擎重算。".scriptConverted)
            }
        }
        .navigationTitle("前瞻登记".scriptConverted)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 14) {
                    if let u = exportCache {
                        ShareLink(item: u) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("导出前瞻登记")
                    } else {
                        Button { exportCache = Self.writeExport(store.exportData(), "forecasts-export.json") } label: { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("导出前瞻登记")
                    }
                    Button { showingNew = true } label: { Image(systemName: "plus") }.accessibilityLabel("新增前瞻登记")
                }
            }
        }
        .sheet(isPresented: $showingNew) { ForecastFormView(store: store, person: PeopleStore.shared.currentPerson) }
    }
}

struct ForecastFormView: View {
    @ObservedObject var store: ForecastStore
    /// P0-4：登记归到当前命主（由前瞻列表页传入）；无当前命主时不可登记，须先去人物档案建人并设为当前命主。
    let person: Person?
    @State private var text = ""
    @State private var year = Calendar.current.component(.year, from: Date()) + 1
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                // P0-4：登记给当前命主，不再自由填姓名（自由文本姓名会串人）。
                Text(person.map { "登记给：\($0.name)" } ?? "请先在人物档案里建好人物并设为当前命主，再回来登记")
                    .foregroundStyle(person == nil ? Ky.cinnabar : Ky.ink)
                Stepper("目标年份：\(year)", value: $year, in: 2024...2100)
                TextField("断语原文（写下冻结，不可改）", text: $text, axis: .vertical).lineLimit(3...6)
            }
            .navigationTitle("新登记".scriptConverted)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消".scriptConverted) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("登记".scriptConverted) {
                        store.add(ForecastEntry(personID: person?.id, personName: person?.name ?? "", text: text, targetYear: year))
                        dismiss()
                    }.disabled(person == nil || text.isEmpty)
                }
            }
        }
    }
}
