// 命书 PDF 导出（2026-10-30）：人物档案一键出 PDF——基本信息/四柱细盘/五行/大运流年/
// 逐年直断（当前大运十年）/紫微摘要。UIGraphicsPDFRenderer 纯文本排版，宋体优先。
import SwiftUI
import UIKit
import CryptoKit
import CoreText

/// 命书三档（G1 报告体系）：档位只做章节取舍，不改任何结论文案与引擎口径。
/// 简洁＝总纲＋核心结论＋要点；专业＝现行全部 6 章（默认档位，等于改版前输出）；
/// 完整＝6 章＋逐项依据与附录级明细。
enum ReportTier: String, CaseIterable {
    case concise = "简洁"
    case professional = "专业"
    case complete = "完整"
    var displayName: String { rawValue }
    /// 文件名与元数据用 ASCII 码，避免文件名／PDF 关键字编码歧义
    var fileCode: String {
        switch self {
        case .concise: return "concise"
        case .professional: return "professional"
        case .complete: return "complete"
        }
    }
    /// 报告中心档位分组顺序：简洁 → 专业 → 完整 → 无档位（旧文件／海报）
    var sortOrder: Int {
        switch self {
        case .concise: return 0
        case .professional: return 1
        case .complete: return 2
        }
    }
}

enum ReportBuilder {
    /// 引擎口径版本（G1）：随口径变更才递增；进入 contentHash 口径与 PDF 元数据，
    /// 同一版本同一输入哈希相同。
    static let engineVersion = "2026.11-g1"

    /// 内容哈希口径（G1 版本锁定）：只对规范化内容算哈希——输入为 lines() 排版行数组
    /// 之前缀档位码与引擎口径版本；封面日期、PDF 自身 CreationDate / ModDate、
    /// 文件名时间戳一律不进入哈希输入，故同一输入两次生成哈希必相同。
    /// 实现用 CryptoKit SHA256（系统库，无第三方依赖）。
    static func contentHash(lines: [String], tier: ReportTier) -> String {
        let normalized = ([engineVersion, tier.fileCode] + lines).joined(separator: "\n")
        let digest = SHA256.hash(data: Data(normalized.utf8))
        var out = ""
        for b in digest {
            out += String(format: "%02x", b)
        }
        return out
    }

    /// Keep user names inside one bounded filesystem component (UTF-8 filenames have byte limits).
    static func exportName(_ name: String) -> String {
        let forbidden = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/\\:"))
        let clean = name.components(separatedBy: forbidden).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var result = ""
        for character in clean {
            guard result.utf8.count + String(character).utf8.count <= 80 else { break }
            result.append(character)
        }
        return result.isEmpty ? "未命名" : result
    }

