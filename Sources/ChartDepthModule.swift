// 深度图表页（Insight 第 3 批 G11，2026-11-09）
//
// 独立的交互式五行十神深度图表页：五行雷达（可点）＋五行占比条（可点）＋
// 十神分布条（可点）＋十神雷达（可点）。点任一五行或十神元素，联动定位到
// 对应干支；点 30 维结论行，复用 G4 InterpretEngine.locateTarget 定位到目标柱。
//
// 数据来源（只读已有引擎与盘面，不新编口径、不新增断语）：
//   五行占比 chart.wuxingPercents（BaziTables.wuxingPercents 同口径）；
//   十神分布由 chart.stemShiShen＋chart.hideShiShen 现数（与 PosterModule
//   shiShenBars 同口径，日干位「日主」不计入十神）；
//   喜忌行复用 InterpretEngine.posterXiJi 定论原文；
//   结论行复用 InterpretEngine.interpret 30 条原文。
// 联动规则（本页唯一新增的展示层映射，只读盘面，不改引擎）：
//   点五行 → 高亮「含该五行」的柱：天干五行、或地支本气五行、或任一藏干五行
//   与之相同（五行归属取 KyV2.element(ofChar:)，与 DesignSystemV2 同口径）；
//   点十神 → 高亮该十神所在柱：天干十神相同、或藏干十神含该十神
//   （天干优先于藏干，柱内多处命中时明细逐条列出）；
//   点结论 → G4 locateTarget 给出的目标柱＋十神。
// 跨页联动：写共享 SceneStorage 键 "bazi.selectedPillar"（与 BaziModule、
// InterpretModule 同键），八字页四柱卡随之高亮；本页内同时高亮匹配的全部柱。
// 选态用 -1／空串哨兵（沿用 BaziModule 选柱哨兵写法，不用 Optional 计算属性
// 包装，避免 SceneStorage 计算属性赋值铁律）；无阴影；系统动态字体；
// 入口只走 AllToolsView NavigationLink，不用全屏弹出。
// 口径：本页只展示盘面事实（占比、计数、所在柱）与引擎已有定论，不写寿数、
// 不落健康病名、不断确定性断语、不作改命转运功效宣称。
import SwiftUI

/// 单柱命中明细：柱下标（0 年／1 月／2 日／3 时）＋命中点文字（如 天干甲／地支寅／藏干丙）。
struct ChartDepthMatch {
    let pillar: Int
    let details: [String]
}

/// 十神计数行：十神名／出现次数（天干＋藏干）／所在柱下标。
struct ChartDepthShishenCount {
    let name: String
    let count: Int
    let pillars: [Int]
}

struct ChartDepthView: View {
    let person: Person
    let chart: BaziChart

    // 选态哨兵：-1＝未选五行／未选柱，空串＝未选十神
    @State private var selectedWuxing: Int = -1
    @State private var selectedShishen: String = ""
    @State private var selectedPillar: Int = -1
    // 跨页共享选柱键（只写 stored 本身，不包计算属性；与 BaziModule 同键）
    @SceneStorage("bazi.selectedPillar") private var sharedPillarStored: Int = -1

    private static let pillarNames = ["年柱", "月柱", "日柱", "时柱"]
    private static let wxNames = ["木", "火", "土", "金", "水"]
    static let shiShenOrder = ["正官", "七杀", "正印", "偏印", "比肩", "劫财", "食神", "伤官", "正财", "偏财"]

    private var items: [InterpretItem] { InterpretEngine.interpret(chart: chart) }

    private var xiJi: (xi: [Int], ji: [Int], neutral: [Int], level: String, tongDang: Double, tiaoHou: [Int]) {
        InterpretEngine.posterXiJi(chart: chart)
    }

    private var xiJiLine: String {
        let xi = xiJi.xi.map { Self.wxNames[$0] }.joined(separator: "、")
        let ji = xiJi.ji.map { Self.wxNames[$0] }.joined(separator: "、")
        let xiText = xi.isEmpty ? "—" : xi
        let jiText = ji.isEmpty ? "无" : ji
        return "喜 \(xiText) · 忌 \(jiText) · 身 \(xiJi.level)"
    }

