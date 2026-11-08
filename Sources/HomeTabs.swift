// 底部 Tab 栏与核心分页（2026-11-05 build-72 iOS 27 架构升级版）
// 底部 5 大核心 Tab：合参（首页总工作台） / 八字 / 紫微 / 奇门 / 堪舆（风水与档案设置）
// 彻底替换掉原版在底部栏冗余且闪退的「日历」「黄历」Tab（黄历与择吉已修复闪退并整合至首页顶部今日黄历卡与专项工具）。
import SwiftUI
import UIKit
import LunarSwift

struct RootTabView: View {
    @AppStorage("onboardingDone") private var onboardingDone = false
    @AppStorage("uiStyle") private var appearanceRaw = "system"
    @ObservedObject private var errorCenter = AppErrorCenter.shared
    @State private var showingOnboarding = false
    @State private var tab = 0  // 默认落在「合参」主工作台

    /// 显示设置（MyView (6) 深色三档）：跟随系统时返回 nil；浅色／深色强制对应外观
    private var appearanceScheme: ColorScheme? {
        if appearanceRaw == "dark" { return .dark }
        if appearanceRaw == "light" { return .light }
        return nil
    }
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { HomePageView(selectedTab: $tab) }
                .tabItem { Label("合参".scriptConverted, systemImage: "sparkles.rectangle.stack.fill") }.tag(0)
            NavigationStack { BaziHomeView() }
                .tabItem { Label("八字".scriptConverted, systemImage: "tablecells.fill") }.tag(1)
            NavigationStack { ZiweiHomeView() }
                .tabItem { Label("紫微".scriptConverted, systemImage: "moon.stars.fill") }.tag(2)
            NavigationStack { QimenHomeView() }
                .tabItem { Label("奇门".scriptConverted, systemImage: "circle.grid.3x3.fill") }.tag(3)
            NavigationStack { KanyuWorkbenchTabView() }
                .tabItem { Label("堪舆".scriptConverted, systemImage: "safari.fill") }.tag(4)
        }
        .toolbarBackground(Ky.bg, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .tint(Ky.qingdai)
        .preferredColorScheme(appearanceScheme)
        .sheet(isPresented: $showingOnboarding) {
            OnboardingView(onDone: { onboardingDone = true; showingOnboarding = false })
        }
        .onAppear {
            DataProtection.protectExistingFiles()
            if !onboardingDone { showingOnboarding = true }
        }
        .overlay(alignment: .top) {
            if let message = errorCenter.message {
                AppErrorBanner(message: message) { errorCenter.dismiss() }
                    .padding(.horizontal, 16).padding(.top, 8)
            }
        }
    }
}

// MARK: - 日历选日页（供首页/黄历内跳转使用，已根治闪退）
struct MonthCalendarTabView: View {
    @State private var date = Date()
    var body: some View {
        let info = AlmanacLunarCache.dayInfo(for: date)
        ScrollView {
            LazyVStack(spacing: 14) {
                AlmanacCalendarCard(date: $date)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(info.dayInGanZhi + "日")
                            .font(.system(.title2, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
                        Text("\(info.yearInGanZhi)年 · \(info.monthInGanZhi)月 · 农历\(info.monthInChinese)月\(info.dayInChinese)".scriptConverted)
                            .font(.caption).foregroundStyle(Ky.sub)
                        Spacer()
                        KyBadge(text: "\(info.zhiXing)日", color: Ky.qingdai)
                    }
                    HStack(spacing: 10) {
                        KyBadge(text: "宜", color: Ky.jade, filled: true)
                        Text(info.dayYi.prefix(6).joined(separator: " ")).font(.caption).foregroundStyle(Ky.ink).lineLimit(1)
                    }
                    HStack(spacing: 10) {
                        KyBadge(text: "忌", color: Ky.cinnabar, filled: true)
                        Text(info.dayJi.prefix(6).joined(separator: " ")).font(.caption).foregroundStyle(Ky.sub).lineLimit(1)
                    }
                    Divider()
                    NavigationLink { AlmanacView(initialDate: date) } label: {
                        HStack {
                            Image(systemName: "book.pages.fill").foregroundStyle(Ky.qingdai)
                            Text("查看当日完整黄历（二十八宿 · 吉神 · 十二时辰）".scriptConverted)
                                .font(.subheadline).fontWeight(.medium).foregroundStyle(Ky.qingdai)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Ky.qingdai)
                        }
                    }.buttonStyle(.plain)
                }.kyCard()
            }
            .padding(16)
            .padding(.bottom, 100)
        }
        .background(Ky.bg)
        .navigationTitle(Text("干支日历".scriptConverted)).navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 择吉：按事项查近 30 天宜日（结果缓存化，滚动零重算）
struct ZejiView: View {
    @EnvironmentObject var peopleStore: PeopleStore
    @State private var zejiPersonID: UUID?
    @State private var filteredCount = 0
    private var zejiPerson: Person? {
        if let id = zejiPersonID { return peopleStore.people.first(where: { $0.id == id }) }
        return peopleStore.people.first
    }

