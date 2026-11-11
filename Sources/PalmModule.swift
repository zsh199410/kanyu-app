// 手相面相模块（P4 提前量，2026-10-30；2026-11-09 重新设计 P0＋P1）：
// 手相＝Vision 21 点几何测量（掌型/指长比可复核）＋掌纹三线关节点锚定（掌心坐标系，
// 腕→中指根为纵轴，线按关节点落位，不再用写死全图坐标）＋逐点可拖修正；另有掌纹参考
// 描边（CIEdges 掌区增强，仅作参考，不自动定线）。面相＝Vision Rev 3 自动标眉/鼻底/
// 下颌线（发际线仍手动）＋MediaPipe 478 点补五眼与面宽。全程娱乐定性，不做疾病灾祸预测。
import SwiftUI
import PhotosUI
import Vision
import CoreImage
import MediaPipeTasksVision

struct PalmHomeView: View {
    @State private var quickPerson: Person?
    var body: some View {
        List {
            Section {
                PersonQuickBar(store: PeopleStore.shared) { p in quickPerson = p }
                if let q = quickPerson {
                    HStack(spacing: 6) {
                        Image(systemName: "person.fill").foregroundStyle(Ky.qingdai)
                        Text("当前命主：".scriptConverted + (q.name.isEmpty ? "未命名" : q.name) + "（测量记录按此人归档）".scriptConverted).font(.caption).foregroundStyle(Ky.ink)
                    }
                }
            }
            NavigationLink { HandMeasureView(personName: quickPerson?.name ?? "") } label: {
                Label("手相 · 测量与描线".scriptConverted, systemImage: "hand.raised")
            }
            NavigationLink { FaceMeasureView(personName: quickPerson?.name ?? "") } label: {
                Label("面相 · 三停校准".scriptConverted, systemImage: "face.smiling")
            }
            NavigationLink { PalmRecordListView() } label: {
                Label("测量记录（按人存档）".scriptConverted, systemImage: "archivebox")
            }
            Text("用法：手相用掌心正对、光线均匀的照片；面相用正面自然光、无美颜的照片。测量是几何事实，判读为娱乐参考。".scriptConverted)
                .font(.caption).foregroundStyle(Ky.sub)
        }
        .navigationTitle("手相面相".scriptConverted)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 图像装配（选图＋aspectFit 画布）
struct FittedImage<Overlay: View>: View {
    let image: UIImage
    @ViewBuilder let overlay: (CGRect) -> Overlay
    var body: some View {
        GeometryReader { geo in
            let rect = Self.fit(image: image, in: geo.size)
            ZStack(alignment: .topLeading) {
                Image(uiImage: image).resizable().frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                overlay(rect)
            }
            .coordinateSpace(name: "fittedCanvas")
        }
    }
    static func fit(image: UIImage, in size: CGSize) -> CGRect {
        guard image.size.width > 0, size.width > 0 else { return .zero }
        let scale = min(size.width / image.size.width, size.height / image.size.height)
        let w = image.size.width * scale; let h = image.size.height * scale
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }
}

@MainActor
final class PhotoBox: ObservableObject {
    @Published var image: UIImage?
    func load(_ item: PhotosPickerItem?) async {
        if let data = try? await item?.loadTransferable(type: Data.self),
           let ui = UIImage(data: data) { image = ui.normalizedOrientation() }
    }
}

// MARK: - 方向归一化（UIImage(data:) 保留 EXIF 方向，cgImage 是未旋转像素；
// Vision 用 cgImage 算点、显示用 UIImage，两边对不上会让关节点错位，故先转正）
extension UIImage {
    func normalizedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: size)) }
    }
}

// MARK: - 手相三线关节点锚定（纯函数，可单元测试）
// 掌心坐标系：原点＝腕点，纵轴 U＝腕→中指根（指向手指），横轴 V＝U 的垂线，
// 朝拇指侧为正（用 thumbCMC 定向，不依赖左右手）；纵向单位 L＝|腕→中指根|，
// 横向单位 W＝|食指根→小指根|。线用 (a, b) 表示：a＝腕 0 → 中指根 1，b＝拇指侧为正。
// 解剖依据：感情线＝远侧掌横纹，智慧线＝近侧掌横纹，生命线＝大鱼际纹。
// 输入 joints 为 Vision 归一化坐标（左下原点）；输出为画布相对坐标（左上原点 0-1）。
func palmFrame(joints: [String: CGPoint]) -> (origin: CGPoint, u: CGVector, v: CGVector, length: CGFloat, width: CGFloat)? {
    guard let wrist = joints["wrist"], let mm = joints["middleMCP"],
          let im = joints["indexMCP"], let lm = joints["littleMCP"],
          let tc = joints["thumbCMC"] else { return nil }
    let ux = mm.x - wrist.x; let uy = mm.y - wrist.y
    let len = (ux * ux + uy * uy).squareRoot()
    guard len > 0.05 else { return nil }
    let u = CGVector(dx: ux / len, dy: uy / len)
    var v = CGVector(dx: -u.dy, dy: u.dx)
    let toThumb = CGVector(dx: tc.x - wrist.x, dy: tc.y - wrist.y)
    if v.dx * toThumb.dx + v.dy * toThumb.dy < 0 { v = CGVector(dx: -v.dx, dy: -v.dy) }
    let wx = im.x - lm.x; let wy = im.y - lm.y
    let wid = (wx * wx + wy * wy).squareRoot()
    guard wid > 0.05 else { return nil }
    return (wrist, u, v, len, wid)
}

func anchoredPalmLines(joints: [String: CGPoint]) -> [[CGPoint]]? {
    guard let f = palmFrame(joints: joints) else { return nil }
    func p(_ a: CGFloat, _ b: CGFloat) -> CGPoint {
        let vx = f.origin.x + f.u.dx * a * f.length + f.v.dx * b * f.width
        let vy = f.origin.y + f.u.dy * a * f.length + f.v.dy * b * f.width
        return CGPoint(x: min(max(vx, 0), 1), y: min(max(1 - vy, 0), 1))
    }
    let heart = [p(0.80, -0.45), p(0.84, -0.15), p(0.85, 0.12), p(0.84, 0.33)]
    let head = [p(0.60, 0.42), p(0.60, 0.15), p(0.58, -0.15), p(0.58, -0.45)]
    let life = [p(0.62, 0.40), p(0.40, 0.24), p(0.22, 0.22), p(0.12, 0.35)]
    return [heart, head, life]
}

// MARK: - 平滑曲线（Catmull-Rom 采样，纯函数，可单元测试）
// 把锚点连成平滑曲线再画线：锚点仍是拖动控制点，采样点只用于画线，
// 避免 4 个锚点用直线段直接相连时出现折角。首尾段端点复用以固定切线。
func smoothLinePoints(_ anchors: [CGPoint], segmentsPerSpan: Int = 16) -> [CGPoint] {
    guard anchors.count >= 3 else { return anchors }
    var out: [CGPoint] = [anchors[0]]
    for i in 0..<(anchors.count - 1) {
        let p0 = anchors[max(i - 1, 0)]
        let p1 = anchors[i]
        let p2 = anchors[i + 1]
        let p3 = anchors[min(i + 2, anchors.count - 1)]
        for s in 1...segmentsPerSpan {
            let t = CGFloat(s) / CGFloat(segmentsPerSpan)
            let t2 = t * t
            let t3 = t2 * t
            let x = 0.5 * ((2 * p1.x) + (-p0.x + p2.x) * t + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3)
            let y = 0.5 * ((2 * p1.y) + (-p0.y + p2.y) * t + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3)
            out.append(CGPoint(x: x, y: y))
        }
    }
    // 末点直接取末锚点：t = 1 的公式值受浮点累计误差影响，末点会偏离锚点约 1e-16，
    // 线尾须与拖动圆点精确重合，故以锚点为准。
    out[out.count - 1] = anchors[anchors.count - 1]
    return out
}

