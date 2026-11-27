import SwiftUI

/// Native observation entrances. Measurement and annotation stay in the proven photo modules.
struct V5PalmPage: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                V5ArtHeader(eyebrow: "观形察象 · 原生图解", title: "手相与面相", subtitle: "先读懂图，再看自己的照片；所有测量均可手动复核。")
                HStack(alignment: .top, spacing: 16) {
                    V5FeatureGlyph(kind: .palm, size: 64)
                    V5FeatureGlyph(kind: .face, size: 64)
                    Spacer(minLength: 0)
                }.accessibilityHidden(true)
                NavigationLink { PhysiognomyGuideView(kind: .hand) } label: {
                    V5Card { V5LibraryRow(title: "道家手相图解", detail: "主线、掌丘、五指与传统线名", icon: "hand.raised") }
                }.buttonStyle(.plain).accessibilityIdentifier("physiognomy.open.hand")
                NavigationLink { PhysiognomyGuideView(kind: .face) } label: {
                    V5Card { V5LibraryRow(title: "面相十二宫图解", detail: "十二宫、三停与五眼的白话对照", icon: "face.smiling") }
                }.buttonStyle(.plain).accessibilityIdentifier("physiognomy.open.face")
                V5SectionHeading(title: "用自己的照片观测")
                NavigationLink { V5ObservationPage(kind: .hand) } label: {
                    V5LibraryRow(title: "手掌照片与记录", detail: "三线控制点、掌型指比及按人归档", icon: "camera")
                }
                NavigationLink { V5FacePage() } label: {
                    V5LibraryRow(title: "面相照片与记录", detail: "正面照片、三停与五眼的手动校准", icon: "viewfinder")
                }
                NavigationLink { PalmHomeView() } label: {
                    V5LibraryRow(title: "全部测量与原记录", detail: "原有照片标注、关联、分享与管理", icon: "archivebox")
                }
                Text("传统名称不代表疾病或命运判断。照片仅用于本人授权的观察与留存。")
                    .font(.footnote).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
            }.padding(V5Metric.page)
        }.background { V5SceneBackground() }.foregroundStyle(V5Palette.color(V5Palette.current.ink))
            .navigationTitle("手相面相").navigationBarTitleDisplayMode(.inline)
    }
}
struct V5FacePage: View {
    var body: some View { V5ObservationPage(kind: .face) }
}
private enum V5ObservationKind {
    case hand, face
    var title: String { self == .hand ? "手相观测" : "面相观测" }
    var recordKind: String { self == .hand ? "手相" : "面相" }
    var symbol: String { self == .hand ? "hand.raised" : "face.smiling" }
}
private struct V5ObservationPage: View {
    let kind: V5ObservationKind
    @EnvironmentObject private var people: PeopleStore
    @EnvironmentObject private var router: V5Router
    @State private var records: [PalmRecord] = []
    @State private var recordError: String?
    @State private var reading = true
    @State private var revision = 0
    private var ownedRecords: [PalmRecord] {
        guard let person = people.currentPerson else { return [] }
        return records.filter { $0.personID == person.id && $0.kind == kind.recordKind }
            .sorted { $0.createdEpoch > $1.createdEpoch }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: V5Metric.gap) {
                V5ObservationPersonCard()
                V5SectionHeading(title: kind.title, subtitle: "先读图解，再测量与复核，最后按人物保存观察记录。")
                guideEntry
                measurementEntry
                V5Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("拍摄与复核", systemImage: "viewfinder").font(V5Typography.title)
                        if kind == .hand {
                            Text("掌心正对镜头，手掌自然展开。让手腕与五指完整入镜，使用均匀自然光。")
                            Text("识别结果需要核对：可拖动三线控制点，掌纹参考描边仅用于辅助观察。")
                        } else {
                            Text("使用正面、自然光、无美颜照片，头部保持端正，让额头与下颌完整入镜。")
                            Text("眉、鼻底、下颌标线需核对；发际线仍需手动校正。三停与五眼结果来自实际照片测量。")
                        }
                        Text("照片中的动态标注、拖动校正与测量计算沿用原专业模块。")
                            .font(V5Typography.evidence).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
                    }.font(V5Typography.body)
                }
                recordSection
                V5SectionHeading(title: "继续观测")
                if kind == .hand {
                    NavigationLink { V5FacePage() } label: {
                        V5ObservationEntryLabel(title: "面相观测", detail: "十二宫图解 · 三停校准 · 五眼测量", icon: "face.smiling")
                    }.buttonStyle(.plain)
                } else {
                    NavigationLink { V5PalmPage() } label: {
                        V5ObservationEntryLabel(title: "手相观测", detail: "三大主线 · 掌型指比 · 手动描线", icon: "hand.raised")
                    }.buttonStyle(.plain)
                }
                NavigationLink { PalmHomeView() } label: {
                    V5ObservationEntryLabel(title: "完整手相面相工作台", detail: "原图解、照片测量、全部记录、归属管理与导出", icon: "square.grid.2x2")
                }.buttonStyle(.plain)
                V5ObservationReferenceNote()
            }.padding(V5Metric.page)
        }
        .v5ObservationBackground(title: kind.title)
        .accessibilityIdentifier(kind == .hand ? "v5.palm.page" : "v5.face.page")
        .task(id: "\(people.currentPerson?.id.uuidString ?? "none"):\(revision)") {
            await loadRecordSnapshot()
        }
    }
    @ViewBuilder private var guideEntry: some View {
        if kind == .hand {
            NavigationLink { PhysiognomyGuideView(kind: .hand) } label: {
                V5ObservationEntryLabel(title: "道家手相图解", detail: "三大主线、掌丘与五指，点图阅读白话解释", icon: "book.closed")
            }.buttonStyle(.plain).accessibilityIdentifier("physiognomy.open.hand")
        } else {
            NavigationLink { PhysiognomyGuideView(kind: .face) } label: {
                V5ObservationEntryLabel(title: "面相十二宫图解", detail: "认识十二宫与三停位置，无需上传照片", icon: "book.closed")
            }.buttonStyle(.plain).accessibilityIdentifier("physiognomy.open.face")
        }
    }
    @ViewBuilder private var measurementEntry: some View {
        if let person = people.currentPerson {
            if kind == .hand {
                NavigationLink { HandMeasureView(person: person).id(person) } label: {
                    V5ObservationEntryLabel(title: "开始手掌照片测量", detail: "识别关节点 → 核对三线 → 保存到当前档案", icon: "camera")
                }.buttonStyle(.plain).accessibilityIdentifier("v5.palm.measure")
            } else {
                NavigationLink { FaceMeasureView(person: person).id(person) } label: {
                    V5ObservationEntryLabel(title: "开始面部比例校准", detail: "选择照片 → 校正标线 → 查看三停与五眼", icon: "camera")
                }.buttonStyle(.plain).accessibilityIdentifier("v5.face.measure")
            }
        } else {
            V5Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("先选择真实人物档案").font(V5Typography.title)
                    Text("照片测量记录按人物 UUID 归档。添加人物后即可开始测量，图解可直接阅读。")
                    Button("前往档案") { router.tab = 3 }.buttonStyle(V5PrimaryButton())
                }
            }
        }
    }
    private var recordSection: some View {
        VStack(alignment: .leading, spacing: V5Metric.gap) {
            V5SectionHeading(title: "当前人物的观测记录", subtitle: "仅显示明确归属当前人物 UUID 的\(kind.recordKind)记录。")
            if reading {
                ProgressView("正在读取本机观测记录")
            } else if let recordError {
                V5StatusPanel(state: .failure, title: "记录暂时无法读取", message: recordError, retry: { revision += 1 })
            } else if people.currentPerson == nil {
                V5StatusPanel(state: .empty, title: "尚未选择人物", message: "选择档案后查看该人物的观测记录。")
            } else if ownedRecords.isEmpty {
                V5StatusPanel(state: .empty, title: "还没有\(kind.recordKind)记录", message: "完成照片标线复核后，在测量页保存，记录会出现在这里。")
            } else {
                ForEach(ownedRecords.prefix(3)) { record in
                    V5Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(Date(timeIntervalSince1970: record.createdEpoch), format: .dateTime.year().month().day().hour().minute())
                                .font(V5Typography.evidence).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
                            Text(record.summary).font(V5Typography.body).fixedSize(horizontal: false, vertical: true)
                            if !record.linesFlat.isEmpty {
                                Text("已保存手动校正线条").font(V5Typography.evidence)
                            }
                        }.accessibilityElement(children: .combine)
                    }
                }
            }
            NavigationLink { PalmRecordListView() } label: {
                V5ObservationEntryLabel(title: "管理全部测量记录", detail: "查看照片标注 · 明确关联或解除人物归属 · 导出与删除", icon: "archivebox")
            }.buttonStyle(.plain)
        }
    }
    /// Read-only snapshot of the existing Codable index. Do not instantiate a second
    /// mutable PalmRecordStore at this entrance: its init performs legacy migration.
    /// Reload after returning from measurement so summaries reflect the original store's saves.
    private func loadRecordSnapshot() async {
        reading = true; recordError = nil
        let worker = Task.detached(priority: .utility) { () throws -> [PalmRecord] in
            try Task.checkCancellation()
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("palm_records.json")
            guard FileManager.default.fileExists(atPath: url.path) else { return [] }
            let snapshot = try JSONDecoder().decode([PalmRecord].self, from: Data(contentsOf: url, options: .mappedIfSafe))
            try Task.checkCancellation()
            return snapshot
        }
        do {
            let snapshot = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
            guard !Task.isCancelled else { return }
            records = snapshot; reading = false
        } catch {
            guard !Task.isCancelled else { return }
            records = []; reading = false
            recordError = "未能读取已保存的测量索引。请重试，或进入原记录工作台检查。原文件保持不变。"
        }
    }
}

