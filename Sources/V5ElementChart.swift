import SwiftUI

/// A view of the engine's five values, never an alternative scoring algorithm.
/// Labels remain readable independently of the decorative element colors.
struct V5ElementCycle: View {
    let values: [Double]
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected = 0
    private let labels = ["木", "火", "土", "金", "水"]
    private var valid: Bool { values.count == 5 && values.allSatisfy { $0.isFinite && $0 >= 0 } }
    var body: some View {
        if valid {
            VStack(alignment: .leading, spacing: 12) {
                if typeSize <= .large {
                    GeometryReader { geometry in
                        let side = min(geometry.size.width, geometry.size.height)
                        let center = CGPoint(x: geometry.size.width / 2, y: side / 2)
                        let radius = max(0, side / 2 - 42)
                        ZStack {
                            Circle().stroke(V5Palette.color(V5Palette.current.ornament).opacity(0.4), lineWidth: 1)
                                .frame(width: radius * 2, height: radius * 2).position(center)
                            Path { path in
                                for i in 0..<5 {
                                    path.move(to: point(i, center: center, radius: radius))
                                    path.addLine(to: point((i + 2) % 5, center: center, radius: radius))
                                }
                            }.stroke(V5Palette.color(V5Palette.current.ornament).opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                                .accessibilityHidden(true)
                            Text("五行\n构成比例").font(V5Typography.title).multilineTextAlignment(.center).position(center)
                            ForEach(0..<5) { i in
                                Button {
                                    selected = i
                                    V5Motion.selectionFeedback()
                                } label: {
                                    VStack(spacing: 3) {
                                        Text(labels[i]).font(.system(.title2, design: .serif).weight(.semibold))
                                        Text(String(format: "%.1f%%", values[i])).font(.caption.monospacedDigit())
                                    }
                                    .frame(width: 76, height: 76)
                                    .background(V5Palette.color(V5Palette.current.surface), in: Circle())
                                    .overlay(Circle().stroke(KyV2.wuxingColors[i], lineWidth: selected == i ? 3 : 1))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(labels[i])，占比\(String(format: "%.1f", values[i]))百分比")
                                .accessibilityAddTraits(selected == i ? .isSelected : [])
                                .position(point(i, center: center, radius: radius))
                            }
                        }
                    }.frame(height: 300)
                }
                Text("\(labels[selected]) · \(String(format: "%.1f%%", values[selected]))")
                    .font(V5Typography.title).contentTransition(.numericText())
                    .animation(reduceMotion ? nil : V5Motion.press, value: selected)
                Text("相生：木→火→土→金→水→木；虚线示相克：木→土→水→火→金→木。比例沿用排盘引擎口径，不代表健康或吉凶评分。")
                    .font(.footnote).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
            }.foregroundStyle(V5Palette.color(V5Palette.current.ink))
        }
    }
    private func point(_ index: Int, center: CGPoint, radius: CGFloat) -> CGPoint {
        let angle = Double(index) * .pi * 2 / 5 - .pi / 2
        return CGPoint(x: center.x + radius * CGFloat(cos(angle)), y: center.y + radius * CGFloat(sin(angle)))
    }
}

struct V5TenGodDistribution: View {
    let chart: BaziChart
    private let order = ["比肩", "劫财", "食神", "伤官", "偏财", "正财", "七杀", "正官", "偏印", "正印"]
    var body: some View {
        V5Card {
            VStack(alignment: .leading, spacing: 12) {
                V5SectionHeading(title: "十神分布", subtitle: "分别统计天干与藏干出现次数；日主不计，未添加权重或改算命盘。")
                ForEach(order, id: \.self) { name in
                    let stems = chart.stemShiShen.filter { $0 == name }.count
                    let hidden = chart.hideShiShen.flatMap { $0 }.filter { $0 == name }.count
                    HStack {
                        Text(name)
                        Spacer(minLength: 8)
                        Text("天干 \(stems) · 藏干 \(hidden)").monospacedDigit()
                    }.font(.subheadline).accessibilityElement(children: .combine)
                }
            }
        }
    }
}