// MARK: - 掌纹边缘贴合（把模板锚点吸到真实掌纹上）
// 原理：Vision/MediaPipe 只给关节点、没有掌纹输出；但掌纹是掌区最强的边缘。
// 复用掌纹参考描边的 CIEdges 结果做成 EdgeMap，锚点沿局部法线在小半径内
// 搜最强边缘并吸过去。吸不到（边缘太弱）就留在模板位置，不硬拽；
// 拖动圆点永远可以修正，贴合只是初始落位更准。控制点仍是每线 4 个，
// 记录与海报的“每线 4 点”格式不动。
struct EdgeMap {
    let width: Int
    let height: Int
    let values: [Float]  // 行主序，0-1，行 0 ＝图顶
    init(width: Int, height: Int, values: [Float]) {
        self.width = max(width, 1); self.height = max(height, 1)
        self.values = values
    }
    func strength(at p: CGPoint) -> CGFloat {
        guard p.x >= 0, p.x <= 1, p.y >= 0, p.y <= 1 else { return 0 }
        let fx = p.x * CGFloat(width - 1)
        let fy = p.y * CGFloat(height - 1)
        let x0 = Int(fx); let y0 = Int(fy)
        let x1 = min(x0 + 1, width - 1); let y1 = min(y0 + 1, height - 1)
        let tx = fx - CGFloat(x0); let ty = fy - CGFloat(y0)
        func v(_ x: Int, _ y: Int) -> CGFloat { CGFloat(values[y * width + x]) }
        let top = v(x0, y0) * (1 - tx) + v(x1, y0) * tx
        let bot = v(x0, y1) * (1 - tx) + v(x1, y1) * tx
        return top * (1 - ty) + bot * ty
    }
}

// 从边缘参考图（CIEdges＋透明底，全图同尺寸）取 alpha 做 EdgeMap；
// 下采样到最长边 512 以内，采样与计算都轻。坐标与画布一致（左上原点 0-1）。
func edgeMap(from image: UIImage, maxSide: Int = 512) -> EdgeMap? {
    guard let cg = image.cgImage, cg.width > 0, cg.height > 0 else { return nil }
    let scale = min(1, CGFloat(maxSide) / CGFloat(max(cg.width, cg.height)))
    let w = max(1, Int(CGFloat(cg.width) * scale))
    let h = max(1, Int(CGFloat(cg.height) * scale))
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let data = ctx.data else { return nil }
    let bytes = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
    var values: [Float] = []
    values.reserveCapacity(w * h)
    for i in 0..<(w * h) {
        values.append(Float(bytes[i * 4 + 3]) / 255)
    }
    return EdgeMap(width: w, height: h, values: values)
}

// 单线贴合：每个锚点沿局部法线 ±radius 搜最强边缘，强度 ≥ threshold 才吸过去；
// 返回贴合后的线与吸动点数（吸动 < 0.002 视为未动）。
func snapLineToEdges(_ line: [CGPoint], edge: EdgeMap,
                     radius: CGFloat = 0.05, step: CGFloat = 0.004,
                     threshold: CGFloat = 0.30) -> (line: [CGPoint], moved: Int) {
    guard line.count >= 2 else { return (line, 0) }
    var out = line
    var moved = 0
    for i in line.indices {
        let prev = line[max(i - 1, 0)]
        let next = line[min(i + 1, line.count - 1)]
        var dx = next.x - prev.x; var dy = next.y - prev.y
        let len = (dx * dx + dy * dy).squareRoot()
        guard len > 0.001 else { continue }
        dx /= len; dy /= len
        let nx = -dy; let ny = dx
        let base = edge.strength(at: line[i])
        var bestT: CGFloat = 0
        var bestS = base
        var t = -radius
        while t <= radius + 0.0001 {
            let s = edge.strength(at: CGPoint(x: line[i].x + nx * t, y: line[i].y + ny * t))
            if s > bestS {
                bestS = s
                bestT = t
            }
            t += step
        }
        if bestS >= threshold, abs(bestT) > 0.002 {
            out[i] = CGPoint(x: line[i].x + nx * bestT, y: line[i].y + ny * bestT)
            moved += 1
        }
    }
    return (out, moved)
}

func snapPalmLines(_ lines: [[CGPoint]], edge: EdgeMap) -> (lines: [[CGPoint]], moved: [Int]) {
    var out: [[CGPoint]] = []
    var moved: [Int] = []
    for line in lines {
        let r = snapLineToEdges(line, edge: edge)
        out.append(r.line); moved.append(r.moved)
    }
    return (out, moved)
}

// MARK: - 掌纹参考描边（仅作视觉参考，不自动定线）
// 取掌区 ROI → CIEdges 提边缘 → 转透明底贴回全图同尺寸；界面以低透明度叠加，可开关。
func palmEdgeReferenceImage(from image: UIImage, joints: [String: CGPoint]) -> UIImage? {
    guard let cg = image.cgImage, !joints.isEmpty else { return nil }
    let xs = joints.values.map { $0.x }; let ys = joints.values.map { $0.y }
    guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return nil }
    let pad: CGFloat = 0.08
    let rx = max(minX - pad, 0); let ry = max(minY - pad, 0)
    let rw = min(maxX - minX + pad * 2, 1 - rx); let rh = min(maxY - minY + pad * 2, 1 - ry)
    let w = CGFloat(cg.width); let h = CGFloat(cg.height)
    let roi = CGRect(x: rx * w, y: ry * h, width: rw * w, height: rh * h)
    let ci = CIImage(cgImage: cg).cropped(to: roi)
    let edges = ci.applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 1.0])
        .applyingFilter("CIMaskToAlpha")
    let full = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0))
        .cropped(to: CGRect(x: 0, y: 0, width: w, height: h))
    let composed = edges.composited(over: full)
    let ctx = CIContext(options: nil)
    guard let out = ctx.createCGImage(composed, from: CGRect(x: 0, y: 0, width: w, height: h)) else { return nil }
    return UIImage(cgImage: out, scale: image.scale, orientation: .up)
}

// MARK: - 面相五眼比例（纯函数，可单元测试）
// MediaPipe 478 点（左上原点 0-1）：左眼外角 33、内角 133；右眼内角 362、外角 263；
// 颧 234↔454。眼宽单位＝双眼眼宽均值；眼间距＝133↔362；面宽＝234↔454。
struct FiveEyesResult { var gapRatio: CGFloat; var faceRatio: CGFloat }

func fiveEyesRatios(points: [CGPoint]) -> FiveEyesResult? {
    guard points.count >= 478 else { return nil }
    func d(_ a: Int, _ b: Int) -> CGFloat {
        let dx = points[a].x - points[b].x; let dy = points[a].y - points[b].y
        return (dx * dx + dy * dy).squareRoot()
    }
    let eyeUnit = (d(33, 133) + d(263, 362)) / 2
    guard eyeUnit > 0.01 else { return nil }
    return FiveEyesResult(gapRatio: d(133, 362) / eyeUnit, faceRatio: d(234, 454) / eyeUnit)
}

// MARK: - 面相头姿矩阵（纯函数，可单元测试）
// 来源：MediaPipe FaceLandmarker 的 facialTransformationMatrixes（4x4，需
// options.outputFacialTransformationMatrixes = true 才输出）。矩阵把静态标准
// 脸模型映到当前脸（均匀缩放＋旋转＋平移，最后一行恒为 0 0 0 1）。
// 度量空间约定（官方 3D Face Transform 文档）：右手系，相机在原点朝 -Z，
// +X 朝画面右、+Y 朝上、+Z 朝向观者。旋转部分记 R = Rz(roll)·Ry(yaw)·Rx(pitch)，
// 则 roll = atan2(R[1][0], R[0][0])、yaw = atan2(-R[2][0], hypot(R[2][1], R[2][2]))、
// pitch = atan2(R[2][1], R[2][2])（0 起下标）。roll 为正＝头顶向画面左偏。
// 校验：图上眼线角 θ（33→263，左上原点 y 朝下，顺时针为正）应满足 roll ≈ -θ；
// 运行时两者差 > 0.35 rad 即以眼线为准（点位是图上几何真值，矩阵只是模型拟合）。
struct HeadPose { var roll: Double; var pitch: Double; var yaw: Double }

