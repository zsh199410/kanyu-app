// 全部工具二级页（UI 2.0 P0 新建，2026-11-08）：收纳审计 §3.2 的全部专项工具，零删除。
// 分组：排盘／历法择吉／知识库／工具；含搜索（KySearchBar）与分类（KyFilterBar）。
// 「最近使用」读 UserDefaults 键 "recentTools.v1"（人物／工具 id 列表，见 AllToolsData）。
import SwiftUI

// MARK: - 工具清单数据（HomePageView 06 层共用）

enum ToolGroup: String, CaseIterable {
    case all = "全部"
    case paipan = "排盘"
    case calendar = "历法择吉"
    case knowledge = "知识库"
    case tools = "工具"
}

struct ToolItem: Identifiable {
    let id: String
    let title: String
    let desc: String
    let icon: String
    let color: Color
    let group: ToolGroup
}

enum RecentEntry: Identifiable {
    case person(Person)
    case tool(ToolItem)

    var id: String {
        switch self {
        case .person(let p):
            return "person:" + p.id.uuidString
        case .tool(let t):
            return t.id
        }
    }
}

struct AllToolsData {
    static let recentKey = "recentTools.v1"
    static let recentLimit = 6

    static let allItems: [ToolItem] = [
        ToolItem(id: "astro", title: "星命合参", desc: "八字 × 西洋星盘 · 双术印证", icon: "sparkles", color: Ky.gold, group: .paipan),
        ToolItem(id: "synastry", title: "合盘合婚", desc: "合婚四看 · 喜用互补", icon: "heart.circle.fill", color: Ky.cinnabar, group: .paipan),
        ToolItem(id: "wealth", title: "八字论财", desc: "财星 · 财库 · 财运大运", icon: "yensign.circle.fill", color: Ky.gold, group: .paipan),
        ToolItem(id: "ganzhi", title: "干支反查", desc: "由四柱反推公历生辰", icon: "magnifyingglass.circle.fill", color: Ky.qingdai, group: .paipan),
        ToolItem(id: "family", title: "全家盘", desc: "三人盘并置 · 合参裁决", icon: "person.3.fill", color: Ky.jade, group: .paipan),
        ToolItem(id: "sharecard", title: "合盘分享卡", desc: "双盘速览 · 总评一句 · 二维码", icon: "qrcode", color: Ky.qingdai, group: .paipan),
        ToolItem(id: "compare", title: "多盘对比", desc: "2–4 人并排比四柱", icon: "person.3.fill", color: Ky.jade, group: .paipan),
        ToolItem(id: "yearly", title: "逐年四查", desc: "大运流年 · 逐年直断", icon: "calendar", color: Ky.qingdai, group: .paipan),
        ToolItem(id: "interpret", title: "30 维详批", desc: "30 条详批 · 分类导航", icon: "doc.text.fill", color: Ky.gold, group: .paipan),
        ToolItem(id: "poster", title: "海报导出", desc: "四款海报 · 1080 宽长图", icon: "photo.fill", color: Ky.qingdai, group: .paipan),
        ToolItem(id: "reportcenter", title: "报告中心", desc: "已生成命书与海报 · 按人物归档", icon: "archivebox.fill", color: Ky.qingdai, group: .paipan),
        ToolItem(id: "almanac", title: "万年历", desc: "公历农历 · 干支节气宜忌", icon: "calendar.day.timeline.left", color: Ky.qingdai, group: .calendar),
        ToolItem(id: "monthcal", title: "干支日历选日", desc: "按月翻日 · 干支速查", icon: "calendar", color: Ky.gold, group: .calendar),
        ToolItem(id: "zeji", title: "择吉", desc: "近 30 天择吉通参", icon: "sparkles", color: Ky.gold, group: .calendar),
        ToolItem(id: "yunqi", title: "五运六气", desc: "岁运 · 司天在泉主客气", icon: "aqi.medium", color: Ky.qingdai, group: .calendar),
        ToolItem(id: "chenggu", title: "称骨", desc: "四重称重 · 52 格歌诀", icon: "scalemass.fill", color: Ky.cinnabar, group: .calendar),
        ToolItem(id: "meihua", title: "六爻梅花", desc: "时间起卦 · 体用六亲", icon: "yinyang", color: Ky.qingdai, group: .calendar),
        ToolItem(id: "library", title: "五典断语库", desc: "100 条已核定类象 · 格局 · 调候", icon: "text.book.closed.fill", color: Ky.qingdai, group: .knowledge),
        ToolItem(id: "classics", title: "古籍检索", desc: "《滴天髓》歌诀 · 《子平真诠》全文", icon: "book.fill", color: Ky.jade, group: .knowledge),
        ToolItem(id: "academy", title: "学堂", desc: "图书馆 · 古籍 · 题库一页收拢", icon: "graduationcap.fill", color: Ky.qingdai, group: .knowledge),
        ToolItem(id: "quiz", title: "排盘口径自测", desc: "44 题口径自测 · 引擎现算复核", icon: "questionmark.circle.fill", color: Ky.gold, group: .knowledge),
        ToolItem(id: "celeb", title: "名人命例库", desc: "公开史料生辰 · 双盘即时对参", icon: "person.crop.rectangle.stack.fill", color: Ky.gold, group: .knowledge),
        ToolItem(id: "shahandbook", title: "风水知识与解煞手册", desc: "玄空八宅测法 · 17 类形煞分层化解", icon: "books.vertical.fill", color: Ky.cinnabar, group: .knowledge),
        ToolItem(id: "compass", title: "罗盘实测", desc: "磁北／真北 · 锁定带入堪舆", icon: "safari.fill", color: Ky.gold, group: .tools),
        ToolItem(id: "floorplan", title: "户型压盘", desc: "导入户型图 · 拖拽立极中宫", icon: "square.split.diagonal.2x2", color: Ky.qingdai, group: .tools),
        ToolItem(id: "ask", title: "AI 问答", desc: "只引引擎事实 · 附依据链", icon: "bubble.left.and.text.bubble.right.fill", color: Ky.jade, group: .tools),
        ToolItem(id: "forecast", title: "前瞻登记簿", desc: "起卦断语封存 · 到期回验", icon: "checkmark.seal.fill", color: Ky.jade, group: .tools),
        ToolItem(id: "backup", title: "备份恢复", desc: "人物与前瞻备份 · ZIP 导入恢复", icon: "archivebox.fill", color: Ky.qingdai, group: .tools),
        ToolItem(id: "caliber", title: "排盘口径设置", desc: "晚子时 · 紫微闰月 · 签名证书", icon: "slider.horizontal.3", color: Ky.qingdai, group: .tools),
        ToolItem(id: "workbench", title: "风水勘察", desc: "罗盘定盘 · 玄空八宅 · 案件", icon: "safari.fill", color: Ky.gold, group: .tools),
    ]

