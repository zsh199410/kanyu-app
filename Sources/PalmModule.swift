// 手相面相模块（P4 提前量，2026-10-30）：
// 手相＝Vision 21 点几何测量（掌型/指长比可复核）＋可编辑标注层——掌纹是皮肤纹理，
// 任何检测框架都提不出掌线（调研定版），故三线走「预置线形＋逐点可拖修正」，修正值即资产。
// 面相＝三停标线手动校准（发际线必须人工，调研定版）。全程娱乐定性，不做疾病灾祸预测。
import SwiftUI
import PhotosUI
import Vision

struct PalmHomeView: View {
    var body: some View {
        List {
            NavigationLink { HandMeasureView() } label: {
                Label("手相 · 测量与描线", systemImage: "hand.raised")
            }
            NavigationLink { FaceMeasureView() } label: {
                Label("面相 · 三停校准", systemImage: "face.smiling")
            }
            NavigationLink { PalmRecordListView() } label: {
                Label("测量记录（按人存档）", systemImage: "archivebox")
            }
            Text("用法：手相用掌心正对、光线均匀的照片；面相用正面自然光、无美颜的照片。测量是几何事实，判读为娱乐参考。")
                .font(.caption).foregroundStyle(Ky.sub)
        }
        .navigationTitle("手相面相")
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
           let ui = UIImage(data: data) { image = ui }
    }
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
    @State private var measure: HandMeasure?
    @State private var note = ""
    // 可编辑三线（画布相对坐标，左上原点 0-1）：感情/智慧/生命各 4 控制点
    @State private var lines: [[CGPoint]] = [
        [CGPoint(x: 0.16, y: 0.30), CGPoint(x: 0.38, y: 0.27), CGPoint(x: 0.62, y: 0.27), CGPoint(x: 0.84, y: 0.30)],
        [CGPoint(x: 0.14, y: 0.44), CGPoint(x: 0.38, y: 0.45), CGPoint(x: 0.62, y: 0.48), CGPoint(x: 0.82, y: 0.54)],
        [CGPoint(x: 0.30, y: 0.36), CGPoint(x: 0.24, y: 0.55), CGPoint(x: 0.30, y: 0.74), CGPoint(x: 0.48, y: 0.88)],
    ]
    @State private var selectedLine = 0
    @State private var personName = ""
    @State private var savedTip = false
    private let lineNames = ["感情线", "智慧线", "生命线"]
    private let lineCards = [
        "感情线看情感表达的方式：走向、深浅、终点位置三项，须以你修正后的描线为准细读。",
        "智慧线看思维与决断的方式：起止、倾斜、长短三项，须以你修正后的描线为准细读。",
        "生命线看体力与生活节奏的纹路：弧度、包围范围、清晰度三项，须以你修正后的描线为准细读；与寿命长短无关。",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PhotosPicker(selection: $item, matching: .images) {
                    Label(box.image == nil ? "选一张手掌照片" : "换一张照片", systemImage: "photo")
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Ky.card).clipShape(RoundedRectangle(cornerRadius: 12))
                }
                if let img = box.image {
                    FittedImage(image: img) { rect in
                        ZStack(alignment: .topLeading) {
                            skeleton(rect)
                            editableLines(rect)
                        }
                    }.frame(height: 380).background(Ky.card).clipShape(RoundedRectangle(cornerRadius: 12))
                    lineChips
                    if selectedLine >= 0 {
                        Text(lineCards[selectedLine]).font(.caption).foregroundStyle(Ky.ink)
                            .padding(12).background(Ky.card).clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                if !note.isEmpty { Text(note).font(.caption).foregroundStyle(Ky.cinnabar) }
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
                Text("测量口径：Vision 21 点关节点几何（学术同款管线在本工作室已实测）；三线为手描修正层——把每个圆点拖到你真实掌纹上，描准了判读才有意义。娱乐参考。")
                    .font(.caption2).foregroundStyle(Ky.sub)
            }.padding(16)
        }
        .background(Ky.bg)
        .navigationTitle("手相 · 测量与描线")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: item) { _, new in Task { @MainActor in await box.load(new); detect() } }
    }

    private var lineChips: some View {
        HStack(spacing: 8) {
            ForEach(lineNames.indices, id: \.self) { i in
                Button { selectedLine = i } label: {
                    Text(lineNames[i]).font(.caption).fontWeight(selectedLine == i ? .semibold : .regular)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(selectedLine == i ? Ky.gold.opacity(0.22) : Ky.card)
                        .clipShape(Capsule())
                }.buttonStyle(.plain).foregroundStyle(Ky.ink)
            }
            Spacer()
            Text("拖动圆点修正").font(.caption2).foregroundStyle(Ky.sub)
        }
    }

    private func skeleton(_ rect: CGRect) -> some View {
        Canvas { ctx, _ in
            func p(_ name: String) -> CGPoint? {
                guard let v = joints[name] else { return nil }
                return CGPoint(x: rect.minX + v.x * rect.width, y: rect.minY + (1 - v.y) * rect.height)
            }
            let chains: [[String]] = [
                ["wrist", "thumbCMC", "thumbMP", "thumbIP", "thumbTip"],
                ["wrist", "indexMCP", "indexPIP", "indexDIP", "indexTip"],
                ["wrist", "middleMCP", "middlePIP", "middleDIP", "middleTip"],
                ["wrist", "ringMCP", "ringPIP", "ringDIP", "ringTip"],
                ["wrist", "littleMCP", "littlePIP", "littleDIP", "littleTip"],
                ["indexMCP", "middleMCP", "ringMCP", "littleMCP"],
            ]
            for chain in chains {
                var path = Path()
                for (k, name) in chain.enumerated() {
                    guard let pt = p(name) else { continue }
                    if k == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                }
                ctx.stroke(path, with: .color(Ky.jade.opacity(0.75)), lineWidth: 1.6)
            }
            for (_, v) in joints {
                let pt = CGPoint(x: rect.minX + v.x * rect.width, y: rect.minY + (1 - v.y) * rect.height)
                ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 2.6, y: pt.y - 2.6, width: 5.2, height: 5.2)),
                         with: .color(Ky.cinnabar))
            }
        }
    }

    private func editableLines(_ rect: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            Canvas { ctx, _ in
                for (li, line) in lines.enumerated() {
                    var path = Path()
                    for (k, pt) in line.enumerated() {
                        let v = CGPoint(x: rect.minX + pt.x * rect.width, y: rect.minY + pt.y * rect.height)
                        if k == 0 { path.move(to: v) } else { path.addLine(to: v) }
                    }
                    ctx.stroke(path, with: .color(li == selectedLine ? Ky.cinnabar : Ky.gold.opacity(0.75)),
                               lineWidth: li == selectedLine ? 2.4 : 1.6)
                }
            }
            ForEach(lines[selectedLine].indices, id: \.self) { pi in
                let pt = lines[selectedLine][pi]
                Circle().fill(Ky.cinnabar).frame(width: 18, height: 18)
                    .position(x: rect.minX + pt.x * rect.width, y: rect.minY + pt.y * rect.height)
                    .gesture(DragGesture(coordinateSpace: .named("fittedCanvas")).onChanged { v in
                        let nx = min(max((v.location.x - rect.minX) / rect.width, 0), 1)
                        let ny = min(max((v.location.y - rect.minY) / rect.height, 0), 1)
                        lines[selectedLine][pi] = CGPoint(x: nx, y: ny)
                    })
            }
        }
    }

    private func measureCard(_ m: HandMeasure) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("测量结果").font(.system(.subheadline, design: .serif)).fontWeight(.semibold).foregroundStyle(Ky.ink)
            Text("掌型：\(m.palmType)（掌宽/掌长 \(String(format: "%.2f", m.palmWidth / m.palmLen))）")
                .font(.callout).foregroundStyle(Ky.ink)
            Text("中指/掌长 \(String(format: "%.2f", m.middleLen / m.palmLen)) · 食指/无名指 \(String(format: "%.2f", m.ratio24))（\(m.ratio24 >= 1 ? "食指不短于无名指" : "无名指长于食指")）")
                .font(.callout).foregroundStyle(Ky.ink)
            Text("判读要点（按相书通说，娱乐参考）：掌型定大框架——方掌重实际与秩序，长掌重感受与想象；指长比看行事风格的细腻度。细读须结合修正后的三线。")
                .font(.caption).foregroundStyle(Ky.sub)
        }
        .kyCard()
    }

    private func detect() {
        joints = [:]; measure = nil; note = ""
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
            for (key, joint) in names {
                if let p = try? obs.recognizedPoint(joint), p.confidence > 0.3 { found[key] = p.location }
            }
            joints = found
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
    @State private var savedTip = false
    @State private var marks: [Double] = [0.14, 0.40, 0.63, 0.93]  // 发际/眉/鼻底/下颌（相对图高）
    private let labels = ["发际线", "眉线", "鼻底", "下颌"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
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
                                Text(labels[i]).font(.caption2).foregroundStyle(Ky.ink)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Ky.card.opacity(0.85)).clipShape(Capsule())
                                    .position(x: rect.minX + 30, y: y - 9)
                                    .gesture(DragGesture(coordinateSpace: .named("fittedCanvas")).onChanged { v in
                                        marks[i] = min(max((v.location.y - rect.minY) / rect.height, 0.02), 0.98)
                                    })
                            }
                        }
                    }.frame(height: 380).background(Ky.card).clipShape(RoundedRectangle(cornerRadius: 12))
                    resultCard
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
                Text("校准口径：发际线以实际发际为准手动拖准（儿童发际未定型更要人工校正）；三停比例为几何事实，判读按相书通说、娱乐参考，不套成人断语于儿童。")
                    .font(.caption2).foregroundStyle(Ky.sub)
            }.padding(16)
        }
        .background(Ky.bg)
        .navigationTitle("面相 · 三停校准")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: item) { _, new in Task { @MainActor in await box.load(new) } }
    }

    private var resultCard: some View {
        let up = marks[1] - marks[0]; let mid = marks[2] - marks[1]; let low = marks[3] - marks[2]
        let total = up + mid + low
        let p = [up, mid, low].map { total > 0 ? $0 / total * 100 : 0 }
        return VStack(alignment: .leading, spacing: 6) {
            Text("三停比例").font(.system(.subheadline, design: .serif)).fontWeight(.semibold).foregroundStyle(Ky.ink)
            Text(String(format: "上停 %.0f%% · 中停 %.0f%% · 下停 %.0f%%", p[0], p[1], p[2]))
                .font(KyV2.tabular(15)).foregroundStyle(Ky.ink)
            Text(abs(p[0] - 33) <= 5 && abs(p[1] - 33) <= 5 && abs(p[2] - 33) <= 5
                 ? "三停接近均等：面部比例匀称（相书谓三停平等、五岳丰盈者福相）。"
                 : "三停不均：以最长一停为主象细读——上停主早年与额相，中停主中年与鼻相，下停主晚年与地阁；须结合五官逐项看，不单凭比例下断。")
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
        if let data = try? Data(contentsOf: indexURL),
           let list = try? JSONDecoder().decode([PalmRecord].self, from: data) { records = list }
    }
    func save() {
        if let data = try? JSONEncoder().encode(records) { try? data.write(to: indexURL) }
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
    var body: some View {
        List {
            if store.records.isEmpty {
                Text("还没有记录。在手相/面相测量页填上姓名、描准线条后点「保存记录」，描线和测量值会按人存档在这里。")
                    .font(.callout).foregroundStyle(Ky.sub)
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
                            Text(r.summary).font(.caption).foregroundStyle(Ky.sub).lineLimit(1)
                        }
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { store.remove(r) } label: { Label("删除", systemImage: "trash") }
                }
            }
        }
        .navigationTitle("测量记录")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PalmRecordDetailView: View {
    @ObservedObject var store: PalmRecordStore
    let record: PalmRecord
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let img = store.image(of: record) {
                    FittedImage(image: img) { rect in
                        Canvas { ctx, _ in
                            let pts = stride(from: 0, to: record.linesFlat.count, by: 2).map {
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
                Text(record.summary).font(.callout).foregroundStyle(Ky.ink)
                Text("记录时间：\(Date(timeIntervalSince1970: record.createdEpoch).formatted(date: .abbreviated, time: .shortened)) · 描线为当时人工修正的点位，已冻结存档。")
                    .font(.caption2).foregroundStyle(Ky.sub)
            }.padding(16)
        }
        .background(Ky.bg)
        .navigationTitle("\(record.personName) · \(record.kind)")
        .navigationBarTitleDisplayMode(.inline)
    }
}