/// 从 3x3 旋转行（R[row][col]）分解头姿角；含均匀缩放时先按列归一化。零矩阵或形状不对返回 nil。
func headPoseAngles(rotationRows: [[Double]]) -> HeadPose? {
    guard rotationRows.count == 3, rotationRows.allSatisfy({ $0.count == 3 }) else { return nil }
    var r = rotationRows
    for c in 0..<3 {
        let len = (r[0][c] * r[0][c] + r[1][c] * r[1][c] + r[2][c] * r[2][c]).squareRoot()
        guard len > 1e-6 else { return nil }
        for row in 0..<3 { r[row][c] /= len }
    }
    let roll = atan2(r[1][0], r[0][0])
    let yaw = atan2(-r[2][0], (r[2][1] * r[2][1] + r[2][2] * r[2][2]).squareRoot())
    let pitch = atan2(r[2][1], r[2][2])
    return HeadPose(roll: roll, pitch: pitch, yaw: yaw)
}

/// 从 MediaPipe 变换矩阵取左上 3x3 旋转行；非 4x4 返回 nil。
func rotationRows(of matrix: TransformMatrix) -> [[Double]]? {
    guard matrix.rows == 4, matrix.columns == 4 else { return nil }
    var rows: [[Double]] = []
    for row in 0..<3 {
        var line: [Double] = []
        for col in 0..<3 { line.append(Double(matrix.value(atRow: UInt(row), column: UInt(col)))) }
        rows.append(line)
    }
    return rows
}

/// 眼线 roll（与矩阵同一约定）：33→263 眼线角 θ 的负值。点数不足或眼距过小返回 nil。
func eyeLineRoll(points: [CGPoint]) -> Double? {
    guard points.count >= 478 else { return nil }
    let dx = points[263].x - points[33].x
    let dy = points[263].y - points[33].y
    guard (dx * dx + dy * dy).squareRoot() > 0.01 else { return nil }
    return -atan2(dy, dx)
}

/// 把点绕 center 旋转 angle（左上原点 y 朝下；angle 为正＝画面上顺时针）。
/// 头姿校正时传矩阵 roll：roll 为正＝头顶向画面左偏，正好把脸转回正。
func derotatePoints(_ points: [CGPoint], angle: Double, center: CGPoint) -> [CGPoint] {
    let c = cos(angle); let s = sin(angle)
    return points.map { p in
        let dx = p.x - center.x; let dy = p.y - center.y
        return CGPoint(x: center.x + dx * c - dy * s, y: center.y + dx * s + dy * c)
    }
}

/// Vision 76 点四区（Vision 归一化坐标，左下原点），供头姿校正第二遍使用。
struct VisionFaceRegions {
    var leftEyebrow: [CGPoint]; var rightEyebrow: [CGPoint]
    var nose: [CGPoint]; var faceContour: [CGPoint]
}

/// 按头姿 roll 校正眉/鼻底/下颌三线：先把 Vision 点换到左上原点、绕鼻区中心
/// 转回正，再取各区底边（与原口径一致：原 lowestY 取 Vision 坐标最小 y，
/// 即图上最下一点，换到左上原点就是最大 y）。返回三线相对图高的分数。
func poseCorrectedFaceMarks(regions: VisionFaceRegions, roll: Double) -> (brow: Double, nose: Double, chin: Double)? {
    guard !regions.leftEyebrow.isEmpty, !regions.rightEyebrow.isEmpty,
          !regions.nose.isEmpty, !regions.faceContour.isEmpty else { return nil }
    func flip(_ pts: [CGPoint]) -> [CGPoint] { pts.map { CGPoint(x: $0.x, y: 1 - $0.y) } }
    let nosePts = flip(regions.nose)
    let cx = nosePts.map { $0.x }.reduce(CGFloat(0), +) / CGFloat(nosePts.count)
    let cy = nosePts.map { $0.y }.reduce(CGFloat(0), +) / CGFloat(nosePts.count)
    let center = CGPoint(x: cx, y: cy)
    func bottomY(_ pts: [CGPoint]) -> CGFloat? {
        derotatePoints(flip(pts), angle: roll, center: center).map { $0.y }.max()
    }
    guard let lb = bottomY(regions.leftEyebrow), let rb = bottomY(regions.rightEyebrow),
          let n = bottomY(regions.nose), let c = bottomY(regions.faceContour) else { return nil }
    return (brow: Double((lb + rb) / 2), nose: Double(n), chin: Double(c))
}

/// 头姿提示行（度数取整）：侧倾已按矩阵/眼线校正；yaw/pitch 只按幅值提示，不改判定。
func poseSummaryText(pose: HeadPose, appliedRoll: Double, rollSource: String) -> String {
    func deg(_ r: Double) -> Int { Int((r * 180 / Double.pi).rounded()) }
    var text = "头姿：侧倾 \(deg(appliedRoll))°（\(rollSource)校正）· 转头 \(deg(pose.yaw))° · 俯仰 \(deg(pose.pitch))°"
    if abs(pose.yaw) > 0.26 { text += "；侧转较大，五眼比值仅供参考，请转正脸重拍" }
    if abs(pose.pitch) > 0.35 { text += "；低头/抬头较大，三停比例可能失真" }
    return text
}

// MARK: - 手相测量
struct HandMeasure {
    var palmLen: Double; var palmWidth: Double
    var indexLen: Double; var ringLen: Double; var middleLen: Double
    var palmType: String; var ratio24: Double
}

