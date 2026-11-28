import SwiftUI
import UIKit

/// Approved layers are independent files: never extract text or data from a concept screenshot.
enum V5ArtworkRole: String, CaseIterable {
    case landscape, emblem, personObject = "person-object", bookCoverArt = "book-cover-art", texture, flourish
    case bazi = "glyph-bazi", ziwei = "glyph-ziwei", palm = "glyph-palm", face = "glyph-face", survey = "glyph-survey"
    case navHome = "nav-home", navMeasure = "nav-measure", navReports = "nav-reports", navProfiles = "nav-profiles"
    var displayPixelSize: Int {
        switch self {
        case .landscape: return 2048
        case .bookCoverArt: return 1600
        case .personObject: return 1200
        case .texture, .flourish: return 768
        default: return 192
        }
    }
    func name(for theme: V5Theme) -> String { "v5-\(theme.rawValue)-\(rawValue)" }
}
enum V5ArtworkRegistry {
    @MainActor static func tabImage(_ role: V5ArtworkRole) -> UIImage? {
        let theme = V5ThemeStore.shared.theme
        guard let original = image(role, theme: theme) else { return nil }
        let size = CGSize(width: 28, height: 28)
        let format = UIGraphicsImageRendererFormat();format.opaque = false;format.preferredRange = .standard
        let thumbnail = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let scale = min(size.width/original.size.width, size.height/original.size.height)
            let fitted = CGSize(width: original.size.width*scale, height: original.size.height*scale)
            original.draw(in: CGRect(x: (size.width-fitted.width)/2, y: (size.height-fitted.height)/2, width: fitted.width, height: fitted.height))
        }
        return thumbnail
    }
    static func image(_ role: V5ArtworkRole, theme: V5Theme = V5ThemeStore.shared.theme) -> UIImage? {
        guard let url = url(role, theme: theme) else { return nil }
        return V5ArtworkStore.shared.image(at: url, maximumPixelSize: role.displayPixelSize)
    }
    static func url(_ role: V5ArtworkRole, theme: V5Theme, bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: role.name(for: theme), withExtension: "png", subdirectory: "V5Artwork")
            ?? bundle.url(forResource: role.name(for: theme), withExtension: "png")
    }
    static func missing(theme: V5Theme) -> [String] {
        V5ArtworkRole.allCases.filter { url($0, theme: theme) == nil }.map { $0.name(for: theme) + ".png" }
    }
}
/// Screen-only asynchronous artwork. Export renderers use Registry.image synchronously.
struct V5ArtworkLayer<Content: View>: View {
    let role: V5ArtworkRole
    var theme: V5Theme = V5ThemeStore.shared.theme
    @ViewBuilder let content: (UIImage) -> Content
    @State private var loaded: (key: String, image: UIImage)?
    private var key: String { role.name(for: theme) }
    var body: some View {
        ZStack {
            if let loaded, loaded.key == key { content(loaded.image) }
        }
        .task(id: key) {
            guard let url = V5ArtworkRegistry.url(role, theme: theme),
                  let image = await V5ArtworkStore.shared.load(at: url, maximumPixelSize: role.displayPixelSize),
                  !Task.isCancelled else { return }
            loaded = (key, image)
        }
        .accessibilityHidden(true).allowsHitTesting(false)
    }
}
enum V5FeatureKind: String, CaseIterable {
    case bazi, ziwei, palm, face, survey, calendar, qimen, tools
    var artwork: V5ArtworkRole? {
        switch self { case .bazi: return .bazi; case .ziwei: return .ziwei; case .palm: return .palm
        case .face: return .face; case .survey: return .survey; default: return nil }
    }
    var symbol: String {
        switch self { case .bazi: return "circle.lefthalf.filled"; case .ziwei: return "sparkles"; case .palm: return "hand.raised"
        case .face: return "face.smiling"; case .survey: return "mountain.2"; case .calendar: return "calendar"
        case .qimen: return "square.grid.3x3"; case .tools: return "square.grid.2x2" }
    }
}
struct V5FeatureGlyph: View {
    let kind: V5FeatureKind
    var size: CGFloat = 42
    var body: some View {
        Group {
            if let role = kind.artwork, let image = V5ArtworkRegistry.image(role) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                // Functional system symbol while art is missing; never counts as approved original artwork.
                Image(systemName: kind.symbol).font(.system(size: size * 0.76, weight: .ultraLight))
                    .foregroundStyle(V5Palette.color(V5Palette.current.ornamentText))
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}