    /// 干支单字的五行序号（木 0 火 1 土 2 金 3 水 4）；非法字符返回 -1
    private func wxIndex(of ch: Character) -> Int {
        let el = KyV2.element(ofChar: ch)
        if el.isEmpty {
            return -1
        }
        return Self.wxNames.firstIndex(of: el) ?? -1
    }

    /// 点五行 → 含该五行的柱（天干／地支本气／任一藏干三处任一命中即算）
    private func pillarsForWuxing(_ wx: Int) -> [ChartDepthMatch] {
        var out: [ChartDepthMatch] = []
        for i in 0..<4 {
            let gz = chart.pillars[i]
            var details: [String] = []
            if wxIndex(of: gz.first!) == wx {
                details.append("天干 \(gz.first!)")
            }
            if wxIndex(of: gz.last!) == wx {
                details.append("地支 \(gz.last!)")
            }
            for h in chart.hideGan[i] {
                if wxIndex(of: h.first!) == wx {
                    details.append("藏干 \(h)")
                }
            }
            if details.isEmpty == false {
                out.append(ChartDepthMatch(pillar: i, details: details))
            }
        }
        return out
    }

    /// 点十神 → 该十神所在柱（天干十神相同，或藏干十神含该十神）
    private func pillarsForShishen(_ name: String) -> [ChartDepthMatch] {
        var out: [ChartDepthMatch] = []
        for i in 0..<4 {
            var details: [String] = []
            if chart.stemShiShen[i] == name {
                details.append("天干 \(chart.pillars[i].first!)")
            }
            for j in chart.hideShiShen[i].indices {
                if chart.hideShiShen[i][j] == name {
                    details.append("藏干 \(chart.hideGan[i][j])")
                }
            }
            if details.isEmpty == false {
                out.append(ChartDepthMatch(pillar: i, details: details))
            }
        }
        return out
    }

    /// 十神分布计数（天干＋全部藏干；日干位「日主」不在十神序内，不计入）
    private var shiShenCounts: [ChartDepthShishenCount] {
        var counts: [String: Int] = [:]
        var pillarSet: [String: Set<Int>] = [:]
        for i in 0..<4 {
            let stem = chart.stemShiShen[i]
            counts[stem, default: 0] += 1
            pillarSet[stem, default: []].insert(i)
            for ss in chart.hideShiShen[i] {
                counts[ss, default: 0] += 1
                pillarSet[ss, default: []].insert(i)
            }
        }
        return Self.shiShenOrder.compactMap { name in
            let c = counts[name] ?? 0
            if c == 0 {
                return nil
            }
            return ChartDepthShishenCount(name: name, count: c, pillars: Array(pillarSet[name] ?? []).sorted())
        }
    }

    private var maxShishenCount: Int {
        shiShenCounts.map { $0.count }.max() ?? 1
    }

    /// 当前高亮柱集合：五行命中／十神命中／单柱选中，三者取其一
    private var highlightedPillars: Set<Int> {
        if selectedWuxing >= 0 {
            return Set(pillarsForWuxing(selectedWuxing).map { $0.pillar })
        }
        if selectedShishen.isEmpty == false {
            return Set(pillarsForShishen(selectedShishen).map { $0.pillar })
        }
        if selectedPillar >= 0 {
            return [selectedPillar]
        }
        return []
    }

    /// 当前命中明细（供联动说明卡展示）
    private var currentMatches: [ChartDepthMatch] {
        if selectedWuxing >= 0 {
            return pillarsForWuxing(selectedWuxing)
        }
        if selectedShishen.isEmpty == false {
            return pillarsForShishen(selectedShishen)
        }
        if selectedPillar >= 0 {
            return [ChartDepthMatch(pillar: selectedPillar, details: ["本柱"])]
        }
        return []
    }

    /// 当前选中元素的可读名（五行名／十神名／柱名）
    private var currentSelectionName: String {
        if selectedWuxing >= 0 {
            return Self.wxNames[selectedWuxing]
        }
        if selectedShishen.isEmpty == false {
            return selectedShishen
        }
        if selectedPillar >= 0 {
            return Self.pillarNames[selectedPillar]
        }
        return ""
    }

