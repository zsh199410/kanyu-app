import SwiftUI

/// A compact real-data preview for the home composition. No second chart engine.
struct V5HomeChartPreview: View {
    let chart: BaziChart
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        if typeSize > .large {
            VStack(alignment: .leading, spacing: 16) {
                Text("四柱").font(.headline)
                V5FourPillars(chart: chart, compact: true)
                Text("五行构成").font(.headline)
                V5FiveElementBars(values: chart.wuxingPercents)
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("四柱").font(.caption.weight(.semibold))
                    V5FourPillars(chart: chart, compact: true)
                }.frame(maxWidth: .infinity)
                Rectangle().fill(V5Palette.color(V5Palette.current.ornament).opacity(0.3)).frame(width: 0.7, height: 112)
                VStack(alignment: .leading, spacing: 8) {
                    Text("五行").font(.caption.weight(.semibold))
                    V5CompactElementMedallion(values: chart.wuxingPercents)
                }.frame(maxWidth: .infinity)
            }
        }
    }
}
/// Live engine percentages arranged around a native ring, with semantic element
/// colors shared with the professional charts. Larger text uses the full bars above.
private struct V5CompactElementMedallion: View {
    let values: [Double]
    private let names = ["木", "火", "土", "金", "水"]
    var body: some View {
        if values.count == 5 && values.allSatisfy({ $0.isFinite && $0 >= 0 }) {
            GeometryReader { geometry in
                let side = min(geometry.size.width, geometry.size.height)
                let center = CGPoint(x: geometry.size.width / 2, y: side / 2)
                let radius = max(0, (side - 44) / 2)
                ZStack {
                    Circle().stroke(V5Palette.color(V5Palette.current.ornament).opacity(0.4), lineWidth: 0.7)
                        .frame(width: radius * 2, height: radius * 2).position(center)
                    Text("五行\n构成").font(.caption2).multilineTextAlignment(.center)
                        .position(center).accessibilityHidden(true)
                    ForEach(0..<5) { index in
                        let angle = Double(index) * .pi * 2 / 5 - .pi / 2
                        VStack(spacing: 1) {
                            Text(names[index]).font(V5Typography.song(.caption, emphasis: true))
                            Text(String(format: "%.1f%%", values[index])).font(.caption2.monospacedDigit())
                        }.frame(width: 44, height: 44)
                            .background {
                                Circle().fill(V5Palette.color(V5Palette.current.surface))
                                    .overlay(Circle().fill(KyV2.wuxingColors[index].opacity(0.10)))
                            }
                            .overlay(Circle().stroke(KyV2.wuxingColors[index].opacity(0.85), lineWidth: 1))
                            .position(x: center.x + radius * CGFloat(cos(angle)), y: center.y + radius * CGFloat(sin(angle)))
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(names[index])，占比\(String(format: "%.1f", values[index]))百分比")
                    }
                }
            }.frame(height: 154)
        } else { V5FiveElementBars(values: values) }
    }
}

struct V5BirthOverview: View {
    let chart: BaziChart
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("四柱命盘").font(V5Typography.song(.headline, emphasis: true))
                Spacer()
                Text("天干 / 地支").font(.caption).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
            }
            V5FourPillars(chart: chart)
            Divider()
            Text("五行构成").font(V5Typography.song(.headline, emphasis: true)).accessibilityAddTraits(.isHeader)
            V5FiveElementBars(values: chart.wuxingPercents)
            DisclosureGroup("五行生克关系图") { V5ElementCycle(values: chart.wuxingPercents).padding(.top, 12) }
                .font(.subheadline)
            Text("比例沿用天干与藏干的引擎口径，不代表健康或吉凶评分。")
                .font(.caption).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
        }.foregroundStyle(V5Palette.color(V5Palette.current.ink))
    }
}
private struct V5FourPillars: View {
    let chart: BaziChart
    var compact = false
    @Environment(\.dynamicTypeSize) private var typeSize
    private let names = ["年柱", "月柱", "日柱", "时柱"]
    var body: some View {
        if typeSize.isAccessibilitySize {
            ScrollView(.horizontal) { columns(minimumWidth: compact ? 100 : 112) }
        } else { columns(minimumWidth: compact ? 28 : 52) }
    }
    private func columns(minimumWidth: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(chart.pillars.enumerated()), id: \.offset) { index, pillar in
                V5VerticalPillar(name: names[index], pillar: pillar, god: chart.stemShiShen[index],
                                 hidden: chart.hideGan[index], isDay: index == 2, compact: compact)
                    .frame(minWidth: minimumWidth, maxWidth: .infinity)
            }
        }
    }
}
private struct V5VerticalPillar: View {
    let name: String; let pillar: String; let god: String; let hidden: [String]; let isDay: Bool; let compact: Bool
    @ScaledMetric(relativeTo: .title) private var characterSize: CGFloat = 34
    var body: some View {
        VStack(spacing: 0) {
            Text(name).font(.caption).padding(.top, 8).padding(.bottom, 6)
                .foregroundStyle(V5Palette.color(V5Palette.current.secondary))
            if !compact {
                Text(god).font(.caption).padding(.bottom, 8)
                    .foregroundStyle(V5Palette.color(isDay ? V5Palette.current.accent : V5Palette.current.secondary))
            }
            VStack(spacing: compact ? 2 : 5) {
                Text(pillar.first.map(String.init) ?? "—")
                Text(pillar.last.map(String.init) ?? "—")
            }.font(V5Typography.printFont(size: characterSize * (compact ? 0.8 : 1), emphasis: true))
                .foregroundStyle(V5Palette.color(isDay ? V5Palette.current.accent : V5Palette.current.ink))
                .padding(.bottom, compact ? 8 : 12)
            if !compact {
                Text("藏干").font(.caption2).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
                Text(hidden.joined(separator: " ")).font(.caption).padding(.top, 4).padding(.bottom, 8)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity)
            .background(V5Palette.color(V5Palette.current.accent).opacity(isDay ? 0.07 : 0))
            .overlay(alignment: .top) {
                Rectangle().fill(V5Palette.color(isDay ? V5Palette.current.accent : V5Palette.current.ornament).opacity(isDay ? 0.9 : 0.35))
                    .frame(height: isDay ? 2 : 0.7)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(name)，\(pillar)，\(god)\(compact ? "" : "，藏干" + hidden.joined(separator: "、"))\(isDay ? "，日主所在柱" : "")")
    }
}
private struct V5FiveElementBars: View {
    let values: [Double]
    private let names = ["木", "火", "土", "金", "水"]
    var body: some View {
        VStack(spacing: 10) {
            ForEach(Array(values.prefix(5).enumerated()), id: \.offset) { index, value in
                HStack(spacing: 12) {
                    Text(names[index]).font(.body).frame(minWidth: 24, alignment: .leading)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(V5Palette.color(V5Palette.current.secondary).opacity(0.12))
                            if value.isFinite {
                                Capsule().fill(V5Palette.color(V5Palette.current.accent))
                                    .frame(width: geometry.size.width * CGFloat(min(100, max(0, value))) / 100)
                            }
                        }
                    }.frame(height: 8).accessibilityHidden(true)
                    Text(value.isFinite ? String(format: "%.1f%%", value) : "未提供")
                        .font(.subheadline.monospacedDigit()).frame(minWidth: 64, alignment: .trailing)
                }.accessibilityElement(children: .combine)
            }
        }
    }
}

