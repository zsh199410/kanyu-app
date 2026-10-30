// 人物档案（P1，2026-10-30）：建一次，三术共用——八字盘面/解盘直接调人，
// 后续手相照片与风水案件关联同一人。数据只存本机 Documents/people.json，不出设备。
import SwiftUI

struct Person: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var relation: String = ""          // 关系备注：本人/丈夫/儿子/客户…
    var gender: String = "M"           // M/F
    var birthEpoch: Double             // 出生钟表时间（北京时间记录）
    var useLongitude: Bool = true
    var longitude: Double = 107.8
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
}

struct PeopleView: View {
    @StateObject private var store = PeopleStore()
    @State private var editing: Person?
    @State private var showingNew = false
    private static var fmt: DateFormatter {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = TimeZone(secondsFromGMT: 8 * 3600); return f
    }
    var body: some View {
        List {
            if store.people.isEmpty {
                Text("还没有人物。把家里人先建上：建一次，八字盘面、解盘直接调人，不用每次重输生日。")
                    .font(.callout).foregroundStyle(Ky.sub)
            }
            ForEach(store.people) { p in
                NavigationLink { PersonDetailView(person: p, store: store) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(p.name).font(.headline).foregroundStyle(Ky.ink)
                            if !p.relation.isEmpty {
                                Text(p.relation).font(.caption2).foregroundStyle(Ky.gold)
                            }
                            Text(p.gender == "M" ? "男" : "女").font(.caption2).foregroundStyle(Ky.sub)
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
        .navigationTitle("人物档案")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingNew = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingNew) {
            PersonFormView(store: store, person: Person(name: "", birthEpoch: Date().timeIntervalSince1970))
        }
        .sheet(item: $editing) { p in PersonFormView(store: store, person: p) }
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
    var body: some View {
        let ch = BaziEngine.paipan(clock: person.birthDate, gender: person.gender,
                                   longitude: person.useLongitude ? person.longitude : nil)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                BaziResultView(chart: ch, name: person.name)
                Text("手相照片与风水案件的按人关联在后续版本接入；此页先通八字盘面与解盘。")
                    .font(.caption2).foregroundStyle(Ky.sub)
            }.padding(16)
        }
        .background(Ky.bg)
        .navigationTitle(person.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
