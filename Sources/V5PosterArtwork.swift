import SwiftUI

/// Illustration selection follows the four approved poster families, never a
/// mutable global theme or a different person's record. All reads are synchronous
/// so the same layers exist in previews, ImageRenderer and formal PNG exports.
enum V5PosterArtworkTheme {
    static func theme(for kind: PosterDynamicKind) -> V5Theme {
        switch kind { case .bazi: return .song; case .ziwei: return .night
        case .palm: return .celadon; case .premium: return .collection }
    }
}
struct V5PosterBrandMark: View {
    let kind: PosterDynamicKind
    var body: some View {
        if let image = V5ArtworkRegistry.image(.emblem, theme: V5PosterArtworkTheme.theme(for: kind)) {
            Image(uiImage: image).resizable().scaledToFit().frame(width: 72, height: 72)
                .accessibilityHidden(true)
        }
    }
}
struct V5PosterHeaderArt: View {
    let kind: PosterDynamicKind
    var body: some View {
        GeometryReader { geometry in
            if let image = V5ArtworkRegistry.image(.landscape, theme: V5PosterArtworkTheme.theme(for: kind)) {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(width: geometry.size.width * 0.64, height: geometry.size.height)
                    .frame(maxWidth: .infinity, alignment: .trailing).opacity(0.16)
            }
        }.accessibilityHidden(true).allowsHitTesting(false)
    }
}
