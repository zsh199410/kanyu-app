import Foundation
import CoreText
import CoreGraphics
import PDFKit

// Isolated font-format probe, never a production font substitution or altered report.
let fontURL = URL(fileURLWithPath: CommandLine.arguments[1])
let folder = URL(fileURLWithPath: CommandLine.arguments[2])
let original = "三术合参 人日 0123456789 甲——乙 丙午 office"
var results: [[String: Any]] = []
for weight in [400, 600] {
    let descriptor = CTFontDescriptorCreateWithAttributes([
        kCTFontURLAttribute: fontURL,
        kCTFontVariationAttribute: [NSNumber(value: 0x77676874): NSNumber(value: weight)]
    ] as CFDictionary)
    let font = CTFontCreateWithFontDescriptor(descriptor, 12, nil)
    let data = NSMutableData()
    guard let consumer = CGDataConsumer(data: data as CFMutableData) else { fatalError("No PDF consumer") }
    var box = CGRect(x: 0, y: 0, width: 595, height: 842)
    guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { fatalError("No PDF context") }
    context.beginPDFPage(nil)
    context.textPosition = CGPoint(x: 48, y: 750)
    let text = NSAttributedString(string: original, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font, .ligature: 0])
    CTLineDraw(CTLineCreateWithAttributedString(text), context)
    context.endPDFPage(); context.closePDF()
    try (data as Data).write(to: folder.appendingPathComponent("font-probe-\(weight).pdf"))
    guard let document = PDFDocument(data: data as Data), let extracted = document.page(at: 0)?.string else { fatalError("Cannot extract") }
    let passed = extracted.trimmingCharacters(in: .whitespacesAndNewlines) == original
    results.append(["weight": weight, "font": CTFontCopyPostScriptName(font) as String,
                    "original": original, "extracted": extracted, "passed": passed])
}
try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]).write(to: folder.appendingPathComponent("font-probe.json"))
print(String(data: try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys]), encoding: .utf8)!)
