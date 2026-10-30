// 命书 PDF 导出（2026-10-30）：人物档案一键出 PDF——基本信息/四柱细盘/五行/大运流年/
// 逐年直断（当前大运十年）/紫微摘要。UIGraphicsPDFRenderer 纯文本排版，宋体优先。
import SwiftUI
import UIKit

enum ReportBuilder {
    static func lines(for person: Person) -> [String] {
        let ch = BaziEngine.paipan(clock: person.birthDate, gender: person.gender,
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
        // 2026-10-31 批次二核对结论：此前命书只含四柱／大运／逐年／紫微摘要，未含解盘 25 维；
        // 此处补一页「维度摘要」：25 维逐条标题＋该维首行结论（首句按「。」切分），不改已验证的排盘字段引用。
        let dims = InterpretEngine.interpret(chart: ch)
        L.append("【解盘维度摘要（\(dims.count)维）】")
        for (i, it) in dims.enumerated() {
            let first = it.conclusion.split(separator: "。", maxSplits: 1, omittingEmptySubsequences: true).first.map { String($0) + "。" } ?? it.conclusion
            L.append("\(i + 1). \(it.title)：\(first)")
        }
        L.append("")
        L.append("【紫微摘要】")
        let zw = ZiweiEngine.chart(clock: person.birthDate, gender: person.gender,
                                   longitude: person.useLongitude ? person.longitude : nil)
        let ming = zw.palaces[zw.mingGong]
        L.append("\(zw.juName)，命宫在\(ming.stem)\(ZiweiCore.DZ[ming.branch])，主星：\(ming.majors.map { $0.star + ($0.mutagen.map { "(化\($0))" } ?? "") }.joined(separator: "、"))；身宫在\(zw.palaces[zw.shenGong].name)")
        for c in ZiweiReading.cards(chart: zw) { L.append("\(c.title)：\(c.conclusion)") }
        L.append("")
        L.append("口径：八字五典为据、结论带依据链；逐年为四查规则生成，重断须多项引动同现，健康只给倾向、六亲生死不在此列。紫微为三合派。娱乐与研习参考。")
        return L
    }

    static func makePDF(for person: Person) -> URL? {
        let lines = lines(for: person)
        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)   // A4 @72dpi
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let titleFont = UIFont(name: "STSongti-SC-Bold", size: 20) ?? UIFont.boldSystemFont(ofSize: 20)
        let bodyFont = UIFont(name: "STSongti-SC-Regular", size: 11.5) ?? UIFont.systemFont(ofSize: 11.5)
        let headFont = UIFont(name: "STSongti-SC-Bold", size: 12.5) ?? UIFont.boldSystemFont(ofSize: 12.5)
        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            var y: CGFloat = 48
            let inset: CGFloat = 48
            let width = pageRect.width - inset * 2
            func draw(_ text: String, _ font: UIFont, gap: CGFloat = 5) {
                let style = NSMutableParagraphStyle(); style.lineSpacing = 3
                let attr: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: style]
                let h = (text as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                                        options: [.usesLineFragmentOrigin], attributes: attr, context: nil).height
                if y + h > pageRect.height - 48 { ctx.beginPage(); y = 48 }
                (text as NSString).draw(with: CGRect(x: inset, y: y, width: width, height: h),
                                        options: [.usesLineFragmentOrigin], attributes: attr, context: nil)
                y += h + gap
            }
            for (i, line) in lines.enumerated() {
                if line.hasPrefix("【解盘维度摘要") { ctx.beginPage(); y = 48 }
                if i == 0 { draw(line, titleFont, gap: 10) }
                else if line.hasPrefix("【") { draw(line, headFont, gap: 6) }
                else { draw(line, bodyFont) }
            }
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("命书-\(person.name).pdf")
        do { try data.write(to: url); return url } catch { return nil }
    }
}
