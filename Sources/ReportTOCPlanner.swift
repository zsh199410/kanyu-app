import UIKit

/// A4 table-of-contents placement only. Does not reflow report content or alter hash input.
/// Each row has measured height; when a row will enter the footer area, create a
/// continuation TOC page. Render and TOC planning use the same UIFont and widths.
enum ReportTOCPlanner {
    struct Entry {
        let title: String
        let page: Int  // historical absolute page (one TOC); caller shifts later
    }
    enum Kind {
        case title
        case continued
        case summary
        case chapter(Entry)
        case indexHeader(Int)
        case itemPair(Entry, Entry?)
        case note
    }
    struct PlacedRow {
        let kind: Kind
        let y: CGFloat
    }
    struct Page {
        var rows: [PlacedRow] = []
    }

    private static func textHeight(_ text: String, font: UIFont, width: CGFloat) -> CGFloat {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: style]
        return ceil((text as NSString).boundingRect(
            with: CGSize(width: max(1, width), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin], attributes: attrs, context: nil
        ).height)
    }

    static func pages(personName: String, chapters: [(title: String, page: Int)],
                      items: [(title: String, page: Int)], pageRect: CGRect,
                      headFont: UIFont, bodyFont: UIFont) -> [Page] {
        let width = pageRect.width - 96
        let colWidth = (width - 16) / 2
        let itemFont = UIFont(name: "STSongti-SC-Regular", size: 10) ?? UIFont.systemFont(ofSize: 10)
        let bottom = pageRect.height - 68 // Reserve 20pt above body/footer boundary.
        var result: [Page] = [Page()]
        var y: CGFloat = 48

        func add(_ kind: Kind, rowHeight: CGFloat, gap: CGFloat) {
            let h = max(1, rowHeight)
            if y + h + gap > bottom && !result[result.count - 1].rows.isEmpty {
                result.append(Page())
                y = 48
                result[result.count - 1].rows.append(
                    PlacedRow(kind: .continued, y: y))
                y += textHeight("目录（续）", font: headFont, width: width) + 16
            }
            result[result.count - 1].rows.append(PlacedRow(kind: kind, y: y))
            y += h + gap
        }
        add(.title, rowHeight: textHeight("目录", font: headFont, width: width), gap: 6)
        // Page-count digits affect only the summary line. Keep a width estimate
        // with more digits than practical report lengths; printed text is measured
        // with the same font and has the full page width.
        let subtitle = "命书 · \(personName)　共 9999 页"
        add(.summary, rowHeight: textHeight(subtitle, font: bodyFont, width: width), gap: 18)
        for ch in chapters {
            let h = textHeight(ch.title, font: bodyFont, width: width - 60)
            add(.chapter(Entry(title: ch.title, page: ch.page)), rowHeight: h + 6, gap: 8)
        }
        if !items.isEmpty {
            y += 6
            add(.indexHeader(items.count),
                rowHeight: textHeight("详批条目（\(items.count) 条）", font: headFont, width: width), gap: 4)
            // Preserve the existing two-column reading order on a single-page TOC.
            let split = (items.count + 1) / 2
            for i in 0..<split {
                let left = Entry(title: items[i].title, page: items[i].page)
                let right: Entry? = i + split < items.count
                    ? Entry(title: items[i + split].title, page: items[i + split].page) : nil
                let lHeight = textHeight(left.title, font: itemFont, width: colWidth - 40)
                let rHeight = right.map { textHeight($0.title, font: itemFont, width: colWidth - 40) } ?? 0
                add(.itemPair(left, right), rowHeight: max(16, lHeight, rHeight), gap: 2)
            }
        }
        add(.note, rowHeight: textHeight("页码与正文实际分页一致；正文每页页脚亦标页码，可逐页核对。",
                                       font: bodyFont, width: width), gap: 10)
        return result
    }
}