struct HandMeasureView: View {
    @StateObject private var box = PhotoBox()
    @State private var item: PhotosPickerItem?
    @State private var joints: [String: CGPoint] = [:]   // Vision 归一化（左下原点）
    @State private var jointConf: [String: Float] = [:]
    @State private var measure: HandMeasure?
    @State private var note = ""
    @State private var tiltNote = ""
    @State private var lineAuto: [Bool] = [true, true, true]  // 该线仍为自动落位（未拖过）
    @State private var showEdgeRef = false
    @State private var edgeImage: UIImage?
    @State private var edgeMap: EdgeMap?
    @State private var lineSnapped: [Bool] = [false, false, false]
    // 可编辑三线（画布相对坐标，左上原点 0-1）：感情/智慧/生命各 4 控制点
    @State private var lines: [[CGPoint]] = [
        [CGPoint(x: 0.16, y: 0.30), CGPoint(x: 0.38, y: 0.27), CGPoint(x: 0.62, y: 0.27), CGPoint(x: 0.84, y: 0.30)],
        [CGPoint(x: 0.14, y: 0.44), CGPoint(x: 0.38, y: 0.45), CGPoint(x: 0.62, y: 0.48), CGPoint(x: 0.82, y: 0.54)],
        [CGPoint(x: 0.30, y: 0.36), CGPoint(x: 0.24, y: 0.55), CGPoint(x: 0.30, y: 0.74), CGPoint(x: 0.48, y: 0.88)],
    ]
    @State private var selectedLine = 0
    @State private var personName = ""
    init(personName: String = "") { _personName = State(initialValue: personName) }
    @State private var savedTip = false
    private let lineCards = [
        "感情线看情感表达的方式：走向、深浅、终点位置三项，须以你修正后的描线为准细读。",
        "智慧线看思维与决断的方式：起止、倾斜、长短三项，须以你修正后的描线为准细读。",
        "生命线看体力与生活节奏的纹路：弧度、包围范围、清晰度三项，须以你修正后的描线为准细读；与寿命长短无关。",
    ]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if box.image == nil { palmGuideCard }
                PhotosPicker(selection: $item, matching: .images) {
                    Label(box.image == nil ? "选一张手掌照片" : "换一张照片", systemImage: "photo")
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Ky.card).clipShape(RoundedRectangle(cornerRadius: 12))
                }
                if let img = box.image {
                    FittedImage(image: img) { rect in
                        ZStack(alignment: .topLeading) {
                            if showEdgeRef, let edge = edgeImage {
                                Image(uiImage: edge).resizable()
                                    .frame(width: rect.width, height: rect.height)
                                    .position(x: rect.midX, y: rect.midY).opacity(0.55)
                            }
                            editableLines(rect)
                        }
                    }.frame(height: 380).background(Ky.card).clipShape(RoundedRectangle(cornerRadius: 12))
                    lineChips
                    if selectedLine >= 0 {
                        Text(lineCards[selectedLine].scriptConverted).font(.caption).foregroundStyle(Ky.ink)
                            .padding(12).background(Ky.card).clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                if !note.isEmpty { Text(note.scriptConverted).font(.caption).foregroundStyle(Ky.cinnabar) }
                if !tiltNote.isEmpty { Text(tiltNote.scriptConverted).font(.caption).foregroundStyle(Ky.cinnabar) }
                if let m = measure { measureCard(m) }
                if box.image != nil && measure != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("姓名（按人归档）", text: $personName)
                            .textFieldStyle(.roundedBorder)
                        Button(savedTip ? "已保存到测量记录" : "保存记录（照片＋描线＋测量值）") {
                            let flat = lines.flatMap { $0.flatMap { [$0.x, $0.y] } }
                            let mm = measure!; let sum = "\(mm.palmType)；掌宽/掌长 \(String(format: "%.2f", mm.palmWidth / mm.palmLen))；食指/无名指 \(String(format: "%.2f", mm.ratio24))"
                            Task { @MainActor in
                                PalmRecordStore().add(PalmRecord(personName: personName, kind: "手相",
                                                                 summary: sum, linesFlat: flat.map { Double($0) }),
                                                      image: box.image)
                                savedTip = true
                            }
                        }.buttonStyle(KyPrimaryButton()).disabled(savedTip)
                    }
                    .kyCard()
                }
                Text("测量口径：视觉识别 21 点关节点几何（学术同款管线在本工作室已实测）；三线先按手自动落位、再沿掌纹边缘贴合，贴合不上的请拖动圆点对准真实掌纹，描准了判读才有意义。娱乐参考。".scriptConverted)
                    .font(.caption2).foregroundStyle(Ky.sub)
            }.padding(16).padding(.bottom, 100)
        }
        .background(Ky.bg)
        .navigationTitle("手相 · 测量与描线".scriptConverted)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: item) { _, new in Task { @MainActor in await box.load(new); detect() } }
    }

    private var palmGuideCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("拍之前先对一下".scriptConverted).font(.system(.subheadline, design: .serif)).fontWeight(.semibold).foregroundStyle(Ky.ink)
            Text("掌心正对镜头 · 五指自然张开 · 手放画面中央 · 背景干净".scriptConverted).font(.caption).foregroundStyle(Ky.ink)
            Text("选图后三条线会按识别到的手自动落到掌心上、再贴合真实掌纹，贴不上的拖动圆点对准；手太斜或识别不稳时会提示重拍。".scriptConverted).font(.caption2).foregroundStyle(Ky.sub)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        .background(Ky.card).clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Ky.gold.opacity(0.6), style: StrokeStyle(lineWidth: 1.2, dash: [6, 4])))
    }

    private var lineChips: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                KyFilterBar(options: [(title: "感情线", count: nil), (title: "智慧线", count: nil), (title: "生命线", count: nil)], selectedIndex: $selectedLine)
                Button((showEdgeRef ? "参考纹路：开" : "参考纹路：关").scriptConverted) { showEdgeRef.toggle() }
                    .font(.caption2).padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Ky.card).clipShape(Capsule())
                if edgeMap != nil {
                    Button("重新贴合".scriptConverted) { resnap() }
                        .font(.caption2).padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Ky.card).clipShape(Capsule())
                }
            }
            Text(lineSnapped[selectedLine] ? "已贴合真实掌纹 · 拖动圆点可修正".scriptConverted : (lineAuto[selectedLine] ? "示意线（已按手自动落位）· 拖动圆点修正".scriptConverted : "已修正 · 拖动圆点可继续调整".scriptConverted))
                .font(.caption2).foregroundStyle(Ky.sub)
        }
    }

    private func editableLines(_ rect: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            Canvas { ctx, _ in
                for (li, line) in lines.enumerated() {
                    var path = Path()
                    let sampled = smoothLinePoints(line)
                    for (k, pt) in sampled.enumerated() {
                        let v = CGPoint(x: rect.minX + pt.x * rect.width, y: rect.minY + pt.y * rect.height)
                        if k == 0 { path.move(to: v) } else { path.addLine(to: v) }
                    }
                    ctx.stroke(path, with: .color(li == selectedLine ? Ky.cinnabar : Ky.gold.opacity(0.75)),
                               lineWidth: li == selectedLine ? 2.4 : 1.6)
                }
            }
            ForEach(lines[selectedLine].indices, id: \.self) { pi in
                let pt = lines[selectedLine][pi]
                Circle().fill(Ky.cinnabar).frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .position(x: rect.minX + pt.x * rect.width, y: rect.minY + pt.y * rect.height)
                    .gesture(DragGesture(coordinateSpace: .named("fittedCanvas")).onChanged { v in
                        let nx = min(max((v.location.x - rect.minX) / rect.width, 0), 1)
                        let ny = min(max((v.location.y - rect.minY) / rect.height, 0), 1)
                        lines[selectedLine][pi] = CGPoint(x: nx, y: ny)
                        lineAuto[selectedLine] = false
                    })
            }
        }
    }

    // 手动重新贴合：以当前线位为起点再吸一次真实掌纹（会覆盖拖动，需用户主动点）
    private func resnap() {
        guard let map = edgeMap else { return }
        let r = snapPalmLines(lines, edge: map)
        lines = r.lines
        lineSnapped = r.moved.map { $0 > 0 }
        lineAuto = [true, true, true]
    }

    private func measureCard(_ m: HandMeasure) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("测量结果".scriptConverted).font(.system(.subheadline, design: .serif)).fontWeight(.semibold).foregroundStyle(Ky.ink)
            Text("掌型：\(m.palmType)（掌宽/掌长 \(String(format: "%.2f", m.palmWidth / m.palmLen))）")
                .font(.callout).foregroundStyle(Ky.ink)
            Text("中指/掌长 \(String(format: "%.2f", m.middleLen / m.palmLen)) · 食指/无名指 \(String(format: "%.2f", m.ratio24))（\(m.ratio24 >= 1 ? "食指不短于无名指".scriptConverted : "无名指长于食指".scriptConverted)）")
                .font(.callout).foregroundStyle(Ky.ink)
            Text("判读要点（按相书通说，娱乐参考）：掌型定大框架——方掌重实际与秩序，长掌重感受与想象；指长比看行事风格的细腻度。细读须结合修正后的三线。".scriptConverted)
                .font(.caption).foregroundStyle(Ky.sub)
        }
        .kyCard()
    }

    private func detect() {
        joints = [:]; jointConf = [:]; measure = nil; note = ""; tiltNote = ""; edgeImage = nil
        edgeMap = nil; lineSnapped = [false, false, false]
        lineAuto = [true, true, true]
        guard let cg = box.image?.cgImage else { return }
        let req = VNDetectHumanHandPoseRequest()
        req.maximumHandCount = 1
        do {
            try VNImageRequestHandler(cgImage: cg, options: [:]).perform([req])
            guard let obs = req.results?.first else { note = "没识别到手：请用掌心正对镜头、五指自然张开、光线均匀的照片重试。"; return }
            let names: [(String, VNHumanHandPoseObservation.JointName)] = [
                ("wrist", .wrist), ("thumbCMC", .thumbCMC), ("thumbMP", .thumbMP), ("thumbIP", .thumbIP), ("thumbTip", .thumbTip),
                ("indexMCP", .indexMCP), ("indexPIP", .indexPIP), ("indexDIP", .indexDIP), ("indexTip", .indexTip),
                ("middleMCP", .middleMCP), ("middlePIP", .middlePIP), ("middleDIP", .middleDIP), ("middleTip", .middleTip),
                ("ringMCP", .ringMCP), ("ringPIP", .ringPIP), ("ringDIP", .ringDIP), ("ringTip", .ringTip),
                ("littleMCP", .littleMCP), ("littlePIP", .littlePIP), ("littleDIP", .littleDIP), ("littleTip", .littleTip),
            ]
            var found: [String: CGPoint] = [:]
            var conf: [String: Float] = [:]
            for (key, joint) in names {
                if let p = try? obs.recognizedPoint(joint), p.confidence > 0.3 { found[key] = p.location; conf[key] = p.confidence }
            }
            joints = found; jointConf = conf
            let required = ["wrist", "middleMCP", "indexMCP", "littleMCP", "thumbCMC"]
            let haveAll = required.allSatisfy { found[$0] != nil }
            let meanConf = required.compactMap { conf[$0] }.reduce(Float(0), +) / Float(required.count)
            if haveAll, meanConf >= 0.6, let anchored = anchoredPalmLines(joints: found) {
                lines = anchored
                lineAuto = [true, true, true]
            } else {
                note = "关节点不全或识别不稳：三线用了缺省位置，请拖动圆点对准真实掌纹，或换一张更清晰的照片重试。".scriptConverted
            }
            if let f = palmFrame(joints: found) {
                let deg = atan2(f.u.dx, f.u.dy) * 180 / .pi
                if abs(deg) > 25 { tiltNote = "手有点斜（约 \(Int(abs(deg)))°），线已按手的方向落位；想更准可以重拍一张摆正的。".scriptConverted }
            }
            if let img = box.image, !found.isEmpty {
                Task.detached {
                    let edge = palmEdgeReferenceImage(from: img, joints: found)
                    let map = edge.flatMap { Kanyu.edgeMap(from: $0) }
                    await MainActor.run {
                        edgeImage = edge
                        edgeMap = map
                        // 识别刚落位、用户还没拖动时，把模板锚点贴合到真实掌纹上
                        if let map, lineAuto == [true, true, true] {
                            let r = snapPalmLines(lines, edge: map)
                            lines = r.lines
                            lineSnapped = r.moved.map { $0 > 0 }
                        }
                    }
                }
            }
            guard let w = found["wrist"], let mm = found["middleMCP"], let mt = found["middleTip"],
                  let im = found["indexMCP"], let it = found["indexTip"],
                  let rm = found["ringMCP"], let rt = found["ringTip"], let lm = found["littleMCP"] else {
                note = "关节点不全：换一张手指完整入镜的照片重试。"; return
            }
            let aspect = Double(cg.width) / Double(cg.height)
            func d(_ a: CGPoint, _ b: CGPoint) -> Double {
                let dx = (a.x - b.x) * aspect; let dy = a.y - b.y
                return (dx * dx + dy * dy).squareRoot()
            }
            let palmLen = d(w, mm); let palmWidth = d(im, lm)
            let ratio = palmWidth / palmLen
            let type = ratio >= 0.95 ? "方掌（土型倾向）" : (ratio <= 0.85 ? "长掌（水型倾向）" : "混合掌")
            measure = HandMeasure(palmLen: palmLen, palmWidth: palmWidth,
                                  indexLen: d(im, it), ringLen: d(rm, rt), middleLen: d(mm, mt),
                                  palmType: type, ratio24: d(im, it) / d(rm, rt))
        } catch {
            note = "识别失败：换一张照片重试。"
        }
    }
}

