import SwiftUI

/// The calculation workspace uses the same selected UUID and routes as the shell.
/// Compact, independent feature entrances retain every professional destination.
struct V5CalculationHub: View {
    @EnvironmentObject private var router: V5Router
    @Environment(\.dynamicTypeSize) private var typeSize
    private var primaryColumns: [GridItem] {
        [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 240 : 140), spacing: 10)]
    }
    private var observationColumns: [GridItem] {
        [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 140 : 86), spacing: 8)]
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                V5CalculationPersonHeader()
                primaryEntries
                observationEntries
                utilityEntries
                Button { router.open(.tools) } label: {
                    HStack {
                        Image(systemName: "square.grid.2x2")
                        Text("全部功能").font(.body.weight(.semibold))
                        Spacer()
                        Text("合婚 · 择吉 · 报告").font(.caption)
                        Image(systemName: "chevron.right").font(.caption)
                    }.frame(minHeight: V5Metric.target).contentShape(Rectangle())
                }.buttonStyle(.plain)
                V5CalculationDisclaimer()
            }.padding(.horizontal, V5Metric.page).padding(.vertical, 12)
        }
        .v5CalculationPage(title: "测算")
        .accessibilityIdentifier("v5.calculation.hub")
    }
    private var primaryEntries: some View {
        LazyVGrid(columns: primaryColumns, spacing: 10) {
            Button { router.open(.bazi) } label: {
                V5CalculationMainEntry(title: "八字", detail: "四柱 · 十神 · 岁运", kind: .bazi)
            }.buttonStyle(.plain).accessibilityIdentifier("v5.measure.bazi")
            Button { router.open(.ziwei) } label: {
                V5CalculationMainEntry(title: "紫微", detail: "十二宫 · 星曜四化", kind: .ziwei)
            }.buttonStyle(.plain).accessibilityIdentifier("v5.measure.ziwei")
        }
    }
    private var observationEntries: some View {
        LazyVGrid(columns: observationColumns, spacing: 8) {
            Button { router.open(.palm) } label: {
                V5CalculationObservationEntry(title: "手相", detail: "掌纹测量", kind: .palm)
            }.buttonStyle(.plain)
            Button { router.open(.face) } label: {
                V5CalculationObservationEntry(title: "面相", detail: "三停五眼", kind: .face)
            }.buttonStyle(.plain)
            Button { router.open(.survey) } label: {
                V5CalculationObservationEntry(title: "风水", detail: "堪舆勘察", kind: .survey)
            }.buttonStyle(.plain)
        }
    }
    private var utilityEntries: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("历法与合参").font(V5Typography.song(.headline, emphasis: true))
                .accessibilityAddTraits(.isHeader).padding(.bottom, 6)
            utility("万年历", detail: "干支节气", icon: "calendar", route: .tool("almanac"))
            Divider()
            utility("奇门遁甲", detail: "时局排盘", icon: "square.grid.3x3", route: .qimen)
            Divider()
            utility("罗盘实测", detail: "磁北与真北", icon: "location.north.circle", route: .tool("compass"))
            Divider()
            utility("星命合参", detail: "八字 × 西洋星盘", icon: "circle.hexagongrid", route: .tool("astro"))
        }
    }
    private func utility(_ title: String, detail: String, icon: String, route: V5Route) -> some View {
        Button { router.open(route) } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).frame(width: 24).accessibilityHidden(true)
                Text(title).font(.body)
                Spacer(minLength: 8)
                Text(detail).font(.caption).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
                Image(systemName: "chevron.right").font(.caption2).accessibilityHidden(true)
            }.frame(minHeight: V5Metric.target).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityElement(children: .combine)
    }
}
private struct V5CalculationMainEntry: View {
    let title: String; let detail: String; let kind: V5FeatureKind
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Text(title).font(V5Typography.song(.title2, emphasis: true))
                Spacer(minLength: 6)
                V5FeatureGlyph(kind: kind, size: 52)
            }
            Text(detail).font(.caption).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("查看命盘").font(.caption.weight(.medium))
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption)
            }.foregroundStyle(V5Palette.color(V5Palette.current.accent)).padding(.top, 4)
        }.padding(14).frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            .background(V5Palette.color(V5Palette.current.surface), in: RoundedRectangle(cornerRadius: 14))
            .overlay(alignment: .top) {
                Rectangle().fill(V5Palette.color(V5Palette.current.ornament)).frame(height: 1)
            }.contentShape(Rectangle()).accessibilityElement(children: .combine)
    }
}
private struct V5CalculationObservationEntry: View {
    let title: String; let detail: String; let kind: V5FeatureKind
    var body: some View {
        VStack(spacing: 7) {
            V5FeatureGlyph(kind: kind, size: 38)
            Text(title).font(V5Typography.song(.headline, emphasis: true))
            Text(detail).font(.caption).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
        }.multilineTextAlignment(.center).padding(.vertical, 12).padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 106)
            .background(V5Palette.color(V5Palette.current.surface).opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle()).accessibilityElement(children: .combine)
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
                Text("日主 · \(chart.rizhu)").font(V5Typography.song(.headline, emphasis: true))
                Text(chart.lunarText).font(.subheadline)
                Text(chart.longitude == nil ? "北京时间 · 未启用经度校正" : "已按档案经度校正真太阳时")
                    .font(.caption).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
                if let solarDate = chart.trueSolarDate {
                    Text("真太阳时 \(V5DisplayText.dateTime(solarDate))").font(.caption)
                }
                V5BirthOverview(chart: chart)
            }
        }
        V5Card { V5PillarDetailTable(chart: chart) }
        V5Card { V5TenGodLedger(chart: chart) }
        V5Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("大运脉络").font(V5Typography.song(.title2))
                Text("\(chart.qiyunDirection) · 起运 \(chart.qiyunDate)").font(.subheadline)
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(Array(chart.dayunGanZhi.enumerated()), id: \.offset) { index, ganZhi in
                            VStack(spacing: 8) {
                                Text(ganZhi).font(V5Typography.song(.title2))
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
                Text("节气与辅助信息").font(V5Typography.song(.title2))
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
                Text(chart.juName).font(V5Typography.song(.headline, emphasis: true))
                Text(chart.lunarText)
                Text("命宫 \(ZiweiCore.DZ[chart.mingGong]) · 身宫 \(chart.palaces[chart.shenGong].name)")
                Text("点宫位看完整主辅星与对宫；大字号可横向滑动原盘。")
                    .font(.caption).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
            }
        }
        V5ZiweiRing(chart: chart, selectedBranch: $selectedBranch)
        V5Card {
            let palace = chart.palaces[selectedBranch]
            VStack(alignment: .leading, spacing: 12) {
                Text("\(palace.name)宫 · \(palace.stem)\(ZiweiCore.DZ[palace.branch])\(palace.isBody ? " · 身宫" : "")")
                    .font(V5Typography.song(.title2))
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
                Text("十二宫目录").font(V5Typography.song(.title2))
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
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var expandedWidth: CGFloat = 154
    @ScaledMetric(relativeTo: .body) private var expandedHeight: CGFloat = 164
    private let gap: CGFloat = 4
    private var expanded: Bool { typeSize > .large }
    private var cellHeight: CGFloat { expanded ? expandedHeight : 116 }
    var body: some View {
        GeometryReader { geometry in
            let width = expanded ? expandedWidth : max(76, (geometry.size.width - gap * 3) / 4)
            ScrollView(.horizontal) {
                board(width: width)
            }
        }.frame(height: cellHeight * 4 + gap * 3)
            .accessibilityIdentifier("v5.ziwei.ring")
    }
    private func board(width: CGFloat) -> some View {
        VStack(spacing: gap) {
            HStack(spacing: gap) { ForEach([5, 6, 7, 8], id: \.self) { cell($0, width: width) } }
            HStack(spacing: gap) {
                VStack(spacing: gap) { cell(4, width: width); cell(3, width: width) }
                VStack(spacing: expanded ? 12 : 8) {
                    V5FeatureGlyph(kind: .ziwei, size: expanded ? 64 : 38)
                    Text(chart.juName).font(V5Typography.song(expanded ? .title2 : .headline, emphasis: true))
                    Text("命宫 \(ZiweiCore.DZ[chart.mingGong])").font(.caption)
                    Text("禄 · 权 · 科 · 忌").font(.caption2)
                    Text("格内数字为大限年龄").font(.caption2)
                    Text("十二宫环列 · 中央为图例").font(.caption2)
                        .foregroundStyle(V5Palette.color(V5Palette.current.secondary))
                        .multilineTextAlignment(.center)
                }.frame(width: width * 2 + gap, height: cellHeight * 2 + gap)
                    .background(V5Palette.color(V5Palette.current.surface).opacity(0.65))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("紫微盘图例，十二宫环绕中心")
                VStack(spacing: gap) { cell(9, width: width); cell(10, width: width) }
            }
            HStack(spacing: gap) { ForEach([2, 1, 0, 11], id: \.self) { cell($0, width: width) } }
        }
    }
    private func cell(_ branch: Int, width: CGFloat) -> some View {
        let palace = chart.palaces[branch]
        return Button { selectedBranch = branch } label: {
            VStack(alignment: .leading, spacing: expanded ? 8 : 4) {
                HStack(spacing: 2) {
                    Text(palace.name).font(expanded ? .headline : .caption.weight(.semibold))
                    Spacer(minLength: 0)
                    if palace.isBody { Text("身").font(.caption2).fontWeight(.bold) }
                }
                if palace.majors.isEmpty {
                    Text("无主星").font(expanded ? .body : .caption)
                        .foregroundStyle(V5Palette.color(V5Palette.current.secondary))
                } else {
                    ForEach(Array(palace.majors.enumerated()), id: \.offset) { _, star in
                        HStack(spacing: 2) {
                            Text(star.star).font(expanded ? .body : .caption)
                            if let mutagen = star.mutagen {
                                Text(mutagen).font(.caption2.weight(.semibold))
                                    .foregroundStyle(V5Palette.color(V5Palette.current.accent))
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 2) {
                    Text("\(palace.stem)\(ZiweiCore.DZ[branch])")
                    Spacer(minLength: 0)
                    if let first = palace.decadal.first, let last = palace.decadal.last {
                        Text("\(first)–\(last)").monospacedDigit()
                    }
                }.font(.caption2)
            }.padding(expanded ? 12 : 6).frame(width: width, height: cellHeight, alignment: .topLeading)
                .foregroundStyle(V5Palette.color(V5Palette.current.ink))
                .background(V5Palette.color(selectedBranch == branch ? V5Palette.current.paper : V5Palette.current.surface))
                .overlay(Rectangle().stroke(V5Palette.color(selectedBranch == branch ? V5Palette.current.accent : V5Palette.current.ornament).opacity(selectedBranch == branch ? 1 : 0.4), lineWidth: selectedBranch == branch ? 2 : 0.7))
        }.buttonStyle(.plain).accessibilityElement(children: .combine)
            .accessibilityAddTraits(selectedBranch == branch ? .isSelected : [])
            .accessibilityHint("显示此宫全部主辅星与对宫；数字为大限起止年龄")
    }
}

private struct V5CalculationPersonHeader: View {
    @EnvironmentObject private var people: PeopleStore
    @EnvironmentObject private var router: V5Router
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let person = people.currentPerson {
                V5PersonPickerButton {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("当前命主").font(.caption).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
                        Text(person.name).font(.headline)
                        Spacer(minLength: 0)
                        Text("切换").font(.caption)
                        Image(systemName: "chevron.down").font(.caption2)
                    }.frame(maxWidth: .infinity, minHeight: V5Metric.target)
                }
                Text("\(V5DisplayText.dateTime(person.birthDate)) · \(person.useLongitude ? "经度校时" : "北京时间")")
                    .font(.caption).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
                Text("档案 \(person.id.uuidString.prefix(8))").font(.caption2.monospaced())
                    .foregroundStyle(V5Palette.color(V5Palette.current.secondary))
                    .accessibilityIdentifier("v5.calculation.owner").accessibilityValue(person.id.uuidString)
            } else {
                Button { router.tab = 3 } label: {
                    HStack {
                        Label("添加人物档案", systemImage: "person.badge.plus").font(.body.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption)
                    }.frame(minHeight: V5Metric.target)
                }.buttonStyle(.plain)
                Text("建立真实生辰档案后查看个人命盘").font(.caption)
                    .foregroundStyle(V5Palette.color(V5Palette.current.secondary))
            }
        }.padding(.bottom, 8)
            .overlay(alignment: .bottom) {
                Rectangle().fill(V5Palette.color(V5Palette.current.ornament).opacity(0.35)).frame(height: 0.7)
            }
    }
}
private struct V5CalculationProfilePrompt: View {
    @EnvironmentObject private var router: V5Router
    var body: some View {
        V5Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("先建立真实档案").font(V5Typography.song(.title2))
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
                    Text(title).font(.headline)
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
        background { V5SceneBackground() }
            .foregroundStyle(V5Palette.color(V5Palette.current.ink))
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
}
