import SwiftUI
import QuickLook

struct V5LibraryRow: View {
    let title: String
    let detail: String
    let icon: String
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon).font(.system(size: 19)).foregroundStyle(V5Palette.color(V5Palette.current.accent)).frame(width: 26).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
            }.fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).accessibilityHidden(true)
        }.frame(minHeight: V5Metric.target).contentShape(Rectangle())
    }
}

struct V5LibraryPage: View {
    @EnvironmentObject private var people: PeopleStore
    @Environment(\.dynamicTypeSize) private var typeSize
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
    private var columns: [GridItem] {
        typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 150), spacing: 18, alignment: .top)]
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("命书收藏").font(V5Typography.song(.title, emphasis: true)).accessibilityAddTraits(.isHeader)
                    Text("已保存的命书与海报，逐件留存。").font(.subheadline).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
                }
                personContext
                Picker("报告范围", selection: $allPeople) {
                    Text("当前命主").tag(false)
                    Text("全部档案").tag(true)
                }.pickerStyle(.segmented).frame(minHeight: V5Metric.target)
                HStack {
                    Text("本机作品").font(.headline).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Text("共 \(shown.count) 件").font(.subheadline).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
                }
                if loading {
                    ProgressView("正在读取本机归档").frame(maxWidth: .infinity, minHeight: 96)
                } else if shown.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("还没有已保存的作品").font(.headline)
                        Text("在命主详情生成命书，或在结果页导出海报后，作品会出现在这里。未归属文件请切换到全部档案查看。")
                            .font(.subheadline).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
                    }.padding(.vertical, 12)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 26) {
                        ForEach(shown) { entry in workCell(entry) }
                    }
                }
                Divider().padding(.top, 6)
                Text("创作与归档").font(.headline).accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: 10) {
                    NavigationLink { PosterConceptGalleryView(person: selected) } label: {
                        V5LibraryRow(title: "海报设计", detail: "既有四款设计与导出入口", icon: "paintpalette")
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
                Text("未明确归属的旧文件，可在“全部档案”中查看。人物同名时也不会自动归入当前档案。")
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
    private var personContext: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let person = selected {
                Text("当前命主 · \(person.name)").font(.headline).fixedSize(horizontal: false, vertical: true)
                Text("档案 \(person.id.uuidString.prefix(8))").font(.caption.monospaced())
                    .foregroundStyle(V5Palette.color(V5Palette.current.secondary))
                    .accessibilityIdentifier("v5.profile.uuid").accessibilityValue(person.id.uuidString)
                NavigationLink { PersonDetailView(person: person, store: people) } label: {
                    Label("生成命书与专业解读", systemImage: "plus.circle").font(.subheadline.weight(.medium)).frame(minHeight: V5Metric.target)
                }
            } else {
                NavigationLink { V5ProfilesPage() } label: {
                    Label("先建立命主档案", systemImage: "person.badge.plus").frame(minHeight: V5Metric.target)
                }
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background { V5Surface() }
    }
    private func workCell(_ entry: ReportHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            V5WorkThumbnail(url: entry.url, modifiedAt: entry.generatedAt)
                .accessibilityLabel("\(displayKind(entry))的真实文件缩略图")
            Text(displayKind(entry)).font(.headline).fixedSize(horizontal: false, vertical: true)
            Text(ownerLabel(entry)).font(.caption).fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(V5Palette.color(V5Palette.current.secondary))
            Text(V5DisplayText.dateTime(entry.generatedAt)).font(.caption)
                .foregroundStyle(V5Palette.color(V5Palette.current.secondary))
            Text([entry.tierName, "\(entry.sizeKB) 千字节", entry.url.pathExtension.lowercased() == "pdf" ? "文档" : "图片"].compactMap { $0 }.joined(separator: " · "))
                .font(.caption).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { fileActions(entry) }
                VStack(alignment: .leading, spacing: 0) { fileActions(entry) }
            }
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.url.lastPathComponent).textSelection(.enabled)
                    if let id = entry.personID { Text("归属档案：\(id.uuidString)").textSelection(.enabled) }
                    if let hash = entry.hashShort { Text("内容版本：\(hash)").textSelection(.enabled) }
                }.font(.caption).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Text("文件信息").font(.caption).frame(minHeight: V5Metric.target)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    @ViewBuilder private func fileActions(_ entry: ReportHistoryEntry) -> some View {
        Button { preview = entry.url } label: { Label("预览", systemImage: "arrow.up.right.square").font(.subheadline).frame(minHeight: V5Metric.target) }
        ShareLink(item: entry.url) { Label("分享", systemImage: "square.and.arrow.up").font(.subheadline).frame(minHeight: V5Metric.target) }
    }
    private func displayKind(_ entry: ReportHistoryEntry) -> String {
        entry.kind.replacingOccurrences(of: " PDF", with: "文档").replacingOccurrences(of: " PNG", with: "图片")
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
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var editing: Person?
    @State private var pendingDelete: Person?
    @State private var query = ""
    private var filtered: [Person] {
        people.people.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.relation.localizedCaseInsensitiveContains(query) || $0.tags.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("本机人物 · \(people.people.count) 位").font(.subheadline).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
                    Spacer(minLength: 8)
                    Button { editing = Person(name: "", birthEpoch: Date().timeIntervalSince1970) } label: {
                        Label("添加人物", systemImage: "plus").font(.subheadline.weight(.medium)).frame(minHeight: V5Metric.target)
                    }.accessibilityIdentifier("v5.profile.create")
                }
                if filtered.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(query.isEmpty ? "从第一份档案开始" : "未找到匹配档案").font(.headline)
                        Text(query.isEmpty ? "记录真实出生资料，供命盘、合参与个人命书共用。" : "试试姓名、关系或标签。")
                            .font(.subheadline).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
                    }.padding(.vertical, 12)
                }
                ForEach(filtered) { person in profileCard(person) }
                Text("记录与数据").font(.headline).accessibilityAddTraits(.isHeader).padding(.top, 14)
                VStack(alignment: .leading, spacing: 8) {
                    NavigationLink { PeopleView() } label: { V5LibraryRow(title: "档案导入与导出", detail: "沿用原有档案交换格式", icon: "square.and.arrow.up") }
                    Divider()
                    NavigationLink { BackupView() } label: { V5LibraryRow(title: "完整备份与恢复", detail: "人物、手相、前瞻与堪舆案件", icon: "externaldrive") }
                    Divider()
                    NavigationLink { ForecastView() } label: { V5LibraryRow(title: "前瞻登记簿", detail: "封存断语与到期回验", icon: "checkmark.seal") }
                    Divider()
                    NavigationLink { PalmHomeView() } label: { V5LibraryRow(title: "手相面相记录", detail: "测量与原有鉴定记录", icon: "hand.raised") }
                    Divider()
                    NavigationLink { V5SettingsPage() } label: { V5LibraryRow(title: "设置", detail: "外观、口径、语音与数据", icon: "gearshape") }
                }.padding(14).background { V5Surface() }
            }.padding(.horizontal, V5Metric.page).padding(.bottom, 20)
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
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
        return VStack(alignment: .leading, spacing: 10) {
            NavigationLink { PersonDetailView(person: person, store: people) } label: {
                HStack(alignment: .top, spacing: 12) {
                    Text(person.name.isEmpty ? "人" : String(person.name.prefix(1)))
                        .font(.system(size: 23, weight: .medium))
                        .foregroundStyle(V5Palette.color(V5Palette.current.accent))
                        .frame(width: 48, height: 48)
                        .background(V5Palette.color(V5Palette.current.accent).opacity(0.1), in: Circle())
                        .overlay(Circle().stroke(V5Palette.color(V5Palette.current.accent).opacity(current ? 0.7 : 0), lineWidth: 1.5))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(person.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) { identityLabels(person, current: current) }
                            VStack(alignment: .leading, spacing: 6) { identityLabels(person, current: current) }
                        }
                        Text(V5DisplayText.dateTime(person.birthDate) + "（北京时间）")
                            .font(.caption).foregroundStyle(V5Palette.color(V5Palette.current.secondary)).fixedSize(horizontal: false, vertical: true)
                        if !person.tags.isEmpty { Text(person.tags).font(.caption).foregroundStyle(V5Palette.color(V5Palette.current.secondary)) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).padding(.top, 5).accessibilityHidden(true)
                }
            }.buttonStyle(.plain).accessibilityHint("打开专业详情、命盘与命书导出")
            Divider()
            layout {
                Text("档案 \(person.id.uuidString.prefix(8))").font(.caption.monospaced())
                    .foregroundStyle(V5Palette.color(V5Palette.current.secondary))
                    .accessibilityIdentifier("v5.profile.uuid").accessibilityValue(person.id.uuidString)
                if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                HStack(spacing: 4) {
                    Button { people.setCurrentPerson(person) } label: {
                        Text(current ? "已选" : "设为命主").font(.subheadline.weight(.medium)).padding(.horizontal, 8).frame(minHeight: V5Metric.target)
                    }.disabled(current).accessibilityLabel(current ? "已选为当前命主" : "设为当前命主")
                        .accessibilityIdentifier("v5.profile.select.\(person.id.uuidString)")
                    Menu {
                        Button("编辑档案", systemImage: "pencil") { editing = person }
                        Button("删除档案与归属记录", systemImage: "trash", role: .destructive) { pendingDelete = person }
                    } label: {
                        Image(systemName: "ellipsis").font(.body.weight(.semibold)).frame(width: V5Metric.target, height: V5Metric.target)
                    }.accessibilityLabel("管理此档案：\(person.name)").accessibilityIdentifier("v5.profile.manage.\(person.id.uuidString)")
                }
            }
        }.padding(14).background { V5Surface() }
    }
    @ViewBuilder private func identityLabels(_ person: Person, current: Bool) -> some View {
        Text("\(person.relation.isEmpty ? "未备注关系" : person.relation) · \(person.gender == "M" ? "男" : "女")")
            .font(.caption).padding(.horizontal, 8).padding(.vertical, 4)
            .background(V5Palette.color(V5Palette.current.accent).opacity(0.08), in: Capsule())
        if current {
            Label("当前命主", systemImage: "checkmark.circle.fill").font(.caption.weight(.medium))
                .foregroundStyle(V5Palette.color(V5Palette.current.accent))
        }
    }
}