// MARK: - 面相三停（标线手动校准）
struct FaceMeasureView: View {
    @StateObject private var box = PhotoBox()
    @State private var item: PhotosPickerItem?
    @State private var personName = ""
    init(personName: String = "") { _personName = State(initialValue: personName) }
    @State private var savedTip = false
    @State private var marks: [Double] = [0.14, 0.40, 0.63, 0.93]  // 发际/眉/鼻底/下颌（相对图高）
    @State private var markAuto: [Bool] = [false, false, false, false]
    @State private var hairEstimated = false
    @State private var faceNote = ""
    @State private var fiveEyes: FiveEyesResult?
    @State private var visionRegions: VisionFaceRegions?
    @State private var visionRollGated = false
    @State private var headPose: HeadPose?
    @State private var poseNote = ""
    private let labels = ["发际线", "眉线", "鼻底", "下颌"]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                PhotosPicker(selection: $item, matching: .images) {
                    Label(box.image == nil ? "选一张正面照片" : "换一张照片", systemImage: "photo")
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Ky.card).clipShape(RoundedRectangle(cornerRadius: 12))
                }
                if let img = box.image {
                    FittedImage(image: img) { rect in
                        ZStack(alignment: .topLeading) {
                            ForEach(marks.indices, id: \.self) { i in
                                let y = rect.minY + marks[i] * rect.height
                                Rectangle().fill(i == 0 || i == 3 ? Ky.cinnabar : Ky.gold)
                                    .frame(width: rect.width, height: 1.6).position(x: rect.midX, y: y)
                                Text((labels[i] + markSuffix(i)).scriptConverted).font(.caption2).foregroundStyle(Ky.ink)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Ky.card.opacity(0.85)).clipShape(Capsule())
                                    .position(x: rect.minX + 30, y: y - 9)
                                    .gesture(DragGesture(coordinateSpace: .named("fittedCanvas")).onChanged { v in
                                        marks[i] = min(max((v.location.y - rect.minY) / rect.height, 0.02), 0.98)
                                        markAuto[i] = false
                                        if i == 0 { hairEstimated = false }
                                    })
                            }
                        }
                    }.frame(height: 380).background(Ky.card).clipShape(RoundedRectangle(cornerRadius: 12))
                    resultCard
                    if let fe = fiveEyes { fiveEyesCard(fe) }
                    if !poseNote.isEmpty { Text(poseNote.scriptConverted).font(.caption).foregroundStyle(Ky.sub) }
                    if !faceNote.isEmpty { Text(faceNote.scriptConverted).font(.caption).foregroundStyle(Ky.cinnabar) }
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("姓名（按人归档）", text: $personName)
                            .textFieldStyle(.roundedBorder)
                        Button(savedTip ? "已保存到测量记录" : "保存记录（照片＋三停比例）") {
                            let up = marks[1] - marks[0]; let mid = marks[2] - marks[1]; let low = marks[3] - marks[2]
                            let t = up + mid + low
                            let sum = String(format: "三停 上 %.0f%% · 中 %.0f%% · 下 %.0f%%",
                                             t > 0 ? up / t * 100 : 0, t > 0 ? mid / t * 100 : 0, t > 0 ? low / t * 100 : 0)
                            Task { @MainActor in
                                PalmRecordStore().add(PalmRecord(personName: personName, kind: "面相", summary: sum),
                                                      image: box.image)
                                savedTip = true
                            }
                        }.buttonStyle(KyPrimaryButton()).disabled(savedTip)
                    }
                    .kyCard()
                }
                Text("校准口径：眉/鼻底/下颌由识别自动标线，发际线为模型估计或手动拖准（儿童发际未定型更要人工校正）；三停比例为几何事实，判读按相书通说、娱乐参考，不套成人断语于儿童。".scriptConverted)
                    .font(.caption2).foregroundStyle(Ky.sub)
            }.padding(16).padding(.bottom, 100)
        }
        .background(Ky.bg)
        .navigationTitle("面相 · 三停校准".scriptConverted)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: item) { _, new in Task { @MainActor in await box.load(new); detectFace() } }
    }

    private func markSuffix(_ i: Int) -> String {
        if i == 0 && hairEstimated && markAuto[0] { return "·估计" }
        return markAuto[i] ? "·自动" : "·手动"
    }

    // 面相自动标线：Vision Rev 3（76 点）算眉/鼻底/下颌，发际线 Vision 没有，仍手动；
    // 再用 MediaPipe 478 点补五眼，并以 10 号点作发际线估计（标“估计”）。
    // 第二遍（runMediaPipeFace）：取 MediaPipe 头姿矩阵 roll，把 Vision 四区与 478 点
    // 转回正后再算三线与五眼；头太歪时第一遍不标线，等矩阵来救，矩阵也拿不到才提示重拍。
    private func detectFace() {
        faceNote = ""; markAuto = [false, false, false, false]; hairEstimated = false; fiveEyes = nil
        headPose = nil; poseNote = ""; visionRegions = nil; visionRollGated = false
        guard let cg = box.image?.cgImage else { return }
        let req = VNDetectFaceLandmarksRequest()
        req.constellation = .constellation76Points
        let qReq = VNDetectFaceCaptureQualityRequest()
        do {
            try VNImageRequestHandler(cgImage: cg, options: [:]).perform([req, qReq])
            if let q = qReq.results?.first, let quality = q.faceCaptureQuality, quality < 0.5 {
                faceNote = "照片质量偏低（光线/模糊），建议补光重拍；已尽量自动标线，请拖动核对。".scriptConverted
            }
            guard let obs = req.results?.first, let lm = obs.landmarks else {
                faceNote = "没识别到人脸：请用正面、五官完整、无遮挡的照片重试。".scriptConverted
                return
            }
            visionRegions = VisionFaceRegions(
                leftEyebrow: lm.leftEyebrow?.normalizedPoints ?? [],
                rightEyebrow: lm.rightEyebrow?.normalizedPoints ?? [],
                nose: lm.nose?.normalizedPoints ?? [],
                faceContour: lm.faceContour?.normalizedPoints ?? [])
            if let roll = obs.roll?.doubleValue, abs(roll) > 0.26 { visionRollGated = true }
            if !visionRollGated {
                func lowestY(_ region: VNFaceLandmarkRegion2D?) -> CGFloat? {
                    guard let pts = region?.normalizedPoints, !pts.isEmpty else { return nil }
                    return pts.map { $0.y }.min()
                }
                if let lb = lowestY(lm.leftEyebrow), let rb = lowestY(lm.rightEyebrow) {
                    marks[1] = Double(1 - (lb + rb) / 2); markAuto[1] = true
                }
                if let n = lowestY(lm.nose) { marks[2] = Double(1 - n); markAuto[2] = true }
                if let c = lowestY(lm.faceContour) { marks[3] = Double(1 - c); markAuto[3] = true }
            }
            runMediaPipeFace()
        } catch {
            faceNote = "人脸识别失败：换一张照片重试。".scriptConverted
        }
    }

    private func runMediaPipeFace() {
        guard let img = box.image else { return }
        let regions = visionRegions
        let gated = visionRollGated
        Task.detached {
            guard let modelPath = Bundle.main.path(forResource: "face_landmarker", ofType: "task") else {
                await MainActor.run { if gated { faceNote = "头有点歪，自动标线可能不准；建议摆正重拍，或手动拖动核对。".scriptConverted } }
                return
            }
            do {
                let options = FaceLandmarkerOptions()
                options.baseOptions.modelAssetPath = modelPath
                options.runningMode = .image
                options.numFaces = 1
                options.outputFacialTransformationMatrixes = true
                let landmarker = try FaceLandmarker(options: options)
                let mpImage = try MPImage(uiImage: img)
                let result = try landmarker.detect(image: mpImage)
                guard let points = result.faceLandmarks.first, points.count >= 478 else {
                    await MainActor.run { if gated { faceNote = "头有点歪，自动标线可能不准；建议摆正重拍，或手动拖动核对。".scriptConverted } }
                    return
                }
                let pts = points.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
                // 头姿：矩阵为主，眼线交叉核对；矩阵缺失时退到眼线，仍可校正 roll。
                var pose: HeadPose?
                if let m = result.facialTransformationMatrixes.first, let rows = rotationRows(of: m) {
                    pose = headPoseAngles(rotationRows: rows)
                }
                let eyeRoll = eyeLineRoll(points: pts)
                var appliedRoll: Double?
                var rollSource = ""
                if let pr = pose?.roll, let er = eyeRoll, abs(pr - er) > 0.35 {
                    appliedRoll = er; rollSource = "眼线"
                } else if let pr = pose?.roll {
                    appliedRoll = pr; rollSource = "矩阵"
                } else {
                    appliedRoll = eyeRoll; rollSource = "眼线"
                }
                let fixed = appliedRoll.map { derotatePoints(pts, angle: $0, center: pts[1]) } ?? pts
                let ratios = fiveEyesRatios(points: fixed)
                let hairY = fixed[10].y
                let corrected = appliedRoll.flatMap { r in regions.flatMap { poseCorrectedFaceMarks(regions: $0, roll: r) } }
                await MainActor.run {
                    if let r = ratios { fiveEyes = r }
                    marks[0] = Double(hairY); markAuto[0] = true; hairEstimated = true
                    if let c = corrected {
                        if markAuto[1] || gated {
                            marks[1] = c.brow
                            markAuto[1] = true
                        }
                        if markAuto[2] || gated {
                            marks[2] = c.nose
                            markAuto[2] = true
                        }
                        if markAuto[3] || gated {
                            marks[3] = c.chin
                            markAuto[3] = true
                        }
                    }
                    if let p = pose, let ar = appliedRoll {
                        headPose = p
                        poseNote = poseSummaryText(pose: p, appliedRoll: ar, rollSource: rollSource)
                    } else if let ar = appliedRoll {
                        poseNote = "头姿矩阵未输出，已按眼线校正侧倾 \(Int((ar * 180 / Double.pi).rounded()))°"
                    }
                }
            } catch {
                // 静默回退：Vision 标线已在位，发际线保持手动；头歪被门控时才提示重拍
                await MainActor.run { if gated { faceNote = "头有点歪，自动标线可能不准；建议摆正重拍，或手动拖动核对。".scriptConverted } }
            }
        }
    }

    private func fiveEyesCard(_ fe: FiveEyesResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("五眼比例".scriptConverted).font(.system(.subheadline, design: .serif)).fontWeight(.semibold).foregroundStyle(Ky.ink)
            Text(String(format: "眼间距 %.1f 眼宽 · 面宽 %.1f 眼宽", fe.gapRatio, fe.faceRatio))
                .font(KyV2.tabular(15)).foregroundStyle(Ky.ink)
            Text("五眼口径：眼间距约 1 眼宽、面宽约 5 眼宽为传统参照；只报比值，不作美丑评判，须结合五官逐项看。".scriptConverted)
                .font(.caption).foregroundStyle(Ky.sub)
        }
        .kyCard()
    }

    private var resultCard: some View {
        let up = marks[1] - marks[0]; let mid = marks[2] - marks[1]; let low = marks[3] - marks[2]
        let total = up + mid + low
        let p = [up, mid, low].map { total > 0 ? $0 / total * 100 : 0 }
        return VStack(alignment: .leading, spacing: 6) {
            Text("三停比例".scriptConverted).font(.system(.subheadline, design: .serif)).fontWeight(.semibold).foregroundStyle(Ky.ink)
            Text(String(format: "上停 %.0f%% · 中停 %.0f%% · 下停 %.0f%%", p[0], p[1], p[2]))
                .font(KyV2.tabular(15)).foregroundStyle(Ky.ink)
            Text(abs(p[0] - 33) <= 5 && abs(p[1] - 33) <= 5 && abs(p[2] - 33) <= 5
                 ? "三停接近均等：面部比例匀称（相书谓三停平等、五岳丰盈者福相）。".scriptConverted
                 : "三停不均：以最长一停为主象细读——上停主早年与额相，中停主中年与鼻相，下停主晚年与地阁；须结合五官逐项看，不单凭比例下断。".scriptConverted)
                .font(.caption).foregroundStyle(Ky.sub)
        }
        .kyCard()
    }
}