    @State private var event = "嫁娶"
    @State private var cachedMatches: [ZejiItem] = []
    private static let events = ["嫁娶", "纳采", "开市", "入宅", "移徙", "安葬", "动土", "出行", "祈福", "修造", "立券", "交易"]

    struct ZejiItem: Identifiable {
        let id: String
        let date: Date
        let monthNum: Int
        let dayNum: Int
        let weekInChinese: String
        let lunarTitle: String
        let ganZhiZhiXing: String
        let yiLine: String
        let jiLine: String
        let isSpecial: Bool
    }

    private func computeMatches(for ev: String) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let start = cal.startOfDay(for: Date())
        // 命主八字：日支／年支用于冲克过滤，喜用神用于专属大吉日判定
        let person = zejiPerson
        let pchart: BaziChart? = person.map { BaziEngine.cachedPaipan(clock: $0.birthDate, gender: $0.gender, longitude: $0.useLongitude ? $0.longitude : nil) }
        let xi: [Int] = pchart.map { InterpretEngine.posterXiJi(chart: $0).xi } ?? []
        let dayBr: String? = pchart.map { String($0.pillars[2].last ?? "?") }
        let yearBr: String? = pchart.map { String($0.pillars[0].last ?? "?") }
        var out: [ZejiItem] = []
        var filtered = 0
        for i in 0..<30 {
            guard let d = cal.date(byAdding: .day, value: i, to: start) else { continue }
            let info = AlmanacLunarCache.dayInfo(for: d)
            if info.dayYi.contains(ev) {
                let gz = info.dayInGanZhi
                let dStem = String(gz.first ?? "?")
                let dBranch = String(gz.last ?? "?")
                // 冲克命主日支或年支的日子直接过滤
                if let db = dayBr, let yb = yearBr, person != nil {
                    if Self.clashMap[dBranch] == db || Self.clashMap[dBranch] == yb { filtered += 1; continue }
                }
                // 专属大吉日：日干支生扶喜用神，或与命主日支三合六合
                var special = false
                if person != nil, !xi.isEmpty, let db = dayBr {
                    let sWx = Self.stemWx(dStem), bWx = Self.branchWx(dBranch)
                    if xi.contains(sWx) || xi.contains(bWx) { special = true }
                    if xi.contains((sWx + 1) % 5) || xi.contains((bWx + 1) % 5) { special = true }
                    if Self.liuHeMap[dBranch] == db { special = true }
                    if Self.sanHe.contains(where: { $0.contains(dBranch) && $0.contains(db) }) { special = true }
                }
                let c = cal.dateComponents([.year, .month, .day], from: d)
                out.append(ZejiItem(
                    id: "\(c.year ?? 2026)-\(c.month ?? 1)-\(c.day ?? 1)",
                    date: d,
                    monthNum: c.month ?? 1,
                    dayNum: c.day ?? 1,
                    weekInChinese: info.weekInChinese,
                    lunarTitle: "农历\(info.monthInChinese)月\(info.dayInChinese)",
                    ganZhiZhiXing: "\(info.dayInGanZhi)日 · \(info.zhiXing)",
                    yiLine: "宜：" + info.dayYi.prefix(7).joined(separator: " "),
                    jiLine: "忌：" + info.dayJi.prefix(4).joined(separator: " ") + " · 冲" + info.chongShaText,
                    isSpecial: special
                ))
            }
        }
        cachedMatches = out
        filteredCount = filtered
    }

