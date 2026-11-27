import SwiftUI

/// Read-only presentation of engine output; no copied reference percentages or recalculation.
struct V5BirthOverview: View {
    let chart: BaziChart
    @Environment(\.dynamicTypeSize) private var typeSize
    private let names = ["年柱", "月柱", "日柱", "时柱"]
    private let elements = ["木", "火", "土", "金", "水"]
    var body: some View {
        VStack(alignment: .leading, spacing: V5Metric.gap) {
            Text("四柱命盘").font(.system(.title2, design: .serif))
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(Array(chart.pillars.enumerated()), id: \.offset) { index, pillar in
                        VStack(spacing: 12) {
                            Text(names.indices.contains(index) ? names[index] : "柱")
                                .font(.caption).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
                            Text(pillar).font(.system(typeSize.isAccessibilitySize ? .title : .largeTitle, design: .serif))
                                .fixedSize()
                        }
                        .padding(16).frame(minWidth: 70, minHeight: 112)
                        .background(V5Palette.color(V5Palette.current.surface), in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            .accessibilityLabel("四柱，按年、月、日、时顺序")
            Text("五行构成").font(.system(.title2, design: .serif))
            ForEach(Array(chart.wuxingPercents.prefix(5).enumerated()), id: \.offset) { index, value in
                HStack(spacing: 12) {
                    Text(elements[index]).frame(minWidth: 24)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(V5Palette.color(V5Palette.current.secondary).opacity(0.15))
                            if value.isFinite {
                                Capsule().fill(V5Palette.color(V5Palette.current.accent))
                                    .frame(width: geometry.size.width * CGFloat(min(100, max(0, value))) / 100)
                            }
                        }
                    }.frame(height: 10).accessibilityHidden(true)
                    Text(value.isFinite ? String(format: "%.1f%%", value) : "未提供")
                        .monospacedDigit().frame(minWidth: 64, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
            Text("图表读取当前命主的真实排盘结果。传统民俗参考。")
                .font(.caption).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
        }
        .foregroundStyle(V5Palette.color(V5Palette.current.ink))
    }
}