// MARK: - 测量记录（描线资产化：照片＋修正点位＋测量值全部落盘，按人归档）
struct PalmRecord: Codable, Identifiable {
    var id: UUID = UUID()
    var personName: String
    var kind: String                    // 手相 / 面相
    var createdEpoch: Double = Date().timeIntervalSince1970
    var summary: String                 // 测量摘要（掌型/指比 或 三停比例）
    var linesFlat: [Double] = []        // 手相三线控制点（归一化 x,y 交错）
    var photoFile: String = ""          // Documents/PalmPhotos/<id>.jpg
}

struct PalmExport: Codable { var schemaVersion: Int; var records: [PalmRecord] }

@MainActor
final class PalmRecordStore: ObservableObject {
    @Published var records: [PalmRecord] = []
    private var dir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PalmPhotos", isDirectory: true)
    }
    private var indexURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("palm_records.json")
    }
    init() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexURL) {
            if let list = try? JSONDecoder().decode([PalmRecord].self, from: data) { records = list }
            else { try? FileManager.default.copyItem(at: indexURL, to: indexURL.deletingPathExtension().appendingPathExtension("corrupt.json")) }
        }
    }
    func save() {
        do {
            let data = try JSONEncoder().encode(records)
            try data.write(to: indexURL, options: .atomic)
            DataProtection.applyComplete(to: indexURL)
            StoreSchema.writeMeta(for: indexURL, count: records.count)
        } catch {
            AppErrorCenter.shared.report("手相测量记录保存失败，刚才的改动可能没存入：请重试，仍失败请先导出备份再联系助手。")
        }
    }
    func exportData() -> Data {
        (try? JSONEncoder().encode(PalmExport(schemaVersion: StoreSchema.current, records: records))) ?? Data()
    }
    func add(_ r: PalmRecord, image: UIImage?) {
        var rec = r
        if let img = image, let jpg = img.jpegData(compressionQuality: 0.85) {
            let f = "\(rec.id.uuidString).jpg"
            try? jpg.write(to: dir.appendingPathComponent(f))
            rec.photoFile = f
        }
        records.insert(rec, at: 0); save()
    }
    func image(of r: PalmRecord) -> UIImage? {
        guard !r.photoFile.isEmpty else { return nil }
        return UIImage(contentsOfFile: dir.appendingPathComponent(r.photoFile).path)
    }
    func remove(_ r: PalmRecord) {
        if !r.photoFile.isEmpty { try? FileManager.default.removeItem(at: dir.appendingPathComponent(r.photoFile)) }
        records.removeAll { $0.id == r.id }; save()
    }
    func records(for name: String) -> [PalmRecord] { records.filter { $0.personName == name } }
}