    private static let clashMap: [String: String] = ["子": "午", "午": "子", "丑": "未", "未": "丑", "寅": "申", "申": "寅", "卯": "酉", "酉": "卯", "辰": "戌", "戌": "辰", "巳": "亥", "亥": "巳"]
    private static let liuHeMap: [String: String] = ["子": "丑", "丑": "子", "寅": "亥", "亥": "寅", "卯": "戌", "戌": "卯", "辰": "酉", "酉": "辰", "巳": "申", "申": "巳", "午": "未", "未": "午"]
    private static let sanHe: [[String]] = [["申", "子", "辰"], ["寅", "午", "戌"], ["巳", "酉", "丑"], ["亥", "卯", "未"]]
    private static func stemWx(_ s: String) -> Int {
        switch s { case "甲", "乙": return 0; case "丙", "丁": return 1; case "戊", "己": return 2; case "庚", "辛": return 3; default: return 4 }
    }
    private static func branchWx(_ b: String) -> Int {
        switch b { case "寅", "卯": return 0; case "巳", "午": return 1; case "辰", "戌", "丑", "未": return 2; case "申", "酉": return 3; default: return 4 }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                PersonQuickBar(store: peopleStore, selectedID: zejiPerson?.id) { p in
                    zejiPersonID = p.id
                    computeMatches(for: event)
                }
                if let zp = zejiPerson {
                    Text("命主：\(zp.name.isEmpty ? "未命名" : zp.name) · 已自动过滤冲克其日支／年支的日子\(filteredCount > 0 ? "（\(filteredCount) 天）" : "")，金色徽章为命主专属大吉日。")
                        .font(.caption).foregroundStyle(Ky.sub)
                } else {
                    Text("从上方选一位命主，自动过滤冲克其日支／年支的日子并标出专属大吉日。".scriptConverted)
                        .font(.caption).foregroundStyle(Ky.sub)
                }
                VStack(alignment: .leading, spacing: 10) {
                    KySectionTitle(title: "择吉事项", trailing: "近 30 天历书初筛")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(Self.events, id: \.self) { e in
                            let isSel = event == e
                            Button {
                                event = e
                                computeMatches(for: e)
                            } label: {
                                Text(e)
                                    .font(.subheadline).fontWeight(isSel ? .bold : .regular)
                                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                                    .background(isSel ? Ky.qingdai : Ky.elevated)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .foregroundStyle(isSel ? Color.white : Ky.ink)
                            }.buttonStyle(.plain)
                        }
                    }
                }.kyCard()

                KySectionTitle(title: "宜「\(event)」吉日", trailing: "共 \(cachedMatches.count) 天")

                if cachedMatches.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "calendar.badge.exclamationmark").font(.title2).foregroundStyle(Ky.cinnabar)
                        Text("近 30 天内历书无宜「\(event)」之日".scriptConverted).font(.subheadline).fontWeight(.semibold).foregroundStyle(Ky.ink)
                        Text("可切换上方其他事项，或在黄历页翻看下月日期。".scriptConverted)
                            .font(.caption).foregroundStyle(Ky.sub)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 20)
                    .kyCard()
                } else {
                    ForEach(cachedMatches) { item in
                        NavigationLink { AlmanacView(initialDate: item.date) } label: {
                            HStack(spacing: 12) {
                                VStack(spacing: 2) {
                                    Text("\(item.monthNum)月").font(.caption2).foregroundStyle(Ky.sub)
                                    Text("\(item.dayNum)").font(KyV2.tabular(20, weight: .bold)).foregroundStyle(Ky.qingdai)
                                    Text("周\(item.weekInChinese)").font(.caption2).foregroundStyle(Ky.sub)
                                }
                                .frame(width: 48, height: 56)
                                .background(Ky.elevated)
                                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text(item.lunarTitle).font(.subheadline).fontWeight(.bold).foregroundStyle(Ky.ink)
                                        KyBadge(text: item.ganZhiZhiXing, color: Ky.gold)
                                        if item.isSpecial { KyBadge(text: "命主专属大吉日", color: Ky.cinnabar, filled: true) }
                                    }
                                    Text(item.yiLine).font(.caption).foregroundStyle(Ky.jade).lineLimit(1)
                                    Text(item.jiLine).font(.caption2).foregroundStyle(Ky.sub).lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Ky.sub)
                            }
                            .kyCard()
                        }.buttonStyle(.plain)
                    }
                }
                Text("口径说明：已按所选命主过滤冲克其日支／年支的日子；专属大吉日＝日干支生扶命主喜用神或与日支三合六合；婚嫁、入宅、开市等大事仍须结合全盘综合裁定。".scriptConverted)
                    .font(.caption2).foregroundStyle(Ky.sub)
            }
            .padding(16)
            .padding(.bottom, 100)
        }
        .background(Ky.bg)
        .navigationTitle(Text("择吉通参".scriptConverted)).navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if cachedMatches.isEmpty { computeMatches(for: event) }
        }
    }
}

