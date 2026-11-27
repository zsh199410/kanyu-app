import SwiftUI
import UIKit

/// Approved layers are independent files: never extract text or data from a concept screenshot.
enum V5ArtworkRole: String, CaseIterable {
    case landscape, emblem, personObject = "person-object", bookCoverArt = "book-cover-art", texture, flourish
    case bazi = "glyph-bazi", ziwei = "glyph-ziwei", palm = "glyph-palm", face = "glyph-face", survey = "glyph-survey"
    case navHome = "nav-home", navMeasure = "nav-measure", navReports = "nav-reports", navProfiles = "nav-profiles"
    func name(for theme: V5Theme) -> String { "v5-\(theme.rawValue)-\(rawValue)" }
}
enum V5ArtworkRegistry {
    static func image(_ role: V5ArtworkRole, theme: V5Theme = V5ThemeStore.shared.theme) -> UIImage? {
        UIImage(named: role.name(for: theme))
    }
    static func missing(theme: V5Theme) -> [String] {
        V5ArtworkRole.allCases.filter { image($0, theme: theme) == nil }.map { $0.name(for: theme) + ".png" }
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
