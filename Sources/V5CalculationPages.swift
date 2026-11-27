import SwiftUI

/// The calculation workspace uses the same selected UUID and routes as the shell.
/// Every card is a navigation entry; existing professional tools remain available.
struct V5CalculationHub: View {
    @EnvironmentObject private var router: V5Router
    @Environment(\.dynamicTypeSize) private var typeSize
    private var primaryColumns: [GridItem] {
        [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 250 : 145), spacing: 14)]
    }
    private var matrixColumns: [GridItem] {
        [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 150 : 80), spacing: 12)]
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                V5ArtHeader(eyebrow: "三术合参 · 测算", title: "以命为经\n以术为纬", subtitle: "观天时，察地理，照见自己的生命脉络。")
                V5CalculationPersonHeader()
                primaryMatrix
                observationMatrix
                timingMatrix
                complementaryTools
                V5CalculationDisclaimer()
            }.padding(V5Metric.page)
        }
        .v5CalculationPage(title: "测算")
        .accessibilityIdentifier("v5.calculation.hub")
    }
    private var primaryMatrix: some View {
        VStack(alignment: .leading, spacing: 14) {
            V5SectionHeading(title: "命盘 · 双术", subtitle: "从四柱与十二宫开始")
            LazyVGrid(columns: primaryColumns, spacing: 14) {
                Button { router.open(.bazi) } label: {
                    V5CalculationPrimaryTile(number: "壹", title: "八字命理", detail: "四柱十神 · 五行岁运", kind: .bazi)
                }.buttonStyle(.plain).accessibilityIdentifier("v5.measure.bazi")
                Button { router.open(.ziwei) } label: {
                    V5CalculationPrimaryTile(number: "贰", title: "紫微斗数", detail: "十二宫垣 · 星曜四化", kind: .ziwei)
                }.buttonStyle(.plain).accessibilityIdentifier("v5.measure.ziwei")
            }
        }
    }
    private var observationMatrix: some View {
        V5Card {
            VStack(alignment: .leading, spacing: 20) {
                V5SectionHeading(title: "观形 · 察象", subtitle: "相由形见，地以势观")
                LazyVGrid(columns: matrixColumns, spacing: 16) {
                    Button { router.open(.palm) } label: {
                        V5CalculationMatrixLabel(title: "手相", detail: "掌纹与指比", kind: .palm)
                    }.buttonStyle(.plain)
                    NavigationLink { V5FacePage() } label: {
                        V5CalculationMatrixLabel(title: "面相", detail: "三停与五眼", kind: .face)
                    }.buttonStyle(.plain)
                    Button { router.open(.survey) } label: {
                        V5CalculationMatrixLabel(title: "风水", detail: "堪舆与户型", kind: .survey)
                    }.buttonStyle(.plain)
                }
            }
        }
    }
    private var timingMatrix: some View {
        V5Card {
            VStack(alignment: .leading, spacing: 20) {
                V5SectionHeading(title: "时序 · 万象", subtitle: "循节气，识时局，览诸术")
                LazyVGrid(columns: matrixColumns, spacing: 16) {
                    Button { router.open(.tool("almanac")) } label: {
                        V5CalculationMatrixLabel(title: "万年历", detail: "干支与节气", kind: .calendar)
                    }.buttonStyle(.plain)
                    Button { router.open(.qimen) } label: {
                        V5CalculationMatrixLabel(title: "奇门", detail: "时局与解读", kind: .qimen)
                    }.buttonStyle(.plain)
                    Button { router.open(.tools) } label: {
                        V5CalculationMatrixLabel(title: "全部功能", detail: "合婚与择吉", kind: .tools)
                    }.buttonStyle(.plain)
                }
            }
        }
    }
    private var complementaryTools: some View {
        VStack(alignment: .leading, spacing: 14) {
            V5SectionHeading(title: "相参 · 互证")
            LazyVGrid(columns: primaryColumns, spacing: 14) {
                Button { router.open(.tool("compass")) } label: {
                    V5CalculationCompanionLabel(title: "罗盘实测", detail: "磁北 · 真北 · 定向", icon: "location.north.circle")
                }.buttonStyle(.plain)
                Button { router.open(.tool("astro")) } label: {
                    V5CalculationCompanionLabel(title: "星命合参", detail: "八字 × 西洋星盘", icon: "circle.hexagongrid")
                }.buttonStyle(.plain)
            }
        }
    }
}
private struct V5CalculationPrimaryTile: View {
    let number: String; let title: String; let detail: String; let kind: V5FeatureKind
    var body: some View {
        V5Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    Text(number).font(V5Typography.song(.title2))
                        .foregroundStyle(V5Palette.color(V5Palette.current.ornamentText))
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.caption).accessibilityHidden(true)
                }
                V5FeatureGlyph(kind: kind, size: 82).frame(maxWidth: .infinity).padding(.vertical, 6).accessibilityHidden(true)
                Rectangle().fill(V5Palette.color(V5Palette.current.ornament).opacity(0.4)).frame(height: 1)
                Text(title).font(V5Typography.song(.title2, emphasis: true))
                Text(detail).font(.caption).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, minHeight: V5Metric.target, alignment: .leading)
        }.accessibilityElement(children: .ignore).accessibilityLabel("\(title)，\(detail)")
    }
}
private struct V5CalculationMatrixLabel: View {
    let title: String; let detail: String; let kind: V5FeatureKind
    var body: some View {
        VStack(spacing: 12) {
            V5FeatureGlyph(kind: kind, size: 56).accessibilityHidden(true)
            Text(title).font(V5Typography.title)
            Text(detail).font(.caption).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
        }.multilineTextAlignment(.center).frame(maxWidth: .infinity, minHeight: 136)
            .padding(.vertical, 4).contentShape(Rectangle())
            .accessibilityElement(children: .combine)
    }
}
private struct V5CalculationCompanionLabel: View {
    let title: String; let detail: String; let icon: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon).font(.title2).foregroundStyle(V5Palette.color(V5Palette.current.accent)).accessibilityHidden(true)
            Text(title).font(V5Typography.title)
            Text(detail).font(.caption).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
        }.padding(16).frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .background(V5Palette.color(V5Palette.current.surface).opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
            .overlay(alignment: .leading) {
                Rectangle().fill(V5Palette.color(V5Palette.current.ornament).opacity(0.7)).frame(width: 2)
            }.accessibilityElement(children: .combine)
    }
}

