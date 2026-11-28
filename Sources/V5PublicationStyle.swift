import UIKit

/// Rendering-only bridge for ReportBuilder's existing CGPDFContext and single pagination pass.
/// Capture a theme once per export. This type never writes PDFs, paginates, changes report lines,
/// hashes, metadata, UUID ownership, or archive paths. ReportBuilder captures one style per export.
/// Adoption points: makePDF's font declarations/body attributes and page backgrounds; drawCover/
/// drawTOC color lookups; drawFooter delegates here. Keep paginate/layoutFragments, pages/TOC,
/// direct CGPDFContext metadata and ReportExportArchive.save unchanged. Header use is optional.
struct V5PublicationStyle {
    enum TextRole: Equatable { case title, heading, body, caption, brand }
    enum Failure: Error { case invalidGeometry, textExceedsFrame, invalidPageNumber }

    let theme: V5Theme
    let palette: V5Palette
    init(theme: V5Theme) {
        self.theme = theme
        palette = theme.palette
    }

    var coverInk: UIColor { Self.color(palette.heroInk) }
    var coverSecondary: UIColor { Self.color(palette.heroSecondary) }
    var coverAccent: UIColor { Self.color(palette.ornament) }
    var pageInk: UIColor { Self.color(palette.readingInk) }
    var pageSecondary: UIColor { Self.color(palette.readingSecondary) }
    var pageAccent: UIColor { Self.color(palette.readingAccent) }

    func drawCoverArtwork(in context: CGContext, pageRect: CGRect) {
        guard let cover = V5ArtworkRegistry.image(.bookCoverArt, theme: theme) else { return }
        // Illustration and typography remain separate. The body paginator, cover
        // text metrics, searchable Chinese fonts and ownership metadata are untouched.
        let area = pageRect.insetBy(dx: 24, dy: 32)
        let scale = min(area.width / cover.size.width, area.height / cover.size.height)
        let size = CGSize(width: cover.size.width * scale, height: cover.size.height * scale)
        context.saveGState()
        UIGraphicsPushContext(context)
        context.setAlpha(palette.isDark ? 0.22 : 0.38)
        cover.draw(in: CGRect(x: area.midX-size.width/2, y: area.midY-size.height/2, width: size.width, height: size.height))
        context.setAlpha(0.65)
        context.setStrokeColor(coverAccent.cgColor);context.setLineWidth(0.7)
        context.stroke(pageRect.insetBy(dx: 32, dy: 40))
        UIGraphicsPopContext();context.restoreGState()
    }

    // Match the existing ReportBuilder metrics exactly so a style-only adoption cannot repaginate.
    static let a4 = CGRect(x: 0, y: 0, width: 595, height: 842)
    static let inset: CGFloat = 48
    static let lineSpacing: CGFloat = 3

    // CoreGraphics embeds Noto CFF glyph aliases as radicals/private-use digits in PDF ToUnicode.
    // Keep the proven system Songti for searchable, lossless PDF text; app UI uses Noto.
    static let regularFontName = "STSongti-SC-Regular"
    static let emphasizedFontName = "STSongti-SC-Bold"

    func font(for role: TextRole) -> UIFont {
        let specification: (name: String, size: CGFloat, bold: Bool)
        switch role {
        case .title: specification = (Self.emphasizedFontName, 20, true)
        case .heading: specification = (Self.emphasizedFontName, 12.5, true)
        case .body: specification = (Self.regularFontName, 11.5, false)
        case .caption: specification = (Self.regularFontName, 9, false)
        case .brand: specification = (Self.emphasizedFontName, 28, true)
        }
        return UIFont(name: specification.name, size: specification.size)
            ?? (specification.bold ? .boldSystemFont(ofSize: specification.size) : .systemFont(ofSize: specification.size))
    }
    func attributes(for role: TextRole, alignment: NSTextAlignment = .left, cover: Bool = false) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineSpacing = role == .caption || role == .brand ? 0 : Self.lineSpacing
        paragraph.lineBreakMode = .byWordWrapping
        let ink = cover ? (role == .caption ? palette.heroSecondary : palette.heroInk) : palette.readingInk
        return [.font: font(for: role), .ligature: 0, .paragraphStyle: paragraph, .foregroundColor: Self.color(ink)]
    }
    func contentRect(in pageRect: CGRect) -> CGRect {
        pageRect.insetBy(dx: Self.inset, dy: Self.inset)
    }

    /// Caller retains ReportBuilder's top-left UIKit coordinate transform; no raster text or PDFKit reserialization.
    func drawBackground(in context: CGContext, pageRect: CGRect, cover: Bool = false) {
        context.saveGState()
        defer { context.restoreGState() }
        context.setFillColor(Self.color(cover ? palette.heroSurface : palette.readingPaper).cgColor)
        context.fill(pageRect)
    }

    /// Does not silently ellipsize or clip. Oversized content must go through the existing paginator.
    /// A running title that cannot fit its reserved band must be omitted or redesigned by the caller,
    /// while its complete text remains on the cover/body. No new pagination policy lives here.
    @discardableResult
    func drawText(_ text: String, role: TextRole, in rect: CGRect, context: CGContext,
                  alignment: NSTextAlignment = .left, cover: Bool = false) throws -> CGFloat {
        guard rect.width.isFinite, rect.height.isFinite, rect.minX.isFinite, rect.minY.isFinite,
              rect.width > 0, rect.height > 0 else { throw Failure.invalidGeometry }
        let attributes = attributes(for: role, alignment: alignment, cover: cover)
        let measured = ceil((text as NSString).boundingRect(with: CGSize(width: rect.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin], attributes: attributes, context: nil).height)
        guard measured <= rect.height else { throw Failure.textExceedsFrame }
        context.saveGState()
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext(); context.restoreGState() }
        (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin], attributes: attributes, context: nil)
        return measured
    }

    /// Optional furniture only: the reserved band ends at y=40; existing body starts at y=48.
    func drawHeader(_ text: String, in context: CGContext, pageRect: CGRect) throws {
        let rect = CGRect(x: pageRect.minX + Self.inset, y: pageRect.minY + 12,
                          width: pageRect.width - Self.inset * 2, height: 28)
        try drawText(text, role: .caption, in: rect, context: context)
    }

    /// Exact existing footer wording and position; the live page count comes from the existing pages array.
    func drawFooter(in context: CGContext, pageRect: CGRect, page: Int, total: Int) throws {
        guard page > 0, total >= page else { throw Failure.invalidPageNumber }
        let rect = CGRect(x: pageRect.minX + Self.inset, y: pageRect.maxY - 30,
                          width: pageRect.width - Self.inset * 2, height: 12)
        try drawText("三术合参 · 命书 — 第 \(page) 页（共 \(total) 页）", role: .caption,
                     in: rect, context: context, alignment: .center)
    }

    // Conversion only: all RGB values are supplied by the existing V5Palette authority.
    private static func color(_ rgb: UInt32) -> UIColor {
        UIColor(red: CGFloat((rgb >> 16) & 0xff) / 255,
                green: CGFloat((rgb >> 8) & 0xff) / 255,
                blue: CGFloat(rgb & 0xff) / 255, alpha: 1)
    }
}