    static func lines(for person: Person, tier: ReportTier = .professional) -> [String] {
        let ch = BaziEngine.cachedPaipan(clock: person.birthDate, gender: person.gender,
                                   longitude: person.useLongitude ? person.longitude : nil)
        var L: [String] = []
        L.append("命书 · \(person.name)")
        L.append("生辰：\(DisplayTimeReceipt.beijing(person.birthDate))（\(person.gender == "M" ? "男" : "女")，经度 \(person.useLongitude ? String(format: "%.1f", person.longitude) : "未校正")）")
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
        // G1 三档取舍：简洁档只留总纲（上文四柱细盘）＋核心结论（下文总纲摘要）＋要点（末尾口径行），
        // 大运／逐年明细、双术合参、紫微摘要只在专业／完整档出现；专业档走下面全部分支，输出与改版前逐行一致。
        if tier != .concise {
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
        }
        // 2026-10-31 批次二核对结论：此前命书只含四柱／大运／逐年／紫微摘要，未含解盘 30 条；
        // 此处补一页「维度摘要」：30 条逐条标题＋该维首行结论（首句按「。」切分），不改已验证的排盘字段引用。
        // G1：实际条目数为 InterpretEngine.interpret 全量（5 总纲＋25 维，十神看点为条件项，
        // 有则 30 条、无则 29 条，按实际报数不凑数）；简洁档只列 5 总纲首行。
        let dims = InterpretEngine.interpret(chart: ch)
        let shownDims = tier == .concise ? dims.filter { InterpretEngine.coreTitles.contains($0.title) } : dims
        L.append(tier == .concise ? "【解盘维度摘要（\(shownDims.count)维）】" : "【逐项解盘详解（\(shownDims.count)维）】")
        for (i, it) in shownDims.enumerated() {
            let first = it.conclusion.split(separator: "。", maxSplits: 1, omittingEmptySubsequences: true).first.map { String($0) + "。" } ?? it.conclusion
            L.append("\(i + 1). \(it.title)：\(tier == .concise ? first : it.conclusion)")
            if tier != .concise {
                if let mechanism = it.mechanism { L.append("作用机制：\(mechanism)") }
                if let advice = it.advice { L.append("现实建议：\(advice)") }
                if let timeRange = it.timeRange { L.append("时间范围：\(timeRange)") }
            }
        }
        L.append("")
        if tier != .concise {
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
        }
        if tier == .complete {
            // 完整档附录：逐项依据只收拢引擎已有内容（全文结论＋依据链＋G2 六段字段），不新编文案；
            // 附录行首用「附录 N · 标题」格式，不与摘要条目的「N. 标题」格式重合，故目录条目级
            // 检测只会命中摘要区，不会把附录重复计入目录。
            L.append("【白话阅读指南】")
            L.append(LearningContent.readingOrder)
            let readingText = dims.map { $0.conclusion + $0.links.map { $0.text }.joined() }.joined()
            for term in LearningContent.terms(in: readingText) {
                L.append("\(term.name)：\(term.meaning)")
            }
            L.append("")
            L.append("【逐项依据（附录）】")
            for (i, it) in dims.enumerated() {
                L.append("附录 \(i + 1) · \(it.title)")
                L.append(it.conclusion)
                for link in it.links {
                    L.append("  \(link.label)：\(link.text)")
                }
                if let mechanism = it.mechanism {
                    L.append("  作用机制：\(mechanism)")
                }
                if let timeRange = it.timeRange {
                    L.append("  时间范围：\(timeRange)")
                }
                if let advice = it.advice {
                    L.append("  现实建议：\(advice)")
                }
            }
            L.append("")
            L.append("【附录 · 版本与口径】")
            let coreCount = dims.filter { InterpretEngine.coreTitles.contains($0.title) }.count
            L.append("报告档位：完整")
            L.append("引擎口径版本：\(engineVersion)")
            L.append("详批条目：\(dims.count) 条（总纲 \(coreCount) 条＋分维 \(dims.count - coreCount) 条，十神看点为条件项）")
            L.append("")
        }
        L.append("口径：八字五典为据、结论带依据链；逐年为四查规则生成，重断须多项引动同现，健康只给倾向、非西医疾病诊断、六亲生死不在此列。紫微为三合派。娱乐与研习参考。")
        return L
    }

