import SwiftUI

/// A scene is made of independently reviewed, text-free layers. No concept image is a page.
struct V5SceneBackground: View {
    private var theme: V5Theme { V5ThemeStore.shared.theme }
    var body: some View {
        ZStack {
            V5Palette.color(theme.palette.paper)
            if let image = V5ArtworkRegistry.image(.texture) {
                Image(uiImage: image).resizable(resizingMode: .tile).opacity(theme.scheme == .dark ? 0.14 : 0.22)
            }
        }.ignoresSafeArea().accessibilityHidden(true).allowsHitTesting(false)
    }
}
struct V5ArtHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Rectangle().fill(V5Palette.color(V5Palette.current.ornament)).frame(width: 28, height: 1)
                Text(eyebrow).font(.caption.weight(.medium)).tracking(3)
            }.foregroundStyle(V5Palette.color(V5Palette.current.ornamentText))
            Text(title).font(.system(.largeTitle, design: .serif).weight(.semibold)).accessibilityAddTraits(.isHeader)
            Text(subtitle).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(V5Palette.color(V5Palette.current.secondary))
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
    }
}
struct V5PanelSilhouette: Shape {
    let theme: V5Theme
    func path(in rect: CGRect) -> Path {
        if theme == .celadon {
            let r = min(CGFloat(30), rect.height / 4)
            var p = Path()
            p.move(to: CGPoint(x: r, y: 5))
            p.addCurve(to: CGPoint(x: rect.maxX-r, y: 5), control1: CGPoint(x: rect.width*0.36, y: -7), control2: CGPoint(x: rect.width*0.66, y: 17))
            p.addQuadCurve(to: CGPoint(x: rect.maxX, y: r), control: CGPoint(x: rect.maxX, y: 0))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY-r))
            p.addQuadCurve(to: CGPoint(x: rect.maxX-r, y: rect.maxY-4), control: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addCurve(to: CGPoint(x: r, y: rect.maxY-4), control1: CGPoint(x: rect.width*0.64, y: rect.maxY-15), control2: CGPoint(x: rect.width*0.32, y: rect.maxY+3))
            p.addQuadCurve(to: CGPoint(x: 0, y: rect.maxY-r), control: CGPoint(x: 0, y: rect.maxY))
            p.addLine(to: CGPoint(x: 0, y: r)); p.addQuadCurve(to: CGPoint(x: r, y: 5), control: .zero);p.closeSubpath()
            return p
        }
        return RoundedRectangle(cornerRadius: theme == .collection ? 12 : (theme == .night ? 26 : 22), style: .continuous).path(in: rect)
    }
}
struct V5Surface: View {
    @Environment(\.colorSchemeContrast) private var contrast
    private var theme: V5Theme { V5ThemeStore.shared.theme }
    var body: some View {
        let p = theme.palette
        V5PanelSilhouette(theme: theme)
            .fill(V5Palette.color(p.surface))
            .overlay {
                if let texture = V5ArtworkRegistry.image(.texture) {
                    Image(uiImage: texture).resizable(resizingMode: .tile).opacity(0.07)
                        .clipShape(V5PanelSilhouette(theme: theme))
                }
            }
            .overlay {
                V5PanelSilhouette(theme: theme).stroke(
                    LinearGradient(colors: [V5Palette.color(p.ornament).opacity(0.8), V5Palette.color(p.surface), V5Palette.color(p.ornament).opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: contrast == .increased ? 1.6 : 0.8)
            }
            .shadow(color: V5Palette.color(p.ink).opacity(theme == .night ? 0.07 : 0.09), radius: 12, x: 0, y: 7)
            .accessibilityHidden(true).allowsHitTesting(false)
    }
}
struct V5BrandHero: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    private var theme: V5Theme { V5ThemeStore.shared.theme }
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                if let emblem = V5ArtworkRegistry.image(.emblem) {
                    Image(uiImage: emblem).resizable().scaledToFit().frame(width: 62, height: 62).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("三术合参").font(.system(.largeTitle, design: .serif).weight(.semibold)).tracking(2)
                        Text("5.0").font(.caption2.bold()).padding(4).foregroundStyle(.white)
                            .background(KanyuV6.Palette.cinnabar, in: RoundedRectangle(cornerRadius: 4))
                    }
                    Text("八字 · 紫微 · 相法").font(.subheadline).tracking(3)
                }
            }
            Text("东方命理 · 个人命书").font(.subheadline).tracking(4)
                .foregroundStyle(V5Palette.color(theme.palette.ornamentText))
            if let landscape = V5ArtworkRegistry.image(.landscape) {
                Image(uiImage: landscape).resizable().scaledToFill()
                    .frame(height: typeSize.isAccessibilitySize ? 90 : (theme == .collection ? 120 : 100))
                    .clipped().accessibilityHidden(true).padding(.horizontal, -V5Metric.page)
            }
        }.frame(maxWidth: .infinity).padding(.top, 12).padding(.bottom, 4)
            .foregroundStyle(V5Palette.color(theme.palette.ink))
    }
}

/// A native book: art is only the front-cover illustration; title/person remain live text.
struct V5BookCover: View {
    let personName: String?
    var title: String = "个人命书"
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var theme: V5Theme { V5ThemeStore.shared.theme }
    var body: some View {
        let p = theme.palette
        HStack(spacing: 0) {
            Rectangle().fill(V5Palette.color(p.ornament)).frame(width: compact ? 5 : 8)
                .overlay(alignment: .leading) { Rectangle().fill(V5Palette.color(p.ink).opacity(0.25)).frame(width: 1) }
            ZStack(alignment: .trailing) {
                V5Palette.color(theme == .collection ? p.heroSurface : p.surface)
                if let art = V5ArtworkRegistry.image(.bookCoverArt) { Image(uiImage: art).resizable().scaledToFill().clipped() }
                HStack(alignment: .top, spacing: 4) {
                    Spacer(minLength: 6)
                    VStack(spacing: 5) {
                        ForEach(Array(title.enumerated()), id: \.offset) { _, c in Text(String(c)).font(.system(compact ? .caption : .headline, design: .serif)) }
                        Rectangle().fill(KanyuV6.Palette.cinnabar).frame(width: 8, height: 12)
                    }.padding(.horizontal, compact ? 5 : 8).padding(.vertical, 10)
                        .foregroundStyle(V5Palette.color(p.readingInk)).background(V5Palette.color(p.readingPaper))
                        .overlay(Rectangle().stroke(V5Palette.color(p.ornament), lineWidth: 0.5))
                }.padding(.trailing, compact ? 9 : 14).padding(.vertical, 12)
            }
        }
        .aspectRatio(0.68, contentMode: .fit)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 3, bottomTrailingRadius: 9, topTrailingRadius: 9))
        .overlay(alignment: .bottom) { Rectangle().fill(V5Palette.color(p.ornament).opacity(0.4)).frame(height: 3) }
        .rotation3DEffect(.degrees(reduceMotion ? 0 : -11), axis: (x: 0, y: 1, z: 0))
        .shadow(color: V5Palette.color(p.ink).opacity(0.18), radius: 8, x: 4, y: 7)
        .accessibilityElement(children: .ignore).accessibilityLabel((personName.map { $0 + "的" } ?? "") + title + "封面")
    }
}
