import SwiftUI
import QuickLook

struct V5LibraryRow: View {
    let title: String
    let detail: String
    let icon: String
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.title3).foregroundStyle(V5Palette.color(V5Palette.current.accent)).frame(width: 28)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
            }.fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).accessibilityHidden(true)
        }.frame(minHeight: V5Metric.target, alignment: .center).contentShape(Rectangle())
    }
}
struct V5LibraryPage: View {
    @EnvironmentObject private var people: PeopleStore
    @State private var entries: [ReportHistoryEntry] = []
    @State private var allPeople = false
    @State private var loading = true
    @State private var preview: URL?
    @State private var revision = 0
    private var selected: Person? { people.currentPerson }
    private var shown: [ReportHistoryEntry] {
        if allPeople { return entries }
        guard let id = selected?.id else { return [] }
        return entries.filter { $0.personID == id }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: V5Metric.gap) {
                V5Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("个人命书").font(.system(.largeTitle, design: .serif))
                        Text("已生成的命书与海报，留存于本机。").foregroundStyle(V5Palette.color(V5Palette.current.secondary))
                        if let person = selected {
                            Text("当前命主 · \(person.name)").font(.headline)
                            Text("档案 \(person.id.uuidString.prefix(8))").font(.caption.monospaced())
                                .accessibilityIdentifier("v5.profile.uuid").accessibilityValue(person.id.uuidString)
                            NavigationLink { PersonDetailView(person: person, store: people) } label: {
                                Label("生成命书 / 专业解读", systemImage: "doc.badge.plus").frame(minHeight: V5Metric.target)
                            }
                        } else {
                            NavigationLink("建立命主档案") { V5ProfilesPage() }.frame(minHeight: V5Metric.target)
                        }
                    }
                }
                Picker("报告范围", selection: $allPeople) {
                    Text("当前命主").tag(false)
                    Text("全部档案").tag(true)
                }.pickerStyle(.segmented)
                Text("本机归档 · \(shown.count) 份").font(.title2.bold())
                if loading { ProgressView("正在读取本机归档") }
                else if shown.isEmpty {
                    V5Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("暂无已生成的文件", systemImage: "book.closed")
                            Text("在命主详情中生成命书，或在结果页导出海报。当前命主仅按档案 UUID 筛选；未归属文件可在全部档案中查看。")
                                .font(.subheadline)
                        }
                    }
                }
                ForEach(shown) { entry in
                    V5Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(entry.kind, systemImage: entry.icon).font(.headline)
                            Text(ownerLabel(entry)).font(.subheadline)
                            Text(entry.generatedAt.formatted(date: .abbreviated, time: .shortened) + " · \(entry.sizeKB) KB").font(.caption)
                            if let tier = entry.tierName { Text("命书档位 · \(tier)").font(.caption) }
                            if let hash = entry.hashShort { Text("内容版本 · \(hash)").font(.caption.monospaced()).textSelection(.enabled) }
                            ViewThatFits(in: .horizontal) {
                                HStack { fileActions(entry); Spacer(minLength: 0) }
                                VStack(alignment: .leading) { fileActions(entry) }
                            }
                        }
                    }
                }
                V5Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("创作与年度档案").font(.title2)
                        NavigationLink { PosterConceptGalleryView(person: selected) } label: {
                            V5LibraryRow(title: "海报作品库", detail: "查看既有四款设计与导出入口", icon: "paintpalette")
                        }
                        NavigationLink { AnnualArchiveView(person: selected) } label: {
                            V5LibraryRow(title: "年度档案", detail: "查看已生成的年度报告", icon: "calendar")
                        }
                        NavigationLink { ReportCenterView(person: selected) } label: {
                            V5LibraryRow(title: "完整报告中心", detail: "原有年度生成、历史与全部导出功能", icon: "archivebox")
                        }
                    }
                }
                Text("旧文件若缺少明确的 UUID，只在全部档案展示，不按姓名自动归给当前命主。本页不改写、迁移或删除任何文件。")
                    .font(.footnote).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
            }.padding(V5Metric.page)
        }
        .background(V5Palette.color(V5Palette.current.paper)).foregroundStyle(V5Palette.color(V5Palette.current.ink))
        .navigationTitle("命书").navigationBarTitleDisplayMode(.inline)
        .quickLookPreview($preview)
        .task(id: revision) {
            loading = true
            let result = await Task.detached(priority: .utility) { ReportHistory.scan().map(V5ReportOwnership.verified) }.value
            guard !Task.isCancelled else { return }
            entries = result; loading = false
        }
        .refreshable { revision += 1 }
    }
    @ViewBuilder private func fileActions(_ entry: ReportHistoryEntry) -> some View {
        Button { preview = entry.url } label: { Label("预览", systemImage: "doc.text.magnifyingglass").frame(minHeight: V5Metric.target) }
        ShareLink(item: entry.url) { Label("分享文件", systemImage: "square.and.arrow.up").frame(minHeight: V5Metric.target) }
    }
    private func ownerLabel(_ entry: ReportHistoryEntry) -> String {
        guard let id = entry.personID else { return "未归属 · \(entry.personName)" }
        if let person = people.people.first(where: { $0.id == id }) {
            return "\(person.name) · \(person.relation) · 档案 \(id.uuidString.prefix(8))"
        }
        return "档案 \(id.uuidString.prefix(8)) · \(entry.personName)"
    }
}