    /// 封面＋目录＋正文三段式命书 PDF（P3 第 7 项）。
    /// 页码铁律：分页只由 paginate() 算一次——目录读到的章节页码与绘制时逐页 beginPage 的顺序
    /// 共用同一份 pages 数组；内容第 k 页（k 从 0 起）恒为绝对页 k + 3（封面 1、目录 2），
    /// 绘制循环不再另算断页，故目录页码与实际分页不可能错位。
    /// G1：默认档位为专业（等于改版前输出）；文件名带档位＋时间戳＋内容哈希短码，
    /// PDF 元数据 Keywords 内写全量 contentHash（64 位 hex）＋档位码＋引擎口径版本。
    /// P0-4：Keywords 再加 personID=<uuid>（命书按人物 UUID 归属；文件名不动，G1 解析口径不变）。
    static func makePDF(for person: Person, tier: ReportTier = .professional) -> URL? {
        let lines = lines(for: person, tier: tier)
        let hash = contentHash(lines: lines, tier: tier)
        let hashShort = String(hash.prefix(12))
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)   // A4 @72dpi
        let keywordString = "contentHash=\(hash);tier=\(tier.fileCode);engine=\(engineVersion);personID=\(person.id.uuidString)"
        let titleFont = UIFont(name: "STSongti-SC-Bold", size: 20) ?? UIFont.boldSystemFont(ofSize: 20)
        let bodyFont = UIFont(name: "STSongti-SC-Regular", size: 11.5) ?? UIFont.systemFont(ofSize: 11.5)
        let headFont = UIFont(name: "STSongti-SC-Bold", size: 12.5) ?? UIFont.boldSystemFont(ofSize: 12.5)
        let (pages, chapters, tocItems) = paginate(lines: lines, titleFont: titleFont, bodyFont: bodyFont, headFont: headFont, pageRect: pageRect)
        let totalPages = pages.count + 2
        let stampFormatter = DateFormatter()
        stampFormatter.dateFormat = "yyyyMMdd-HHmmss"
        stampFormatter.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        let stamp = stampFormatter.string(from: Date())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("命书-\(exportName(person.name))-\(tier.displayName)-\(stamp)-\(hashShort).pdf")
        // P0-4 fix: write the PDF in a single pass via CGPDFContext so /Keywords
        // lands in the file. UIGraphicsPDFRenderer drops Keywords, and PDFKit
        // re-serialization breaks CJK text extraction (readability test).
        // The aux dict uses the official kCGPDFContext* constants.
        var mediaBox = pageRect
        let aux: [String: Any] = [
            kCGPDFContextTitle as String: "命书 · \(person.name)",
            kCGPDFContextAuthor as String: "三术合参",
            kCGPDFContextCreator as String: "三术合参 \(engineVersion)",
            kCGPDFContextSubject as String: "档位：\(tier.displayName)",
            kCGPDFContextKeywords as String: keywordString
        ]
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, aux as CFDictionary) else { return nil }
        context.beginPDFPage(nil)
        flipForUIKit(context: context, pageRect: pageRect)
        UIGraphicsPushContext(context)
        drawCover(ctx: context, lines: lines, pageRect: pageRect, tier: tier, hashShort: hashShort)
        drawFooter(ctx: context, pageRect: pageRect, page: 1, total: totalPages)
        UIGraphicsPopContext()
        context.endPDFPage()
        context.beginPDFPage(nil)
        flipForUIKit(context: context, pageRect: pageRect)
        UIGraphicsPushContext(context)
        drawTOC(ctx: context, person: person, chapters: chapters, tocItems: tocItems, total: totalPages, pageRect: pageRect, headFont: headFont, bodyFont: bodyFont)
        drawFooter(ctx: context, pageRect: pageRect, page: 2, total: totalPages)
        UIGraphicsPopContext()
        context.endPDFPage()
        for (idx, page) in pages.enumerated() {
            context.beginPDFPage(nil)
            flipForUIKit(context: context, pageRect: pageRect)
            UIGraphicsPushContext(context)
            for placed in page.lines {
                let style = NSMutableParagraphStyle()
                style.lineSpacing = 3
                let attr: [NSAttributedString.Key: Any] = [.font: placed.font, .paragraphStyle: style]
                (placed.text as NSString).draw(with: CGRect(x: 48, y: placed.y, width: pageRect.width - 96, height: placed.height),
                                                options: [.usesLineFragmentOrigin], attributes: attr, context: nil)
            }
            drawFooter(ctx: context, pageRect: pageRect, page: idx + 3, total: totalPages)
            UIGraphicsPopContext()
            context.endPDFPage()
        }
        context.closePDF()
        do {
            let data = try Data(contentsOf: url)
            _ = try ReportExportArchive.save(data, fileName: url.lastPathComponent)
            return url
        } catch { return nil }
    }

    /// Flip a raw CGPDFContext to UIKit coordinates (origin top-left) so the
    /// existing NSString.draw calls land at the intended positions, upright.
    private static func flipForUIKit(context: CGContext, pageRect: CGRect) {
        context.translateBy(x: 0, y: pageRect.height)
        context.scaleBy(x: 1, y: -1)
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
    /// 返回 pages（逐页已排版行）、chapters（章节标题 → 绝对页码，含封面 1、目录 2 的偏移）
    /// 与 tocItems（解盘维度摘要区内的条目级目录：序号＋标题 → 绝对页码，与 chapters 同源、
    /// 同一偏移，故页码同样构造性保证；完整档附录行首为「附录 N · 标题」，不在此列）。
    private static func paginate(lines: [String], titleFont: UIFont, bodyFont: UIFont, headFont: UIFont, pageRect: CGRect) -> (pages: [ContentPage], chapters: [(title: String, page: Int)], tocItems: [(title: String, page: Int)]) {
        let inset: CGFloat = 48
        let width = pageRect.width - inset * 2
        let bottom = pageRect.height - 48
        var pages: [ContentPage] = [ContentPage()]
        var chapters: [(title: String, page: Int)] = []
        var tocItems: [(title: String, page: Int)] = []
        var inSummary = false
        var followsHeading = false
        var y: CGFloat = 48
        for (i, line) in lines.enumerated() {
            let isInterpretationSection = line.hasPrefix("【解盘维度摘要") || line.hasPrefix("【逐项解盘详解")
            if isInterpretationSection {
                pages.append(ContentPage())
                y = 48
            }
            if line.hasPrefix("【") {
                inSummary = isInterpretationSection
            }
            let font = i == 0 ? titleFont : (line.hasPrefix("【") ? headFont : bodyFont)
            let gap: CGFloat = i == 0 ? 10 : (line.hasPrefix("【") ? 6 : 5)
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 3
            let attr: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: style]
            // Keep a chapter with its first paragraph; long paragraphs can begin in the
            // remaining space and continue on the next page without orphaning the title.
            if line.hasPrefix("【"), let nextIndex = lines.indices.dropFirst(i + 1).first(where: {
                !lines[$0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }) {
                let headingHeight = ceil((line as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin], attributes: attr, context: nil).height)
                let nextFont = lines[nextIndex].hasPrefix("【") ? headFont : bodyFont
                let nextAttr: [NSAttributedString.Key: Any] = [.font: nextFont, .paragraphStyle: style]
                let nextHeight = ceil((lines[nextIndex] as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin], attributes: nextAttr, context: nil).height)
                let blankSpacing = CGFloat(nextIndex - i - 1) * 5
                let firstParagraphSpace = max(0, bottom - inset - headingHeight - gap - blankSpacing)
                let keepHeight = headingHeight + gap + blankSpacing + min(nextHeight, firstParagraphSpace)
                if y + keepHeight > bottom && !pages[pages.count - 1].lines.isEmpty {
                    pages.append(ContentPage())
                    y = inset
                }
            }
            let fragments = layoutFragments(line, attributes: attr, width: width, capacity: bottom - inset,
                                            initialCapacity: followsHeading ? bottom - y : nil)
            var firstPage: Int?
            for fragment in fragments {
                let h = ceil((fragment as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin], attributes: attr, context: nil).height)
                if y + h > bottom && !pages[pages.count - 1].lines.isEmpty {
                    pages.append(ContentPage())
                    y = inset
                }
                if firstPage == nil { firstPage = pages.count + 2 }
                pages[pages.count - 1].lines.append(PlacedLine(text: fragment, font: font, y: y, height: h))
                y += h + gap
            }
            if line.hasPrefix("【") {
                chapters.append((title: line, page: firstPage ?? pages.count + 2))
            }
            if inSummary, let itemTitle = summaryItemTitle(line) {
                tocItems.append((title: itemTitle, page: firstPage ?? pages.count + 2))
            }
            if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                followsHeading = line.hasPrefix("【")
            }
        }
        return (pages, chapters, tocItems)
    }

    // Split oversized paragraphs, including the first paragraph after a chapter heading.
    // Content and hash inputs remain untouched.
    private static func layoutFragments(_ text: String, attributes: [NSAttributedString.Key: Any], width: CGFloat, capacity: CGFloat, initialCapacity: CGFloat? = nil) -> [String] {
        let fullHeight = (text as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin], attributes: attributes, context: nil).height
        let firstCapacity = max(1, min(capacity, initialCapacity ?? capacity))
        guard fullHeight > firstCapacity else { return [text] }
        var remaining = text as NSString
        var result: [String] = []
        while remaining.length > 0 {
            let attributed = NSAttributedString(string: remaining as String, attributes: attributes)
            let setter = CTFramesetterCreateWithAttributedString(attributed as CFAttributedString)
            let fragmentCapacity = result.isEmpty ? firstCapacity : capacity
            let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: max(1, fragmentCapacity - 8)), transform: nil)
            let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil)
            let count = CTFrameGetVisibleStringRange(frame).length
            // A composed-character fallback guarantees progress without splitting surrogate pairs.
            let length = count > 0 ? count : remaining.rangeOfComposedCharacterSequence(at: 0).length
            result.append(remaining.substring(to: length))
            remaining = remaining.substring(from: length) as NSString
        }
        return result
    }

    /// 摘要区条目行「N. 标题：首句…」→ 目录条目「N. 标题」；非此格式返回 nil。
    /// 标题取到中文冒号之前；序号必须为纯数字，避免误命中逐年行等其他数字开头行。
    private static func summaryItemTitle(_ line: String) -> String? {
        guard let dot = line.firstIndex(of: ".") else { return nil }
        let num = line[line.startIndex..<dot]
        guard !num.isEmpty, num.allSatisfy({ $0.isNumber }) else { return nil }
        let rest = line[line.index(after: dot)...].trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty else { return nil }
        if let colon = rest.firstIndex(of: "：") {
            let title = String(rest[rest.startIndex..<colon])
            if title.isEmpty { return nil }
            return "\(num). \(title)"
        }
        return "\(num). \(rest)"
    }

    /// 居中画一行并返回下一行 y（行高按实际 bounding 高度取，不写死）
    private static func drawCentered(ctx: CGContext, text: String, font: UIFont, y: CGFloat, width: CGFloat, color: UIColor) -> CGFloat {
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
    private static func drawLeft(ctx: CGContext, text: String, font: UIFont, y: CGFloat, x: CGFloat, width: CGFloat, color: UIColor) -> CGFloat {
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
    /// G1：封面底部加档位与内容哈希短码（与 PDF 元数据 Keywords 内全量哈希同源），版本可目视核对。
    private static func drawCover(ctx: CGContext, lines: [String], pageRect: CGRect, tier: ReportTier, hashShort: String) {
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
        ctx.setFillColor(cinnabar.cgColor)
        ctx.fill(sealRect)
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
        _ = drawCentered(ctx: ctx, text: "档位：\(tier.displayName) · 内容哈希 \(hashShort) · 口径 \(engineVersion)", font: smallFont, y: sealRect.maxY + 78, width: pageRect.width, color: sub)
    }

    /// 目录（第 2 页）：章节标题＋绝对页码，页码取自 paginate() 的同一份 chapters；
    /// 另注总页数，页码与正文逐页绘制顺序一致。
    /// G1：章节之下加条目级目录（tocItems，与 chapters 同源、同偏移，页码同样构造性保证），
    /// 30 条分两栏紧凑排布，仍在一页内；简洁档只列总纲条目（实际数），完整档不重复列附录。
    private static func drawTOC(ctx: CGContext, person: Person, chapters: [(title: String, page: Int)], tocItems: [(title: String, page: Int)], total: Int, pageRect: CGRect, headFont: UIFont, bodyFont: UIFont) {
        let inset: CGFloat = 48
        let width = pageRect.width - inset * 2
        let ink = UIColor(red: 0.18, green: 0.165, blue: 0.15, alpha: 1)
        let sub = UIColor(red: 0.478, green: 0.447, blue: 0.408, alpha: 1)
        let accent = UIColor(red: 0.153, green: 0.306, blue: 0.361, alpha: 1)
        let itemFont = UIFont(name: "STSongti-SC-Regular", size: 10) ?? UIFont.systemFont(ofSize: 10)
        var y: CGFloat = 48
        y = drawLeft(ctx: ctx, text: "目录", font: headFont, y: y, x: inset, width: width, color: ink)
        y += 6
        y = drawLeft(ctx: ctx, text: "命书 · \(person.name)　共 \(total) 页", font: bodyFont, y: y, x: inset, width: width, color: sub)
        y += 18
        for ch in chapters {
            y = drawTOCRow(ctx: ctx, title: ch.title, page: ch.page, y: y, x: inset, width: width, bodyFont: bodyFont, ink: ink, sub: sub)
            y += 8
        }
        if !tocItems.isEmpty {
            y += 6
            y = drawLeft(ctx: ctx, text: "详批条目（\(tocItems.count) 条）", font: headFont, y: y, x: inset, width: width, color: ink)
            y += 4
            let colWidth = (width - 16) / 2
            let rows = (tocItems.count + 1) / 2
            let rowHeight: CGFloat = 16
            for r in 0..<rows {
                let left = tocItems[r]
                drawTOCItemCell(ctx: ctx, title: left.title, page: left.page, y: y, x: inset, width: colWidth, font: itemFont, ink: ink)
                let rightIndex = r + rows
                if rightIndex < tocItems.count {
                    let right = tocItems[rightIndex]
                    drawTOCItemCell(ctx: ctx, title: right.title, page: right.page, y: y, x: inset + colWidth + 16, width: colWidth, font: itemFont, ink: ink)
                }
                y += rowHeight
            }
        }
        y += 10
        _ = drawLeft(ctx: ctx, text: "页码与正文实际分页一致；正文每页页脚亦标页码，可逐页核对。", font: bodyFont, y: y, x: inset, width: width, color: accent)
    }

    /// 目录条目级小格（两栏用）：标题左对齐、页码右对齐，无发丝线；单行高度固定 16pt
    private static func drawTOCItemCell(ctx: CGContext, title: String, page: Int, y: CGFloat, x: CGFloat, width: CGFloat, font: UIFont, ink: UIColor) {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        let titleAttr: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink, .paragraphStyle: style]
        let h = (title as NSString).boundingRect(with: CGSize(width: width - 40, height: .greatestFiniteMagnitude),
                                                  options: [.usesLineFragmentOrigin], attributes: titleAttr, context: nil).height
        (title as NSString).draw(with: CGRect(x: x, y: y, width: width - 40, height: h),
                                  options: [.usesLineFragmentOrigin], attributes: titleAttr, context: nil)
        let pageText = "\(page)"
        let pageStyle = NSMutableParagraphStyle()
        pageStyle.alignment = NSTextAlignment.right
        let pageAttr: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink, .paragraphStyle: pageStyle]
        (pageText as NSString).draw(with: CGRect(x: x + width - 32, y: y, width: 32, height: h),
                                     options: [.usesLineFragmentOrigin], attributes: pageAttr, context: nil)
    }

    /// 目录一行：标题左对齐、页码右对齐、行下发丝线；返回下一行 y
    private static func drawTOCRow(ctx: CGContext, title: String, page: Int, y: CGFloat, x: CGFloat, width: CGFloat, bodyFont: UIFont, ink: UIColor, sub: UIColor) -> CGFloat {
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
        ctx.setStrokeColor(sub.withAlphaComponent(0.4).cgColor)
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: x, y: y + h + 4))
        ctx.addLine(to: CGPoint(x: x + width, y: y + h + 4))
        ctx.strokePath()
        return y + h + 6
    }

    /// 页脚（每页）：「三术合参 · 命书 — 第 N 页（共 M 页）」居中，画在正文区（y ≤ 794）之外，不参与分页。
    private static func drawFooter(ctx: CGContext, pageRect: CGRect, page: Int, total: Int) {
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