struct PalmRecordListView: View {
    @StateObject private var store = PalmRecordStore()
    @State private var exportCache: URL?
    // UI 2.1 第6批：删除测量记录须确认（照片文件随记录删，照片原件不在备份包内）
    @State private var pendingDeleteRecord: PalmRecord? = nil
    @State private var showDeleteConfirm = false
    var body: some View {
        List {
            if store.records.isEmpty {
                KyEmptyState(icon: "archivebox", title: "还没有记录", message: "在手相/面相测量页填上姓名、描准线条后点「保存记录」，描线和测量值会按人存档在这里。")
            }
            ForEach(store.records) { r in
                NavigationLink { PalmRecordDetailView(store: store, record: r) } label: {
                    HStack(spacing: 10) {
                        if let img = store.image(of: r) {
                            Image(uiImage: img).resizable().scaledToFill()
                                .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(r.personName.isEmpty ? "未命名" : r.personName) · \(r.kind)")
                                .font(.subheadline).fontWeight(.medium).foregroundStyle(Ky.ink)
                            Text(r.summary.scriptConverted).font(.caption).foregroundStyle(Ky.sub).lineLimit(1)
                        }
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        pendingDeleteRecord = r
                        showDeleteConfirm = true
                    } label: { Label("删除".scriptConverted, systemImage: "trash") }
                }
            }
        }
        .confirmationDialog("删除测量记录？".scriptConverted, isPresented: $showDeleteConfirm) {
            Button("删除".scriptConverted, role: .destructive) {
                if let r = pendingDeleteRecord { store.remove(r) }
                pendingDeleteRecord = nil
            }
            Button("取消".scriptConverted, role: .cancel) { pendingDeleteRecord = nil }
        } message: {
            if let r = pendingDeleteRecord {
                Text("将删除「\(r.personName.isEmpty ? "未命名" : r.personName)」的测量记录，照片文件随记录一并删除，照片原件不在备份包内。".scriptConverted)
            }
        }
        .navigationTitle("测量记录".scriptConverted)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let u = exportCache {
                    ShareLink(item: u) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("导出测量记录")
                } else {
                    Button {
                        let url = FileManager.default.temporaryDirectory.appendingPathComponent("palm-records-export.json")
                        try? store.exportData().write(to: url, options: .atomic)
                        exportCache = url
                    } label: { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("导出测量记录")
                }
            }
        }
    }
}

