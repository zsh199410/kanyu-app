// 命书 PDF 导出（2026-10-30）：人物档案一键出 PDF——基本信息/四柱细盘/五行/大运流年/
// 逐年直断（当前大运十年）/紫微摘要。UIGraphicsPDFRenderer 纯文本排版，宋体优先。
import SwiftUI
import UIKit

enum ReportBuilder {
    static func lines(for person: Person) -> [String] {
        let ch = BaziEngine.cachedPaipan(clock: person.birthDate, gender: person.gender,
                                   longitude: person.useLongitude ? person.longitude : nil)
        var L: [String] = []
        L.append("命书 · \(person.name)")
        L.append("生辰：\(person.birthDate.formatted(date: .long, time: .shortened))（\(person.gender == "M" ? "男" : "女")，经度 \(person.useLongitude ? String(format: "%.1f", person.longitude) : "未校正")）")
        L.append("四柱：\(ch.pillars.joined(separator: " ")) · 起运方向：\(ch.qiyunDirection) · 日柱旬空：\(ch.xunKong)")
        L.append("胎元 \(ch.taiYuan) · 胎息 \(ch.taiXi) · 命宫 \(ch.mingGong) · 身宫 \(ch.shenGong)")
        L.append("")
        L.append("【四柱细盘】")
        let heads = ["年柱", "月柱", "日柱", "时柱"]
        for i in 0..<4 {
            L.append("\(heads[i]) \(ch.pillars[i])：干十神 \(ch.stemShiShen[i])，藏干 \(ch.hideGan[i].joined(separator: " "))（\(ch.hideShiShen[i].joined(separator: " "))），星运 \(ch.diShi[i])，纳音 \(ch.naYin[i])")
        }
        let wxNames = ["木", "火", "土", "金", "水"]
        L.append("五行占比：" + (0..<5).map { "\(wxNames[$0]) \(String(format: "%.0f%%", ch.wuxingPercents[$0]))" }.joined(separator: " · "))
        L.append("")
        L.append("【大运】\(ch.qiyunYear) 年起运（起运日 \(ch.qiyunDate)）")
        for i in ch.dayunGanZhi.indices {
            let y0 = ch.dayunStartYear(i)
            L.append("\(y0)–\(y0 + 9) \(ch.dayunGanZhi[i])运")
        }
        L.append("")
        L.append("【逐年直断（当前大运十年）】")
        let now = Calendar.current.component(.year, from: Date())
        let di = YearEngine.dayunIndex(chart: ch, year: now) ?? 0
        let start = ch.dayunStartYear(di)
        for y in start...(start + 9) {
            let r = YearEngine.report(chart: ch, year: y)
            L.append("\(y) \(r.gz)［\(r.level)］")
            for line in r.lines { L.append("  · \(line)") }
        }
        L.append("")
        // 2026-10-31 批次二核对结论：此前命书只含四柱／大运／逐年／紫微摘要，未含解盘 30 条；
        // 此处补一页「维度摘要」：30 条逐条标题＋该维首行结论（首句按「。」切分），不改已验证的排盘字段引用。
        let dims = InterpretEngine.interpret(chart: ch)
        L.append("【解盘维度摘要（\(dims.count)维）】")
        for (i, it) in dims.enumerated() {
            let first = it.conclusion.split(separator: "。", maxSplits: 1, omittingEmptySubsequences: true).first.map { String($0) + "。" } ?? it.conclusion
            L.append("\(i + 1). \(it.title)：\(first)")
        }
        L.append("")
        L.append("【双术合参 · 交叉印证】")
        let zw = ZiweiEngine.chart(clock: person.birthDate, gender: person.gender,
                                   longitude: person.useLongitude ? person.longitude : nil)
        for v in BaziZiweiCrossEngine.verdicts(bazi: ch, ziwei: zw) {
            L.append("\(v.title)［\(v.kind.rawValue)］：\(v.verdict)")
            L.append("  八字：\(v.bazi)；紫微：\(v.ziwei)")
        }
        L.append("")
        L.append("【紫微摘要】")
        let ming = zw.palaces[zw.mingGong]
        L.append("\(zw.juName)，命宫在\(ming.stem)\(ZiweiCore.DZ[ming.branch])，主星：\(ming.majors.map { $0.star + ($0.mutagen.map { "(化\($0))" } ?? "") }.joined(separator: "、"))；身宫在\(zw.palaces[zw.shenGong].name)")
        for c in ZiweiReading.cards(chart: zw) { L.append("\(c.title)：\(c.conclusion)") }
        L.append("")
        L.append("口径：八字五典为据、结论带依据链；逐年为四查规则生成，重断须多项引动同现，健康只给倾向、非西医疾病诊断、六亲生死不在此列。紫微为三合派。娱乐与研习参考。")
        return L
    }