struct V5BaziPage: View {
    @EnvironmentObject private var people: PeopleStore
    @EnvironmentObject private var router: V5Router
    @State private var result: V5BaziSnapshot?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: V5Metric.gap) {
                V5ArtHeader(eyebrow: "四柱 · 岁运", title: "八字命理", subtitle: "一字一柱，读原局，观岁运。")
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
                Text("日主 · \(chart.rizhu)").font(V5Typography.song(.title))
                Text(chart.lunarText).font(.subheadline)
                Text(chart.longitude == nil ? "北京时间 · 未启用经度校正" : "已按档案经度校正真太阳时")
                    .font(.caption).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
                if let solarDate = chart.trueSolarDate {
                    Text("真太阳时 \(DisplayTimeReceipt.beijing(solarDate))").font(.caption)
                }
                V5BirthOverview(chart: chart)
            }
        }
        V5Card { V5PillarDetailTable(chart: chart) }
        V5TenGodDistribution(chart: chart)
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
                V5ArtHeader(eyebrow: "十二宫 · 星曜", title: "紫微斗数", subtitle: "循宫垣观星曜，以三方四正互参。")
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
                Text(chart.juName).font(V5Typography.song(.title))
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
                        VStack(spacing: 12) {
                            V5FeatureGlyph(kind: .ziwei, size: 88).accessibilityHidden(true)
                            Text("紫 微").font(V5Typography.song(.largeTitle))
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
        VStack(alignment: .leading, spacing: 8) {
            if let person = people.currentPerson {
                Menu {
                    ForEach(people.people) { candidate in
                        Button { people.setCurrentPerson(candidate) } label: {
                            Text("\(candidate.name) · \(candidate.relation) · \(DisplayTimeReceipt.beijing(candidate.birthDate)) · \(candidate.id.uuidString.prefix(8))")
                        }
                    }
                    Button("管理档案") { router.tab = 3 }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("当前命主").font(.caption).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
                        Text(person.name).font(V5Typography.song(.title3, emphasis: true))
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down").font(.caption)
                    }.frame(minHeight: V5Metric.target)
                }.accessibilityLabel("切换命主，当前为\(person.name)")
                Text(DisplayTimeReceipt.beijing(person.birthDate)).font(.caption)
                Text("档案 \(person.id.uuidString.prefix(8)) · \(person.useLongitude ? "经度校时" : "北京时间")")
                    .font(.caption2).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
                    .accessibilityIdentifier("v5.calculation.owner").accessibilityValue(person.id.uuidString)
            } else {
                Button("添加人物档案") { router.tab = 3 }.font(V5Typography.title).frame(minHeight: V5Metric.target)
                Text("从真实生辰出发，展开个人命盘。").font(.caption)
            }
            Rectangle().fill(V5Palette.color(V5Palette.current.ornament).opacity(0.45)).frame(height: 1).padding(.top, 8)
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
                    Text(title).font(V5Typography.song(.title3, emphasis: true))
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
