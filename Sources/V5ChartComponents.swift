import SwiftUI

/// Read-only typesetting of actual engine output. Each stem sits above its branch.
struct V5BirthOverview: View {
    let chart: BaziChart
    @Environment(\.dynamicTypeSize) private var typeSize
    private let names = ["年柱", "月柱", "日柱", "时柱"]
    private let elements = ["木", "火", "土", "金", "水"]
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .firstTextBaseline) {
                Text("四柱命盘").font(V5Typography.section)
                Spacer()
                Text("天干在上 · 地支在下").font(.caption)
                    .foregroundStyle(V5Palette.color(V5Palette.current.secondary))
            }
            if typeSize.isAccessibilitySize {
                ScrollView(.horizontal) { pillarColumns(minimumWidth: 112) }
            } else {
                pillarColumns(minimumWidth: 52)
            }
            Divider().overlay(V5Palette.color(V5Palette.current.ornament).opacity(0.3))
            V5SectionHeading(title: "五行气象", subtitle: "天干与藏干的真实构成比例")
            V5ElementCycle(values: chart.wuxingPercents)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 110 : 46))], spacing: 12) {
                ForEach(Array(chart.wuxingPercents.prefix(5).enumerated()), id: \.offset) { index, value in
                    VStack(spacing: 8) {
                        Text(elements[index]).font(V5Typography.song(.title2))
                        Text(value.isFinite ? String(format: "%.1f%%", value) : "未提供")
                            .font(.caption.monospacedDigit())
                    }.padding(.vertical, 12).frame(maxWidth: .infinity)
                        .overlay(alignment: .top) {
                            Rectangle().fill(V5Palette.color(V5Palette.current.ornament).opacity(0.4)).frame(height: 1)
                        }
                        .accessibilityElement(children: .combine)
                }
            }
            Text("图表读取当前命主的真实排盘结果。传统民俗参考。")
                .font(V5Typography.evidence).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
        }.foregroundStyle(V5Palette.color(V5Palette.current.ink))
    }
    private func pillarColumns(minimumWidth: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(chart.pillars.enumerated()), id: \.offset) { index, pillar in
                V5VerticalPillar(name: names[index], pillar: pillar,
                                 god: chart.stemShiShen[index], hidden: chart.hideGan[index], isDay: index == 2)
                    .frame(minWidth: minimumWidth, maxWidth: .infinity)
            }
        }
    }
}
private struct V5VerticalPillar: View {
    let name: String; let pillar: String; let god: String; let hidden: [String]; let isDay: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var characterSize: CGFloat = 42
    var body: some View {
        VStack(spacing: 0) {
            Text(name).font(.caption).padding(.top, 12).padding(.bottom, 10)
                .foregroundStyle(V5Palette.color(V5Palette.current.secondary))
            Text(god).font(.caption).padding(.bottom, 14)
                .foregroundStyle(V5Palette.color(isDay ? V5Palette.current.accent : V5Palette.current.secondary))
            VStack(spacing: 10) {
                Text(pillar.first.map(String.init) ?? "—")
                Text(pillar.last.map(String.init) ?? "—")
            }.font(V5Typography.printFont(size: characterSize, emphasis: true))
                .foregroundStyle(V5Palette.color(isDay ? V5Palette.current.accent : V5Palette.current.ink))
                .padding(.bottom, 18)
            Rectangle().fill(V5Palette.color(V5Palette.current.ornament).opacity(0.45))
                .frame(width: 24, height: 1).padding(.bottom, 12)
            Text("藏干").font(.caption2).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
            Text(hidden.joined(separator: " ")).font(.caption).padding(.top, 6).padding(.bottom, 14)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .background(V5Palette.color(V5Palette.current.accent).opacity(isDay ? 0.07 : 0))
        .overlay(alignment: .top) {
            Rectangle().fill(V5Palette.color(isDay ? V5Palette.current.accent : V5Palette.current.ornament).opacity(isDay ? 0.9 : 0.35))
                .frame(height: isDay ? 3 : 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name)，\(pillar)，\(god)，藏干\(hidden.joined(separator: "、"))\(isDay ? "，日主所在柱" : "")")
    }
}

/// Dense data is arranged as one aligned ledger, rather than four repeated prose cards.
struct V5PillarDetailTable: View {
    let chart: BaziChart
    @ScaledMetric(relativeTo: .body) private var columnWidth: CGFloat = 84
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            V5SectionHeading(title: "命局细目", subtitle: "横向展开四柱，按同一行核对十神、藏干与纳音。")
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
            Text("日柱旬空 · \(chart.xunKong)").font(V5Typography.detail)
                .foregroundStyle(V5Palette.color(V5Palette.current.secondary))
        }
    }
    private func row(_ title: String, values: [String], emphasized: Bool = false) -> some View {
        GridRow(alignment: .top) {
            Text(title).font(.caption).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
                .frame(width: 36, alignment: .leading).padding(.vertical, 12)
            ForEach(Array(values.prefix(4).enumerated()), id: \.offset) { _, value in
                Text(value).font(emphasized ? V5Typography.title : V5Typography.detail)
                    .multilineTextAlignment(.center).frame(width: columnWidth)
                    .fixedSize(horizontal: false, vertical: true).padding(.vertical, 12)
            }
        }.background(emphasized ? V5Palette.color(V5Palette.current.accent).opacity(0.05) : .clear)
            .accessibilityElement(children: .combine)
    }
}
