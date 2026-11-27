import SwiftUI

/// A compact editorial overview; full charts remain one tap away in the calculation workspace.
struct V5HomeChartPreview: View {
    let chart: BaziChart
    @Environment(\.dynamicTypeSize) private var typeSize
    private let elements = ["木", "火", "土", "金", "水"]
    private var theme: V5Theme { V5ThemeStore.shared.theme }
    var body: some View {
        if typeSize > .large {
            VStack(alignment: .leading, spacing: 12) { pillars; values }
        } else if theme == .night {
            HStack(spacing: 18) { medallion.frame(width: 122, height: 132); values }
        } else {
            HStack(alignment: .center, spacing: 14) { pillars; medallion.frame(width: 132, height: 132) }
        }
    }
    private var pillars: some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(Array(chart.pillars.enumerated()), id: \.offset) { index, pillar in
                VStack(spacing: 8) {
                    Text(["年柱", "月柱", "日柱", "时柱"][index]).font(.caption2)
                        .foregroundStyle(V5Palette.color(V5Palette.current.secondary))
                    Text(pillar.map(String.init).joined(separator: "\n"))
                        .font(V5Typography.song(.title2, emphasis: index == 2))
                        .lineSpacing(6).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity).padding(.vertical, 10)
                    .overlay(alignment: .top) { Rectangle().fill(V5Palette.color(V5Palette.current.ornament).opacity(index == 2 ? 0.8 : 0.2)).frame(height: index == 2 ? 2 : 0.5) }
                    .accessibilityElement(children: .ignore).accessibilityLabel(["年柱", "月柱", "日柱", "时柱"][index] + "，" + pillar)
            }
        }
    }
    private var values: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(chart.wuxingPercents.prefix(5).enumerated()), id: \.offset) { index, value in
                HStack(spacing: 6) {
                    Text(elements[index]).font(.caption).frame(width: 16)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(V5Palette.color(V5Palette.current.secondary).opacity(0.15))
                            if value.isFinite { Capsule().fill(KyV2.wuxingColors[index]).frame(width: proxy.size.width * CGFloat(min(100,max(0,value))) / 100) }
                        }
                    }.frame(height: 7).accessibilityHidden(true)
                    Text(value.isFinite ? String(format: "%.1f%%", value) : "未提供").font(.caption.monospacedDigit()).frame(minWidth: 42, alignment: .trailing)
                }.accessibilityElement(children: .combine)
            }
        }
    }
    private var medallion: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width/2,y: proxy.size.height/2)
            let radius = min(proxy.size.width,proxy.size.height)/2-19
            ZStack {
                Circle().stroke(V5Palette.color(V5Palette.current.ornament).opacity(0.5), lineWidth: 1)
                    .frame(width: radius*2,height: radius*2).position(center)
                Path { p in
                    for i in 0..<5 {
                        p.move(to: point(i,center:center,radius:radius))
                        p.addLine(to: point((i+2)%5,center:center,radius:radius))
                    }
                }.stroke(V5Palette.color(V5Palette.current.ornament).opacity(0.24),style:StrokeStyle(lineWidth:0.5,dash:[2,3]))
                Text("五行\n构成").font(V5Typography.printFont(size:12)).multilineTextAlignment(.center).position(center)
                ForEach(0..<min(5,chart.wuxingPercents.count),id:\.self) { index in
                    VStack(spacing:1) {
                        Text(elements[index]).font(V5Typography.printFont(size:14,emphasis:true))
                        Text(String(format:"%.1f%%",chart.wuxingPercents[index])).font(.system(size:8).monospacedDigit())
                    }.frame(width:36,height:36)
                        .background(V5Palette.color(V5Palette.current.surface),in:Circle())
                        .overlay(Circle().stroke(KyV2.wuxingColors[index],lineWidth:1))
                        .position(point(index,center:center,radius:radius))
                }
            }
        }.accessibilityElement(children:.ignore).accessibilityLabel("五行构成，" + chart.wuxingPercents.prefix(5).enumerated().map { "\(elements[$0.offset])\(String(format:"%.1f",$0.element))百分比" }.joined(separator:"，"))
    }
    private func point(_ index:Int,center:CGPoint,radius:CGFloat)->CGPoint {
        let angle=Double(index)*2*Double.pi/5-Double.pi/2
        return CGPoint(x:center.x+radius*CGFloat(cos(angle)),y:center.y+radius*CGFloat(sin(angle)))
    }
}