// MARK: - 八字论财：财星 / 财库 / 五行占比 / 财运大运
struct WealthView: View {
    @EnvironmentObject var peopleStore: PeopleStore
    @State private var selectedID: UUID?
    private var person: Person? {
        peopleStore.people.first(where: { $0.id == selectedID }) ?? peopleStore.people.first
    }
    private var chart: BaziChart? {
        guard let p = person else { return nil }
        return BaziEngine.cachedPaipan(clock: p.birthDate, gender: p.gender,
                                 longitude: p.useLongitude ? p.longitude : nil)
    }
    private static let kuOf: [String: String] = ["木": "未", "火": "戌", "土": "辰", "金": "丑", "水": "辰"]
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if peopleStore.people.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.badge.exclamationmark").font(.largeTitle).foregroundStyle(Ky.gold)
                        Text("尚无人物档案".scriptConverted).font(.headline).foregroundStyle(Ky.ink)
                        Text("请先在「人物档案」或「八字排盘」中保存至少一位命主，即可在此查看专盘论财。".scriptConverted)
                            .font(.caption).foregroundStyle(Ky.sub).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 24).kyCard()
                } else {
                    PersonQuickBar(store: peopleStore, selectedID: selectedID) { p in selectedID = p.id }
                    if let p = person, let ch = chart {
                        wealthCard(p: p, ch: ch)
                    }
                }
                Text("论财纪律：财星多不等于发财，原局无财亦不等于穷（须查食伤生财、禄当财看及大运补财）；须结合日主承载力与岁运引动综合看。".scriptConverted)
                    .font(.caption2).foregroundStyle(Ky.sub)
            }
            .padding(16)
            .padding(.bottom, 100)
        }
        .background(Ky.bg)
        .navigationTitle(Text("八字论财".scriptConverted)).navigationBarTitleDisplayMode(.inline)
    }

    private func wealthCard(p: Person, ch: BaziChart) -> some View {
        let dayStem = ch.rizhu.first!
        let dayWx = BaziTables.wx[dayStem]?.0 ?? ""
        let allShiShen = ch.stemShiShen.enumerated().filter { $0.offset != 2 }.map { $0.element } + ch.hideShiShen.flatMap { $0 }
        let zhengCai = allShiShen.filter { $0 == "正财" }.count
        let pianCai = allShiShen.filter { $0 == "偏财" }.count
        let ku = Self.kuOf[dayWx] ?? ""
        let kuPillars = ["年", "月", "日", "时"].enumerated().filter { ch.pillars[$0.offset].last.map { String($0) } == ku }.map { $0.element }
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(p.name.isEmpty ? "未命名" : p.name)")
                        .font(.system(.title3, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
                    KyBadge(text: "日主 \(ch.rizhu)\(dayWx)", color: KyV2.color(forChar: dayStem))
                    Spacer()
                    Text(ch.pillars.joined(separator: "  "))
                        .font(.system(.subheadline, design: .serif)).fontWeight(.semibold).foregroundStyle(Ky.qingdai)
                }
                Divider()
                HStack(spacing: 10) {
                    metricBox("正财（透＋藏）", "\(zhengCai) 处", zhengCai > 0 ? Ky.jade : Ky.sub)
                    metricBox("偏财（透＋藏）", "\(pianCai) 处", pianCai > 0 ? Ky.gold : Ky.sub)
                    metricBox("财库（\(dayWx)库\(ku)）", kuPillars.isEmpty ? "原局无库" : "\(kuPillars.joined(separator: "、"))柱见库", kuPillars.isEmpty ? Ky.sub : Ky.cinnabar)
                }
            }.kyCard()

            VStack(alignment: .leading, spacing: 10) {
                KySectionTitle(title: "五行力量", trailing: "天干＋藏干加权")
                WuxingBarsView(percents: ch.wuxingPercents)
            }.kyCard()

            VStack(alignment: .leading, spacing: 10) {
                KySectionTitle(title: "财运大运", trailing: "标亮正偏财透干之运")
                ForEach(ch.dayunGanZhi.indices, id: \.self) { i in
                    let gz = ch.dayunGanZhi[i]
                    let ss = BaziTables.shiShen(day: dayStem, stem: gz.first!)
                    let isCai = (ss == "正财" || ss == "偏财")
                    HStack {
                        Text("\(String(ch.dayunStartYear(i)))–\(String(ch.dayunStartYear(i) + 9))")
                            .font(KyV2.tabular(13, weight: .medium)).foregroundStyle(Ky.sub)
                            .frame(width: 86, alignment: .leading)
                        Text("\(gz)运".scriptConverted)
                            .font(.system(.callout, design: .serif)).fontWeight(.bold)
                            .foregroundStyle(isCai ? Ky.cinnabar : Ky.ink)
                        Spacer()
                        KyBadge(text: "运干 · \(ss)", color: isCai ? Ky.gold : Ky.sub, filled: isCai)
                    }
                    .padding(.vertical, 4)
                    if i < ch.dayunGanZhi.count - 1 { Divider().opacity(0.4) }
                }
            }.kyCard()
        }
    }

    private func metricBox(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(Ky.sub).lineLimit(1)
            Text(value).font(.subheadline).fontWeight(.bold).foregroundStyle(color).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .kySubCard()
    }
}

