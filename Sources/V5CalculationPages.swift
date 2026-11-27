import SwiftUI

/// The calculation workspace uses the same selected UUID and routes as the shell.
/// Every card is a navigation entry; existing professional tools remain available.
struct V5CalculationHub: View {
    @EnvironmentObject private var people: PeopleStore
    @EnvironmentObject private var router: V5Router
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: V5Metric.gap) {
                V5CalculationPersonHeader()
                Text("以命为经 · 以术为纬").font(.system(.title, design: .serif))
                Text("从真实档案出发，核对命盘，再展开专业分析。")
                    .foregroundStyle(V5Palette.color(V5Palette.current.secondary))
                V5CalculationEntry(title: "八字命理", detail: "四柱 · 藏干十神 · 五行 · 大运", icon: "tablecells") { router.open(.bazi) }.accessibilityIdentifier("v5.measure.bazi")
                V5CalculationEntry(title: "紫微斗数", detail: "十二宫原盘 · 主辅星 · 生年四化", icon: "sparkles") { router.open(.ziwei) }.accessibilityIdentifier("v5.measure.ziwei")
                Text("观形察象").font(.system(.title2, design: .serif))
                V5CalculationEntry(title: "手相", detail: "掌纹图解、照片测量与按人归档", icon: "hand.raised") { router.open(.palm) }
                NavigationLink {
                    V5FacePage()
                } label: {
                    V5CalculationEntryLabel(title: "面相", detail: "正面照片三停校准 · 手动复核标线", icon: "face.smiling")
                }.buttonStyle(.plain)
                V5CalculationEntry(title: "风水与罗盘", detail: "罗盘实测 · 户型立极 · 玄空八宅", icon: "safari") { router.open(.survey) }
                toolEntry("compass", title: "罗盘实测", detail: "磁北、真北与锁定方位", icon: "location.north.circle")
                Text("时序与合参").font(.system(.title2, design: .serif))
                toolEntry("almanac", title: "万年历", detail: "公农历 · 干支 · 节气与宜忌", icon: "calendar")
                toolEntry("astro", title: "星命合参", detail: "八字与西洋星盘的双术印证", icon: "circle.hexagongrid")
                V5CalculationEntry(title: "奇门遁甲", detail: "时局排盘与专业解读", icon: "square.grid.3x3") { router.open(.qimen) }
                V5CalculationEntry(title: "全部功能", detail: "合婚、全家盘、择吉、报告与知识库", icon: "square.grid.2x2") { router.open(.tools) }
                V5CalculationDisclaimer()
            }.padding(V5Metric.page)
        }
        .v5CalculationPage(title: "测算")
        .accessibilityIdentifier("v5.calculation.hub")
    }
    private func toolEntry(_ id: String, title: String, detail: String, icon: String) -> some View {
        V5CalculationEntry(title: title, detail: detail, icon: icon) { router.open(.tool(id)) }
    }
}

