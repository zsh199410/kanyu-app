// 底部 Tab 栏与核心分页（2026-11-05 build-72 iOS 27 架构升级版）
// 底部 5 大核心 Tab：合参（首页总工作台） / 八字 / 紫微 / 奇门 / 堪舆（风水与档案设置）
// 彻底替换掉原版在底部栏冗余且闪退的「日历」「黄历」Tab（黄历与择吉已修复闪退并整合至首页顶部今日黄历卡与专项工具）。
import SwiftUI
import LunarSwift

struct RootTabView: View {
    @AppStorage("onboardingDone") private var onboardingDone = false
    @ObservedObject private var errorCenter = AppErrorCenter.shared
    @State private var showingOnboarding = false
    @State private var tab = 0  // 默认落在「合参」主工作台
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { HomePageView(selectedTab: $tab) }
                .tabItem { Label("合参", systemImage: "sparkles.rectangle.stack.fill") }.tag(0)
            NavigationStack { BaziHomeView() }
                .tabItem { Label("八字", systemImage: "tablecells.fill") }.tag(1)
            NavigationStack { ZiweiHomeView() }
                .tabItem { Label("紫微", systemImage: "moon.stars.fill") }.tag(2)
            NavigationStack { QimenHomeView() }
                .tabItem { Label("奇门", systemImage: "circle.grid.3x3.fill") }.tag(3)
            NavigationStack { KanyuWorkbenchTabView() }
                .tabItem { Label("堪舆", systemImage: "safari.fill") }.tag(4)
        }
        .tint(Ky.qingdai)
        .sheet(isPresented: $showingOnboarding) {
            OnboardingView(onDone: { onboardingDone = true; showingOnboarding = false })
        }
        .onAppear { if !onboardingDone { showingOnboarding = true } }
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
            VStack(spacing: 14) {
                AlmanacCalendarCard(date: $date)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(info.dayInGanZhi + "日")
                            .font(.system(.title2, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
                        Text("\(info.yearInGanZhi)年 · \(info.monthInGanZhi)月 · 农历\(info.monthInChinese)月\(info.dayInChinese)")
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
                            Text("查看当日完整黄历（二十八宿 · 吉神 · 十二时辰）")
                                .font(.subheadline).fontWeight(.medium).foregroundStyle(Ky.qingdai)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Ky.qingdai)
                        }
                    }.buttonStyle(.plain)
                }.kyCard()
            }
            .padding(16)
            .padding(.bottom, 32)
        }
        .background(Ky.bg)
        .navigationTitle("干支日历").navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 择吉：按事项查近 30 天宜日（结果缓存化，滚动零重算）
struct ZejiView: View {
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
    }

    private func computeMatches(for ev: String) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let start = cal.startOfDay(for: Date())
        var out: [ZejiItem] = []
        for i in 0..<30 {
            guard let d = cal.date(byAdding: .day, value: i, to: start) else { continue }
            let info = AlmanacLunarCache.dayInfo(for: d)
            if info.dayYi.contains(ev) {
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
                    jiLine: "忌：" + info.dayJi.prefix(4).joined(separator: " ") + " · 冲" + info.chongShaText
                ))
            }
        }
        cachedMatches = out
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
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
                        Text("近 30 天内历书无宜「\(event)」之日").font(.subheadline).fontWeight(.semibold).foregroundStyle(Ky.ink)
                        Text("可切换上方其他事项，或在黄历页翻看下月日期。")
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
                Text("口径说明：择吉只按历书日宜忌初筛；婚嫁、入宅、开市等大事须结合当事人命局喜忌与冲合综合裁定。")
                    .font(.caption2).foregroundStyle(Ky.sub)
            }
            .padding(16)
            .padding(.bottom, 32)
        }
        .background(Ky.bg)
        .navigationTitle("择吉通参").navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if cachedMatches.isEmpty { computeMatches(for: event) }
        }
    }
}