// MARK: - 多盘对比：档案里挑 2–4 人并排比四柱 / 日主 / 命宫身宫 / 旬空
struct CompareView: View {
    @EnvironmentObject var peopleStore: PeopleStore
    @State private var selected: Set<UUID> = []
    private var picked: [Person] { peopleStore.people.filter { selected.contains($0.id) } }
    private func chart(_ p: Person) -> BaziChart {
        BaziEngine.cachedPaipan(clock: p.birthDate, gender: p.gender, longitude: p.useLongitude ? p.longitude : nil)
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                PersonQuickBar(store: peopleStore) { p in
                    if selected.contains(p.id) { selected.remove(p.id) }
                    else if selected.count < 4 { selected.insert(p.id) }
                }
                Text("在档案里勾选 2–4 位命主并排比盘；日主或日柱相同的会高亮标出。".scriptConverted)
                    .font(.caption).foregroundStyle(Ky.sub)
                if peopleStore.people.isEmpty {
                    Text("还没有人物档案——先到「人物档案」建人，再回来对比。".scriptConverted)
                        .font(.callout).foregroundStyle(Ky.sub).padding(.top, 12)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(peopleStore.people) { p in
                            let isSel = selected.contains(p.id)
                            Button {
                                if isSel { selected.remove(p.id) }
                                else if selected.count < 4 { selected.insert(p.id) }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: isSel ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isSel ? Ky.qingdai : Ky.sub)
                                    Text(p.name.isEmpty ? "未命名" : p.name)
                                        .font(.subheadline).fontWeight(isSel ? .semibold : .regular).foregroundStyle(Ky.ink)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(p.gender == "M" ? "男" : "女").font(.caption2).foregroundStyle(Ky.sub)
                                }
                                .padding(10)
                                .background(isSel ? Ky.qingdai.opacity(0.11) : Ky.card)
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(isSel ? Ky.qingdai : Ky.line, lineWidth: isSel ? 1.2 : 0.7))
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }.buttonStyle(.plain)
                        }
                    }

                    if picked.count >= 2 {
                        let charts = picked.map { chart($0) }
                        let sameRizhu = Set(charts.map { $0.rizhu }).count == 1
                        let sameDay = Set(charts.map { $0.dayPillar }).count == 1
                        if sameRizhu || sameDay {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkle").foregroundStyle(Ky.gold)
                                Text("共性发现：\(sameRizhu ? "日主皆为 \(charts[0].rizhu)" : "")\(sameRizhu && sameDay ? "；" : "")\(sameDay ? "日柱皆为 \(charts[0].dayPillar)" : "")")
                                    .font(.callout).fontWeight(.semibold).foregroundStyle(Ky.qingdai)
                            }.kyCard()
                        }
                        ForEach(picked.indices, id: \.self) { i in
                            let p = picked[i]; let ch = charts[i]
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(p.name.isEmpty ? "未命名" : p.name)
                                        .font(.system(.headline, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
                                    KyBadge(text: p.gender == "M" ? "乾造" : "坤造", color: Ky.qingdai)
                                    Spacer()
                                    Text("日主 \(ch.rizhu) · 旬空 \(ch.xunKong)")
                                        .font(.caption).foregroundStyle(Ky.sub)
                                }
                                HStack(spacing: 8) {
                                    ForEach(0..<4, id: \.self) { col in
                                        let gz = ch.pillars[col]
                                        VStack(spacing: 2) {
                                            Text(["年柱", "月柱", "日柱", "时柱"][col]).font(.caption2).foregroundStyle(Ky.sub)
                                            HStack(spacing: 2) {
                                                Text(String(gz.first!)).foregroundStyle(KyV2.color(forChar: gz.first!))
                                                Text(String(gz.last!)).foregroundStyle(KyV2.color(forChar: gz.last!))
                                            }
                                            .font(.system(.title3, design: .serif)).fontWeight(.bold)
                                            Text(ch.stemShiShen[col]).font(.system(size: 10)).foregroundStyle(Ky.gold)
                                        }
                                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                                        .background(Ky.elevated).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    }
                                }
                                Text("命宫 \(ch.mingGong) · 身宫 \(ch.shenGong) · 胎元 \(ch.taiYuan)".scriptConverted)
                                    .font(.caption2).foregroundStyle(Ky.sub)
                            }.kyCard()
                        }
                        NavigationLink { SynastryView() } label: {
                            HStack {
                                Image(systemName: "heart.circle.fill").foregroundStyle(Ky.cinnabar)
                                Text("如需深入合参两人喜用互补与配偶宫关系，点此进入「合盘合婚」".scriptConverted)
                                    .font(.caption).fontWeight(.medium).foregroundStyle(Ky.qingdai)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Ky.sub)
                            }.kyCard()
                        }.buttonStyle(.plain)
                    } else if !selected.isEmpty {
                        Text("已选 \(selected.count) 人，请再勾选至少 1 人以生成并排对比。".scriptConverted)
                            .font(.caption).foregroundStyle(Ky.sub)
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 100)
        }
        .background(Ky.bg)
        .navigationTitle(Text("多盘并排对比".scriptConverted)).navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 五运六气独立页
