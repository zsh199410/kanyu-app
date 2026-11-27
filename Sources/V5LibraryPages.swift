import SwiftUI
import QuickLook

struct V5LibraryRow: View {
    let title: String
    let detail: String
    let icon: String
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(V5Palette.color(V5Palette.current.accent)).frame(width: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(.headline, design: .serif))
                Text(detail).font(.subheadline).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
            }.fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(V5Palette.color(V5Palette.current.ornamentText)).accessibilityHidden(true)
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
    @Environment(\.dynamicTypeSize) private var typeSize
    private var selected: Person? { people.currentPerson }
    private var shown: [ReportHistoryEntry] {
        if allPeople { return entries }
        guard let id = selected?.id else { return [] }
        return entries.filter { $0.personID == id }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: V5Metric.gap) {
                V5ArtHeader(eyebrow: "PERSONAL COLLECTION", title: "命书", subtitle: "三术合参 · 本机珍藏")
                publicationHero
                Picker("报告范围", selection: $allPeople) {
                    Text("当前命主").tag(false)
                    Text("全部档案").tag(true)
                }.pickerStyle(.segmented).frame(minHeight: V5Metric.target)
                V5SectionHeading(title: "已存命书与作品", subtitle: "共 \(shown.count) 份 · \(shown.filter { $0.url.pathExtension.lowercased() == "pdf" }.count) 份 PDF")
                if loading {
                    ProgressView("正在读取本机归档").frame(maxWidth: .infinity, minHeight: V5Metric.target)
                } else if shown.isEmpty {
                    V5StatusPanel(state: .empty, title: "这一册，等待写下", message: "在命主详情中生成命书，或在结果页导出海报。未归属文件可切换到全部档案查看。")
                } else {
                    V5Card {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(shown) { entry in
                                archiveRow(entry)
                                if entry.id != shown.last?.id { Divider().padding(.vertical, 18) }
                            }
                        }
                    }
                }
                V5SectionHeading(title: "续写与创作", subtitle: "年度记录、海报设计与完整归档")
                V5Card {
                    VStack(alignment: .leading, spacing: 8) {
                        NavigationLink { PosterConceptGalleryView(person: selected) } label: {
                            V5LibraryRow(title: "海报作品库", detail: "既有四款设计与导出入口", icon: "paintpalette")
                        }
                        Divider()
                        NavigationLink { AnnualArchiveView(person: selected) } label: {
                            V5LibraryRow(title: "年度档案", detail: "已生成的年度报告", icon: "calendar")
                        }
                        Divider()
                        NavigationLink { ReportCenterView(person: selected) } label: {
                            V5LibraryRow(title: "完整报告中心", detail: "年度生成、历史与全部导出功能", icon: "archivebox")
                        }
                    }
                }
                Text("旧文件若缺少明确的 UUID，只在全部档案展示，不按姓名自动归给当前命主。本页不改写、迁移或删除任何文件。")
                    .font(.footnote).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
            }.padding(V5Metric.page)
        }
        .background { V5SceneBackground() }.foregroundStyle(V5Palette.color(V5Palette.current.ink))
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
    private var publicationHero: some View {
        let vertical = typeSize.isAccessibilitySize || V5ThemeStore.shared.theme == .collection
        let layout = vertical ? AnyLayout(VStackLayout(alignment: .leading, spacing: 20)) : AnyLayout(HStackLayout(alignment: .center, spacing: 20))
        return layout {
            V5BookCover(personName: selected?.name)
                .frame(width: vertical ? 176 : 128)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 12) {
                Text("本机藏书 · 个人卷").font(.caption).tracking(2).foregroundStyle(V5Palette.color(V5Palette.current.ornamentText))
                if let person = selected {
                    Text(person.name).font(.system(.title, design: .serif).weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    Text("三术合参 · 个人命书").font(.subheadline)
                    Text("档案 \(person.id.uuidString.prefix(8))").font(.caption.monospaced())
                        .foregroundStyle(V5Palette.color(V5Palette.current.secondary))
                        .accessibilityIdentifier("v5.profile.uuid").accessibilityValue(person.id.uuidString)
                    NavigationLink { PersonDetailView(person: person, store: people) } label: {
                        Label("生成 / 阅读命书", systemImage: "arrow.up.right").frame(minHeight: V5Metric.target)
                    }.buttonStyle(.bordered)
                } else {
                    Text("为一位真实命主立卷").font(.system(.title2, design: .serif))
                    Text("建立档案后，生成你的个人命书。").font(.subheadline)
                    NavigationLink("建立命主档案") { V5ProfilesPage() }.frame(minHeight: V5Metric.target)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, 12)
    }
    private func archiveRow(_ entry: ReportHistoryEntry) -> some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14)) : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
        return layout {
            if entry.url.pathExtension.lowercased() == "pdf" {
                V5BookCover(personName: entry.personName, title: entry.kind, compact: true)
                    .frame(width: 72).accessibilityHidden(true)
            } else {
                Image(systemName: entry.icon).font(.system(size: 28))
                    .foregroundStyle(V5Palette.color(V5Palette.current.ornamentText))
                    .frame(width: 64).frame(minHeight: 72).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(entry.kind).font(.system(.title3, design: .serif).weight(.semibold))
                Text(ownerLabel(entry)).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                Text(entry.generatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
                Text([entry.tierName, "\(entry.sizeKB) KB", entry.url.pathExtension.uppercased()].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(V5Palette.color(V5Palette.current.ornamentText))
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 20) { fileActions(entry) }
                    VStack(alignment: .leading, spacing: 0) { fileActions(entry) }
                }
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.url.lastPathComponent).textSelection(.enabled)
                        if let hash = entry.hashShort { Text("内容版本 · \(hash)").font(.caption.monospaced()).textSelection(.enabled) }
                    }.font(.caption).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text("文件信息").frame(minHeight: V5Metric.target)
                }.font(.caption)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
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
    @Environment(\.dynamicTypeSize) private var typeSize
    private var filtered: [Person] {
        people.people.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.relation.localizedCaseInsensitiveContains(query) || $0.tags.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: V5Metric.gap) {
                V5ArtHeader(eyebrow: "PEOPLE & RECORDS", title: "人物档案", subtitle: "一人一卷 · 三术共用")
                HStack(alignment: .firstTextBaseline) {
                    Text("本机人物 · \(people.people.count) 位").font(.subheadline).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
                    Spacer(minLength: 8)
                    Button { editing = Person(name: "", birthEpoch: Date().timeIntervalSince1970) } label: {
                        Label("新建", systemImage: "plus").frame(minHeight: V5Metric.target)
                    }.buttonStyle(.bordered).accessibilityIdentifier("v5.profile.create")
                }
                if filtered.isEmpty {
                    V5StatusPanel(state: .empty, title: query.isEmpty ? "从第一份档案开始" : "未找到匹配档案", message: query.isEmpty ? "记录真实出生资料，供命盘、合参与个人命书共用。" : "试试姓名、关系或标签。")
                }
                ForEach(filtered) { person in profileCard(person) }
                V5SectionHeading(title: "记录与管理", subtitle: "数据留存在本机，定期备份更安心")
                V5Card {
                    VStack(spacing: 8) {
                        NavigationLink { PeopleView() } label: { V5LibraryRow(title: "档案导入与导出", detail: "保留原有 JSON 导入、导出与管理功能", icon: "square.and.arrow.up") }
                        Divider()
                        NavigationLink { BackupView() } label: { V5LibraryRow(title: "完整备份与恢复", detail: "人物、手相、前瞻与堪舆案件", icon: "externaldrive") }
                        Divider()
                        NavigationLink { ForecastView() } label: { V5LibraryRow(title: "前瞻登记簿", detail: "封存断语与到期回验", icon: "checkmark.seal") }
                        Divider()
                        NavigationLink { PalmHomeView() } label: { V5LibraryRow(title: "手相面相记录", detail: "测量与原有鉴定记录", icon: "hand.raised") }
                        Divider()
                        NavigationLink { V5SettingsPage() } label: { V5LibraryRow(title: "设置", detail: "外观、口径、语音与数据", icon: "gearshape") }
                    }
                }
            }.padding(V5Metric.page)
        }
        .background { V5SceneBackground() }.foregroundStyle(V5Palette.color(V5Palette.current.ink))
        .navigationTitle("档案").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "姓名、关系或标签")
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
    private func profileCard(_ person: Person) -> some View {
        let current = people.currentPerson?.id == person.id
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        return V5Card {
            VStack(alignment: .leading, spacing: 16) {
                NavigationLink { PersonDetailView(person: person, store: people) } label: {
                    HStack(alignment: .top, spacing: 16) {
                        Text(String(person.name.prefix(1))).font(.system(size: 28, weight: .medium, design: .serif))
                            .foregroundStyle(V5Palette.color(V5Palette.current.accent))
                            .frame(width: 56, height: 64)
                            .background(V5Palette.color(V5Palette.current.accent).opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(person.name).font(.system(.title2, design: .serif).weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                            Text("\(person.relation.isEmpty ? "未备注关系" : person.relation) · \(person.gender == "M" ? "男" : "女")").font(.subheadline)
                                .foregroundStyle(V5Palette.color(V5Palette.current.secondary))
                            if current { Label("当前命主", systemImage: "checkmark.circle.fill").font(.caption.weight(.semibold)).foregroundStyle(V5Palette.color(V5Palette.current.accent)) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.up.right").font(.subheadline).foregroundStyle(V5Palette.color(V5Palette.current.ornamentText)).accessibilityHidden(true)
                    }
                }.buttonStyle(.plain).accessibilityHint("打开专业详情、命盘与命书导出")
                VStack(alignment: .leading, spacing: 6) {
                    Text(DisplayTimeReceipt.beijing(person.birthDate)).font(.subheadline.monospacedDigit())
                    Text("档案 \(person.id.uuidString.prefix(8))").font(.caption.monospaced())
                        .foregroundStyle(V5Palette.color(V5Palette.current.secondary))
                        .accessibilityIdentifier("v5.profile.uuid").accessibilityValue(person.id.uuidString)
                    if !person.tags.isEmpty { Text(person.tags).font(.caption).foregroundStyle(V5Palette.color(V5Palette.current.secondary)) }
                }
                Divider()
                layout {
                    Button { people.setCurrentPerson(person) } label: {
                        Label(current ? "已选为当前命主" : "设为当前命主", systemImage: current ? "checkmark.circle" : "person.crop.circle.badge.checkmark")
                            .font(.subheadline.weight(.medium)).frame(minHeight: V5Metric.target)
                    }.disabled(current).accessibilityIdentifier("v5.profile.select.\(person.id.uuidString)")
                    if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                    Menu {
                        Button("编辑档案", systemImage: "pencil") { editing = person }
                        Button("删除档案与归属记录", systemImage: "trash", role: .destructive) { pendingDelete = person }
                    } label: {
                        Label("管理", systemImage: "ellipsis").font(.subheadline).padding(.horizontal, 12).frame(minHeight: V5Metric.target)
                    }.accessibilityLabel("管理此档案：\(person.name)")
                        .accessibilityIdentifier("v5.profile.manage.\(person.id.uuidString)")
                }
            }
        }
    }

}
