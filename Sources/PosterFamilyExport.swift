import SwiftUI
import UIKit
import ImageIO

/// Native four-style export, using only the immutable, owner-checked snapshot.
/// The concept JPEGs contain example data and must never become export pixels.
@MainActor
enum PosterFamilyExport {
    enum Failure: LocalizedError {
        case unverifiedOwner, renderingFailed
        var errorDescription: String? {
            switch self {
            case .unverifiedOwner: return "当前报告缺少可信人物归属或数据来源，禁止导出。"
            case .renderingFailed: return "海报渲染失败，请重试。"
            }
        }
    }

    private static func render(snapshot: PosterDynamicSnapshot, scale: CGFloat) throws -> PosterRasterizer.Output {
        let content = PosterFamilyExportCanvas(snapshot: snapshot)
            .frame(width: 1080, alignment: .topLeading)
            .fixedSize(horizontal: true, vertical: true)
            .frame(minHeight: 1081, alignment: .top)
            .background(PosterFamilyPalette(kind: snapshot.kind).paper)
            .environment(\.colorScheme, .light)
            .environment(\.dynamicTypeSize, .large)
        return try PosterRasterizer.render(content, scale: scale)
    }

    /// Low-resolution bitmap from exactly the same layout; never writes a file.
    static func preview(snapshot: PosterDynamicSnapshot) throws -> UIImage {
        try render(snapshot: snapshot, scale: 0.40).image
    }

    static func image(snapshot: PosterDynamicSnapshot) throws -> URL {
        guard snapshot.canArchive, snapshot.ownerID != nil else { throw Failure.unverifiedOwner }
        let output = try render(snapshot: snapshot, scale: 1)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kanyu-\(snapshot.kind.rawValue)-\(UUID().uuidString).png")
        try output.pngData.write(to: url, options: .atomic)
        return url
    }
}

private struct PosterFamilyPalette {
    let paper: Color
    let ink: Color
    let panel: Color
    let accent: Color
    let line: Color
    init(kind: PosterDynamicKind) {
        switch kind {
        case .bazi:
            paper = Color(red: 0.97, green: 0.93, blue: 0.85)
            ink = Color(red: 0.24, green: 0.18, blue: 0.12)
            panel = Color(red: 0.99, green: 0.97, blue: 0.91)
            accent = Color(red: 0.55, green: 0.18, blue: 0.12)
            line = Color(red: 0.64, green: 0.48, blue: 0.29)
        case .palm:
            paper = Color(red: 0.94, green: 0.92, blue: 0.84)
            ink = Color(red: 0.08, green: 0.20, blue: 0.25)
            panel = Color(red: 0.99, green: 0.97, blue: 0.91)
            accent = Color(red: 0.13, green: 0.37, blue: 0.36)
            line = Color(red: 0.65, green: 0.52, blue: 0.29)
        case .ziwei:
            paper = Color(red: 0.065, green: 0.10, blue: 0.19)
            ink = Color(red: 0.98, green: 0.92, blue: 0.76)
            panel = Color(red: 0.10, green: 0.16, blue: 0.27)
            accent = Color(red: 0.91, green: 0.74, blue: 0.43)
            line = Color(red: 0.59, green: 0.49, blue: 0.32)
        case .premium:
            paper = Color(red: 0.97, green: 0.94, blue: 0.87)
            ink = Color(red: 0.27, green: 0.19, blue: 0.15)
            panel = Color(red: 1.0, green: 0.98, blue: 0.93)
            accent = Color(red: 0.53, green: 0.18, blue: 0.14)
            line = Color(red: 0.67, green: 0.48, blue: 0.30)
        }
    }
}

