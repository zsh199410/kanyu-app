import SwiftUI

struct V5AppearancePage: View {
    private var selected: V5Theme { V5ThemeStore.shared.theme }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                V5ArtHeader(eyebrow: "四时外观 · 随心切换", title: "四境同源", subtitle: "一份真实命盘，四种东方意境。切换外观不会更改档案或测算口径。")
                ForEach(V5Theme.allCases) { theme in
                    Button { V5Motion.selectionFeedback();V5ThemeStore.shared.select(theme) } label: {
                        preview(theme)
                    }.buttonStyle(.plain)
                        .accessibilityLabel(theme.title)
                        .accessibilityAddTraits(theme == selected ? .isSelected : [])
                }
            }.padding(V5Metric.page)
        }.background { V5SceneBackground() }.foregroundStyle(V5Palette.color(V5Palette.current.ink))
            .navigationTitle("四时外观").navigationBarTitleDisplayMode(.inline)
    }
    private func preview(_ theme: V5Theme) -> some View {
        let p = theme.palette
        return VStack(alignment: .leading, spacing: 16) {
            ZStack(alignment: .bottomLeading) {
                V5Palette.color(p.paper)
                if let texture = V5ArtworkRegistry.image(.texture, theme: theme) {
                    Image(uiImage: texture).resizable(resizingMode: .tile).opacity(0.14)
                }
                if let scene = V5ArtworkRegistry.image(.landscape, theme: theme) { Image(uiImage: scene).resizable().scaledToFill() }
            }.frame(height: 110).clipped().accessibilityHidden(true)
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(theme.title).font(V5Typography.section)
                    Text(description(theme)).font(.subheadline).foregroundStyle(V5Palette.color(p.secondary))
                }
                Spacer(minLength: 0)
                Image(systemName: selected == theme ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(V5Palette.color(p.accent)).accessibilityHidden(true)
            }.padding(.horizontal, 20).padding(.bottom, 20)
        }.frame(maxWidth: .infinity, minHeight: V5Metric.target, alignment: .leading)
            .foregroundStyle(V5Palette.color(p.ink)).background(V5Palette.color(p.surface))
            .clipShape(RoundedRectangle(cornerRadius: theme == .collection ? 12 : 24))
            .overlay(RoundedRectangle(cornerRadius: theme == .collection ? 12 : 24).stroke(V5Palette.color(p.ornament), lineWidth: selected == theme ? 1.5 : 0.6))
    }
    private func description(_ theme: V5Theme) -> String {
        switch theme {
        case .song: return "宋纸青黛 · 山水雅卷"
        case .night: return "玄夜星河 · 金色天仪"
        case .celadon: return "白玉流光 · 青瓷云水"
        case .collection: return "玄黑锦纹 · 朱漆金册"
        }
    }
}
