import SwiftUI

/// A scene is made of independently reviewed, text-free layers. No concept image is a page.
struct V5SceneBackground: View {
    private var theme: V5Theme { V5ThemeStore.shared.theme }
    var body: some View {
        ZStack(alignment: theme == .celadon ? .bottom : .top) {
            V5Palette.color(theme.palette.paper)
            if let image = V5ArtworkRegistry.image(.texture) {
                Image(uiImage: image).resizable(resizingMode: .tile).opacity(theme.scheme == .dark ? 0.12 : 0.18)
            }
            if let landscape = V5ArtworkRegistry.image(.landscape) {
                Image(uiImage: landscape).resizable().scaledToFill()
                    .frame(maxWidth: .infinity).frame(height: theme == .collection ? 300 : 280).clipped()
                    .mask(LinearGradient(colors: theme == .celadon ? [.clear, .white] : [.white, .clear], startPoint: .top, endPoint: .bottom))
                    .opacity(theme.scheme == .dark ? 0.55 : 0.38)
            }
        }.ignoresSafeArea().accessibilityHidden(true).allowsHitTesting(false)
    }
}
struct V5ArtHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Rectangle().fill(V5Palette.color(V5Palette.current.ornament)).frame(width: 28, height: 1)
                Text(eyebrow).font(.caption.weight(.medium)).tracking(3)
            }.foregroundStyle(V5Palette.color(V5Palette.current.ornamentText))
            Text(title).font(V5Typography.song(.title2, emphasis: true)).accessibilityAddTraits(.isHeader)
            Text(subtitle).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(V5Palette.color(V5Palette.current.secondary))
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
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
            .overlay(alignment: .bottomTrailing) {
                if let flourish = V5ArtworkRegistry.image(.flourish) {
                    Image(uiImage: flourish).resizable().scaledToFit().frame(width: 160, height: 42)
                        .opacity(0.2).padding(6).clipShape(V5PanelSilhouette(theme: theme))
                }
            }
            .overlay {
                V5PanelSilhouette(theme: theme).stroke(
                    V5Palette.color(p.ornament).opacity(theme == .collection ? 0.65 : 0.32), lineWidth: contrast == .increased ? 1.6 : 0.8)
            }
            .shadow(color: V5Palette.color(p.ink).opacity(theme == .night ? 0.06 : 0.07), radius: 7, x: 0, y: 3)
            .accessibilityHidden(true).allowsHitTesting(false)
    }
}
struct V5BrandHero: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    private var theme: V5Theme { V5ThemeStore.shared.theme }
    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            HStack(spacing: 10) {
                if !typeSize.isAccessibilitySize, let emblem = V5ArtworkRegistry.image(.emblem) {
                    Image(uiImage: emblem).resizable().scaledToFit().frame(width: 42, height: 42).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("三术合参").font(V5Typography.song(.title2, emphasis: true)).tracking(2)
                    Text("八字 · 紫微 · 相法").font(.caption).tracking(2)
                        .foregroundStyle(V5Palette.color(theme.palette.secondary))
                }
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 4) }
            Text("传统民俗参考").font(.caption2)
                .foregroundStyle(V5Palette.color(theme.palette.secondary))
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
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
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4).fill(V5Palette.color(p.readingPaper))
                .overlay(alignment: .trailing) {
                    VStack(spacing: 2) { ForEach(0..<10, id: \.self) { _ in Rectangle().fill(V5Palette.color(p.readingSecondary).opacity(0.18)).frame(height: 0.5) } }
                        .padding(.trailing, 1).frame(width: 7)
                }.offset(x: 5, y: 4)
            HStack(spacing: 0) {
                V5Palette.color(p.ornament).frame(width: compact ? 6 : 9)
                    .overlay(alignment: .trailing) { Rectangle().fill(V5Palette.color(p.ink).opacity(0.25)).frame(width: 1) }
                ZStack {
                    V5Palette.color(theme == .collection ? p.heroSurface : p.surface)
                    if let art = V5ArtworkRegistry.image(.bookCoverArt) {
                        Image(uiImage: art).resizable().scaledToFill().clipped()
                    }
                    Rectangle().stroke(V5Palette.color(p.ornament).opacity(0.65), lineWidth: 0.7).padding(5)
                    VStack(alignment: .trailing, spacing: 0) {
                        HStack(alignment: .top) {
                            Spacer(minLength: 3)
                            VStack(spacing: 3) {
                                ForEach(Array(title.enumerated()), id: \.offset) { _, character in
                                    Text(String(character)).font(V5Typography.printFont(size: compact ? 12 : 17, emphasis: true))
                                }
                            }.padding(.horizontal, compact ? 4 : 7).padding(.vertical, 9)
                                .foregroundStyle(V5Palette.color(p.readingInk))
                                .background(V5Palette.color(p.readingPaper))
                        }
                        Spacer(minLength: 4)
                        HStack {
                            Text(personName ?? "三术合参").font(V5Typography.printFont(size: compact ? 7 : 9))
                                .lineLimit(2).foregroundStyle(V5Palette.color(p.heroInk))
                            Spacer(minLength: 3)
                            Text("合\n参").font(V5Typography.printFont(size: compact ? 7 : 9, emphasis: true))
                                .padding(3).foregroundStyle(.white).background(KanyuV6.Palette.cinnabar)
                        }.padding(.bottom, 8)
                    }.padding(.horizontal, 10).padding(.top, 10)
                }.clipped()
            }.clipShape(UnevenRoundedRectangle(topLeadingRadius: 2, bottomLeadingRadius: 2, bottomTrailingRadius: 5, topTrailingRadius: 5))
        }
        .aspectRatio(0.68, contentMode: .fit)
        .rotation3DEffect(.degrees(reduceMotion ? 0 : -10), axis: (x: 0, y: 1, z: 0))
        .shadow(color: V5Palette.color(p.ink).opacity(0.18), radius: 6, x: 4, y: 5)
        .accessibilityElement(children: .ignore).accessibilityLabel((personName.map { $0 + "的" } ?? "") + title + "封面")
    }
}