struct YunQiPageView: View {
    @State private var year: Int = Calendar.current.component(.year, from: Date())
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                HStack {
                    Text("推算年份").font(.subheadline).fontWeight(.medium).foregroundStyle(Ky.ink)
                    Spacer()
                    Button { year = max(1901, year - 1) } label: {
                        Image(systemName: "chevron.left").frame(width: 30, height: 30).background(Ky.elevated).clipShape(Circle())
                    }.accessibilityLabel("上一年")
                    Text("\(String(year)) 年").font(KyV2.tabular(16, weight: .bold)).frame(minWidth: 80, alignment: .center)
                    Button { year = min(2099, year + 1) } label: {
                        Image(systemName: "chevron.right").frame(width: 30, height: 30).background(Ky.elevated).clipShape(Circle())
                    }.accessibilityLabel("下一年")
                    Button("今年") { year = Calendar.current.component(.year, from: Date()) }
                        .font(.caption).foregroundStyle(Ky.qingdai)
                }.kyCard()
                YunQiView(year: year)
                Text("依据：中运出《素问·天元纪大论》，主气六步与司天在泉出《素问·六元正纪大论》《六微旨大论》体系，与 Web /api/wuyunliuqi 同口径；季度提示只讲节律，不落病名。金标准见 Web tools/tests/test_wuyunliuqi.py（12 年份＋5 人小运逐项复算）。".scriptConverted)
                    .font(.caption2).foregroundStyle(Ky.sub)
            }
            .padding(16)
            .padding(.bottom, 100)
        }
        .background(Ky.bg)
        .navigationTitle(Text("五运六气".scriptConverted)).navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 我的与系统设置页
struct MyView: View {
    // G1 每日运势本地通知：默认关闭；开关＋时间（默认 07:30），只存本机偏好
    @AppStorage("todayNotify.enabled") private var notifyEnabled = false
    @AppStorage("todayNotify.hour") private var notifyHour = 7
    @AppStorage("todayNotify.minute") private var notifyMinute = 30
    @AppStorage("uiStyle") private var appearanceRaw = "system"