struct V5BaziPage: View {
    @EnvironmentObject private var people: PeopleStore
    @EnvironmentObject private var router: V5Router
    @State private var result: V5BaziSnapshot?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: V5Metric.gap) {
                V5CalculationPersonHeader()
                if let person = people.currentPerson {
                    if let result, result.person == person {
                        Text("命盘档案 \(result.person.id.uuidString.prefix(8))").font(.caption.monospaced())
                            .accessibilityIdentifier("v5.bazi.result.owner").accessibilityValue(result.person.id.uuidString)
                        content(result.chart)
                    } else {
                        ProgressView("正在排出当前命主的四柱").frame(minHeight: 120)
                    }
                } else {
                    V5CalculationProfilePrompt()
                }
                NavigationLink { BaziHomeView().id(people.currentPerson) } label: {
                    V5CalculationEntryLabel(title: "八字专业工作台", detail: "录入校时 · 专业细盘 · 流年流月 · 合参与导出", icon: "slider.horizontal.3")
                }.buttonStyle(.plain)
                V5CalculationEntry(title: "全部命理工具", detail: "30 维详批、论财、逐年四查与多盘对比", icon: "square.grid.2x2") { router.open(.tools) }
                V5CalculationDisclaimer()
            }.padding(V5Metric.page)
        }
        .v5CalculationPage(title: "八字命理")
        .accessibilityIdentifier("v5.bazi.page")
        .task(id: people.currentPerson) {
            let selected = people.currentPerson
            // The immutable full Person value includes UUID and every birth input.
            // Keep results only while they match that exact selection, including edits.
            guard result?.person != selected else { return }
            result = nil
            await Task.yield()
            guard let selected, !Task.isCancelled else { return }
            let chart = BaziEngine.cachedPaipan(clock: selected.birthDate, gender: selected.gender,
                                               longitude: selected.useLongitude ? selected.longitude : nil)
            guard !Task.isCancelled, people.currentPerson == selected else { return }
            result = V5BaziSnapshot(person: selected, chart: chart)
        }
    }
    @ViewBuilder private func content(_ chart: BaziChart) -> some View {
        V5Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("日主 · \(chart.rizhu)").font(.system(.title, design: .serif))
                Text(chart.lunarText).font(.subheadline)
                Text(chart.longitude == nil ? "北京时间 · 未启用经度校正" : "已按档案经度校正真太阳时")
                    .font(.caption).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
                if let solarDate = chart.trueSolarDate {
                    Text("真太阳时 \(DisplayTimeReceipt.beijing(solarDate))").font(.caption)
                }
                V5BirthOverview(chart: chart)
            }
        }
        V5Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("四柱细读").font(.system(.title2, design: .serif))
                ForEach(Array(chart.pillars.enumerated()), id: \.offset) { index, pillar in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(["年柱", "月柱", "日柱", "时柱"][index]) · \(pillar)").font(.headline)
                        Text("天干十神：\(chart.stemShiShen[index])　地势：\(chart.diShi[index])")
                        Text("藏干：\(chart.hideGan[index].joined(separator: "、"))")
                        Text("藏干十神：\(chart.hideShiShen[index].joined(separator: "、"))")
                        Text("纳音：\(chart.naYin[index])").foregroundStyle(V5Palette.color(V5Palette.current.secondary))
                    }.font(.subheadline).accessibilityElement(children: .combine)
                    if index < 3 { Divider() }
                }
                Text("日柱旬空：\(chart.xunKong)").font(.subheadline)
            }
        }
        V5TenGodDistribution(chart: chart)
        V5Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("大运脉络").font(.system(.title2, design: .serif))
                Text("\(chart.qiyunDirection) · 起运 \(chart.qiyunDate)").font(.subheadline)
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(Array(chart.dayunGanZhi.enumerated()), id: \.offset) { index, ganZhi in
                            VStack(spacing: 8) {
                                Text(ganZhi).font(.system(.title2, design: .serif))
                                Text("\(String(chart.dayunStartYear(index))) 年起").font(.caption).monospacedDigit()
                            }.padding(12).background(V5Palette.color(V5Palette.current.paper), in: RoundedRectangle(cornerRadius: 12))
                                .accessibilityElement(children: .combine)
                        }
                    }
                }
                Text("岁运需结合原局阅读，可在专业工作台继续查看流年与流月。")
                    .font(.caption).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
            }
        }
        V5Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("节气与辅助信息").font(.system(.title2, design: .serif))
                Text(chart.prevJieQiText)
                Text(chart.nextJieQiText)
                Text("胎元 \(chart.taiYuan) · 胎息 \(chart.taiXi)")
                Text("命宫 \(chart.mingGong) · 身宫 \(chart.shenGong)")
            }.font(.subheadline)
        }
    }
}
private struct V5BaziSnapshot { let person: Person; let chart: BaziChart }
private struct V5ZiweiSnapshot { let person: Person; let chart: ZiweiChart }