// MARK: - 八字论财：财星 / 财库 / 五行占比 / 财运大运
struct WealthView: View {
    @StateObject private var peopleStore = PeopleStore()
    @State private var selectedID: UUID?
    private var person: Person? {
        peopleStore.people.first(where: { $0.id == selectedID }) ?? peopleStore.people.first
    }
    private var chart: BaziChart? {
        guard let p = person else { return nil }
        return BaziEngine.paipan(clock: p.birthDate, gender: p.gender,
                                 longitude: p.useLongitude ? p.longitude : nil)
    }
    private static let kuOf: [String: String] = ["木": "未", "火": "戌", "土": "辰", "金": "丑", "水": "辰"]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if peopleStore.people.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.badge.exclamationmark").font(.largeTitle).foregroundStyle(Ky.gold)
                        Text("尚无人物档案").font(.headline).foregroundStyle(Ky.ink)
                        Text("请先在「人物档案」或「八字排盘」中保存至少一位命主，即可在此查看专盘论财。")
                            .font(.caption).foregroundStyle(Ky.sub).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 24).kyCard()
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(peopleStore.people) { p in
                                let active = person?.id == p.id
                                Button { selectedID = p.id } label: {
                                    HStack(spacing: 5) {
                                        Text(p.name.isEmpty ? "未命名" : p.name)
                                            .font(.subheadline).fontWeight(active ? .bold : .medium)
                                        Text(p.gender == "M" ? "男" : "女")
                                            .font(.caption2).opacity(0.8)
                                    }
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(active ? Ky.qingdai : Ky.card)
                                    .foregroundStyle(active ? Color.white : Ky.ink)
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(active ? Ky.qingdai : Ky.line, lineWidth: 0.8))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    if let p = person, let ch = chart {
                        wealthCard(p: p, ch: ch)
                    }
                }
                Text("论财纪律：财星多不等于发财，原局无财亦不等于穷（须查食伤生财、禄当财看及大运补财）；须结合日主承载力与岁运引动综合看。")
                    .font(.caption2).foregroundStyle(Ky.sub)
            }
            .padding(16)
            .padding(.bottom, 32)
        }
        .background(Ky.bg)
        .navigationTitle("八字论财").navigationBarTitleDisplayMode(.inline)
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
                        Text("\(ch.dayunStartYear(i))–\(ch.dayunStartYear(i) + 9)")
                            .font(KyV2.tabular(13, weight: .medium)).foregroundStyle(Ky.sub)
                            .frame(width: 86, alignment: .leading)
                        Text("\(gz)运")
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
    @StateObject private var peopleStore = PeopleStore()
    @State private var selected: Set<UUID> = []
    private var picked: [Person] { peopleStore.people.filter { selected.contains($0.id) } }
    private func chart(_ p: Person) -> BaziChart {
        BaziEngine.paipan(clock: p.birthDate, gender: p.gender, longitude: p.useLongitude ? p.longitude : nil)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("在档案里勾选 2–4 位命主并排比盘；日主或日柱相同的会高亮标出。")
                    .font(.caption).foregroundStyle(Ky.sub)
                if peopleStore.people.isEmpty {
                    Text("还没有人物档案——先到「人物档案」建人，再回来对比。")
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
                                Text("命宫 \(ch.mingGong) · 身宫 \(ch.shenGong) · 胎元 \(ch.taiYuan)")
                                    .font(.caption2).foregroundStyle(Ky.sub)
                            }.kyCard()
                        }
                        NavigationLink { SynastryView() } label: {
                            HStack {
                                Image(systemName: "heart.circle.fill").foregroundStyle(Ky.cinnabar)
                                Text("如需深入合参两人喜用互补与配偶宫关系，点此进入「合盘合婚」")
                                    .font(.caption).fontWeight(.medium).foregroundStyle(Ky.qingdai)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Ky.sub)
                            }.kyCard()
                        }.buttonStyle(.plain)
                    } else if !selected.isEmpty {
                        Text("已选 \(selected.count) 人，请再勾选至少 1 人以生成并排对比。")
                            .font(.caption).foregroundStyle(Ky.sub)
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 32)
        }
        .background(Ky.bg)
        .navigationTitle("多盘并排对比").navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 五运六气独立页
struct YunQiPageView: View {
    @State private var year: Int = Calendar.current.component(.year, from: Date())
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack {
                    Text("推算年份").font(.subheadline).fontWeight(.medium).foregroundStyle(Ky.ink)
                    Spacer()
                    Button { year = max(1901, year - 1) } label: {
                        Image(systemName: "chevron.left").frame(width: 30, height: 30).background(Ky.elevated).clipShape(Circle())
                    }.accessibilityLabel("上一年")
                    Text("\(year) 年").font(KyV2.tabular(16, weight: .bold)).frame(minWidth: 80, alignment: .center)
                    Button { year = min(2099, year + 1) } label: {
                        Image(systemName: "chevron.right").frame(width: 30, height: 30).background(Ky.elevated).clipShape(Circle())
                    }.accessibilityLabel("下一年")
                    Button("今年") { year = Calendar.current.component(.year, from: Date()) }
                        .font(.caption).foregroundStyle(Ky.qingdai)
                }.kyCard()
                YunQiView(year: year)
            }
            .padding(16)
            .padding(.bottom, 32)
        }
        .background(Ky.bg)
        .navigationTitle("五运六气").navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 我的与系统设置页
struct MyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    AppLogoView(size: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("三术合参").font(.system(.title3, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
                        Text("子平五典 · 天纪斗数 · 统宗奇门 · 堪舆SOP")
                            .font(.caption).foregroundStyle(Ky.qingdai)
                        Text("全本机离线演算 · 零云端追踪")
                            .font(.caption2).foregroundStyle(Ky.sub)
                    }
                    Spacer()
                }.kyCard()

                KySectionTitle(title: "档案账本", trailing: "本机持久化存储")
                VStack(spacing: 10) {
                    myLink("person.2.fill", "人物档案管理", "家人与命例建档 · 支持 JSON 导入导出备份", Ky.qingdai) { PeopleView() }
                    myLink("checkmark.seal.fill", "前瞻断语登记簿", "事前封存断语 · 到期核验命中率", Ky.jade) { ForecastView() }
                    myLink("hand.raised.fill", "手相面相与测量记录", "21点几何掌型 · 三线手描 · 三停校准归档", Ky.gold) { PalmHomeView() }
                }

                KySectionTitle(title: "智库设置", trailing: "口径与条文")
                VStack(spacing: 10) {
                    myLink("slider.horizontal.3", "排盘口径与签名证书设置", "晚子时归日 · 紫微闰月 · 侧载证书到期提醒", Ky.qingdai) { CaliberSettingsView() }
                    myLink("text.book.closed.fill", "五典与实务断语库（100条）", "类象 · 长生 · 格局 · 健康 · 合婚 · 破局调理", Ky.gold) { LibraryView() }
                    myLink("books.vertical.fill", "风水知识与解煞手册", "玄空八宅测法 · 17类形煞L1-L3分层化解", Ky.cinnabar) { ShaHandbookView() }
                }
            }
            .padding(16)
            .padding(.bottom, 32)
        }
        .background(Ky.bg)
        .navigationTitle("档案与设置").navigationBarTitleDisplayMode(.inline)
    }

    private func myLink<Dest: View>(_ icon: String, _ title: String, _ sub: String, _ color: Color, @ViewBuilder dest: @escaping () -> Dest) -> some View {
        NavigationLink(destination: dest()) {
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