    private var notifyTimeBinding: Binding<Date> {
        Binding(
            get: {
                var cal = Calendar.current
                cal.timeZone = TimeZone(secondsFromGMT: 8 * 3600) ?? TimeZone.current
                var dc = cal.dateComponents([.year, .month, .day], from: Date())
                dc.hour = notifyHour
                dc.minute = notifyMinute
                return cal.date(from: dc) ?? Date()
            },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                notifyHour = c.hour ?? 7
                notifyMinute = c.minute ?? 30
                if notifyEnabled {
                    let p = PeopleStore.shared.people.first(where: { $0.relation == "本人" }) ?? PeopleStore.shared.people.first
                    TodayNotificationManager.scheduleDaily(person: p)
                }
            }
        )
    }

    @MainActor private func rescheduleTodayNotification() {
        let p = PeopleStore.shared.people.first(where: { $0.relation == "本人" }) ?? PeopleStore.shared.people.first
        TodayNotificationManager.scheduleDaily(person: p)
    }

    /// (1) 个人资料：全局当前命主卡片 → PersonDetailView；无档案时进 PeopleView 建档
    @ViewBuilder
    private var personalProfileSection: some View {
        if let p = PeopleStore.shared.currentPerson {
            NavigationLink { PersonDetailView(person: p, store: PeopleStore.shared) } label: {
                HStack(spacing: 12) {
                    Text(currentPersonAvatarText)
                        .font(.system(size: 16, weight: .bold, design: .serif))
                        .foregroundStyle(Ky.qingdai)
                        .frame(width: 44, height: 44)
                        .background(Ky.qingdai.opacity(0.14))
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(currentPersonDisplayName)
                            .font(.subheadline).fontWeight(.bold).foregroundStyle(Ky.ink)
                        Text(currentPersonSubtitle)
                            .font(.caption2).foregroundStyle(Ky.sub).lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Ky.sub)
                }
                .kyCard()
            }.buttonStyle(.plain)
        } else {
            NavigationLink { PeopleView() } label: {
                HStack(spacing: 12) {
                    Text("命")
                        .font(.system(size: 16, weight: .bold, design: .serif))
                        .foregroundStyle(Ky.qingdai)
                        .frame(width: 44, height: 44)
                        .background(Ky.qingdai.opacity(0.14))
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("尚未建档")
                            .font(.subheadline).fontWeight(.bold).foregroundStyle(Ky.ink)
                        Text("去添加第一位命主档案，建档一次三术通用".scriptConverted)
                            .font(.caption2).foregroundStyle(Ky.sub).lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Ky.sub)
                }
                .kyCard()
            }.buttonStyle(.plain)
        }
    }

    private var currentPersonAvatarText: String {
        if let p = PeopleStore.shared.currentPerson, !p.name.isEmpty { return String(p.name.prefix(1)) }
        return "命"
    }

    private var currentPersonDisplayName: String {
        if let p = PeopleStore.shared.currentPerson, !p.name.isEmpty { return p.name }
        return "未命名"
    }

    private var currentPersonSubtitle: String {
        if let p = PeopleStore.shared.currentPerson {
            var lon: Double? = nil
            if p.useLongitude { lon = p.longitude }
            let chart = BaziEngine.cachedPaipan(clock: p.birthDate, gender: p.gender, longitude: lon)
            var sub = chart.pillars.joined(separator: " ") + " · 日主" + chart.rizhu
            if !p.relation.isEmpty { sub = p.relation + " · " + sub }
            return sub
        }
        return ""
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    AppLogoView(size: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("三术合参".scriptConverted).font(.system(.title3, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
                        Text("子平五典 · 天纪斗数 · 统宗奇门 · 堪舆勘察".scriptConverted)
                            .font(.caption).foregroundStyle(Ky.qingdai)
                        Text("全本机离线演算 · 零云端追踪".scriptConverted)
                            .font(.caption2).foregroundStyle(Ky.sub)
                    }
                    Spacer()
                }.kyCard()

                // (1) 个人资料：全局当前命主的 PersonDetailView（不新建「我的资料」页）
                KySectionTitle(title: "个人资料", trailing: "当前命主")
                personalProfileSection

                // (2) 人物档案
                KySectionTitle(title: "人物档案", trailing: "本机持久化存储")
                VStack(spacing: 10) {
                    myLink("person.2.fill", "人物档案管理", "家人与命例建档 · 支持数据导入导出备份", Ky.qingdai) { PeopleView() }
                }

                // (3) 我的记录：前瞻登记簿＋手相面相记录（原散落在「档案账本」组内，现立分组标题）
                KySectionTitle(title: "我的记录", trailing: "封存与回验")
                VStack(spacing: 10) {
                    myLink("checkmark.seal.fill", "前瞻断语登记簿", "事前封存断语 · 到期核验命中率", Ky.jade) { ForecastView() }
                    myLink("hand.raised.fill", "手相面相与测量记录", "21点几何掌型 · 三线手描 · 三停校准归档", Ky.gold) { PalmHomeView() }
                }

                // (4) 我的命书／报告中心（P3）：报告中心已上线——按人物归档已生成的命书 PDF 与海报
                KySectionTitle(title: "我的命书／报告中心", trailing: "已生成命书与海报")
                VStack(alignment: .leading, spacing: 8) {
                    myLink("doc.text.fill", "生成我的命书（PDF）", "当前命主的命书文件 · 在详情页生成后分享", Ky.qingdai) {
                        if let p = PeopleStore.shared.currentPerson {
                            PersonDetailView(person: p, store: PeopleStore.shared)
                        } else {
                            PeopleView()
                        }
                    }
                    myLink("archivebox.fill", "报告中心", "已生成的命书 PDF 与海报 · 按人物归档 · 含生成时间与类型", Ky.gold) {
                        ReportCenterView()
                    }
                }

                // (5) 智库设置
                KySectionTitle(title: "智库设置", trailing: "口径与条文")
                VStack(spacing: 10) {
                    myLink("slider.horizontal.3", "排盘口径与签名证书设置", "晚子时归日 · 紫微闰月 · 侧载证书到期提醒", Ky.qingdai) { CaliberSettingsView() }
                    myLink("text.book.closed.fill", "五典与实务断语库（100条）", "类象 · 长生 · 格局 · 健康 · 合婚 · 破局调理", Ky.gold) { LibraryView() }
                    myLink("books.vertical.fill", "风水知识与解煞手册", "玄空八宅测法 · 17类形煞L1-L3分层化解", Ky.cinnabar) { ShaHandbookView() }
                }

                // (6) 显示设置：深色手动切换（跟随系统／浅色／深色三档）＋语言（简／繁）
                KySectionTitle(title: "显示设置", trailing: "深色 · 语言")
                VStack(alignment: .leading, spacing: 8) {
                    Text("深色模式")
                        .font(.subheadline).fontWeight(.semibold).foregroundStyle(Ky.ink)
                    Picker("深色模式", selection: $appearanceRaw) {
                        Text("跟随系统".scriptConverted).tag("system")
                        Text("浅色".scriptConverted).tag("light")
                        Text("深色").tag("dark")
                    }
                    .pickerStyle(.segmented)
                    Text("跟随系统时随 iOS 外观自动切换；浅色为宋纸暖白，深色为暗夜玄金。字号走系统动态字体，不另设。".scriptConverted)
                        .font(.caption2).foregroundStyle(Ky.sub).lineSpacing(2)
                    ScriptSettingsView()
                }.kyCard()

                // (7) 通知设置（原「每日运势」组，内容不动）
                KySectionTitle(title: "通知设置", trailing: "本机本地通知")
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("每日推送今日运势", isOn: $notifyEnabled)
                        .font(.subheadline).fontWeight(.semibold).foregroundStyle(Ky.ink)
                        .tint(Ky.qingdai)
                        .onChange(of: notifyEnabled) { _, newValue in
                            if newValue {
                                TodayNotificationManager.requestAuthorization { granted in
                                    if granted {
                                        rescheduleTodayNotification()
                                    } else {
                                        notifyEnabled = false
                                    }
                                }
                            } else {
                                TodayNotificationManager.cancel()
                            }
                        }
                    if notifyEnabled {
                        DatePicker("推送时间", selection: notifyTimeBinding, displayedComponents: .hourAndMinute)
                            .font(.callout).foregroundStyle(Ky.ink)
                    }
                    Text("默认关闭；开启后每天一条（当日干支＋三行首句），iOS 本地通知，不走服务端、不收集数据；未建档时不排期。".scriptConverted)
                        .font(.caption2).foregroundStyle(Ky.sub).lineSpacing(2)
                }.kyCard()

                // (8) 数据管理：备份恢复入口原只挂堪舆工作台，现并入个人中心
                KySectionTitle(title: "数据管理", trailing: "备份与恢复")
                VStack(spacing: 10) {
                    myLink("archivebox.fill", "数据备份与恢复", "人物 · 前瞻 · 手相记录 · 堪舆案件打包 ZIP · 支持 iCloud", Ky.qingdai) { BackupView() }
                }

                // (9) 关于
                KySectionTitle(title: "关于", trailing: "版本与隐私")
                VStack(spacing: 10) {
                    myLink("info.circle.fill", "关于三术合参", "版本号 · 构建号 · 致谢 · 隐私说明", Ky.qingdai) { AboutView() }
                }

            }
            .padding(16)
            .padding(.bottom, 100)
        }
        .background(Ky.bg)
        .navigationTitle(Text("档案与设置".scriptConverted)).navigationBarTitleDisplayMode(.inline)
    }

    private func myLink<Dest: View>(_ icon: String, _ title: String, _ sub: String, _ color: Color, @ViewBuilder dest: @escaping () -> Dest) -> some View {
        NavigationLink {
            dest()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(color)
                    .frame(width: 36, height: 36).background(color.opacity(0.13)).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline).fontWeight(.semibold).foregroundStyle(Ky.ink)
                    Text(sub).font(.caption2).foregroundStyle(Ky.sub)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Ky.sub)
            }
            .kyCard()
        }.buttonStyle(.plain)
    }
}