struct V5SurveyPage: View {
    @EnvironmentObject private var store: SurveyStore
    @EnvironmentObject private var lockStore: CompassLockStore
    @EnvironmentObject private var router: V5Router
    @State private var query = ""
    @State private var showingNewCase = false
    private var matchingCases: [CaseData] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return store.cases }
        return store.cases.filter {
            $0.surveyCase.name.localizedCaseInsensitiveContains(query) ||
            $0.surveyCase.locationNote.localizedCaseInsensitiveContains(query)
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: V5Metric.gap) {
                V5SectionHeading(title: "察地理 · 记实测", subtitle: "罗盘定向、户型立极与现场采集，围绕真实勘察案件整理。")
                overview
                NavigationLink { CompassStandaloneView() } label: {
                    V5ObservationEntryLabel(title: "罗盘实测", detail: "真北／磁北 · 二十四山 · 采样锁定 · 带入案件", icon: "safari")
                }.buttonStyle(.plain).accessibilityIdentifier("v5.survey.compass")
                NavigationLink { FloorPlanOverlayView() } label: {
                    V5ObservationEntryLabel(title: "户型立极压盘", detail: "导入户型图 · 校正中宫 · 查看九运飞星", icon: "square.split.diagonal.2x2")
                }.buttonStyle(.plain)
                compassReceipt
                caseSection
                V5SectionHeading(title: "勘察手册", subtitle: "先核对测量条件，再阅读传统类象。")
                NavigationLink { KnowledgeView() } label: {
                    V5ObservationEntryLabel(title: "风水知识卡", detail: "玄空飞星 · 八宅游年 · 二十四山测法", icon: "books.vertical")
                }.buttonStyle(.plain)
                NavigationLink { ShaHandbookView() } label: {
                    V5ObservationEntryLabel(title: "犯煞与解煞手册", detail: "17 类形煞 · 实证机理 · 分层处理建议", icon: "shield.lefthalf.filled")
                }.buttonStyle(.plain)
                NavigationLink { KanyuWorkbenchTabView() } label: {
                    V5ObservationEntryLabel(title: "完整勘察工作台", detail: "全部案件管理与删除 · 现场采集 · 专业分析 · 设置", icon: "square.grid.2x2")
                }.buttonStyle(.plain)
                Button { router.tab = 3 } label: {
                    V5ObservationEntryLabel(title: "人物档案管理", detail: "家人与客户生辰档案 · 独立于案件常住人资料", icon: "person.2")
                }.buttonStyle(.plain)
                NavigationLink { BackupView() } label: {
                    V5ObservationEntryLabel(title: "数据备份与恢复", detail: "本地 ZIP 导出导入 · iCloud 同步", icon: "archivebox")
                }.buttonStyle(.plain)
                NavigationLink { CaliberSettingsView() } label: {
                    V5ObservationEntryLabel(title: "排盘口径与签名证书", detail: "排盘规则 · 侧载证书到期信息", icon: "slider.horizontal.3")
                }.buttonStyle(.plain)
                V5ObservationReferenceNote()
            }.padding(V5Metric.page)
        }
        .v5ObservationBackground(title: "风水勘察")
        .accessibilityIdentifier("v5.survey.page")
        // Original creation sheet owns its NavigationStack, form and save semantics.
        .sheet(isPresented: $showingNewCase) { NewCaseView() }
    }
    private var overview: some View {
        V5Card {
            VStack(alignment: .leading, spacing: 14) {
                Text("我的勘察档案").font(V5Typography.section)
                statRow("勘察案件", value: store.cases.count)
                statRow("已测坐向", value: store.cases.filter { data in
                    data.headings.contains { $0.pointName == "大门外朝内" && $0.trueNorth >= 0 }
                }.count)
                statRow("采集素材", value: store.cases.reduce(0) { $0 + $1.media.count })
                Button { showingNewCase = true } label: { Label("新建勘察案件", systemImage: "plus") }
                    .buttonStyle(V5PrimaryButton()).accessibilityIdentifier("v5.survey.create")
            }
        }
    }
    @ViewBuilder private var compassReceipt: some View {
        if let lock = lockStore.lock {
            V5Card {
                VStack(alignment: .leading, spacing: 10) {
                    Label("已保存的罗盘锁定", systemImage: "lock").font(V5Typography.title)
                    Text(lock.sitFaceText).font(V5Typography.body)
                    Text("真北 \(lock.trueNorth, specifier: "%.1f")° · 磁北 \(lock.magnetic, specifier: "%.1f")°")
                        .font(V5Typography.numeric)
                    Text(lock.declinationSourceText).font(V5Typography.detail)
                    Text(lock.timestamp, format: .dateTime.year().month().day().hour().minute()).font(V5Typography.evidence)
                    Text("此处显示已保存的锁定收据。新的现场方位须进入罗盘实测重新采样。")
                        .font(V5Typography.evidence).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
                }.accessibilityElement(children: .combine)
            }
        } else {
            V5StatusPanel(state: .empty, title: "尚无锁定方位", message: "进入罗盘实测，核对磁干扰与手机水平后采样。")
        }
    }
    private var caseSection: some View {
        VStack(alignment: .leading, spacing: V5Metric.gap) {
            V5SectionHeading(title: "勘察案件", subtitle: "在案件中查看任务单、现场照片、方位记录与专业分析。")
            if let error = store.loadError {
                V5StatusPanel(state: .failure, title: "案件读取异常", message: error)
            }
            V5Card {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").accessibilityHidden(true)
                    TextField("搜索案件名称或位置", text: $query).font(V5Typography.body)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .frame(minHeight: V5Metric.target)
                        .accessibilityIdentifier("v5.survey.search")
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill").frame(minWidth: V5Metric.target, minHeight: V5Metric.target)
                        }.accessibilityLabel("清除案件搜索")
                    }
                }
            }
            if matchingCases.isEmpty {
                V5StatusPanel(state: .empty, title: store.cases.isEmpty ? "还没有勘察案件" : "没有匹配的案件",
                              message: store.cases.isEmpty ? "新建案件后，可按任务单采集罗盘、照片与视频。" : "尝试案件名称或所在位置的其他关键词。")
            }
            ForEach(matchingCases) { data in
                NavigationLink { CaseDetailView(caseId: data.id) } label: {
                    V5Card {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top) {
                                Text(data.surveyCase.name).font(V5Typography.title)
                                Spacer(minLength: 12)
                                Image(systemName: "chevron.right").accessibilityHidden(true)
                            }
                            Text(data.surveyCase.type.rawValue + (data.surveyCase.locationNote.isEmpty ? "" : " · " + data.surveyCase.locationNote))
                                .font(V5Typography.detail)
                            let tasks = TaskFactory.tasks(for: data.surveyCase.type)
                            let completed = tasks.filter { data.taskDone[$0.id] == true }.count
                            Text("任务 \(completed)/\(tasks.count) · 素材 \(data.media.count) · 方位 \(data.headings.count)")
                                .font(V5Typography.evidence).monospacedDigit()
                            ProgressView(value: Double(completed), total: Double(max(tasks.count, 1)))
                                .tint(V5Palette.color(V5Palette.current.accent))
                                .accessibilityLabel("任务完成进度")
                                .accessibilityValue("已完成 \(completed) 项，共 \(tasks.count) 项")
                        }.frame(minHeight: V5Metric.target)
                    }.accessibilityElement(children: .combine)
                }.buttonStyle(.plain)
            }
        }
    }
    private func statRow(_ title: String, value: Int) -> some View {
        HStack { Text(title); Spacer(); Text(value, format: .number).font(V5Typography.numeric) }
            .font(V5Typography.body).accessibilityElement(children: .combine)
    }
}

