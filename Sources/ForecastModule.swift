// 前瞻登记（独门，2026-10-30）：断语先落盘冻结、到期回验——同类 App 无此功能。
// 与八字线《前瞻断语登记簿》同规矩：原文不许改，只许到期标状态（待验/命中/部分/未中）。
import SwiftUI

struct ForecastEntry: Codable, Identifiable {
    var id: UUID = UUID()
    var personName: String
    var text: String
    var targetYear: Int
    var status: String = "待验"   // 待验/命中/部分/未中
    var createdEpoch: Double = Date().timeIntervalSince1970
}

@MainActor
final class ForecastStore: ObservableObject {
    @Published var entries: [ForecastEntry] = []
    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("forecasts.json")
    }
    init() {
        if let data = try? Data(contentsOf: fileURL) {
            if let list = try? JSONDecoder().decode([ForecastEntry].self, from: data) { entries = list }
            else { try? FileManager.default.copyItem(at: fileURL, to: fileURL.deletingPathExtension().appendingPathExtension("corrupt.json")) }
        }
    }
    func save() {
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: fileURL, options: .atomic) }
    }
    func add(_ e: ForecastEntry) { entries.insert(e, at: 0); save() }
    func setStatus(_ e: ForecastEntry, _ s: String) {
        if let i = entries.firstIndex(where: { $0.id == e.id }) { entries[i].status = s; save() }
    }
    func remove(_ e: ForecastEntry) { entries.removeAll { $0.id == e.id }; save() }
    func exportData() -> Data { (try? JSONEncoder().encode(entries)) ?? Data() }
}

struct ForecastView: View {
    @StateObject private var store = ForecastStore()
    @State private var showingNew = false
    @State private var exportCache: URL?
    static func writeExport(_ data: Data, _ name: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? data.write(to: url, options: .atomic)
        return url
    }
    var body: some View {
        List {
            if store.entries.isEmpty {
                Text("还没有登记。规矩：断语写下就冻结，到期只标命中与否、不许改原文——这是咱们断得准不准的账本。")
                    .font(.callout).foregroundStyle(Ky.sub)
            }
            ForEach(store.entries) { e in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(e.personName).font(.subheadline).fontWeight(.semibold).foregroundStyle(Ky.ink)
                        Text("\(e.targetYear) 年").font(.caption).foregroundStyle(Ky.gold)
                        Spacer()
                        Menu {
                            ForEach(["待验", "命中", "部分", "未中"], id: \.self) { s in
                                Button(s) { store.setStatus(e, s) }
                            }
                        } label: {
                            Text(e.status).font(.caption2).fontWeight(.semibold)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(e.status == "命中" ? Ky.jade.opacity(0.18)
                                            : e.status == "未中" ? Ky.cinnabar.opacity(0.14) : Ky.bg)
                                .clipShape(Capsule()).foregroundStyle(Ky.ink)
                        }
                    }
                    Text(e.text).font(.callout).foregroundStyle(Ky.ink)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { store.remove(e) } label: { Label("删除", systemImage: "trash") }
                }
            }
        }
        .navigationTitle("前瞻登记")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 14) {
                    if let u = exportCache {
                        ShareLink(item: u) { Image(systemName: "square.and.arrow.up") }
                    } else {
                        Button { exportCache = Self.writeExport(store.exportData(), "forecasts-export.json") } label: { Image(systemName: "square.and.arrow.up") }
                    }
                    Button { showingNew = true } label: { Image(systemName: "plus") }
                }
            }
        }
        .sheet(isPresented: $showingNew) { ForecastFormView(store: store) }
    }
}

struct ForecastFormView: View {
    @ObservedObject var store: ForecastStore
    @State private var personName = ""
    @State private var text = ""
    @State private var year = Calendar.current.component(.year, from: Date()) + 1
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                TextField("人物（姓名）", text: $personName)
                Stepper("目标年份：\(year)", value: $year, in: 2024...2100)
                TextField("断语原文（写下冻结，不可改）", text: $text, axis: .vertical).lineLimit(3...6)
            }
            .navigationTitle("新登记")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("登记") {
                        store.add(ForecastEntry(personName: personName, text: text, targetYear: year))
                        dismiss()
                    }.disabled(personName.isEmpty || text.isEmpty)
                }
            }
        }
    }
}