struct V5ZiweiPage: View {
    @EnvironmentObject private var people: PeopleStore
    @State private var result: V5ZiweiSnapshot?
    @State private var selectedBranch: Int = 0
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: V5Metric.gap) {
                V5CalculationPersonHeader()
                if let person = people.currentPerson {
                    if let result, result.person == person {
                        Text("命盘档案 \(result.person.id.uuidString.prefix(8))").font(.caption.monospaced())
                            .accessibilityIdentifier("v5.ziwei.result.owner").accessibilityValue(result.person.id.uuidString)
                        content(result.chart)
                    } else {
                        ProgressView("正在安置当前命主的十二宫星曜").frame(minHeight: 120)
                    }
                } else { V5CalculationProfilePrompt() }
                NavigationLink { ZiweiHomeView().id(people.currentPerson) } label: {
                    V5CalculationEntryLabel(title: "紫微专业工作台", detail: "飞化 · 三方四正 · 大限流年 · 归属确认与导出", icon: "slider.horizontal.3")
                }.buttonStyle(.plain)
                V5CalculationDisclaimer()
            }.padding(V5Metric.page)
        }
        .v5CalculationPage(title: "紫微斗数")
        .accessibilityIdentifier("v5.ziwei.page")
        .task(id: people.currentPerson) {
            let selected = people.currentPerson
            guard result?.person != selected else { return }
            result = nil
            await Task.yield()
            guard let selected, !Task.isCancelled else { return }
            let chart = ZiweiEngine.cachedChart(clock: selected.birthDate, gender: selected.gender,
                                                longitude: selected.useLongitude ? selected.longitude : nil)
            guard !Task.isCancelled, people.currentPerson == selected else { return }
            selectedBranch = chart.mingGong
            result = V5ZiweiSnapshot(person: selected, chart: chart)
        }
    }
    @ViewBuilder private func content(_ chart: ZiweiChart) -> some View {
        V5Card {
            VStack(alignment: .leading, spacing: 8) {
                Text(chart.juName).font(.system(.title, design: .serif))
                Text(chart.lunarText)
                Text("命宫 \(ZiweiCore.DZ[chart.mingGong]) · 身宫 \(chart.palaces[chart.shenGong].name)")
                Text("横向滑动阅读完整原盘，点宫位查看全部星曜。中心为图例，不是宫位。")
                    .font(.caption).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
            }
        }
        V5ZiweiRing(chart: chart, selectedBranch: $selectedBranch)
        V5Card {
            let palace = chart.palaces[selectedBranch]
            VStack(alignment: .leading, spacing: 12) {
                Text("\(palace.name)宫 · \(palace.stem)\(ZiweiCore.DZ[palace.branch])\(palace.isBody ? " · 身宫" : "")")
                    .font(.system(.title2, design: .serif))
                Text("主星：\(starText(palace.majors, empty: "无主星，请结合对宫参考"))")
                Text("辅星：\(starText(palace.minors, empty: "无"))")
                if let first = palace.decadal.first, let last = palace.decadal.last {
                    Text("大限：\(first)–\(last) 岁")
                }
                let opposite = chart.palaces[(selectedBranch + 6) % 12]
                Text("对宫 \(opposite.name)：\(starText(opposite.majors, empty: "无主星"))")
                    .foregroundStyle(V5Palette.color(V5Palette.current.secondary))
            }.font(.subheadline).accessibilityElement(children: .combine)
        }
        V5Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("十二宫目录").font(.system(.title2, design: .serif))
                ForEach(chart.palaces, id: \.branch) { palace in
                    Button { selectedBranch = palace.branch } label: {
                        HStack(alignment: .top) {
                            Text("\(palace.name) · \(ZiweiCore.DZ[palace.branch])").font(.headline)
                            Spacer(minLength: 12)
                            Text(starText(palace.majors, empty: "无主星"))
                                .multilineTextAlignment(.trailing)
                            if selectedBranch == palace.branch { Image(systemName: "checkmark.circle.fill") }
                        }.frame(minHeight: V5Metric.target)
                    }.buttonStyle(.plain)
                        .accessibilityAddTraits(selectedBranch == palace.branch ? .isSelected : [])
                    Divider()
                }
            }
        }
    }
    private func starText(_ stars: [(star: String, mutagen: String?)], empty: String) -> String {
        stars.isEmpty ? empty : stars.map { $0.star + ($0.mutagen.map { "（\($0)）" } ?? "") }.joined(separator: "、")
    }
}

/// Same 子→亥 data mapping as ZiweiBoardView and PosterFamilyExport.
/// A 4×4 perimeter contains twelve real palaces; the 2×2 center is decorative.
private struct V5ZiweiRing: View {
    let chart: ZiweiChart
    @Binding var selectedBranch: Int
    @ScaledMetric(relativeTo: .body) private var cellWidth: CGFloat = 154
    @ScaledMetric(relativeTo: .body) private var cellHeight: CGFloat = 164
    private let gap: CGFloat = 6
    var body: some View {
        ScrollView(.horizontal) {
            VStack(spacing: gap) {
                HStack(spacing: gap) { ForEach([5, 6, 7, 8], id: \.self) { cell($0) } }
                HStack(spacing: gap) {
                    VStack(spacing: gap) { cell(4); cell(3) }
                    ZStack {
                        Circle().stroke(V5Palette.color(V5Palette.current.ornament).opacity(0.35), lineWidth: 1)
                            .padding(24)
                        Circle().stroke(V5Palette.color(V5Palette.current.ornament).opacity(0.2), lineWidth: 1)
                            .padding(44)
                        VStack(spacing: 12) {
                            Text("紫 微").font(.system(.largeTitle, design: .serif))
                            Text(chart.juName).font(.headline)
                            Text("十二宫 · 生年四化").font(.caption)
                            Text("禄 · 权 · 科 · 忌").font(.caption)
                        }
                    }
                    .frame(width: cellWidth * 2 + gap, height: cellHeight * 2 + gap)
                    .background(V5Palette.color(V5Palette.current.surface), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityElement(children: .ignore).accessibilityLabel("紫微盘图例，十二宫环绕中心")
                    VStack(spacing: gap) { cell(9); cell(10) }
                }
                HStack(spacing: gap) { ForEach([2, 1, 0, 11], id: \.self) { cell($0) } }
            }.padding(2)
        }.accessibilityIdentifier("v5.ziwei.ring")
    }
    private func cell(_ branch: Int) -> some View {
        let palace = chart.palaces[branch]
        return Button { selectedBranch = branch } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(palace.name).font(.headline)
                    Spacer(minLength: 0)
                    if palace.isBody { Text("身").font(.caption).fontWeight(.bold) }
                }
                Text(palace.majors.isEmpty ? "无主星" : palace.majors.map { $0.star + ($0.mutagen ?? "") }.joined(separator: " · "))
                    .font(.body)
                Spacer(minLength: 0)
                Text("\(palace.stem)\(ZiweiCore.DZ[branch])").font(.caption)
                if let first = palace.decadal.first, let last = palace.decadal.last {
                    Text("\(first)–\(last) 岁").font(.caption).monospacedDigit()
                }
            }
            .padding(12).frame(width: cellWidth, height: cellHeight, alignment: .topLeading)
            .foregroundStyle(V5Palette.color(V5Palette.current.ink))
            .background(V5Palette.color(selectedBranch == branch ? V5Palette.current.paper : V5Palette.current.surface), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(V5Palette.color(selectedBranch == branch ? V5Palette.current.accent : V5Palette.current.ornament).opacity(selectedBranch == branch ? 1 : 0.4), lineWidth: selectedBranch == branch ? 2 : 0.7))
        }.buttonStyle(.plain).accessibilityElement(children: .combine)
            .accessibilityAddTraits(selectedBranch == branch ? .isSelected : [])
            .accessibilityHint("显示此宫全部主辅星与对宫")
    }
}

