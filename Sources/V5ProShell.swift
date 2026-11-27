import SwiftUI
import Observation
import UIKit

/// The only V5 palette authority. Artwork is independently supplied; no reference screenshot is rendered.
enum V5Theme: String, CaseIterable, Identifiable {
    case song, night, celadon, collection
    var id: String { rawValue }
    var title: String {
        switch self {
        case .song: return "宋韵雅集 Pro"
        case .night: return "玄夜星河 Pro"
        case .celadon: return "白玉青瓷 Pro"
        case .collection: return "东方典藏 Pro"
        }
    }
    var scheme: ColorScheme { self == .night ? .dark : .light }
    var palette: V5Palette {
        switch self {
        case .song: return .init(paper: 0xF5EFE3, surface: 0xFCF8EF, ink: 0x173F32, secondary: 0x686054, accent: 0x23624B, ornament: 0xA57A39)
        case .night: return .init(paper: 0x101C29, surface: 0x1A2B3C, ink: 0xF3E9D3, secondary: 0xBEB9AC, accent: 0xA6CEC8, ornament: 0xD9B879)
        case .celadon: return .init(paper: 0xEFF4EE, surface: 0xFAFCF7, ink: 0x214B46, secondary: 0x5B7069, accent: 0x34776D, ornament: 0x96753E)
        case .collection: return .init(paper: 0xF1E6D1, surface: 0xFBF3E2, ink: 0x49382A, secondary: 0x746351, accent: 0x754634, ornament: 0x9A7132)
        }
    }
}
@Observable final class V5ThemeStore {
    static let shared = V5ThemeStore()
    private(set) var theme = V5Theme(rawValue: UserDefaults.standard.string(forKey: "v5.theme") ?? "song") ?? .song
    @MainActor func select(_ value: V5Theme) {
        theme = value
        UserDefaults.standard.set(value.rawValue, forKey: "v5.theme")
    }
}
struct V5Palette {
    let paper: UInt32, surface: UInt32, ink: UInt32, secondary: UInt32, accent: UInt32, ornament: UInt32
    var success: UInt32 { paper == 0x101C29 ? 0x52B788 : 0x367552 }
    var failure: UInt32 { paper == 0x101C29 ? 0xE98A76 : 0x9A2A22 }
    var ornamentText: UInt32 { paper == 0x101C29 ? 0xD9B879 : 0x785521 }
    static var current: V5Palette {
        V5ThemeStore.shared.theme.palette
    }
    enum Role: Sendable { case paper, surface, ink, secondary, accent, ornament, ornamentText, success, failure }
    func hex(_ role: Role) -> UInt32 {
        switch role {
        case .success: return success
        case .failure: return failure
        case .paper: return paper
        case .surface: return surface
        case .ink: return ink
        case .secondary: return secondary
        case .accent: return accent
        case .ornament: return ornament
        case .ornamentText: return ornamentText
        }
    }
    /// Capture the observable selection, then respect explicitly forced rendering
    /// schemes as well (e.g. a light poster while the application is in night mode).
    static func adaptive(_ role: Role) -> Color {
        let selected = V5ThemeStore.shared.theme
        return Color(uiColor: UIColor { traits in
            let scheme: ColorScheme = traits.userInterfaceStyle == .dark ? .dark : .light
            let p = (selected.scheme == scheme ? selected : (scheme == .dark ? V5Theme.night : .song)).palette
            let value = p.hex(role)
            return UIColor(red: CGFloat((value >> 16) & 255)/255,
                           green: CGFloat((value >> 8) & 255)/255,
                           blue: CGFloat(value & 255)/255, alpha: 1)
        })
    }
    static func color(_ value: UInt32) -> Color { Color(rgb: value) }
}
enum V5Metric {
    static let page: CGFloat = 20
    static let gap: CGFloat = 16
    static let corner: CGFloat = 24
    static let target: CGFloat = 48
}
enum V5Route: Hashable { case bazi, ziwei, qimen, survey, palm, tools, settings, appearance, updates, tool(String) }
@MainActor final class V5Router: ObservableObject {
    @Published var tab = 0
    @Published var paths: [Int: [V5Route]] = [:]
    func open(_ route: V5Route) { paths[tab, default: []].append(route) }
    var path: Binding<[V5Route]> { Binding(get: { self.paths[self.tab] ?? [] }, set: { self.paths[self.tab] = $0 }) }
    /// Old feature views keep their semantic destinations; old tab numbers never select V5 tabs directly.
    var legacySelection: Binding<Int> {
        Binding(get: { 0 }, set: { value in
            switch value {
            case 1: self.open(.bazi)
            case 2: self.open(.ziwei)
            case 3: self.open(.qimen)
            case 4: self.open(.survey)
            default: break
            }
        })
    }
}
struct V5ProShell: View {
    @StateObject private var router = V5Router()
    @EnvironmentObject private var people: PeopleStore
    private var theme: V5Theme { V5ThemeStore.shared.theme }
    var body: some View {
        NavigationStack(path: router.path) {
            TabView(selection: $router.tab) {
                V5HomeView().accessibilityIdentifier("v5.home").tabItem { Label("首页", systemImage: "house") }.tag(0)
                V5CalculationHub().accessibilityIdentifier("v5.measure").tabItem { Label("测算", systemImage: "safari") }.tag(1)
                V5LibraryPage()
                    .accessibilityIdentifier("v5.reports")
                    .id(people.currentPerson?.id)
                    .tabItem { Label("命书", systemImage: "book.closed") }.tag(2)
                V5ProfilesPage().accessibilityIdentifier("v5.people").tabItem { Label("档案", systemImage: "person.crop.circle") }.tag(3)
            }
            .navigationDestination(for: V5Route.self) { route in
                switch route {
                case .bazi: V5BaziPage().id(people.currentPerson)
                case .ziwei: V5ZiweiPage().id(people.currentPerson)
                case .qimen: QimenHomeView()
                case .survey: KanyuWorkbenchTabView()
                case .palm: PalmHomeView()
                case .tools: AllToolsView(selectedTab: router.legacySelection)
                case .settings: V5SettingsPage()
                case .updates: V5UpdatePage()
                case .appearance: V5AppearanceView()
                case .tool(let id):
                    if let item = AllToolsData.item(for: id) { ContextualToolDestination(item: item) }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("外观") { router.open(.appearance) }
                        Button("设置、AI 与备份") { router.open(.settings) }
                        Button("全部功能") { router.open(.tools) }
                        Button("更新与自签交接") { router.open(.updates) }
                    } label: { Image(systemName: "ellipsis.circle").frame(minWidth: 48, minHeight: 48) }
                    .accessibilityLabel("全局设置与功能")
                }
            }
        }
        .environmentObject(router)
        .tint(V5Palette.color(theme.palette.accent))
        .preferredColorScheme(theme.scheme)
    }
}
struct V5HomeView: View {
    @EnvironmentObject private var people: PeopleStore
    @EnvironmentObject private var router: V5Router
    @State private var chart: BaziChart?
    @State private var chartPerson: Person?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: V5Metric.gap) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("三术合参").font(.system(.largeTitle, design: .serif).weight(.semibold))
                    Text("东方命理 · 个人命书").font(.subheadline).tracking(3)
                }.padding(.vertical, 24)
                V5Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("当前命主").font(.caption)
                        if let person = people.currentPerson {
                            Menu {
                                ForEach(people.people) { candidate in
                                    Button {
                                        people.setCurrentPerson(candidate)
                                    } label: {
                                        Text("\(candidate.name) · \(candidate.relation) · \(DisplayTimeReceipt.beijing(candidate.birthDate)) · 档案 \(candidate.id.uuidString.prefix(8))")
                                    }
                                }
                                Button("管理人物档案") { router.tab = 3 }
                            } label: {
                                Label(person.name, systemImage: "person.crop.circle")
                                    .font(.system(.title, design: .serif))
                            }
                            .accessibilityLabel("切换命主")
                            .accessibilityIdentifier("v5.person.switch")
                            Text(DisplayTimeReceipt.beijing(person.birthDate)).font(.subheadline)
                            Text(person.relation).font(.caption)
                        } else {
                            Button("添加第一位家人或命主档案") { router.tab = 3 }
                                .frame(minHeight: V5Metric.target)
                            Text("创建真实档案后显示命盘与个人解读。")
                        }
                    }
                }
                V5MeasureLinks()
                if let person = people.currentPerson {
                    V5Card { VStack(alignment: .leading, spacing: 12) {
                        Text("命局 · 速览").font(.system(.title2, design: .serif))
                        if chartPerson == person, let chart {
                            V5BirthOverview(chart: chart)
                        } else {
                            ProgressView("正在读取当前人物命盘")
                        }
                        Button("查看当前人物的真实命盘与解读") { router.open(.tool("interpret")) }
                            .frame(minHeight: V5Metric.target)
                        Text(person.name).font(.caption)
                    } }
                }
                Text("传统民俗参考，不构成疾病诊断或保证性预测。")
                    .font(.footnote).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
            }.padding(V5Metric.page)
        }
        .background(V5Palette.color(V5Palette.current.paper))
        .foregroundStyle(V5Palette.color(V5Palette.current.ink))
        .navigationTitle("首页").navigationBarTitleDisplayMode(.inline)
        .task(id: people.currentPerson) {
            let selected = people.currentPerson
            chart = nil; chartPerson = nil
            await Task.yield()
            guard !Task.isCancelled, let selected else { return }
            let result = BaziEngine.cachedPaipan(clock: selected.birthDate, gender: selected.gender,
                longitude: selected.useLongitude ? selected.longitude : nil)
            guard !Task.isCancelled, people.currentPerson == selected else { return }
            chartPerson = selected; chart = result
        }
    }
}
private struct V5MeasureLinks: View {
    @EnvironmentObject private var router: V5Router
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))], spacing: V5Metric.gap) {
            entry("八字", "tablecells", .bazi)
            entry("紫微", "sparkles", .ziwei)
            entry("手相与面相", "hand.raised", .palm)
            entry("风水勘察", "safari", .survey)
            entry("万年历", "calendar", .tool("almanac"))
            entry("星命合参", "circle.hexagongrid", .tool("astro"))
            entry("奇门", "square.grid.3x3", .qimen)
            entry("全部功能", "square.grid.2x2", .tools)
        }
    }
    private func entry(_ title: String, _ icon: String, _ route: V5Route) -> some View {
        Button { router.open(route) } label: {
            V5Card { Label(title, systemImage: icon).font(.headline).frame(minHeight: V5Metric.target) }
        }.buttonStyle(.plain)
    }
}
struct V5AppearanceView: View {
    private var theme: String { V5ThemeStore.shared.theme.rawValue }
    var body: some View {
        List(V5Theme.allCases) { option in
            Button { V5ThemeStore.shared.select(option) } label: {
                HStack { Text(option.title); Spacer(); if theme == option.rawValue { Image(systemName: "checkmark") } }
                    .frame(minHeight: V5Metric.target)
            }.accessibilityAddTraits(theme == option.rawValue ? .isSelected : [])
        }.navigationTitle("四时外观")
    }
}