    private func selectWuxing(_ wx: Int) {
        KyV6.impact(.light)
        if selectedWuxing == wx {
            selectedWuxing = -1
            selectedShishen = ""
            selectedPillar = -1
            sharedPillarStored = -1
            return
        }
        selectedWuxing = wx
        selectedShishen = ""
        selectedPillar = -1
        let first = pillarsForWuxing(wx).first
        if first == nil {
            sharedPillarStored = -1
        } else {
            sharedPillarStored = first!.pillar
        }
    }

    private func selectShishen(_ name: String) {
        KyV6.impact(.light)
        if selectedShishen == name {
            selectedWuxing = -1
            selectedShishen = ""
            selectedPillar = -1
            sharedPillarStored = -1
            return
        }
        selectedWuxing = -1
        selectedShishen = name
        selectedPillar = -1
        let first = pillarsForShishen(name).first
        if first == nil {
            sharedPillarStored = -1
        } else {
            sharedPillarStored = first!.pillar
        }
    }

    private func selectPillar(_ i: Int) {
        KyV6.impact(.light)
        if selectedPillar == i {
            selectedWuxing = -1
            selectedShishen = ""
            selectedPillar = -1
            sharedPillarStored = -1
            return
        }
        selectedWuxing = -1
        selectedShishen = ""
        selectedPillar = i
        sharedPillarStored = i
    }

    /// G4 结论定位：复用 InterpretEngine.locateTarget，不新编目标柱
    private func locateConclusion(_ item: InterpretItem) {
        KyV6.impact(.light)
        let target = InterpretEngine.locateTarget(for: item, chart: chart)
        selectedWuxing = -1
        selectedShishen = target.shishen
        selectedPillar = target.pillar
        sharedPillarStored = target.pillar
    }