// MARK: - 关于页（UI 2.0 P0 新建，轻量）：版本号／构建号／致谢／隐私说明
struct AboutView: View {
    private var appVersion: String {
        if let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String { return v }
        return "4.6"
    }

    private var buildNumber: String {
        if let v = Bundle.main.infoDictionary?["CFBundleVersion"] as? String { return v }
        return ""
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    AppLogoView(size: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("三术合参".scriptConverted).font(.system(.title3, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
                        Text(("版本 " + appVersion + "（构建 " + buildNumber + "）").scriptConverted)
                            .font(.caption).foregroundStyle(Ky.qingdai)
                        Text("子平八字 · 天纪斗数 · 统宗奇门 · 实景堪舆".scriptConverted)
                            .font(.caption2).foregroundStyle(Ky.sub)
                    }
                    Spacer()
                }.kyCard()

                KySectionTitle(title: "隐私说明", trailing: "本机优先")
                VStack(alignment: .leading, spacing: 8) {
                    Text("三术合参不设账号、不上传生辰：人物档案、前瞻登记与手相测量记录只存在本机 Documents 目录；排盘与解盘全部本机演算；每日运势通知为 iOS 本地通知，不走服务端；AI 问答只把当前命盘的引擎事实发往你自有的免费模型池，问题原文不写库、不记日志。".scriptConverted)
                        .font(.callout).foregroundStyle(Ky.ink).lineSpacing(3)
                }.kyCard()

                KySectionTitle(title: "致谢", trailing: "五典正法")
                VStack(alignment: .leading, spacing: 8) {
                    Text("断语口径以《滴天髓》《子平真诠》《穷通宝鉴》《三命通会》《渊海子平》五典为准；紫微亮度表采中州派口径；奇门拆补法定局依《奇门遁甲统宗》。金标准对拍与依据链见学堂页「依据与金标准」。".scriptConverted)
                        .font(.callout).foregroundStyle(Ky.ink).lineSpacing(3)
                }.kyCard()
            }
            .padding(16)
            .padding(.bottom, 100)
        }
        .background(Ky.bg)
        .navigationTitle(Text("关于".scriptConverted)).navigationBarTitleDisplayMode(.inline)
    }
}