struct V5TenGodLedger: View {
    let chart: BaziChart
    @Environment(\.dynamicTypeSize) private var typeSize
    private let order = ["比肩", "劫财", "食神", "伤官", "偏财", "正财", "七杀", "正官", "偏印", "正印"]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("十神分布").font(V5Typography.song(.headline, emphasis: true)).accessibilityAddTraits(.isHeader)
            Text("天干 / 藏干出现次数 · 不含日主，不加权重").font(.caption)
                .foregroundStyle(V5Palette.color(V5Palette.current.secondary))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 220 : 130))], spacing: 0) {
                ForEach(order, id: \.self) { name in
                    let stems = chart.stemShiShen.filter { $0 == name }.count
                    let hidden = chart.hideShiShen.flatMap { $0 }.filter { $0 == name }.count
                    HStack(spacing: 8) {
                        Text(name).font(.subheadline)
                        Spacer(minLength: 4)
                        Text("\(stems) / \(hidden)").font(.subheadline.monospacedDigit())
                    }.padding(.vertical, 12).padding(.horizontal, 6)
                        .overlay(alignment: .bottom) { Divider() }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(name)，天干\(stems)次，藏干\(hidden)次")
                }
            }
        }
    }
}

/// Dense data is arranged as one aligned ledger, rather than repeated prose cards.
struct V5PillarDetailTable: View {
    let chart: BaziChart
    @ScaledMetric(relativeTo: .body) private var columnWidth: CGFloat = 84
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("命局细目").font(V5Typography.song(.headline, emphasis: true)).accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal) {
                Grid(alignment: .center, horizontalSpacing: 12, verticalSpacing: 0) {
                    row("四柱", values: ["年柱", "月柱", "日柱", "时柱"], emphasized: true)
                    row("干支", values: chart.pillars, emphasized: true)
                    row("十神", values: chart.stemShiShen)
                    row("藏干", values: chart.hideGan.map { $0.joined(separator: " · ") })
                    row("藏神", values: chart.hideShiShen.map { $0.joined(separator: " · ") })
                    row("地势", values: chart.diShi)
                    row("纳音", values: chart.naYin)
                }
            }
            Text("日柱旬空 · \(chart.xunKong)").font(.caption)
                .foregroundStyle(V5Palette.color(V5Palette.current.secondary))
        }
    }
    private func row(_ title: String, values: [String], emphasized: Bool = false) -> some View {
        GridRow(alignment: .top) {
            Text(title).font(.caption).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
                .frame(width: 36, alignment: .leading).padding(.vertical, 9)
            ForEach(Array(values.prefix(4).enumerated()), id: \.offset) { _, value in
                Text(value).font(emphasized ? .headline : .subheadline)
                    .multilineTextAlignment(.center).frame(width: columnWidth)
                    .fixedSize(horizontal: false, vertical: true).padding(.vertical, 9)
            }
        }.background(emphasized ? V5Palette.color(V5Palette.current.accent).opacity(0.05) : .clear)
            .accessibilityElement(children: .combine)
    }
}