struct PalmRecordDetailView: View {
    @ObservedObject var store: PalmRecordStore
    let record: PalmRecord
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if let img = store.image(of: record) {
                    FittedImage(image: img) { rect in
                        Canvas { ctx, _ in
                            let flatN = record.linesFlat.count / 2 * 2
                            let pts = stride(from: 0, to: flatN, by: 2).map {
                                CGPoint(x: record.linesFlat[$0], y: record.linesFlat[$0 + 1])
                            }
                            // 三线各 4 点（保存时按线顺序拼接）
                            for li in 0..<3 {
                                let seg = Array(pts.dropFirst(li * 4).prefix(4))
                                guard seg.count == 4 else { continue }
                                var path = Path()
                                for (k, pt) in seg.enumerated() {
                                    let v = CGPoint(x: rect.minX + pt.x * rect.width, y: rect.minY + pt.y * rect.height)
                                    if k == 0 { path.move(to: v) } else { path.addLine(to: v) }
                                }
                                ctx.stroke(path, with: .color(Ky.gold), lineWidth: 1.8)
                            }
                        }
                    }.frame(height: 380).background(Ky.card).clipShape(RoundedRectangle(cornerRadius: 12))
                }
                Text(record.summary.scriptConverted).font(.callout).foregroundStyle(Ky.ink)
                NavigationLink { PalmPosterSheetView(record: record, store: store) } label: {
                    HStack(spacing: 6) {
                        KySettingsRow(icon: "photo.artframe", title: "生成鉴定海报", subtitle: "三线测量图 · 掌型指比／三停比例 · 相法综合断语", tint: Ky.gold)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Ky.sub)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(Ky.card)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Ky.line.opacity(0.9), lineWidth: 0.8))
                }.buttonStyle(.plain)
                Text("记录时间：\(Date(timeIntervalSince1970: record.createdEpoch).formatted(date: .abbreviated, time: .shortened)) · 描线为当时人工修正的点位，已冻结存档。".scriptConverted)
                    .font(.caption2).foregroundStyle(Ky.sub)
            }.padding(16).padding(.bottom, 100)
        }
        .background(Ky.bg)
        .navigationTitle("\(record.personName) · \(record.kind)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 手相面相鉴定海报（540 宽自适应长图：三线测量图＋掌型指比／三停比例＋相法综合断语）
struct PalmPosterView: View {
    let record: PalmRecord
    let image: UIImage?
    private let paper = Color(red: 0.968, green: 0.949, blue: 0.906)
    private let cardBg = Color(red: 0.992, green: 0.984, blue: 0.961)
    private let ink = Color(red: 0.18, green: 0.165, blue: 0.15)
    private let sub = Color(red: 0.46, green: 0.42, blue: 0.35)
    private let cin = Color(red: 0.604, green: 0.165, blue: 0.133)
    private let gold = Color(red: 0.78, green: 0.64, blue: 0.36)
    private var dateText: String {
        Date(timeIntervalSince1970: record.createdEpoch).formatted(date: .abbreviated, time: .omitted)
    }
    private var lineCards: [String] {
        [
            "感情线看情感表达的方式：走向、深浅、终点位置三项，须以你修正后的描线为准细读。",
            "智慧线看思维与决断的方式：起止、倾斜、长短三项，须以你修正后的描线为准细读。",
            "生命线看体力与生活节奏的纹路：弧度、包围范围、清晰度三项，须以你修正后的描线为准细读；与寿命长短无关。",
        ]
    }
    var body: some View {
        ZStack {
            LinearGradient(colors: [cardBg, paper], startPoint: .top, endPoint: .bottom)
            RoundedRectangle(cornerRadius: 4).stroke(cin.opacity(0.55), lineWidth: 1.1).padding(18)
            VStack(spacing: 0) {
                Text("手 相 面 相 鉴 定".scriptConverted)
                    .font(.system(size: 12, weight: .medium))
                    .tracking(4)
                    .foregroundStyle(cin)
                    .padding(.top, 48)
                Text(record.personName.isEmpty ? "未命名" : record.personName)
                    .font(.system(size: 40, weight: .bold, design: .serif))
                    .foregroundStyle(ink)
                    .padding(.top, 14)
                Text("\(record.kind) · \(dateText)")
                    .font(.system(size: 12)).foregroundStyle(sub).padding(.top, 6)
                HStack(spacing: 8) {
                    Rectangle().fill(cin.opacity(0.35)).frame(width: 140, height: 0.8)
                    Rectangle().fill(cin).frame(width: 5, height: 5).rotationEffect(.degrees(45))
                    Rectangle().fill(cin.opacity(0.35)).frame(width: 140, height: 0.8)
                }.padding(.vertical, 16)
                if let img = image {
                    FittedImage(image: img) { rect in
                        Canvas { ctx, _ in
                            let flatN = record.linesFlat.count / 2 * 2
                            let pts = stride(from: 0, to: flatN, by: 2).map {
                                CGPoint(x: record.linesFlat[$0], y: record.linesFlat[$0 + 1])
                            }
                            for li in 0..<3 {
                                let seg = Array(pts.dropFirst(li * 4).prefix(4))
                                guard seg.count == 4 else { continue }
                                var path = Path()
                                for (k, pt) in seg.enumerated() {
                                    let v = CGPoint(x: rect.minX + pt.x * rect.width, y: rect.minY + pt.y * rect.height)
                                    if k == 0 { path.move(to: v) } else { path.addLine(to: v) }
                                }
                                ctx.stroke(path, with: .color(gold), lineWidth: 2.0)
                            }
                        }
                    }
                    .frame(width: 444, height: 300)
                    .background(cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(cin.opacity(0.35), lineWidth: 0.8))
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("测量数据".scriptConverted)
                        .font(.system(size: 12.5, weight: .bold, design: .serif)).foregroundStyle(cin)
                    Text(record.summary.scriptConverted)
                        .font(.system(size: 12.5)).foregroundStyle(ink)
                        .lineSpacing(3.5).fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 444, alignment: .leading)
                .padding(.top, 18)
                VStack(alignment: .leading, spacing: 6) {
                    Text(record.kind == "手相" ? "三线断语".scriptConverted : "三停断语".scriptConverted)
                        .font(.system(size: 12.5, weight: .bold, design: .serif)).foregroundStyle(cin)
                    if record.kind == "手相" {
                        ForEach(lineCards, id: \.self) { t in
                            Text(t.scriptConverted)
                                .font(.system(size: 11.5)).foregroundStyle(ink)
                                .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        Text("三停比例为几何事实：上停看早年根基，中停看中年事业，下停看晚年归宿；判读按相书通说、娱乐参考，不套成人断语于儿童。".scriptConverted)
                            .font(.system(size: 11.5)).foregroundStyle(ink)
                            .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    }
                    Text("气色与相法古籍综合断语：相法以形定神、以神定气，掌纹观走势、面相观气色，皆为传统相法参考，不作定论、不落病名灾祸。".scriptConverted)
                        .font(.system(size: 11.5)).foregroundStyle(sub)
                        .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 444, alignment: .leading)
                .padding(.top, 16)
                Spacer()
                HStack(alignment: .bottom) {
                    Text("三术合参".scriptConverted)
                        .font(.system(size: 14, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(cin)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("传统相法参考 · 不作定论".scriptConverted)
                            .font(.system(size: 11, design: .serif)).foregroundStyle(cin)
                        Text(dateText)
                            .font(.system(size: 10)).foregroundStyle(sub.opacity(0.8))
                    }
                }
                .padding(.horizontal, 48).padding(.bottom, 42)
            }
        }
        .frame(width: 540)
    }
}

struct PalmPosterSheetView: View {
    let record: PalmRecord
    @ObservedObject var store: PalmRecordStore
    @State private var fileURL: URL?
    @State private var previewImage: UIImage?
    @State private var saveMessage: String?
    @State private var renderError: String?
    @State private var isRendering = false
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if let renderError {
                    VStack(spacing: 12) {
                        Label(renderError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Ky.cinnabar)
                            .multilineTextAlignment(.center)
                        Button("重新生成海报") { render() }
                            .buttonStyle(KyPrimaryButton())
                    }
                    .accessibilityElement(children: .contain)
                } else if let img = previewImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Ky.line, lineWidth: 0.8))
                } else if isRendering {
                    KyLoadingState(title: "正在渲染鉴定海报…")
                }
                if renderError == nil, fileURL != nil, let img = previewImage {
                    ShareLink(item: Image(uiImage: img), preview: SharePreview("手相面相鉴定海报", image: Image(uiImage: img))) {
                        Label("保存 / 分享鉴定海报（1080宽 · 自适应长图）".scriptConverted, systemImage: "square.and.arrow.down")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    .buttonStyle(KyPrimaryButton())
                    Button {
                        PosterPhotoSaver.save(img) { saveMessage = $0 }
                    } label: {
                        Label("保存到相册", systemImage: "photo.badge.plus")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    .buttonStyle(KyPrimaryButton())
                    if let saveMessage {
                        Text(saveMessage)
                            .font(.caption).foregroundStyle(Ky.sub).multilineTextAlignment(.center)
                    }
                    Text("分享单点「存储图像」可存入相册，或点「保存到相册」直接存入；也可以直接转发微信。".scriptConverted)
                        .font(.caption).foregroundStyle(Ky.sub).multilineTextAlignment(.center)
                }
            }
            .padding(20)
        }
        .background(Ky.bg)
        .navigationTitle("手相面相鉴定海报".scriptConverted).navigationBarTitleDisplayMode(.inline)
        .task { render() }
    }
    private func render() {
        guard !isRendering else { return }
        isRendering = true
        // Clear any previous successful share target before starting another render.
        fileURL = nil
        previewImage = nil
        renderError = nil
        saveMessage = nil
        let img = store.image(of: record)
        let view = PalmPosterView(record: record, image: img)
        Task { @MainActor in
            // ImageRenderer and SwiftUI view rendering are MainActor-isolated.
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2.0
            guard let out = renderer.uiImage, let data = out.pngData() else {
                renderError = "海报生成失败，请重试；没有保存任何文件。"
                isRendering = false
                return
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("palm-poster-\(record.id.uuidString).png")
            do {
                try data.write(to: url, options: .atomic)
                previewImage = out
                fileURL = url
            } catch {
                renderError = "海报写入失败，请检查设备剩余空间后重试。"
            }
            isRendering = false
        }
    }
}