    static func item(for id: String) -> ToolItem? {
        allItems.first(where: { $0.id == id })
    }

    /// 记一次最近使用（工具 id 或 "person:<uuid>"，去重后置顶，上限 6 条）
    static func recordRecent(tool id: String) {
        var list: [String] = []
        if let stored = UserDefaults.standard.stringArray(forKey: recentKey) { list = stored }
        list.removeAll(where: { $0 == id })
        list.insert(id, at: 0)
        if list.count > recentLimit { list = Array(list.prefix(recentLimit)) }
        UserDefaults.standard.set(list, forKey: recentKey)
    }

    static func recordRecent(person p: Person) {
        recordRecent(tool: "person:" + p.id.uuidString)
    }

    /// 最近使用条目（按记录顺序；人物 id 解析不到档案时跳过）
    static func recentEntries(people: [Person]) -> [RecentEntry] {
        var out: [RecentEntry] = []
        if let stored = UserDefaults.standard.stringArray(forKey: recentKey) {
            for key in stored {
                if key.hasPrefix("person:") {
                    let idString = String(key.dropFirst("person:".count))
                    if let id = UUID(uuidString: idString), let p = people.first(where: { $0.id == id }) {
                        out.append(.person(p))
                    }
                } else if let item = item(for: key) {
                    out.append(.tool(item))
                }
            }
        }
        return out
    }
}

// MARK: - 工具目标页（HomePageView 最近使用共用；风水勘察走切 Tab，不进此 switch）

@ViewBuilder
func toolDestination(for item: ToolItem, person: Person, chart: BaziChart) -> some View {
    switch item.id {
    case "astro":
        AstroHomeView(person: person, chart: chart)
    case "synastry":
        SynastryView()
    case "wealth":
        WealthView()
    case "ganzhi":
        GanZhiLookupView()
    case "family":
        FamilyChartView()
    case "sharecard":
        SynastryShareCardView()
    case "compare":
        CompareView()
    case "yearly":
        YearByYearView(chart: chart, name: person.name)
    case "interpret":
        InterpretView(chart: chart, name: person.name)
    case "poster":
        BaziResultView(chart: chart, name: person.name)
    case "reportcenter":
        ReportCenterView()
    case "almanac":
        AlmanacView()
    case "monthcal":
        MonthCalendarTabView()
    case "zeji":
        ZejiView()
    case "yunqi":
        YunQiPageView()
    case "chenggu":
        ChengguView(person: person, chart: chart)
    case "meihua":
        MeihuaView()
    case "library":
        LibraryView()
    case "classics":
        ClassicsView()
    case "academy":
        AcademyView()
    case "quiz":
        QuizView()
    case "celeb":
        CelebView()
    case "shahandbook":
        ShaHandbookView()
    case "compass":
        CompassStandaloneView()
    case "floorplan":
        FloorPlanOverlayView()
    case "ask":
        AskView()
    case "forecast":
        ForecastView()
    case "backup":
        BackupView()
    case "caliber":
        CaliberSettingsView()
    default:
        EmptyView()
    }
}