private struct V5CalculationPersonHeader: View {
    @EnvironmentObject private var people: PeopleStore
    @EnvironmentObject private var router: V5Router
    var body: some View {
        V5Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("当前命主").font(.caption).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
                if let person = people.currentPerson {
                    Menu {
                        ForEach(people.people) { candidate in
                            Button { people.setCurrentPerson(candidate) } label: {
                                Text("\(candidate.name) · \(candidate.relation) · \(DisplayTimeReceipt.beijing(candidate.birthDate)) · \(candidate.id.uuidString.prefix(8))")
                            }
                        }
                        Button("管理档案") { router.tab = 3 }
                    } label: {
                        HStack {
                            Label(person.name, systemImage: "person.crop.circle")
                            Spacer()
                            Image(systemName: "chevron.down")
                        }.font(.system(.title2, design: .serif)).frame(minHeight: V5Metric.target)
                    }.accessibilityLabel("切换命主，当前为\(person.name)")
                    Text(DisplayTimeReceipt.beijing(person.birthDate)).font(.subheadline)
                    Text("档案 \(person.id.uuidString.prefix(8)) · \(person.useLongitude ? "经度校时" : "北京时间")")
                        .font(.caption).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
                        .accessibilityIdentifier("v5.calculation.owner").accessibilityValue(person.id.uuidString)
                } else {
                    Text("尚未选择人物档案").font(.headline)
                    Button("添加人物档案") { router.tab = 3 }.frame(minHeight: V5Metric.target)
                }
            }
        }
    }
}
private struct V5CalculationProfilePrompt: View {
    @EnvironmentObject private var router: V5Router
    var body: some View {
        V5Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("先建立真实档案").font(.system(.title2, design: .serif))
                Text("排盘需要出生时间、性别与校时设置。添加档案后，命盘会随当前人物更新。")
                Button("前往档案创建人物") { router.tab = 3 }.frame(minHeight: V5Metric.target)
            }
        }
    }
}
private struct V5CalculationEntry: View {
    let title: String; let detail: String; let icon: String; let action: () -> Void
    var body: some View {
        Button(action: action) { V5CalculationEntryLabel(title: title, detail: detail, icon: icon) }.buttonStyle(.plain)
    }
}
private struct V5CalculationEntryLabel: View {
    let title: String; let detail: String; let icon: String
    var body: some View {
        V5Card {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: icon).font(.title2).frame(width: V5Metric.target)
                    .foregroundStyle(V5Palette.color(V5Palette.current.accent))
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.system(.title3, design: .serif).weight(.semibold))
                    Text(detail).font(.subheadline).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption)
            }.frame(minHeight: V5Metric.target)
        }.accessibilityElement(children: .combine)
    }
}
private struct V5CalculationDisclaimer: View {
    var body: some View {
        Text("传统民俗参考。排盘与象义不构成疾病诊断或保证性预测。")
            .font(.footnote).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
    }
}
private extension View {
    func v5CalculationPage(title: String) -> some View {
        background(V5Palette.color(V5Palette.current.paper))
            .foregroundStyle(V5Palette.color(V5Palette.current.ink))
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
}