    private func clearSelection() {
        selectedWuxing = -1
        selectedShishen = ""
        selectedPillar = -1
        sharedPillarStored = -1
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                headerCard
                pillarStripCard
                radarCard
                wuxingBarsCard
                shishenBarsCard
                shishenRadarCard
                linkageCard
                conclusionCard
                footnoteCard
            }
            .padding(.horizontal, KyV6.pageHorizontalMargin)
            .padding(.top, 6)
            .padding(.bottom, 100)
        }
        .background(Ky.bg)
        .navigationTitle("深度图表".scriptConverted)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text((person.name.isEmpty ? "本盘" : person.name) + " · 深度图表".scriptConverted)
                        .font(.system(.headline, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
                    Text("日主 \(chart.rizhu) · 四柱 \(chart.pillars.joined(separator: " "))".scriptConverted)
                        .font(.caption2).foregroundStyle(Ky.sub)
                }
                Spacer()
                if currentSelectionName.isEmpty == false {
                    Button("清除".scriptConverted) { clearSelection() }
                        .font(.caption2).foregroundStyle(Ky.sub)
                        .accessibilityLabel("清除当前选中")
                }
            }
            Text(xiJiLine.scriptConverted)
                .font(.callout).fontWeight(.semibold).foregroundStyle(Ky.qingdai)
            Text("点一点下方任意五行或十神，联动定位到对应干支；点结论行，定位到该条的目标柱。".scriptConverted)
                .font(.caption2).foregroundStyle(Ky.sub)
        }
        .kyCard()
    }

    private var pillarStripCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("四柱".scriptConverted)
                .font(.system(.headline, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { i in
                    pillarCell(i)
                }
            }
            Text("高亮＝当前选中元素所在的柱；点柱卡可单独选中一柱。".scriptConverted)
                .font(.caption2).foregroundStyle(Ky.sub)
        }
        .kyCard()
    }

    private func pillarCell(_ i: Int) -> some View {
        let gz = chart.pillars[i]
        let isHit = highlightedPillars.contains(i)
        let isPrimary = selectedPillar == i
        let stemSS = chart.stemShiShen[i]
        let hideLine = chart.hideGan[i].indices.map { j in
            let h = chart.hideGan[i][j]
            let ss = chart.hideShiShen[i][j]
            return "\(h)(\(KyV2.shiShenShort(ss)))"
        }.joined(separator: " ")
        return Button {
            selectPillar(i)
        } label: {
            VStack(spacing: 4) {
                Text(Self.pillarNames[i].scriptConverted)
                    .font(.caption2).fontWeight(.bold).foregroundStyle(Ky.sub)
                Text(gz)
                    .font(.system(size: 22, weight: .bold, design: .serif)).foregroundStyle(Ky.ink)
                Text(stemSS.scriptConverted)
                    .font(.caption2).fontWeight(.semibold).foregroundStyle(Ky.qingdai)
                Text(hideLine)
                    .font(.caption2).foregroundStyle(Ky.sub)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isPrimary ? Ky.cinnabar.opacity(0.12) : (isHit ? Ky.qingdai.opacity(0.12) : Ky.elevated))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isPrimary ? Ky.cinnabar : (isHit ? Ky.qingdai : Ky.line), lineWidth: isHit ? 1.6 : 0.8)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(Self.pillarNames[i]) \(gz)，天干十神 \(stemSS)")
    }

    private var radarCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("五行雷达 · 点顶点定位".scriptConverted)
                .font(.system(.headline, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
            HStack {
                Spacer()
                ChartDepthWuxingRadar(pcts: chart.wuxingPercents, selected: selectedWuxing, onSelect: selectWuxing)
                Spacer()
            }
            Text("占比取 chart.wuxingPercents（天干各 1，藏干本气 1／中气 0.5／余气 0.3，归一化）。".scriptConverted)
                .font(.caption2).foregroundStyle(Ky.sub)
        }
        .kyCard()
    }

    private var wuxingBarsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("五行占比条 · 点行定位".scriptConverted)
                .font(.system(.headline, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
            VStack(spacing: 9) {
                ForEach(0..<5, id: \.self) { i in
                    wuxingBarRow(i)
                }
            }
            Text("强弱标签与 WuxingBarsView 同口径：≥32 偏旺，≥22 得势，≥12 中和，≥3 偏弱，其余缺显。".scriptConverted)
                .font(.caption2).foregroundStyle(Ky.sub)
        }
        .kyCard()
    }

    private func wuxingStateLabel(_ p: Double) -> (String, Color) {
        if p >= 32 {
            return ("偏旺", Ky.cinnabar)
        }
        if p >= 22 {
            return ("得势", Ky.qingdai)
        }
        if p >= 12 {
            return ("中和", Ky.jade)
        }
        if p >= 3 {
            return ("偏弱", Ky.gold)
        }
        return ("缺显", Ky.sub)
    }

    private func wuxingBarRow(_ i: Int) -> some View {
        let p = chart.wuxingPercents[i]
        let st = wuxingStateLabel(p)
        let isSel = selectedWuxing == i
        return Button {
            selectWuxing(i)
        } label: {
            HStack(spacing: 10) {
                Text(Self.wxNames[i])
                    .font(.system(size: 13, weight: .bold, design: .serif))
                    .foregroundStyle(KyV2.wuxingColors[i])
                    .frame(width: 24, height: 24)
                    .background(KyV2.wuxingColors[i].opacity(isSel ? 0.3 : 0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5).fill(Ky.line.opacity(0.45))
                    RoundedRectangle(cornerRadius: 5)
                        .fill(KyV2.wuxingColors[i])
                        .frame(width: max(4, 160 * CGFloat(min(max(p, 0), 100)) / 100))
                }
                .frame(width: 160, height: 10)
                Text(String(format: "%.0f%%", p))
                    .font(KyV2.tabular(13, weight: .semibold)).foregroundStyle(Ky.ink)
                    .frame(width: 38, alignment: .trailing)
                Text(st.0.scriptConverted)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(st.1)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(st.1.opacity(0.12))
                    .clipShape(Capsule())
                    .frame(width: 36, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
            .background(isSel ? Ky.qingdai.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(Self.wxNames[i])占比 \(Int(p.rounded()))%，点按定位到含\(Self.wxNames[i])的柱")
    }

    private var shishenBarsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("十神分布条 · 点行定位".scriptConverted)
                .font(.system(.headline, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
            VStack(spacing: 9) {
                ForEach(shiShenCounts, id: \.name) { row in
                    shishenBarRow(row)
                }
            }
            Text("计数＝天干十神＋全部藏干十神；只列本盘出现过的十神。".scriptConverted)
                .font(.caption2).foregroundStyle(Ky.sub)
        }
        .kyCard()
    }

    private func shishenBarRow(_ row: ChartDepthShishenCount) -> some View {
        let isSel = selectedShishen == row.name
        let pillarText = row.pillars.map { Self.pillarNames[$0] }.joined(separator: "·")
        return Button {
            selectShishen(row.name)
        } label: {
            HStack(spacing: 10) {
                Text(row.name.scriptConverted)
                    .font(.system(size: 13, weight: .bold, design: .serif))
                    .foregroundStyle(Ky.ink)
                    .frame(width: 52, alignment: .leading)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5).fill(Ky.line.opacity(0.45))
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Ky.qingdai)
                        .frame(width: max(4, 160 * CGFloat(row.count) / CGFloat(maxShishenCount)))
                }
                .frame(width: 160, height: 10)
                Text("\(row.count)")
                    .font(KyV2.tabular(13, weight: .semibold)).foregroundStyle(Ky.ink)
                    .frame(width: 24, alignment: .trailing)
                Text(pillarText.scriptConverted)
                    .font(.caption2).foregroundStyle(Ky.sub)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
            .background(isSel ? Ky.qingdai.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(row.name)共 \(row.count) 处，位于 \(pillarText)，点按定位")
    }

    private var shishenRadarCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("十神雷达 · 点顶点定位".scriptConverted)
                .font(.system(.headline, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
            HStack {
                Spacer()
                ChartDepthShishenRadar(counts: shiShenCounts, selected: selectedShishen, onSelect: selectShishen)
                Spacer()
            }
            Text("十轴按正官／七杀／正印／偏印／比肩／劫财／食神／伤官／正财／偏财顺序；半径按出现次数归一化，未出现者不占轴。".scriptConverted)
                .font(.caption2).foregroundStyle(Ky.sub)
        }
        .kyCard()
    }

    private var linkageCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("联动定位".scriptConverted)
                .font(.system(.headline, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
            if currentSelectionName.isEmpty {
                Text("尚未选中。点上方五行雷达／占比条／十神条／十神雷达，或下方结论行，即在此处看到命中干支，并同步高亮上方四柱。".scriptConverted)
                    .font(.callout).foregroundStyle(Ky.sub)
            } else {
                Text("当前选中：\(currentSelectionName)".scriptConverted)
                    .font(.callout).fontWeight(.bold).foregroundStyle(Ky.qingdai)
                ForEach(currentMatches, id: \.pillar) { m in
                    HStack(alignment: .top, spacing: 6) {
                        Text(Self.pillarNames[m.pillar].scriptConverted)
                            .font(.caption).fontWeight(.bold).foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Ky.qingdai)
                            .clipShape(Capsule())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(chart.pillars[m.pillar])
                                .font(.system(.headline, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
                            Text(m.details.joined(separator: " · ").scriptConverted)
                                .font(.caption).foregroundStyle(Ky.ink)
                        }
                    }
                }
                Text("已同步写入八字页选柱，返回八字页可见同一柱高亮。".scriptConverted)
                    .font(.caption2).foregroundStyle(Ky.sub)
            }
        }
        .kyCard()
    }

    private var conclusionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("结论反向定位（G4 复用）".scriptConverted)
                .font(.system(.headline, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
            Text("点一行，定位到该条结论的目标柱与十神（InterpretEngine.locateTarget，30 条全量）。".scriptConverted)
                .font(.caption2).foregroundStyle(Ky.sub)
            VStack(spacing: 8) {
                ForEach(items.indices, id: \.self) { idx in
                    conclusionRow(items[idx])
                }
            }
        }
        .kyCard()
    }

    private func conclusionRow(_ item: InterpretItem) -> some View {
        let target = InterpretEngine.locateTarget(for: item, chart: chart)
        let cols = Self.pillarNames
        let label = "\(cols[target.pillar]) \(chart.pillars[target.pillar]) · \(target.shishen)"
        let isSel = selectedPillar == target.pillar && selectedShishen == target.shishen
        return Button {
            locateConclusion(item)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "scope").font(.caption2).foregroundStyle(Ky.qingdai)
                Text(item.title.scriptConverted)
                    .font(.caption).fontWeight(.semibold).foregroundStyle(Ky.ink)
                    .lineLimit(1)
                Spacer()
                Text(label)
                    .font(.caption).fontWeight(.bold).foregroundStyle(isSel ? Ky.cinnabar : Ky.ink)
                    .lineLimit(1)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Ky.sub)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(isSel ? Ky.cinnabar.opacity(0.08) : Ky.elevated)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("定位到\(label)")
    }

    private var footnoteCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("口径与来源".scriptConverted)
                .font(.system(.headline, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
            Text("本页只展示盘面事实（五行占比、十神计数、所在柱）与引擎已有定论（喜忌、30 维结论原文），不新编断语；五行归属与十神关系与 BaziModule 同口径。".scriptConverted)
                .font(.caption2).foregroundStyle(Ky.sub)
        }
        .kyCard()
    }
}

// MARK: - 可点五行雷达（五边形：木火土金水顺时针；几何取 PosterModule WuxingRadarView 同款）

struct ChartDepthWuxingRadar: View {
    let pcts: [Double]
    let selected: Int
    let onSelect: (Int) -> Void

    private let names = ["木", "火", "土", "金", "水"]
    private let size: CGFloat = 260

    private func point(_ i: Int, scale: CGFloat) -> CGPoint {
        let a = (-90.0 + Double(i) * 72.0) * Double.pi / 180.0
        let r = size / 2 * 0.78 * scale
        return CGPoint(x: size / 2 + r * CGFloat(cos(a)), y: size / 2 + r * CGFloat(sin(a)))
    }

    var body: some View {
        let maxV = max(pcts.max() ?? 1, 1)
        return ZStack {
            Path { p in
                for i in 0..<5 {
                    let q = point(i, scale: 1.0)
                    if i == 0 {
                        p.move(to: q)
                    } else {
                        p.addLine(to: q)
                    }
                }
                p.closeSubpath()
            }
            .stroke(Ky.line, lineWidth: 0.8)
            Path { p in
                for i in 0..<5 {
                    let q = point(i, scale: 0.5)
                    if i == 0 {
                        p.move(to: q)
                    } else {
                        p.addLine(to: q)
                    }
                }
                p.closeSubpath()
            }
            .stroke(Ky.line.opacity(0.5), lineWidth: 0.5)
            Path { p in
                for i in 0..<5 {
                    p.move(to: CGPoint(x: size / 2, y: size / 2))
                    p.addLine(to: point(i, scale: 1.0))
                }
            }
            .stroke(Ky.line.opacity(0.35), lineWidth: 0.5)
            Path { p in
                for i in 0..<5 {
                    let q = point(i, scale: CGFloat(pcts[i] / maxV))
                    if i == 0 {
                        p.move(to: q)
                    } else {
                        p.addLine(to: q)
                    }
                }
                p.closeSubpath()
            }
            .fill(Ky.qingdai.opacity(0.18))
            Path { p in
                for i in 0..<5 {
                    let q = point(i, scale: CGFloat(pcts[i] / maxV))
                    if i == 0 {
                        p.move(to: q)
                    } else {
                        p.addLine(to: q)
                    }
                }
                p.closeSubpath()
            }
            .stroke(Ky.qingdai, lineWidth: 1.2)
            ForEach(0..<5, id: \.self) { i in
                Button {
                    onSelect(i)
                } label: {
                    VStack(spacing: 0) {
                        Text(names[i])
                            .font(.system(size: 13, weight: .bold, design: .serif))
                            .foregroundStyle(selected == i ? Color.white : KyV2.wuxingColors[i])
                        Text("\(Int(pcts[i].rounded()))%")
                            .font(KyV2.tabular(10, weight: .semibold))
                            .foregroundStyle(selected == i ? Color.white : KyV2.wuxingColors[i])
                    }
                    .frame(width: 44, height: 44)
                    .background(selected == i ? KyV2.wuxingColors[i] : KyV2.wuxingColors[i].opacity(0.14))
                    .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .position(point(i, scale: 1.22))
                .accessibilityLabel("\(names[i])占比 \(Int(pcts[i].rounded()))%，点按定位到含\(names[i])的柱")
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 可点十神雷达（十轴：按正官／七杀／正印／偏印／比肩／劫财／食神／伤官／正财／偏财顺序）

struct ChartDepthShishenRadar: View {
    let counts: [ChartDepthShishenCount]
    let selected: String
    let onSelect: (String) -> Void

    private let size: CGFloat = 260

    private func point(_ i: Int, scale: CGFloat) -> CGPoint {
        let a = (-90.0 + Double(i) * 36.0) * Double.pi / 180.0
        let r = size / 2 * 0.78 * scale
        return CGPoint(x: size / 2 + r * CGFloat(cos(a)), y: size / 2 + r * CGFloat(sin(a)))
    }

    private var maxCount: Int {
        counts.map { $0.count }.max() ?? 1
    }

    private func scale(_ i: Int) -> CGFloat {
        if i >= counts.count {
            return 0
        }
        return CGFloat(counts[i].count) / CGFloat(maxCount)
    }

    var body: some View {
        ZStack {
            Path { p in
                for i in 0..<10 {
                    let q = point(i, scale: 1.0)
                    if i == 0 {
                        p.move(to: q)
                    } else {
                        p.addLine(to: q)
                    }
                }
                p.closeSubpath()
            }
            .stroke(Ky.line, lineWidth: 0.8)
            Path { p in
                for i in 0..<10 {
                    let q = point(i, scale: 0.5)
                    if i == 0 {
                        p.move(to: q)
                    } else {
                        p.addLine(to: q)
                    }
                }
                p.closeSubpath()
            }
            .stroke(Ky.line.opacity(0.5), lineWidth: 0.5)
            Path { p in
                for i in 0..<10 {
                    p.move(to: CGPoint(x: size / 2, y: size / 2))
                    p.addLine(to: point(i, scale: 1.0))
                }
            }
            .stroke(Ky.line.opacity(0.35), lineWidth: 0.5)
            Path { p in
                for i in 0..<10 {
                    let q = point(i, scale: scale(i))
                    if i == 0 {
                        p.move(to: q)
                    } else {
                        p.addLine(to: q)
                    }
                }
                p.closeSubpath()
            }
            .fill(Ky.qingdai.opacity(0.18))
            Path { p in
                for i in 0..<10 {
                    let q = point(i, scale: scale(i))
                    if i == 0 {
                        p.move(to: q)
                    } else {
                        p.addLine(to: q)
                    }
                }
                p.closeSubpath()
            }
            .stroke(Ky.qingdai, lineWidth: 1.2)
            ForEach(0..<10, id: \.self) { i in
                let name = ChartDepthView.shiShenOrder[i]
                let hit = counts.first(where: { $0.name == name })
                let n = hit?.count ?? 0
                Button {
                    if n > 0 {
                        onSelect(name)
                    }
                } label: {
                    VStack(spacing: 0) {
                        Text(KyV2.shiShenShort(name))
                            .font(.system(size: 12, weight: .bold, design: .serif))
                            .foregroundStyle(selected == name ? Color.white : (n > 0 ? Ky.ink : Ky.sub))
                        Text("\(n)")
                            .font(KyV2.tabular(10, weight: .semibold))
                            .foregroundStyle(selected == name ? Color.white : (n > 0 ? Ky.ink : Ky.sub))
                    }
                    .frame(width: 40, height: 40)
                    .background(selected == name ? Ky.qingdai : Ky.qingdai.opacity(n > 0 ? 0.14 : 0.05))
                    .clipShape(Circle())
                    .opacity(n > 0 ? 1 : 0.55)
                }
                .buttonStyle(.plain)
                .position(point(i, scale: 1.22))
                .accessibilityLabel("\(name)共 \(n) 处，点按定位")
                .disabled(n == 0)
            }
        }
        .frame(width: size, height: size)
    }
}