// MARK: - 全部工具页

struct AllToolsView: View {
    @EnvironmentObject var peopleStore: PeopleStore
    @Binding var selectedTab: Int
    @State private var query = ""
    @State private var selectedGroup = 0

    private var groups: [ToolGroup] { [.all, .paipan, .calendar, .knowledge, .tools] }

    private var currentPerson: Person {
        if let p = peopleStore.currentPerson { return p }
        return Person(name: "命主", relation: "本人", gender: "M", birthEpoch: Date().timeIntervalSince1970)
    }

    private var currentChart: BaziChart {
        let p = currentPerson
        return BaziEngine.paipan(clock: p.birthDate, gender: p.gender, longitude: p.useLongitude ? p.longitude : nil)
    }

    private var filterOptions: [(title: String, count: Int?)] {
        groups.map { (title: $0.rawValue, count: countFor($0)) }
    }

    private func countFor(_ group: ToolGroup) -> Int? {
        if group == .all { return AllToolsData.allItems.count }
        return AllToolsData.allItems.filter { $0.group == group }.count
    }

    private var filtered: [ToolItem] {
        var list = AllToolsData.allItems
        if selectedGroup > 0 {
            let g = groups[selectedGroup]
            list = list.filter { $0.group == g }
        }
        if !query.isEmpty {
            list = list.filter { $0.title.contains(query) || $0.desc.contains(query) }
        }
        return list
    }

    private var grouped: [(ToolGroup, [ToolItem])] {
        var order: [ToolGroup] = []
        var map: [ToolGroup: [ToolItem]] = [:]
        for item in filtered {
            if map[item.group] == nil { order.append(item.group) }
            map[item.group, default: []].append(item)
        }
        return order.map { ($0, map[$0, default: []]) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                KySearchBar(text: $query, placeholder: "搜索专项工具…")
                KyFilterBar(options: filterOptions, selectedIndex: $selectedGroup)
                recentSection
                ForEach(grouped, id: \.0) { g in
                    KySectionTitle(title: g.0.rawValue, trailing: "共 \(g.1.count) 项")
                    VStack(spacing: 10) {
                        ForEach(g.1) { item in toolRow(item) }
                    }
                }
                if filtered.isEmpty {
                    KyEmptyState(icon: "magnifyingglass", title: "没有找到相关工具", message: "换个关键词试试，或切换上方的分类。")
                }
            }
            .padding(.horizontal, KyV6.pageHorizontalMargin)
            .padding(.top, 6)
            .padding(.bottom, 100)
        }
        .background(Ky.bg)
        .navigationTitle("全部工具".scriptConverted)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var recentSection: some View {
        let recents = AllToolsData.recentEntries(people: peopleStore.people)
        if !recents.isEmpty {
            KySectionTitle(title: "最近使用", trailing: "最近打开的人物与工具")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(recents) { entry in recentChip(entry) }
                }
            }
        }
    }

    @ViewBuilder
    private func recentChip(_ entry: RecentEntry) -> some View {
        switch entry {
        case .person(let p):
            NavigationLink { PersonDetailView(person: p, store: peopleStore) } label: {
                HStack(spacing: 6) {
                    Text(p.name.isEmpty ? "命" : String(p.name.prefix(1)))
                        .font(.system(size: 13, weight: .bold, design: .serif))
                        .foregroundStyle(Ky.qingdai)
                    Text(p.name).font(.subheadline).fontWeight(.semibold).foregroundStyle(Ky.ink)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Ky.card)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Ky.line, lineWidth: 0.8))
            }
            .buttonStyle(.plain)
        case .tool(let item):
            if item.id == "workbench" {
                Button { selectedTab = 4 } label: {
                    chipLabel(item)
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink { toolDestination(for: item, person: currentPerson, chart: currentChart) } label: {
                    chipLabel(item)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func chipLabel(_ item: ToolItem) -> some View {
        HStack(spacing: 6) {
            Image(systemName: item.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(item.color)
            Text(item.title.scriptConverted)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Ky.ink)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Ky.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Ky.line, lineWidth: 0.8))
    }

    @ViewBuilder
    private func toolRow(_ item: ToolItem) -> some View {
        if item.id == "workbench" {
            Button {
                AllToolsData.recordRecent(tool: item.id)
                selectedTab = 4
            } label: {
                rowLabel(item)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                toolDestination(for: item, person: currentPerson, chart: currentChart)
            } label: {
                rowLabel(item)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded { _ in AllToolsData.recordRecent(tool: item.id) })
        }
    }

    private func rowLabel(_ item: ToolItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(item.color)
                .frame(width: 36, height: 36)
                .background(item.color.opacity(0.13))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title.scriptConverted)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(Ky.ink)
                Text(item.desc.scriptConverted)
                    .font(.caption2)
                    .foregroundStyle(Ky.sub)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Ky.sub)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Ky.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Ky.line.opacity(0.9), lineWidth: 0.8))
    }
}
