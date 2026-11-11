import SwiftUI

/// A point in the illustration's normalized coordinate space (0...1, top-left origin).
struct PhysiognomyMarker: Identifiable {
    let id: String
    let label: String
    let x: CGFloat
    let y: CGFloat

    init(id: String, label: String, x: CGFloat, y: CGFloat) {
        self.id = id
        self.label = label
        self.x = x
        self.y = y
    }
}

/// Original schematic artwork for cultural vocabulary, never a photograph or an assessment.
/// Pass a small group of markers at a time; labels and explanations belong below the artwork.
struct PhysiognomyIllustration: View {
    let kind: String
    let selectedID: String?
    let markers: [PhysiognomyMarker]
    let onSelect: (String) -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var ink: Color { scheme == .dark ? Color(red: 0.83, green: 0.88, blue: 0.85) : Color(red: 0.12, green: 0.29, blue: 0.35) }
    private var paper: Color { scheme == .dark ? Color(red: 0.10, green: 0.12, blue: 0.14) : Color(red: 0.98, green: 0.96, blue: 0.91) }
    private var cinnabar: Color { scheme == .dark ? Color(red: 0.94, green: 0.57, blue: 0.49) : Color(red: 0.60, green: 0.16, blue: 0.13) }
    private var isHand: Bool { kind == "hand" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    Canvas { context, size in
                        context.scaleBy(x: size.width / 320, y: size.height / 400)
                        drawBorder(in: &context)
                        if isHand { drawHand(in: &context) } else {
                            drawFace(in: &context)
                            drawFaceLeaders(in: &context)
                        }
                    }
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
                    ForEach(Array(markers.enumerated()), id: \.element.id) { index, marker in
                        markerButton(marker, number: index + 1)
                            .position(x: position(isHand ? marker.x : faceMarkerPosition(marker).x, length: geometry.size.width),
                                      y: position(isHand ? marker.y : faceMarkerPosition(marker).y, length: geometry.size.height))
                    }
                }
            }
            .aspectRatio(0.8, contentMode: .fit)
            .background(paper)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(ink.opacity(0.22), lineWidth: 1).allowsHitTesting(false))

            if isHand {
                // Names are real text, never embedded in an image. Colour is supplementary.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { lineLegend }
                    VStack(alignment: .leading, spacing: 8) { lineLegend }
                }
                .font(.subheadline)
            }
            Text((isHand ? "手掌线条为示意，供认识传统名称与位置。" : "古人正面线描为中性示意，供认识传统部位名称。").scriptConverted)
                .font(.footnote)
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel((isHand ? "手掌部位图解，拇指在左" : "面部部位图解，人物正对").scriptConverted)
    }

    /// Side rails keep the face readable. Midline points use the less populated rail.
    /// Marker numbering always follows the caller's original order.
    private var faceRails: (left: [PhysiognomyMarker], right: [PhysiognomyMarker]) {
        var left = markers.filter { $0.x < 0.48 }
        var right = markers.filter { $0.x > 0.52 }
        for marker in markers.filter({ $0.x >= 0.48 && $0.x <= 0.52 }) {
            if left.count <= right.count { left.append(marker) } else { right.append(marker) }
        }
        let ordered: (PhysiognomyMarker, PhysiognomyMarker) -> Bool = {
            $0.y == $1.y ? $0.id < $1.id : $0.y < $1.y
        }
        return (left.sorted(by: ordered), right.sorted(by: ordered))
    }

    private func faceMarkerPosition(_ marker: PhysiognomyMarker) -> CGPoint {
        let rails = faceRails
        let isLeft = rails.left.contains { $0.id == marker.id }
        let rail = isLeft ? rails.left : rails.right
        let index = rail.firstIndex { $0.id == marker.id } ?? 0
        let y: CGFloat = rail.count < 2 ? 0.5 : 0.1 + 0.8 * CGFloat(index) / CGFloat(rail.count - 1)
        return CGPoint(x: isLeft ? 0.075 : 0.925, y: y)
    }

    private func drawFaceLeaders(in context: inout GraphicsContext) {
        for marker in markers {
            let anchor = faceMarkerPosition(marker)
            let target = CGPoint(x: position(marker.x, length: 320), y: position(marker.y, length: 400))
            let selected = selectedID == marker.id
            var leader = Path()
            leader.move(to: CGPoint(x: anchor.x < 0.5 ? 45 : 275, y: anchor.y * 400))
            leader.addLine(to: target)
            stroke(leader, in: &context, color: (selected ? cinnabar : ink).opacity(selected ? 0.85 : 0.42), width: selected ? 1.4 : 0.8)
            let diameter: CGFloat = selected ? 6 : 4
            context.fill(Path(ellipseIn: CGRect(x: target.x - diameter / 2, y: target.y - diameter / 2,
                                               width: diameter, height: diameter)), with: .color(cinnabar))
        }
    }

    private func position(_ value: CGFloat, length: CGFloat) -> CGFloat {
        let finite = value.isFinite ? value : 0.5
        return min(max(finite * length, 22), max(22, length - 22))
    }

    private func markerButton(_ marker: PhysiognomyMarker, number: Int) -> some View {
        let selected = selectedID == marker.id
        return Button { onSelect(marker.id) } label: {
            Text(String(number))
                .font(.body.monospacedDigit().weight(.bold))
                .foregroundStyle(selected ? paper : ink)
                .frame(minWidth: 36, minHeight: 36)
                .background(selected ? ink : paper, in: Circle())
                .overlay(Circle().strokeBorder(selected ? cinnabar : ink, lineWidth: selected ? 2.5 : 1.5))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("physiognomy.marker.\(marker.id)")
        .accessibilityLabel("图中第\(number)处，\(marker.label)".scriptConverted)
        .accessibilityHint("显示该部位的文字说明".scriptConverted)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: selected)
    }

    @ViewBuilder private var lineLegend: some View {
        legend("生命线", color: cinnabar, dash: [])
        legend("智慧线", color: ink, dash: [5, 3])
        legend("感情线", color: heartColor, dash: [1, 3])
    }
    private var heartColor: Color { scheme == .dark ? Color(red: 0.84, green: 0.72, blue: 0.43) : Color(red: 0.50, green: 0.37, blue: 0.12) }
    private func legend(_ label: String, color: Color, dash: [CGFloat]) -> some View {
        HStack(spacing: 6) {
            Path { path in path.move(to: CGPoint(x: 0, y: 5)); path.addLine(to: CGPoint(x: 23, y: 5)) }
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: dash))
                .frame(width: 24, height: 10).accessibilityHidden(true)
            Text(label.scriptConverted).foregroundStyle(ink).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stroke(_ path: Path, in context: inout GraphicsContext, color: Color? = nil, width: CGFloat = 1.6, dash: [CGFloat] = []) {
        context.stroke(path, with: .color(color ?? ink), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: dash))
    }

    private func drawBorder(in context: inout GraphicsContext) {
        // Low-contrast mountains and cloud curls stay outside the reading area.
        var mountain = Path()
        mountain.move(to: CGPoint(x: 8, y: 383))
        mountain.addLines([CGPoint(x: 26, y: 365), CGPoint(x: 40, y: 375), CGPoint(x: 62, y: 352), CGPoint(x: 83, y: 382)])
        mountain.move(to: CGPoint(x: 240, y: 383))
        mountain.addLines([CGPoint(x: 261, y: 363), CGPoint(x: 275, y: 373), CGPoint(x: 294, y: 350), CGPoint(x: 312, y: 380)])
        stroke(mountain, in: &context, color: ink.opacity(0.15), width: 1)
        for mirrored in [false, true] {
            var cloud = Path()
            let x: CGFloat = mirrored ? 260 : 18
            cloud.move(to: CGPoint(x: x, y: 29))
            cloud.addCurve(to: CGPoint(x: x + 35, y: 25), control1: CGPoint(x: x + 8, y: 13), control2: CGPoint(x: x + 24, y: 40))
            cloud.addCurve(to: CGPoint(x: x + 18, y: 19), control1: CGPoint(x: x + 45, y: 10), control2: CGPoint(x: x + 12, y: 9))
            stroke(cloud, in: &context, color: ink.opacity(0.18), width: 1)
        }
    }

    private func drawHand(in context: inout GraphicsContext) {
        var outline = Path()
        outline.move(to: CGPoint(x: 115, y: 376))
        outline.addCurve(to: CGPoint(x: 92, y: 296), control1: CGPoint(x: 119, y: 340), control2: CGPoint(x: 100, y: 318))
        outline.addCurve(to: CGPoint(x: 44, y: 220), control1: CGPoint(x: 70, y: 278), control2: CGPoint(x: 39, y: 245))
        outline.addCurve(to: CGPoint(x: 58, y: 183), control1: CGPoint(x: 31, y: 198), control2: CGPoint(x: 42, y: 173))
        outline.addCurve(to: CGPoint(x: 98, y: 215), control1: CGPoint(x: 71, y: 185), control2: CGPoint(x: 83, y: 216))
        outline.addCurve(to: CGPoint(x: 102, y: 177), control1: CGPoint(x: 109, y: 216), control2: CGPoint(x: 103, y: 187))
        outline.addLine(to: CGPoint(x: 105, y: 72))
        outline.addCurve(to: CGPoint(x: 135, y: 72), control1: CGPoint(x: 105, y: 48), control2: CGPoint(x: 135, y: 49))
        outline.addLine(to: CGPoint(x: 139, y: 157))
        outline.addQuadCurve(to: CGPoint(x: 149, y: 157), control: CGPoint(x: 145, y: 172))
        outline.addLine(to: CGPoint(x: 151, y: 44))
        outline.addCurve(to: CGPoint(x: 182, y: 44), control1: CGPoint(x: 152, y: 19), control2: CGPoint(x: 181, y: 19))
        outline.addLine(to: CGPoint(x: 185, y: 155))
        outline.addQuadCurve(to: CGPoint(x: 195, y: 157), control: CGPoint(x: 189, y: 173))
        outline.addLine(to: CGPoint(x: 196, y: 62))
        outline.addCurve(to: CGPoint(x: 225, y: 62), control1: CGPoint(x: 197, y: 37), control2: CGPoint(x: 224, y: 37))
        outline.addLine(to: CGPoint(x: 228, y: 177))
        outline.addQuadCurve(to: CGPoint(x: 238, y: 178), control: CGPoint(x: 232, y: 192))
        outline.addLine(to: CGPoint(x: 239, y: 109))
        outline.addCurve(to: CGPoint(x: 266, y: 109), control1: CGPoint(x: 240, y: 87), control2: CGPoint(x: 264, y: 87))
        outline.addCurve(to: CGPoint(x: 260, y: 270), control1: CGPoint(x: 271, y: 157), control2: CGPoint(x: 271, y: 237))
        outline.addCurve(to: CGPoint(x: 213, y: 376), control1: CGPoint(x: 252, y: 316), control2: CGPoint(x: 210, y: 336))
        stroke(outline, in: &context, width: 2)
        for (x, y) in [(120.0, 111.0), (166, 99), (211, 107), (252, 146)] {
            var joint = Path()
            joint.move(to: CGPoint(x: x - 7, y: y))
            joint.addQuadCurve(to: CGPoint(x: x + 7, y: y), control: CGPoint(x: x, y: y + 4))
            stroke(joint, in: &context, color: ink.opacity(0.45), width: 1)
        }
        var life = Path()
        life.move(to: CGPoint(x: 115, y: 196))
        life.addCurve(to: CGPoint(x: 138, y: 336), control1: CGPoint(x: 83, y: 229), control2: CGPoint(x: 92, y: 307))
        stroke(life, in: &context, color: cinnabar, width: 2.4)
        var head = Path()
        head.move(to: CGPoint(x: 115, y: 204))
        head.addCurve(to: CGPoint(x: 234, y: 268), control1: CGPoint(x: 154, y: 214), control2: CGPoint(x: 194, y: 250))
        stroke(head, in: &context, width: 2.2, dash: [5, 3])
        var heart = Path()
        heart.move(to: CGPoint(x: 99, y: 188))
        heart.addCurve(to: CGPoint(x: 246, y: 168), control1: CGPoint(x: 145, y: 193), control2: CGPoint(x: 208, y: 158))
        stroke(heart, in: &context, color: heartColor, width: 2.4, dash: [1, 3])
        var wrist = Path()
        wrist.move(to: CGPoint(x: 125, y: 350))
        wrist.addQuadCurve(to: CGPoint(x: 206, y: 350), control: CGPoint(x: 166, y: 360))
        stroke(wrist, in: &context, color: ink.opacity(0.45), width: 1)
    }

    private func drawFace(in context: inout GraphicsContext) {
        var face = Path()
        face.move(to: CGPoint(x: 79, y: 132))
        face.addCurve(to: CGPoint(x: 160, y: 329), control1: CGPoint(x: 66, y: 220), control2: CGPoint(x: 93, y: 310))
        face.addCurve(to: CGPoint(x: 241, y: 132), control1: CGPoint(x: 227, y: 310), control2: CGPoint(x: 254, y: 220))
        stroke(face, in: &context, width: 2)
        var hair = Path()
        hair.move(to: CGPoint(x: 76, y: 180))
        hair.addCurve(to: CGPoint(x: 160, y: 45), control1: CGPoint(x: 46, y: 85), control2: CGPoint(x: 91, y: 46))
        hair.addCurve(to: CGPoint(x: 244, y: 180), control1: CGPoint(x: 229, y: 46), control2: CGPoint(x: 274, y: 85))
        hair.move(to: CGPoint(x: 79, y: 139))
        hair.addCurve(to: CGPoint(x: 160, y: 85), control1: CGPoint(x: 108, y: 143), control2: CGPoint(x: 116, y: 104))
        hair.addCurve(to: CGPoint(x: 241, y: 139), control1: CGPoint(x: 204, y: 104), control2: CGPoint(x: 212, y: 143))
        hair.move(to: CGPoint(x: 143, y: 46))
        hair.addCurve(to: CGPoint(x: 177, y: 46), control1: CGPoint(x: 126, y: 11), control2: CGPoint(x: 194, y: 11))
        stroke(hair, in: &context, width: 1.8)
        for right in [false, true] {
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: right ? 320 - x : x, y: y) }
            var eye = Path()
            eye.move(to: point(92, 176))
            eye.addQuadCurve(to: point(131, 176), control: point(111, 166))
            eye.addQuadCurve(to: point(92, 176), control: point(111, 183))
            stroke(eye, in: &context, width: 1.4)
            let pupil = CGRect(x: (right ? 208 : 112) - 2, y: 173, width: 4, height: 5)
            context.fill(Path(ellipseIn: pupil), with: .color(ink))
            var brow = Path()
            brow.move(to: point(91, 159))
            brow.addQuadCurve(to: point(132, 158), control: point(110, 149))
            stroke(brow, in: &context, width: 2)
            var ear = Path()
            ear.move(to: point(77, 170))
            ear.addCurve(to: point(80, 228), control1: point(48, 158), control2: point(56, 226))
            ear.move(to: point(70, 184))
            ear.addQuadCurve(to: point(73, 213), control: point(58, 193))
            stroke(ear, in: &context, width: 1.4)
            var neck = Path()
            neck.move(to: point(122, 311))
            neck.addQuadCurve(to: point(115, 350), control: point(124, 338))
            neck.addLine(to: point(55, 376))
            stroke(neck, in: &context, width: 1.5)
        }
        var nose = Path()
        nose.move(to: CGPoint(x: 152, y: 184))
        nose.addQuadCurve(to: CGPoint(x: 145, y: 223), control: CGPoint(x: 150, y: 210))
        nose.addQuadCurve(to: CGPoint(x: 175, y: 223), control: CGPoint(x: 160, y: 236))
        nose.addQuadCurve(to: CGPoint(x: 168, y: 184), control: CGPoint(x: 170, y: 210))
        stroke(nose, in: &context, width: 1.3)
        var mouth = Path()
        mouth.move(to: CGPoint(x: 132, y: 267))
        mouth.addQuadCurve(to: CGPoint(x: 160, y: 263), control: CGPoint(x: 149, y: 257))
        mouth.addQuadCurve(to: CGPoint(x: 188, y: 267), control: CGPoint(x: 171, y: 257))
        mouth.addQuadCurve(to: CGPoint(x: 132, y: 267), control: CGPoint(x: 160, y: 279))
        stroke(mouth, in: &context, width: 1.4)
        var collar = Path()
        collar.move(to: CGPoint(x: 115, y: 350))
        collar.addLines([CGPoint(x: 160, y: 382), CGPoint(x: 205, y: 350)])
        stroke(collar, in: &context, color: cinnabar.opacity(0.7), width: 1.3)
    }
}