struct V5ProfilesPage: View {
    @EnvironmentObject private var people: PeopleStore
    @State private var editing: Person?
    @State private var pendingDelete: Person?
    @State private var query = ""
    private var filtered: [Person] {
        people.people.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.relation.localizedCaseInsensitiveContains(query) || $0.tags.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: V5Metric.gap) {
                V5Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("人物档案").font(.system(.largeTitle, design: .serif))
                        Text("一份真实档案，贯通三术与个人命书。共 \(people.people.count) 位。")
                        Button { editing = Person(name: "", birthEpoch: Date().timeIntervalSince1970) } label: {
                            Label("新建人物", systemImage: "person.badge.plus").frame(minHeight: V5Metric.target)
                        }.accessibilityIdentifier("v5.profile.create")
                    }
                }
                if filtered.isEmpty { Text(query.isEmpty ? "还没有人物档案，请先添加命主。" : "未找到匹配档案。") }
                ForEach(filtered) { person in
                    V5Card {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(person.name).font(.system(.title2, design: .serif).bold())
                                if people.currentPerson?.id == person.id { Label("当前命主", systemImage: "checkmark.circle.fill").font(.caption) }
                            }
                            Text("\(person.relation.isEmpty ? "未备注关系" : person.relation) · \(person.gender == "M" ? "男" : "女")").font(.subheadline)
                            Text(DisplayTimeReceipt.beijing(person.birthDate)).font(.subheadline)
                            Text("档案 \(person.id.uuidString.prefix(8))").font(.caption.monospaced())
                                .accessibilityIdentifier("v5.profile.uuid").accessibilityValue(person.id.uuidString)
                            if !person.tags.isEmpty { Text(person.tags).font(.caption) }
                            NavigationLink { PersonDetailView(person: person, store: people) } label: {
                                V5LibraryRow(title: "专业详情与命书", detail: "合参、命盘、详批与原有导出", icon: "person.text.rectangle")
                            }
                            Button { people.setCurrentPerson(person) } label: {
                                Label(people.currentPerson?.id == person.id ? "已选为当前命主" : "设为当前命主", systemImage: "person.crop.circle.badge.checkmark").frame(minHeight: V5Metric.target)
                            }.disabled(people.currentPerson?.id == person.id)
                            .accessibilityIdentifier("v5.profile.select.\(person.id.uuidString)")
                            Menu {
                                Button("编辑档案", systemImage: "pencil") { editing = person }
                                Button("删除档案与归属记录", systemImage: "trash", role: .destructive) { pendingDelete = person }
                            } label: { Label("管理此档案", systemImage: "ellipsis.circle").frame(minHeight: V5Metric.target) }
                            .accessibilityIdentifier("v5.profile.manage.\(person.id.uuidString)")
                        }
                    }
                }
                V5Card {
                    VStack(spacing: 12) {
                        NavigationLink { PeopleView() } label: { V5LibraryRow(title: "档案导入与导出", detail: "保留原有 JSON 导入、导出与管理功能", icon: "square.and.arrow.up") }
                        NavigationLink { BackupView() } label: { V5LibraryRow(title: "完整备份与恢复", detail: "人物、手相、前瞻与堪舆案件", icon: "externaldrive") }
                        NavigationLink { ForecastView() } label: { V5LibraryRow(title: "前瞻登记簿", detail: "封存断语与到期回验", icon: "checkmark.seal") }
                        NavigationLink { PalmHomeView() } label: { V5LibraryRow(title: "手相面相记录", detail: "测量与原有鉴定记录", icon: "hand.raised") }
                        NavigationLink { V5SettingsPage() } label: { V5LibraryRow(title: "设置", detail: "外观、口径、语音与数据", icon: "gearshape") }
                    }
                }
            }.padding(V5Metric.page)
        }
        .background(V5Palette.color(V5Palette.current.paper)).foregroundStyle(V5Palette.color(V5Palette.current.ink))
        .navigationTitle("档案").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "姓名、关系或标签")
        // The existing form owns its sheet NavigationStack; the V5 page never nests a root stack.
        .sheet(item: $editing) { PersonFormView(store: people, person: $0) }
        .alert("删除人物档案？", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("取消", role: .cancel) { pendingDelete = nil }
            Button("确认删除", role: .destructive) {
                if let person = pendingDelete { people.remove(person) }
                pendingDelete = nil
            }
        } message: {
            Text("将删除 \(pendingDelete?.name ?? "此人物")（档案 \(pendingDelete.map { String($0.id.uuidString.prefix(8)) } ?? "")）及原有级联规则归属的前瞻、手相、命书与海报。此操作无法撤销，建议先导出备份。")
        }
    }
}