    /// 封面＋目录＋正文三段式命书 PDF（P3 第 7 项）。
    /// 页码铁律：分页只由 paginate() 算一次——目录读到的章节页码与绘制时逐页 beginPage 的顺序
    /// 共用同一份 pages 数组；内容第 k 页（k 从 0 起）恒为绝对页 k + 3（封面 1、目录 2），
    /// 绘制循环不再另算断页，故目录页码与实际分页不可能错位。
    static func makePDF(for person: Person) -> URL? {
        let lines = lines(for: person)
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)   // A4 @72dpi
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let titleFont = UIFont(name: "STSongti-SC-Bold", size: 20) ?? UIFont.boldSystemFont(ofSize: 20)
        let bodyFont = UIFont(name: "STSongti-SC-Regular", size: 11.5) ?? UIFont.systemFont(ofSize: 11.5)
        let headFont = UIFont(name: "STSongti-SC-Bold", size: 12.5) ?? UIFont.boldSystemFont(ofSize: 12.5)
        let (pages, chapters) = paginate(lines: lines, titleFont: titleFont, bodyFont: bodyFont, headFont: headFont, pageRect: pageRect)
        let totalPages = pages.count + 2
        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            drawCover(ctx: ctx, lines: lines, pageRect: pageRect)
            drawFooter(ctx: ctx, pageRect: pageRect, page: 1, total: totalPages)
            ctx.beginPage()
            drawTOC(ctx: ctx, person: person, chapters: chapters, total: totalPages, pageRect: pageRect, headFont: headFont, bodyFont: bodyFont)
            drawFooter(ctx: ctx, pageRect: pageRect, page: 2, total: totalPages)
            for (idx, page) in pages.enumerated() {
                ctx.beginPage()
                for placed in page.lines {
                    let style = NSMutableParagraphStyle()
                    style.lineSpacing = 3
                    let attr: [NSAttributedString.Key: Any] = [.font: placed.font, .paragraphStyle: style]
                    (placed.text as NSString).draw(with: CGRect(x: 48, y: placed.y, width: pageRect.width - 96, height: placed.height),
                                                    options: [.usesLineFragmentOrigin], attributes: attr, context: nil)
                }
                drawFooter(ctx: ctx, pageRect: pageRect, page: idx + 3, total: totalPages)
            }
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("命书-\(person.name).pdf")
        do { try data.write(to: url); return url } catch { return nil }
    }

    /// 一行已排版的正文行（绘制时直接取 y 与 height，不再重算断页）
    private struct PlacedLine {
        let text: String
        let font: UIFont
        let y: CGFloat
        let height: CGFloat
    }

    /// 一页正文（按 paginate() 的断页结果原样绘制）
    private struct ContentPage {
        var lines: [PlacedLine] = []
    }

    /// 单一分页函数（P3 第 7 项）：逐行复刻旧 draw() 的断页逻辑——同一字体／同一行距／
    /// 同一强制断页（【解盘维度摘要】前另起页）／同一溢出判断（y + h > 页高 − 48 即另起页）。
    /// 返回 pages（逐页已排版行）与 chapters（章节标题 → 绝对页码，含封面 1、目录 2 的偏移）。
    private static func paginate(lines: [String], titleFont: UIFont, bodyFont: UIFont, headFont: UIFont, pageRect: CGRect) -> (pages: [ContentPage], chapters: [(title: String, page: Int)]) {
        let inset: CGFloat = 48
        let width = pageRect.width - inset * 2
        let bottom = pageRect.height - 48
        var pages: [ContentPage] = [ContentPage()]
        var chapters: [(title: String, page: Int)] = []
        var y: CGFloat = 48
        for (i, line) in lines.enumerated() {
            if line.hasPrefix("【解盘维度摘要") {
                pages.append(ContentPage())
                y = 48
            }
            let font = i == 0 ? titleFont : (line.hasPrefix("【") ? headFont : bodyFont)
            let gap: CGFloat = i == 0 ? 10 : (line.hasPrefix("【") ? 6 : 5)
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 3
            let attr: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: style]
            let h = (line as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                                     options: [.usesLineFragmentOrigin], attributes: attr, context: nil).height
            if y + h > bottom {
                pages.append(ContentPage())
                y = 48
            }
            pages[pages.count - 1].lines.append(PlacedLine(text: line, font: font, y: y, height: h))
            if line.hasPrefix("【") {
                chapters.append((title: line, page: pages.count - 1 + 3))
            }
            y += h + gap
        }
        return (pages, chapters)
    }

    /// 居中画一行并返回下一行 y（行高按实际 bounding 高度取，不写死）
    private static func drawCentered(ctx: UIGraphicsPDFRendererContext, text: String, font: UIFont, y: CGFloat, width: CGFloat, color: UIColor) -> CGFloat {
        let style = NSMutableParagraphStyle()
        style.alignment = NSTextAlignment.center
        style.lineSpacing = 3
        let attr: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
        let h = (text as NSString).boundingRect(with: CGSize(width: width - 96, height: .greatestFiniteMagnitude),
                                                 options: [.usesLineFragmentOrigin], attributes: attr, context: nil).height
        (text as NSString).draw(with: CGRect(x: 48, y: y, width: width - 96, height: h),
                                 options: [.usesLineFragmentOrigin], attributes: attr, context: nil)
        return y + h
    }

    /// 左对齐画一行并返回下一行 y
    private static func drawLeft(ctx: UIGraphicsPDFRendererContext, text: String, font: UIFont, y: CGFloat, x: CGFloat, width: CGFloat, color: UIColor) -> CGFloat {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        let attr: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
        let h = (text as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                                 options: [.usesLineFragmentOrigin], attributes: attr, context: nil).height
        (text as NSString).draw(with: CGRect(x: x, y: y, width: width, height: h),
                                 options: [.usesLineFragmentOrigin], attributes: attr, context: nil)
        return y + h
    }

    /// 封面（第 1 页）：品牌＋命书名＋生辰／四柱收据＋朱砂印＋日期；只取 lines() 前三行原文，不另编断语。
    private static func drawCover(ctx: UIGraphicsPDFRendererContext, lines: [String], pageRect: CGRect) {
        let brandFont = UIFont(name: "STSongti-SC-Bold", size: 28) ?? UIFont.boldSystemFont(ofSize: 28)
        let nameFont = UIFont(name: "STSongti-SC-Bold", size: 20) ?? UIFont.boldSystemFont(ofSize: 20)
        let bodyFont = UIFont(name: "STSongti-SC-Regular", size: 11.5) ?? UIFont.systemFont(ofSize: 11.5)
        let smallFont = UIFont(name: "STSongti-SC-Regular", size: 10) ?? UIFont.systemFont(ofSize: 10)
        let ink = UIColor(red: 0.18, green: 0.165, blue: 0.15, alpha: 1)
        let accent = UIColor(red: 0.153, green: 0.306, blue: 0.361, alpha: 1)
        let sub = UIColor(red: 0.478, green: 0.447, blue: 0.408, alpha: 1)
        let cinnabar = UIColor(red: 0.604, green: 0.165, blue: 0.133, alpha: 1)
        var y: CGFloat = 150
        y = drawCentered(ctx: ctx, text: "三 术 合 参", font: brandFont, y: y, width: pageRect.width, color: accent)
        y += 26
        y = drawCentered(ctx: ctx, text: lines.first ?? "命书", font: nameFont, y: y, width: pageRect.width, color: ink)
        y += 22
        if lines.count > 1 {
            y = drawCentered(ctx: ctx, text: lines[1], font: bodyFont, y: y, width: pageRect.width, color: sub)
            y += 8
        }
        if lines.count > 2 {
            y = drawCentered(ctx: ctx, text: lines[2], font: bodyFont, y: y, width: pageRect.width, color: sub)
            y += 8
        }
        // 朱砂印（64×64，红底白字「三术合参」两行，与海报印章同款）
        let sealSize: CGFloat = 64
        let sealRect = CGRect(x: (pageRect.width - sealSize) / 2, y: y + 18, width: sealSize, height: sealSize)
        ctx.cgContext.setFillColor(cinnabar.cgColor)
        ctx.cgContext.fill(sealRect)
        let sealFont = UIFont(name: "STSongti-SC-Bold", size: 16) ?? UIFont.boldSystemFont(ofSize: 16)
        let sealStyle = NSMutableParagraphStyle()
        sealStyle.alignment = NSTextAlignment.center
        let sealAttr: [NSAttributedString.Key: Any] = [.font: sealFont, .foregroundColor: UIColor.white, .paragraphStyle: sealStyle]
        ("三术" as NSString).draw(with: CGRect(x: sealRect.minX, y: sealRect.minY + 12, width: sealSize, height: 20), options: [], attributes: sealAttr, context: nil)
        ("合参" as NSString).draw(with: CGRect(x: sealRect.minX, y: sealRect.minY + 32, width: sealSize, height: 20), options: [], attributes: sealAttr, context: nil)
        let df = DateFormatter()
        df.dateFormat = "yyyy年M月d日"
        df.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        let dateText = "报告日期：" + df.string(from: Date())
        _ = drawCentered(ctx: ctx, text: dateText, font: bodyFont, y: sealRect.maxY + 26, width: pageRect.width, color: ink)
        _ = drawCentered(ctx: ctx, text: "据子平五典与天纪三合推演 · 仅供娱乐与研习参考", font: smallFont, y: sealRect.maxY + 52, width: pageRect.width, color: sub)
    }

    /// 目录（第 2 页）：章节标题＋绝对页码，页码取自 paginate() 的同一份 chapters；
    /// 另注总页数，页码与正文逐页绘制顺序一致。
    private static func drawTOC(ctx: UIGraphicsPDFRendererContext, person: Person, chapters: [(title: String, page: Int)], total: Int, pageRect: CGRect, headFont: UIFont, bodyFont: UIFont) {
        let inset: CGFloat = 48
        let width = pageRect.width - inset * 2
        let ink = UIColor(red: 0.18, green: 0.165, blue: 0.15, alpha: 1)
        let sub = UIColor(red: 0.478, green: 0.447, blue: 0.408, alpha: 1)
        let accent = UIColor(red: 0.153, green: 0.306, blue: 0.361, alpha: 1)
        var y: CGFloat = 48
        y = drawLeft(ctx: ctx, text: "目录", font: headFont, y: y, x: inset, width: width, color: ink)
        y += 6
        y = drawLeft(ctx: ctx, text: "命书 · \(person.name)　共 \(total) 页", font: bodyFont, y: y, x: inset, width: width, color: sub)
        y += 18
        for ch in chapters {
            y = drawTOCRow(ctx: ctx, title: ch.title, page: ch.page, y: y, x: inset, width: width, bodyFont: bodyFont, ink: ink, sub: sub)
            y += 8
        }
        y += 10
        _ = drawLeft(ctx: ctx, text: "页码与正文实际分页一致；正文每页页脚亦标页码，可逐页核对。", font: bodyFont, y: y, x: inset, width: width, color: accent)
    }

    /// 目录一行：标题左对齐、页码右对齐、行下发丝线；返回下一行 y
    private static func drawTOCRow(ctx: UIGraphicsPDFRendererContext, title: String, page: Int, y: CGFloat, x: CGFloat, width: CGFloat, bodyFont: UIFont, ink: UIColor, sub: UIColor) -> CGFloat {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        let titleAttr: [NSAttributedString.Key: Any] = [.font: bodyFont, .foregroundColor: ink, .paragraphStyle: style]
        let h = (title as NSString).boundingRect(with: CGSize(width: width - 60, height: .greatestFiniteMagnitude),
                                                  options: [.usesLineFragmentOrigin], attributes: titleAttr, context: nil).height
        (title as NSString).draw(with: CGRect(x: x, y: y, width: width - 60, height: h),
                                  options: [.usesLineFragmentOrigin], attributes: titleAttr, context: nil)
        let pageText = "\(page)"
        let pageStyle = NSMutableParagraphStyle()
        pageStyle.alignment = NSTextAlignment.right
        let pageAttr: [NSAttributedString.Key: Any] = [.font: bodyFont, .foregroundColor: ink, .paragraphStyle: pageStyle]
        (pageText as NSString).draw(with: CGRect(x: x + width - 50, y: y, width: 50, height: h),
                                     options: [.usesLineFragmentOrigin], attributes: pageAttr, context: nil)
        ctx.cgContext.setStrokeColor(sub.withAlphaComponent(0.4).cgColor)
        ctx.cgContext.setLineWidth(0.5)
        ctx.cgContext.move(to: CGPoint(x: x, y: y + h + 4))
        ctx.cgContext.addLine(to: CGPoint(x: x + width, y: y + h + 4))
        ctx.cgContext.strokePath()
        return y + h + 6
    }

    /// 页脚（每页）：「三术合参 · 命书 — 第 N 页（共 M 页）」居中，画在正文区（y ≤ 794）之外，不参与分页。
    private static func drawFooter(ctx: UIGraphicsPDFRendererContext, pageRect: CGRect, page: Int, total: Int) {
        let font = UIFont(name: "STSongti-SC-Regular", size: 9) ?? UIFont.systemFont(ofSize: 9)
        let color = UIColor(red: 0.478, green: 0.447, blue: 0.408, alpha: 1)
        let style = NSMutableParagraphStyle()
        style.alignment = NSTextAlignment.center
        let attr: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
        let text = "三术合参 · 命书 — 第 \(page) 页（共 \(total) 页）"
        (text as NSString).draw(with: CGRect(x: 48, y: 812, width: pageRect.width - 96, height: 12),
                                 options: [.usesLineFragmentOrigin], attributes: attr, context: nil)
    }
}
