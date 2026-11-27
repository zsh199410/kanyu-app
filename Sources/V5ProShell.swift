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
    static func initialTheme(in defaults: UserDefaults = .standard) -> V5Theme {
        if let saved = defaults.string(forKey: "v5.theme"), let theme = V5Theme(rawValue: saved) { return theme }
        // Read the existing display preference without rewriting or migrating user defaults.
        return defaults.string(forKey: "uiStyle") == "dark" ? .night : .song
    }
    var scheme: ColorScheme { self == .night || self == .collection ? .dark : .light }
    var palette: V5Palette {
        switch self {
        case .song: return .init(paper: 0xF5EFE3, surface: 0xFCF8EF, ink: 0x173F32, secondary: 0x686054, accent: 0x23624B, ornament: 0xA57A39)
        case .night: return .init(paper: 0x101C29, surface: 0x1A2B3C, ink: 0xF3E9D3, secondary: 0xBEB9AC, accent: 0xD9B879, ornament: 0xD9B879)
        case .celadon: return .init(paper: 0xEFF4EE, surface: 0xFAFCF7, ink: 0x214B46, secondary: 0x5B7069, accent: 0x34776D, ornament: 0x96753E)
        case .collection: return .init(paper: 0x151411, surface: 0x25201B, ink: 0xF1D9AA, secondary: 0xC8B89C, accent: 0xE5BE77, ornament: 0xB88A46)
        }
    }
}
@Observable final class V5ThemeStore {
    static let shared = V5ThemeStore()
    private(set) var theme = V5Theme.initialTheme()
    @MainActor func select(_ value: V5Theme) {
        theme = value
        UserDefaults.standard.set(value.rawValue, forKey: "v5.theme")
    }
}
struct V5Palette {
    let paper: UInt32, surface: UInt32, ink: UInt32, secondary: UInt32, accent: UInt32, ornament: UInt32
    var isDark: Bool { paper == 0x101C29 || paper == 0x151411 }
    var heroSurface: UInt32 { paper == 0x151411 ? 0x641B18 : surface }
    var heroInk: UInt32 { paper == 0x151411 ? 0xF5DCAF : ink }
    var heroSecondary: UInt32 { paper == 0x151411 ? 0xDBC296 : secondary }
    var readingPaper: UInt32 { 0xF7F2E7 }
    var readingInk: UInt32 { 0x2D382F }
    var readingSecondary: UInt32 { 0x686054 }
    var readingAccent: UInt32 { 0x785521 }
    var success: UInt32 { isDark ? 0x52B788 : 0x306B4B }
    var failure: UInt32 { isDark ? 0xE98A76 : 0x9A2A22 }
    var ornamentText: UInt32 { isDark ? 0xD9B879 : 0x785521 }
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
enum V5Route: Hashable { case bazi, ziwei, qimen, survey, palm, face, tools, settings, profileCenter, appearance, updates, tool(String) }
@MainActor final class V5Router: ObservableObject {
    @Published var tab = 0
    @Published var paths: [Int: [V5Route]] = [:]
    func open(_ route: V5Route) {
        if case .tool(let id) = route { AllToolsData.recordRecent(tool: id) }
        paths[tab, default: []].append(route)
    }
    func path(for tab: Int) -> Binding<[V5Route]> {
        Binding(get: { self.paths[tab] ?? [] }, set: { self.paths[tab] = $0 })
    }
    var path: Binding<[V5Route]> { path(for: tab) }
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
    @Environment(\.dynamicTypeSize) private var navigationTypeSize
    @EnvironmentObject private var people: PeopleStore
    private var theme: V5Theme { V5ThemeStore.shared.theme }
    var body: some View {
        TabView(selection: $router.tab) {
            root(0) { V5HomeView() }
                .tabItem { Label { Text("首页") } icon: { tabIcon(.navHome, symbol: "house") } }.tag(0)
            root(1) { V5CalculationHub().accessibilityIdentifier("v5.measure") }
                .tabItem { Label { Text("测算") } icon: { tabIcon(.navMeasure, symbol: "safari") } }.tag(1)
            root(2) { V5LibraryPage().id(people.currentPerson?.id).accessibilityIdentifier("v5.reports") }
                .tabItem { Label { Text("命书") } icon: { tabIcon(.navReports, symbol: "book.closed") } }.tag(2)
            root(3) { V5ProfilesPage().accessibilityIdentifier("v5.people") }
                .tabItem { Label { Text("档案") } icon: { tabIcon(.navProfiles, symbol: "person.crop.circle") } }.tag(3)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            V5BottomNavigation(selection: $router.tab, theme: theme)
                .frame(height: navigationTypeSize.isAccessibilitySize ? 94 : 60)
                .background(V5Palette.color(theme.palette.paper).ignoresSafeArea(edges: .bottom))
        }
        .environmentObject(router)
        .tint(V5Palette.color(theme.palette.accent))
        .preferredColorScheme(theme.scheme)
    }
    private func tabIcon(_ role: V5ArtworkRole, symbol: String) -> Image {
        if let art = V5ArtworkRegistry.tabImage(role) { return Image(uiImage: art).renderingMode(.original) }
        return Image(systemName: symbol)
    }
    // Sibling stacks share typed routing; each tab owns its native title/search
    // preferences and stable path binding. There is no stack nested around TabView.
    private func root<Content: View>(_ tab: Int, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack(path: router.path(for: tab)) {
            content()
            .navigationDestination(for: V5Route.self) { route in
                switch route {
                case .bazi: V5BaziPage().id(people.currentPerson)
                case .ziwei: V5ZiweiPage().id(people.currentPerson)
                case .qimen: QimenHomeView()
                case .survey: V5SurveyPage()
                case .palm: V5PalmPage()
                case .face: V5FacePage()
                case .tools: AllToolsView(selectedTab: router.legacySelection)
                case .settings: V5SettingsPage()
                case .profileCenter: V5ProfileCenterView()
                case .updates: V5UpdatePage()
                case .appearance: V5AppearanceView()
                case .tool(let id):
                    if id == "almanac" { V5AlmanacPage() }
                    else if let item = AllToolsData.item(for: id) { ContextualToolDestination(item: item) }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { router.open(.profileCenter) } label: {
                        Image(systemName: "person.crop.circle").frame(minWidth: 48, minHeight: 48)
                    }
                    .accessibilityLabel("个人中心与全局设置")
                    .accessibilityIdentifier("全局设置与功能")
                }
            }
        }
        // Tab-bar visibility is a preference of each TabView child. Applying it
        // to TabView itself leaves the iOS 26 system bar alive beside our bar.
        .toolbar(.hidden, for: .tabBar)
    }
}
struct V5HomeView: View {
    @EnvironmentObject private var people: PeopleStore
    @EnvironmentObject private var router: V5Router
    @State private var chart: BaziChart?
    @State private var chartPerson: Person?
    @State private var showingCreatePerson = false
    var body: some View {
        VStack(spacing: 0) {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                V5BrandHero().accessibilityElement(children: .contain).accessibilityIdentifier("v5.home")
                V5PersonHero(chart: chartPerson == people.currentPerson ? chart : nil)
                V5PrimaryFeatureDeck().accessibilityElement(children: .contain).accessibilityIdentifier("v5.home.features")
                if V5ThemeStore.shared.theme == .celadon || V5ThemeStore.shared.theme == .collection { V5HomeBookEntry() }
                if let person = people.currentPerson {
                    V5Card {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("四柱 · 五行").font(V5Typography.section)
                                Spacer(minLength: 4)
                                Button { router.open(.bazi) } label: { Image(systemName: "chevron.right").frame(width: 48, height: 48) }
                                    .accessibilityLabel("查看八字命盘")
                            }
                            if chartPerson == person, let chart { V5HomeChartPreview(chart: chart) }
                            else { ProgressView("正在读取当前人物命盘") }
                            Button("阅读白话解读") { router.open(.tool("interpret")) }.font(.subheadline.weight(.medium)).frame(minHeight: V5Metric.target)
                        }
                    }
                }
                if V5ThemeStore.shared.theme == .song || V5ThemeStore.shared.theme == .night { V5HomeBookEntry() }
                V5HomeUtilityShelf()
                Text("传统民俗参考，不构成疾病诊断或保证性预测。")
                    .font(.footnote).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
            }.padding(.horizontal, V5Metric.page).padding(.bottom, 24)
        }
        .accessibilityIdentifier("home.scroll")
        }
        .background { V5SceneBackground() }
        .foregroundStyle(V5Palette.color(V5Palette.current.ink))
        .navigationTitle("首页").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showingCreatePerson = true } label: {
                    Image(systemName: "person.badge.plus").frame(width: 48, height: 48)
                }
                .accessibilityLabel("快速新建档案")
                .accessibilityHint("新建档案，保留当前命主选择")
                .accessibilityIdentifier("v5.home.create")
            }
        }
        .sheet(isPresented: $showingCreatePerson) {
            PersonFormView(store: people, person: Person(name: "", birthEpoch: Date().timeIntervalSince1970))
        }
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
struct V5AppearanceView: View {
    var body: some View { V5AppearancePage() }
}