private struct V5ObservationPersonCard: View {
    @EnvironmentObject private var people: PeopleStore
    @EnvironmentObject private var router: V5Router
    var body: some View {
        V5Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("当前观察对象").font(V5Typography.evidence).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
                if let person = people.currentPerson {
                    Menu {
                        ForEach(people.people) { candidate in
                            Button { people.setCurrentPerson(candidate) } label: {
                                Text("\(candidate.name) · \(candidate.relation) · 档案 \(candidate.id.uuidString.prefix(8))")
                            }
                        }
                        Button("管理档案") { router.tab = 3 }
                    } label: {
                        HStack {
                            Label(person.name, systemImage: "person.crop.circle")
                            Spacer()
                            Image(systemName: "chevron.down")
                        }.font(V5Typography.section).frame(minHeight: V5Metric.target)
                    }.accessibilityLabel("切换观察人物，当前为\(person.name)")
                    Text("档案 \(person.id.uuidString.prefix(8)) · \(person.relation)").font(V5Typography.evidence)
                } else {
                    Text("尚未选择人物").font(V5Typography.title)
                    Button("添加或选择档案") { router.tab = 3 }.buttonStyle(V5PrimaryButton())
                }
            }
        }
    }
}
private struct V5ObservationEntryLabel: View {
    let title: String; let detail: String; let icon: String
    var body: some View {
        V5Card {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: icon).font(.title2).frame(width: V5Metric.target)
                    .foregroundStyle(V5Palette.color(V5Palette.current.accent)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(V5Typography.title)
                    Text(detail).font(V5Typography.detail).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
                }.fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).accessibilityHidden(true)
            }.frame(minHeight: V5Metric.target)
        }.accessibilityElement(children: .combine)
    }
}
private struct V5ObservationReferenceNote: View {
    var body: some View {
        Text("图解与传统相法、风水类象仅供民俗参考。照片测量用于记录位置、比例与描线，不作疾病诊断或保证性预测。")
            .font(V5Typography.evidence).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
    }
}
private extension View {
    func v5ObservationBackground(title: String) -> some View {
        background(V5Palette.color(V5Palette.current.paper))
            .foregroundStyle(V5Palette.color(V5Palette.current.ink))
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
}