/// Decorative vector marks are not astronomical positions or measured palm lines.
private struct PosterFamilyOrnament: View {
    let kind: PosterDynamicKind
    let tint: Color
    var body: some View {
        Canvas { context, size in
            if kind == .ziwei {
                let center = CGPoint(x: size.width * 0.74, y: size.height * 0.50)
                for radius in [CGFloat(58), 94, 130, 166] {
                    let rect = CGRect(x: center.x - radius, y: center.y - radius,
                                      width: radius * 2, height: radius * 2)
                    context.stroke(Path(ellipseIn: rect), with: .color(tint.opacity(0.28)), lineWidth: 2)
                }
                for i in 0..<38 {
                    let x = CGFloat((i * 137 + 29) % 947) / 947 * size.width
                    let y = CGFloat((i * 79 + 17) % 313) / 313 * size.height
                    let d: CGFloat = i % 5 == 0 ? 7 : 3
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: d, height: d)),
                                 with: .color(tint.opacity(0.46)))
                }
            } else {
                for band in 0..<3 {
                    let y = size.height * (0.65 + CGFloat(band) * 0.11)
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: size.height))
                    path.addLine(to: CGPoint(x: 0, y: y))
                    for i in 1...10 {
                        let x = CGFloat(i) / 10 * size.width
                        let peak = CGFloat((i * 29 + band * 17) % 67)
                        path.addLine(to: CGPoint(x: x, y: y - peak))
                    }
                    path.addLine(to: CGPoint(x: size.width, y: size.height))
                    path.closeSubpath()
                    context.fill(path, with: .color(tint.opacity(0.075 + Double(band) * 0.035)))
                }
                if kind == .palm {
                    for i in 0..<4 {
                        let x = size.width * 0.66 + CGFloat(i) * 31
                        var p = Path()
                        p.move(to: CGPoint(x: x, y: 24))
                        p.addQuadCurve(to: CGPoint(x: x + 64, y: size.height - 25),
                                       control: CGPoint(x: x - 38, y: size.height * 0.60))
                        context.stroke(p, with: .color(tint.opacity(0.3)), lineWidth: 2)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct PosterFamilyExportCanvas: View {
    let snapshot: PosterDynamicSnapshot
    private var palette: PosterFamilyPalette { .init(kind: snapshot.kind) }
    private var isPremium: Bool { snapshot.kind == .premium }
    private var isNight: Bool { snapshot.kind == .ziwei }
    private var title: String {
        switch snapshot.kind {
        case .bazi: return "个人命理解析"
        case .palm: return "你的个人指南"
        case .ziwei: return "紫微命盘"
        case .premium: return "八字尊享预测单"
        }
    }
    private var subtitle: String {
        switch snapshot.kind {
        case .bazi: return "宋纸长卷  ·  四柱与五行"
        case .palm: return "青黛金线  ·  个人测量记录"
        case .ziwei: return "玄夜星图  ·  十二宫主星"
        case .premium: return "朱砂册页  ·  专属深读"
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            header
            if snapshot.kind == .palm { palmPhoto }
            ForEach(Array(snapshot.sections.enumerated()), id: \.element.id) { index, section in
                sectionView(section, index: index)
            }
            decorativeFooter
            VStack(alignment: .leading, spacing: 15) {
                Text("来源与说明").font(.system(size: 28, weight: .semibold, design: .serif))
                    .foregroundStyle(palette.accent)
                Text(snapshot.caution.replacingOccurrences(of: "此预览不生成文件。", with: ""))
                    .font(.system(size: 23)).fixedSize(horizontal: false, vertical: true)
                Text(snapshot.receipt).font(.system(size: 20)).fixedSize(horizontal: false, vertical: true)
                Text("三术合参  ·  个人与家庭使用").font(.system(size: 22, design: .serif))
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Rectangle().fill(palette.line).frame(height: 2) }
        }
        .padding(45)
        .foregroundStyle(palette.ink)
        .frame(width: 1080, alignment: .topLeading)
        .background(palette.paper)
        .overlay { ornamentFrame }
    }

    // Only approved illustration-only crops are loaded here. Full concept posters
    // contain sample names/values and must never be used as render backgrounds.
    private func illustration(_ name: String) -> UIImage? {
        let url = Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "PosterArtworkV2")
            ?? Bundle.main.url(forResource: name, withExtension: "jpg")
        return url.flatMap { UIImage(contentsOfFile: $0.path) }
    }

    @ViewBuilder private var decorativeFooter: some View {
        switch snapshot.kind {
        case .palm, .ziwei:
            let name = snapshot.kind == .palm ? "palm-landscape" : "ziwei-landscape"
            if let art = illustration(name) {
                Image(uiImage: art).resizable().scaledToFit()
                    .frame(maxWidth: .infinity)
                    .overlay { Rectangle().strokeBorder(palette.line, lineWidth: 2) }
                    .accessibilityHidden(true)
            }
        case .bazi:
            if let scholar = illustration("bazi-scholar") {
                HStack(spacing: 24) {
                    Image(uiImage: scholar).resizable().scaledToFit().frame(width: 175)
                    VStack(alignment: .leading, spacing: 9) {
                        Text("观命 · 知己").font(.system(size: 35, weight: .semibold, design: .serif))
                        Text("传统文化参考 · 以当下行动为重").font(.system(size: 23))
                    }
                    Spacer(minLength: 0)
                }
                .padding(18).background(palette.panel)
                .overlay { Rectangle().strokeBorder(palette.line, lineWidth: 2) }
            }
        case .premium:
            if let left = illustration("premium-landscape-left"),
               let right = illustration("premium-landscape-right") {
                HStack(spacing: 0) {
                    Image(uiImage: left).resizable().scaledToFit()
                    Image(uiImage: right).resizable().scaledToFit()
                }.accessibilityHidden(true)
            }
        }
    }

    private var ornamentFrame: some View {
        ZStack {
            Rectangle().strokeBorder(palette.line.opacity(0.65), lineWidth: 2).padding(16)
            Rectangle().strokeBorder(palette.line.opacity(0.32), lineWidth: 1).padding(24)
            Canvas { context, size in
                for (x, y, sx, sy) in [(CGFloat(16), CGFloat(16), CGFloat(1), CGFloat(1)),
                                       (size.width - 16, CGFloat(16), CGFloat(-1), CGFloat(1)),
                                       (CGFloat(16), size.height - 16, CGFloat(1), CGFloat(-1)),
                                       (size.width - 16, size.height - 16, CGFloat(-1), CGFloat(-1))] {
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: y + sy * 72))
                    p.addLine(to: CGPoint(x: x + sx * 13, y: y + sy * 72))
                    p.addLine(to: CGPoint(x: x + sx * 13, y: y + sy * 13))
                    p.addLine(to: CGPoint(x: x + sx * 72, y: y + sy * 13))
                    p.addLine(to: CGPoint(x: x + sx * 72, y: y))
                    context.stroke(p, with: .color(palette.line), lineWidth: 3)
                }
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                V5PosterBrandMark(kind: snapshot.kind)
                Text("三 术 合 参").font(.system(size: 26, weight: .medium, design: .serif))
                Spacer(minLength: 16)
                Text(isPremium ? "尊享" : "个人").font(.system(size: 25, weight: .bold, design: .serif))
                    .padding(13)
                    .foregroundStyle(snapshot.kind == .palm ? Color(red: 0.98, green: 0.94, blue: 0.82) : (isNight ? palette.ink : palette.accent))
                    .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(snapshot.kind == .palm ? palette.line : palette.accent, lineWidth: 2) }
            }
            Text(title).font(.system(size: 70, weight: .bold, design: .serif))
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle).font(.system(size: 27, design: .serif))
            Rectangle().fill(palette.line).frame(height: 2)
            Text(snapshot.displayName.isEmpty ? "未命名" : snapshot.displayName)
                .font(.system(size: 38, weight: .semibold, design: .serif))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(38)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(snapshot.kind == .palm ? Color(red: 0.98, green: 0.94, blue: 0.82) : palette.ink)
        .background { V5PosterHeaderArt(kind: snapshot.kind) }
        .background(snapshot.kind == .palm ? palette.ink : palette.panel)
        .background { PosterFamilyOrnament(kind: snapshot.kind, tint: palette.line) }
        .overlay(alignment: .bottom) {
            PosterFamilyOrnament(kind: snapshot.kind, tint: palette.line)
                .frame(height: 125).allowsHitTesting(false)
        }
        .overlay { Rectangle().strokeBorder(palette.line, lineWidth: 2).padding(9).allowsHitTesting(false) }
    }

    @ViewBuilder
    private func sectionView(_ section: PosterBoundSection, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(String(format: "%02d", index + 1))
                    .font(.system(size: 25, weight: .bold, design: .serif))
                    .foregroundStyle(isNight ? palette.paper : Color.white)
                    .padding(12).background(palette.accent)
                Text(section.title)
                    .font(.system(size: 39, weight: .semibold, design: .serif))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            Rectangle().fill(palette.line.opacity(0.6)).frame(height: 2)
            if (snapshot.kind == .bazi || isPremium) && section.id == "pillars" {
                fieldGrid(section.fields, columns: 4)
            } else if snapshot.kind == .bazi && section.id == "dayun" {
                fieldGrid(section.fields, columns: 3)
            } else if isNight && section.id == "palaces" {
                if section.fields.count == 12 &&
                    section.fields.enumerated().allSatisfy({ $0.element.id == "palace.\($0.offset)" }) {
                    palaceBoard(section.fields)
                } else {
                    // Never guess spatial positions when the snapshot is incomplete.
                    fieldGrid(section.fields, columns: 3)
                }
            } else if section.id == "elements" && !isPremium {
                fiveElementPanel(section.fields)
            } else {
                ForEach(section.fields) { field in fieldRow(field) }
            }
        }
        .padding(isPremium ? 38 : 30)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.panel)
        .overlay { Rectangle().strokeBorder(palette.line.opacity(0.7), lineWidth: 2) }
    }

    // ZiweiChart.palaces is ordered 子→亥. Match the existing ZiweiBoardView
    // arrangement exactly; the center is a decorative legend, not a thirteenth palace.
    private func palaceBoard(_ fields: [PosterBoundField]) -> some View {
        let cellWidth: CGFloat = 222
        let cellHeight: CGFloat = 200
        let gap: CGFloat = 8
        return VStack(spacing: gap) {
            HStack(spacing: gap) {
                ForEach([5, 6, 7, 8], id: \.self) { i in
                    palaceCell(fields[i], branch: i, width: cellWidth, height: cellHeight)
                }
            }
            HStack(spacing: gap) {
                VStack(spacing: gap) {
                    ForEach([4, 3], id: \.self) { i in
                        palaceCell(fields[i], branch: i, width: cellWidth, height: cellHeight)
                    }
                }
                ZStack {
                    PosterFamilyOrnament(kind: .ziwei, tint: palette.line)
                    VStack(spacing: 15) {
                        Text("紫 微").font(.system(size: 52, weight: .bold, design: .serif))
                        Text("十二宫主星").font(.system(size: 28, design: .serif))
                        Rectangle().fill(palette.line).frame(width: 108, height: 2)
                        Text("地支方位 · 原盘顺序").font(.system(size: 22))
                    }
                    .foregroundStyle(palette.accent)
                }
                .frame(width: cellWidth * 2 + gap, height: cellHeight * 2 + gap)
                .overlay { Rectangle().strokeBorder(palette.line, lineWidth: 2) }
                VStack(spacing: gap) {
                    ForEach([9, 10], id: \.self) { i in
                        palaceCell(fields[i], branch: i, width: cellWidth, height: cellHeight)
                    }
                }
            }
            HStack(spacing: gap) {
                ForEach([2, 1, 0, 11], id: \.self) { i in
                    palaceCell(fields[i], branch: i, width: cellWidth, height: cellHeight)
                }
            }
            Text("宫名、主星与四化：ZiweiChart.palaces · 地支序子至亥")
                .font(.system(size: 20))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
    }

    private func palaceCell(_ field: PosterBoundField, branch: Int, width: CGFloat, height: CGFloat) -> some View {
        let branches = ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(field.label).font(.system(size: 27, weight: .semibold, design: .serif))
                Spacer(minLength: 0)
                Text(branches[branch]).font(.system(size: 23, design: .serif))
            }.foregroundStyle(palette.accent)
            Rectangle().fill(palette.line.opacity(0.6)).frame(height: 1)
            Text(field.value.replacingOccurrences(of: "、", with: "\n"))
                .font(.system(size: 28, weight: .medium, design: .serif))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(palette.paper.opacity(0.55))
        .overlay { Rectangle().strokeBorder(palette.line.opacity(0.75), lineWidth: 1.5) }
    }

    private func fieldGrid(_ fields: [PosterBoundField], columns: Int) -> some View {
        let starts = Array(stride(from: 0, to: fields.count, by: columns))
        return VStack(spacing: 12) {
            ForEach(starts, id: \.self) { start in
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(fields[start..<min(start + columns, fields.count)])) { field in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(field.label).font(.system(size: 25, weight: .semibold, design: .serif))
                                .foregroundStyle(palette.accent)
                            Text(field.value).font(.system(size: isNight ? 30 : 42, weight: .medium, design: .serif))
                                .fixedSize(horizontal: false, vertical: true)
                            Text("来源：\(field.source)").font(.system(size: 17))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .overlay { Rectangle().strokeBorder(palette.line.opacity(0.55), lineWidth: 1.5) }
                    }
                }
            }
        }
    }

    private func fieldRow(_ field: PosterBoundField) -> some View {
        VStack(alignment: .leading, spacing: isPremium ? 14 : 10) {
            Text(field.label).font(.system(size: 27, weight: .bold, design: .serif))
                .foregroundStyle(palette.accent)
            Text(field.value).font(.system(size: 30))
                .fixedSize(horizontal: false, vertical: true)
            Text("来源：\(field.source)").font(.system(size: 20))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(isPremium ? 30 : 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.paper.opacity(isNight ? 0.42 : 0.55))
        .overlay(alignment: .leading) { Rectangle().fill(palette.line).frame(width: 3) }
    }

    /// Five-element diagram is a labelled composition, not a fabricated forecast.
    private func elementColor(_ label: String) -> Color {
        switch label {
        case "木": return Color(red: 0.24, green: 0.40, blue: 0.28)
        case "火": return Color(red: 0.63, green: 0.24, blue: 0.16)
        case "土": return Color(red: 0.58, green: 0.39, blue: 0.22)
        case "金": return Color(red: 0.66, green: 0.46, blue: 0.15)
        case "水": return Color(red: 0.18, green: 0.35, blue: 0.47)
        default: return palette.accent
        }
    }

    @ViewBuilder private func fiveElementPanel(_ fields: [PosterBoundField]) -> some View {
        if fields.count == 5 && fields.map(\.label) == ["木", "火", "土", "金", "水"] {
            HStack(alignment: .center, spacing: 24) {
                ZStack {
                    Circle().strokeBorder(palette.line.opacity(0.65), lineWidth: 2)
                        .frame(width: 270, height: 270)
                    Circle().strokeBorder(palette.line.opacity(0.30), lineWidth: 2)
                        .frame(width: 210, height: 210)
                    VStack(spacing: 5) {
                        Text("五 行").font(.system(size: 33, weight: .semibold, design: .serif))
                        Text("构成比例").font(.system(size: 21))
                    }
                    ForEach(Array(fields.enumerated()), id: \.element.id) { index, field in
                        let angle = Double(index) * 2 * Double.pi / 5 - Double.pi / 2
                        Text(field.label)
                            .font(.system(size: 36, weight: .semibold, design: .serif))
                            .foregroundStyle(.white)
                            .frame(width: 74, height: 74)
                            .background(elementColor(field.label), in: Circle())
                            .overlay { Circle().strokeBorder(palette.line, lineWidth: 2) }
                            .offset(x: CGFloat(cos(angle)) * 135, y: CGFloat(sin(angle)) * 135)
                    }
                }
                .frame(width: 370, height: 370)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(fields) { field in elementRow(field) }
                }
            }
        } else {
            ForEach(fields) { field in elementRow(field) }
        }
    }

    private func elementRow(_ field: PosterBoundField) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(field.label).font(.system(size: 30, weight: .semibold, design: .serif))
                Spacer()
                Text(field.value).font(.system(size: 28, weight: .medium))
            }
            if let number = Double(field.value.replacingOccurrences(of: "%", with: "")),
               number.isFinite, (0...100).contains(number) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(palette.line.opacity(0.15))
                        Rectangle().fill(elementColor(field.label)).frame(width: geometry.size.width * CGFloat(number / 100))
                    }
                }.frame(height: 14)
            }
            Text("来源：\(field.source)").font(.system(size: 20))
        }.padding(.vertical, 7)
    }

    @ViewBuilder
    private var palmPhoto: some View {
        if let image = ownedPalmPhoto() {
            VStack(alignment: .leading, spacing: 16) {
                Text("本人原始掌纹").font(.system(size: 39, weight: .semibold, design: .serif))
                Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: 740, maxHeight: 820)
                    .frame(maxWidth: .infinity)
                Text("来自当前人物关联的测量照片；未添加推测掌纹。").font(.system(size: 23))
            }.padding(30).background(palette.panel)
                .overlay { Rectangle().strokeBorder(palette.line, lineWidth: 2) }
        } else {
            Text("未附可读取的本人掌纹照片 · 以下仅展示已保存测量记录")
                .font(.system(size: 25)).padding(25)
                .frame(maxWidth: .infinity, alignment: .leading).background(palette.panel)
        }
    }

    private func ownedPalmPhoto() -> UIImage? {
        guard snapshot.canArchive, let asset = snapshot.imageAssets.first(where: { $0.kind == "photo" }),
              asset.sourcePath.hasPrefix("PalmPhotos/") else { return nil }
        let name = String(asset.sourcePath.dropFirst("PalmPhotos/".count))
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"),
              let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let url = docs.appendingPathComponent("PalmPhotos", isDirectory: true).appendingPathComponent(name)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1000
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: thumbnail)
    }
}

struct PosterFamilyShareSheet: UIViewControllerRepresentable {
    let url: URL
    var title: String = "命盘海报"
    @Environment(\.dismiss) private var dismiss
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [V5PosterShareItem(url: url, title: title)], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            DispatchQueue.main.async { dismiss() }
        }
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
