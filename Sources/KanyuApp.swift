// 堪舆勘察 Kanyu Survey — 风水勘察数据采集 App
// 按《勘察作业标准-SOP》字段设计：建案表单 / 罗盘定向（磁北+真北+二十四山）/
// 任务单拍照录像（照片烙印方位、视频同步记录罗盘轨迹）/ 一键导出数据包 ZIP。
import SwiftUI
import CoreLocation
import CoreMotion
import AVFoundation
import ARKit
import SceneKit
import RoomPlan
import UIKit
import ZIPFoundation

// MARK: - 数据模型

enum CaseType: String, Codable, CaseIterable, Identifiable {
    case yangzhai = "阳宅"
    case yinzhai = "阴宅"
    case courtyard = "庭院"
    var id: String { rawValue }
}

struct Resident: Identifiable, Codable {
    var id = UUID()
    var label: String = ""        // 如：户主 / 配偶 / 长子（可空）
    var birthYear: String = ""    // 出生年（八宅命卦用）
    var gender: String = "男"
}

struct SurveyCase: Identifiable, Codable {
    var id = UUID()
    var name: String = ""
    var type: CaseType = .yangzhai
    var locationNote: String = "" // 所在乡镇/小区（粗略即可）
    var builtYear: String = ""    // 建成年
    var movedInYear: String = ""  // 入住年
    var renovatedYear: String = ""// 大装修年（可空）
    var residents: [Resident] = []
    var createdAt = Date()
}

struct HeadingReading: Identifiable, Codable {
    var id = UUID()
    var pointName: String         // 测点名，如 大门外朝外
    var magnetic: Double          // 磁北方位角
    var trueNorth: Double         // 真北方位角
    var mountain: String          // 二十四山
    var palace: String            // 八卦宫
    var timestamp = Date()
    var latitude: Double?
    var longitude: Double?
    var headingAccuracy: Double = -1
    var tiltDegrees: Double = -1   // 记录时手机倾斜角（放平采样，越小越可信）
    var sampleSpread: Double = -1  // 采样集中度 R（0–1，越接近 1 读数越稳）
}

struct HeadingSample: Codable {
    var t: Double                 // 距录像开始的秒数
    var trueNorth: Double
    var magnetic: Double
}

struct MediaItem: Identifiable, Codable {
    var id = UUID()
    var taskId: String
    var taskTitle: String
    var kind: String              // photo / video
    var fileName: String          // 原始文件（相对案件目录）
    var stampedFileName: String?  // 烙印版照片（仅照片）
    var samplesFileName: String?  // 罗盘轨迹 JSON（仅视频）
    var timestamp = Date()
    var trueHeading: Double = -1
    var magneticHeading: Double = -1
    var mountain: String = ""
    var latitude: Double?
    var longitude: Double?
    var note: String = ""
    var tilt: Double = -1          // 拍摄时倾斜角（照片=地平线倾斜，罗盘类=放平倾斜）
    var extraFile: String = ""     // 附加数据文件（3D 扫描的房间结构摘要 JSON 等）
}

struct CaseData: Identifiable, Codable {
    var surveyCase: SurveyCase
    var headings: [HeadingReading] = []
    var media: [MediaItem] = []
    var taskDone: [String: Bool] = [:]
    var taskNotes: [String: String] = [:]
    var id: UUID { surveyCase.id }
}

struct ExportPackage: Codable {
    var exportedAt = Date()
    var surveyCase: SurveyCase
    var headings: [HeadingReading]
    var media: [MediaItem]
    var taskNotes: [String: String]
}

// MARK: - 二十四山 / 八宫换算

enum CompassMath {
    static let mountains = ["子","癸","丑","艮","寅","甲","卯","乙","辰","巽","巳","丙","午","丁",
                            "未","坤","申","庚","酉","辛","戌","乾","亥","壬"]
    static let palaces = ["坎","艮","震","巽","离","坤","兑","乾"] // 北起顺时针，每宫45°
    static func normalize(_ deg: Double) -> Double {
        var d = deg.truncatingRemainder(dividingBy: 360)
        if d < 0 { d += 360 }
        return d
    }
    static func mountain(for deg: Double) -> String {
        let d = normalize(deg)
        let idx = Int((d + 7.5) / 15) % 24
        return mountains[idx]
    }
    static func palace(for deg: Double) -> String {
        let d = normalize(deg)
        let idx = Int((d + 22.5) / 45) % 8
        return palaces[idx]
    }
    static func format(_ deg: Double) -> String {
        deg >= 0 ? String(format: "%.1f°", normalize(deg)) : "—"
    }
    // 圆周平均：角度不能算术平均（359° 与 1° 的均值应是 0° 而非 180°）。
    // 返回均值与集中度 R（0–1，越接近 1 采样越稳）。
    static func circularMean(_ degs: [Double]) -> (mean: Double, r: Double) {
        guard !degs.isEmpty else { return (-1, 0) }
        var sx = 0.0, sy = 0.0
        for d in degs { let rad = d * .pi / 180; sx += cos(rad); sy += sin(rad) }
        let n = Double(degs.count)
        let mx = sx / n, my = sy / n
        let r = min(1.0, (mx * mx + my * my).squareRoot())
        var mean = atan2(my, mx) * 180 / .pi
        if mean < 0 { mean += 360 }
        return (mean, r)
    }
    // 最短角差（to − from，归一到 −180…180；正＝顺时针/向右转）
    static func shortestDiff(from: Double, to: Double) -> Double {
        normalize(to - from + 180) - 180
    }
}

// MARK: - 任务单（按 SOP 生成）

enum TaskKind { case photo, video, heading, scan3D, arTrack }

struct SurveyTask: Identifiable {
    var id: String
    var title: String
    var instruction: String
    var kind: TaskKind
}

enum TaskFactory {
    static func tasks(for type: CaseType) -> [SurveyTask] {
        switch type {
        case .yangzhai: return yangzhaiTasks
        case .yinzhai: return yinzhaiTasks
        case .courtyard: return courtyardTasks
        }
    }
    static let yangzhaiTasks: [SurveyTask] = [
        .init(id: "h_door_out", title: "罗盘·大门外朝外", instruction: "站在大门外正中，面朝出门方向（背对房子），手机贴胸端平，稳住后到罗盘页记录「大门外朝外」。", kind: .heading),
        .init(id: "h_door_in", title: "罗盘·大门外朝内（坐山）", instruction: "同一位置转身面对大门，到罗盘页记录「大门外朝内」。与朝外读数应相差约 180°，互校用。", kind: .heading),
        .init(id: "h_balcony", title: "罗盘·主阳台朝外", instruction: "站在主阳台/客厅大窗前，面朝窗外，到罗盘页记录「主阳台朝外」。没有阳台就记客厅主窗。", kind: .heading),
        .init(id: "h_back", title: "罗盘·房后朝外", instruction: "站在房子正后方，背对后墙面朝外，到罗盘页记录「房后朝外」。", kind: .heading),
        .init(id: "p_front", title: "照片·正立面全景", instruction: "退到能拍全整栋的位置，正对大门拍整栋全景，左右邻居边缘也要带进来。", kind: .photo),
        .init(id: "p_mingtang", title: "照片·门前向外（明堂）", instruction: "站在大门口向外拍：门前空地、道路、对面景物一次拍全。", kind: .photo),
        .init(id: "p_left", title: "照片·左侧邻舍", instruction: "站到房子左前方，拍左侧邻居建筑与本宅的间距、高度关系。", kind: .photo),
        .init(id: "p_right", title: "照片·右侧邻舍", instruction: "站到房子右前方，拍右侧邻居建筑与本宅的间距、高度关系。", kind: .photo),
        .init(id: "p_back", title: "照片·后立面", instruction: "站到房后能拍全的位置，拍后墙全貌及紧贴后墙的地面。", kind: .photo),
        .init(id: "p_backland", title: "照片·房后地势与排水", instruction: "拍房后地块全貌：坡势、排水沟、积水处、杂物堆放，重点拍清雨水可能往哪流。", kind: .photo),
        .init(id: "p_surround", title: "照片·周边路口与水体", instruction: "附近有路口、河流、水塘、变压器、庙宇的，各拍一张并在备注里写方位（如：大门左前方）。", kind: .photo),
        .init(id: "v_front_env", title: "视频·门前环境环拍", instruction: "站在大门外，原地慢转一圈（约 30 秒），把前方、左右、路面都扫到。罗盘轨迹会同步记录。", kind: .video),
        .init(id: "v_back_env", title: "视频·房后环境环拍", instruction: "站在房后，原地慢转一圈，拍清后方地势远近。", kind: .video),
        .init(id: "p_entry", title: "照片·入户向内", instruction: "站在大门外向屋内拍：进门第一眼看到什么（墙/厅/厕/灶）要拍清。", kind: .photo),
        .init(id: "p_living", title: "照片·客厅全景", instruction: "站客厅角上拍全景，沙发、电视、窗的位置都要在画面里。", kind: .photo),
        .init(id: "p_kitchen", title: "照片·厨房与灶台", instruction: "拍厨房全景＋灶台近景，水槽与灶的相对位置要清楚。", kind: .photo),
        .init(id: "p_master", title: "照片·主卧（床头）", instruction: "拍主卧全景，床头靠哪面墙、床头朝向画面里要能判断。", kind: .photo),
        .init(id: "p_bed2", title: "照片·其他卧室", instruction: "每间卧室一张全景，多间就在备注里注明是哪间、谁住。", kind: .photo),
        .init(id: "p_bath", title: "照片·卫生间位置", instruction: "拍卫生间门与周围房间的关系，能看出它在房子哪个方位区域即可，不必拍内部细节。", kind: .photo),
        .init(id: "p_stair", title: "照片·楼梯位置", instruction: "多层住宅拍楼梯所在位置与走向；平层可跳过，在备注写「平层无楼梯」。", kind: .photo),
        .init(id: "v_flow", title: "视频·室内动线", instruction: "从大门进屋，慢慢走到客厅、厨房、主卧，边走边拍，像带人参观一样走一遍。", kind: .video),
        .init(id: "s_roomscan", title: "3D扫描·户型建模（激光雷达）", instruction: "仅带激光雷达的 Pro 机型：逐间房各扫一遍。开始前站在门口、身体朝向屋内站直再开始，沿墙慢走、把每面墙和家具都扫到，单间别超过 5 分钟；扫完点完成，生成带米数尺寸的 3D 户型模型（墙/门/窗/床/灶台位置自动识别）。", kind: .scan3D),
        .init(id: "s_artrack_in", title: "AR轨迹·室内动线", instruction: "从大门内侧点开始，举着手机（镜头朝前）按平时走法走遍全屋再点结束。轨迹自动记录位置（米）与真北朝向，比手绘动线准。", kind: .arTrack),
        .init(id: "s_artrack_env", title: "AR轨迹·绕屋一周", instruction: "在屋外点开始，绕房子慢走一圈回到起点点结束（中途别停太久）。轨迹带真北朝向与米数距离，用于核对房子与周边道路/空地的相对方位。开阔处效果好，高楼遮挡处可能漂移，备注写明。", kind: .arTrack),
    ]
    static let yinzhaiTasks: [SurveyTask] = [
        .init(id: "h_bei", title: "罗盘·碑向", instruction: "站在墓碑正前方，面朝碑面方向（即朝山方向），到罗盘页记录「碑向朝外」；再转身记录坐方。", kind: .heading),
        .init(id: "p_yuan", title: "照片·陵园大局", instruction: "拍陵园整体：背后靠山、左右护持、前方视野，站在高处拍一张全景。", kind: .photo),
        .init(id: "v_yuan", title: "视频·墓区环拍", instruction: "站在选位处原地慢转一圈，四周地势、道路、水体都扫到。", kind: .video),
        .init(id: "p_wei", title: "照片·选位近景", instruction: "拍选定排位近景：左右相邻位、上下排距、挡墙距离。", kind: .photo),
        .init(id: "p_shui", title: "照片·排水与坡面", instruction: "拍选位周边排水沟、坡面、挡土墙，有淋头水/积水隐患的重点拍。", kind: .photo),
        .init(id: "p_lu", title: "照片·园区道路", instruction: "拍通往选位的道路走向：是环抱还是直冲选位。", kind: .photo),
    ]
    static let courtyardTasks: [SurveyTask] = [
        .init(id: "h_gate", title: "罗盘·院门朝外", instruction: "站在院门外，面朝出门方向，到罗盘页记录「院门朝外」。", kind: .heading),
        .init(id: "v_all", title: "视频·院内全景环拍", instruction: "站在院子中心慢转一圈，院墙、主体房、水景、植物都扫到。", kind: .video),
        .init(id: "p_gate_out", title: "照片·院门向外", instruction: "站在院门内向外拍：门前道路、空地、对面景物。", kind: .photo),
        .init(id: "p_water", title: "照片·水景", instruction: "拍池/溪/水缸等水体与房子的相对位置，水流方向在备注里写清。", kind: .photo),
        .init(id: "p_rock", title: "照片·假山与置石", instruction: "拍假山、景石的位置与形状，尖锐对门窗的要带上门窗一起拍。", kind: .photo),
        .init(id: "p_plants", title: "照片·主要植物", instruction: "拍大树与主要植栽，尤其正对门窗、压屋的树。", kind: .photo),
        .init(id: "p_wall", title: "照片·影壁与院墙", instruction: "拍影壁/照墙、院墙完整度与高度。", kind: .photo),
    ]
}

// MARK: - 数据存储与导出

@MainActor
final class SurveyStore: ObservableObject {
    @Published var cases: [CaseData] = []
    private let baseDir: URL
    private var indexURL: URL { baseDir.appendingPathComponent("index.json") }

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        baseDir = docs.appendingPathComponent("AppData", isDirectory: true)
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        load()
    }

    func caseDir(_ id: UUID) -> URL {
        let d = baseDir.appendingPathComponent(id.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? Self.decoder.decode([CaseData].self, from: data) else { return }
        cases = decoded
    }

    func save() {
        guard let data = try? Self.encoder.encode(cases) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    static var encoder: JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e
    }
    static var decoder: JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }

    func addCase(_ c: SurveyCase) {
        cases.insert(CaseData(surveyCase: c), at: 0)
        _ = caseDir(c.id)
        save()
    }

    func deleteCase(at offsets: IndexSet) {
        for i in offsets {
            let dir = caseDir(cases[i].surveyCase.id)
            try? FileManager.default.removeItem(at: dir)
        }
        cases.remove(atOffsets: offsets)
        save()
    }

    func update(_ data: CaseData) {
        if let i = cases.firstIndex(where: { $0.surveyCase.id == data.surveyCase.id }) {
            cases[i] = data
            save()
        }
    }

    // 保存一张照片（原图＋烙印图），返回 MediaItem
    func savePhoto(caseId: UUID, task: SurveyTask, imageData: Data, loc: LocationManager, tilt: Double = -1) -> MediaItem? {
        guard let image = UIImage(data: imageData) else { return nil }
        let dir = caseDir(caseId)
        let stamp = Date()
        let base = "\(task.id)_\(Int(stamp.timeIntervalSince1970))"
        let origName = "\(base).jpg"
        let stampedName = "\(base)_stamp.jpg"
        let trueH = loc.displayTrueHeading
        let magH = loc.displayMagneticHeading
        let mountain = trueH >= 0 ? CompassMath.mountain(for: trueH) : ""
        // 原图
        if let jpg = image.jpegData(compressionQuality: 0.9) {
            try? jpg.write(to: dir.appendingPathComponent(origName))
        }
        // 烙印图
        let lines = [
            "\(Self.timeFormatter.string(from: stamp))",
            "真北 \(CompassMath.format(trueH)) \(mountain)山 · 磁北 \(CompassMath.format(magH))",
            loc.coordinateText
        ]
        let stamped = StampDrawer.stamped(image: image, lines: lines)
        if let jpg = stamped.jpegData(compressionQuality: 0.9) {
            try? jpg.write(to: dir.appendingPathComponent(stampedName))
        }
        return MediaItem(taskId: task.id, taskTitle: task.title, kind: "photo",
                         fileName: origName, stampedFileName: stampedName,
                         timestamp: stamp, trueHeading: trueH, magneticHeading: magH,
                         mountain: mountain,
                         latitude: loc.currentLocation?.coordinate.latitude,
                         longitude: loc.currentLocation?.coordinate.longitude,
                         tilt: tilt)
    }

    // 保存一段视频（文件已由相机写入临时路径）＋罗盘轨迹
    func saveVideo(caseId: UUID, task: SurveyTask, tempURL: URL, samples: [HeadingSample], loc: LocationManager, tilt: Double = -1) -> MediaItem? {
        let dir = caseDir(caseId)
        let stamp = Date()
        let base = "\(task.id)_\(Int(stamp.timeIntervalSince1970))"
        let name = "\(base).mov"
        let dest = dir.appendingPathComponent(name)
        do { try FileManager.default.moveItem(at: tempURL, to: dest) } catch { return nil }
        var samplesName: String? = nil
        if !samples.isEmpty {
            samplesName = "\(base)_headings.json"
            if let data = try? Self.encoder.encode(samples) {
                try? data.write(to: dir.appendingPathComponent(samplesName!))
            }
        }
        let trueH = samples.first?.trueNorth ?? loc.displayTrueHeading
        let magH = samples.first?.magnetic ?? loc.displayMagneticHeading
        return MediaItem(taskId: task.id, taskTitle: task.title, kind: "video",
                         fileName: name, samplesFileName: samplesName,
                         timestamp: stamp, trueHeading: trueH, magneticHeading: magH,
                         mountain: trueH >= 0 ? CompassMath.mountain(for: trueH) : "",
                         latitude: loc.currentLocation?.coordinate.latitude,
                         longitude: loc.currentLocation?.coordinate.longitude,
                         tilt: tilt)
    }

    // 保存 AR 轨迹（JSON 即本体文件）
    func saveARTrack(caseId: UUID, task: SurveyTask, samples: [ARTrackSample], loc: LocationManager) -> MediaItem? {
        guard !samples.isEmpty else { return nil }
        let dir = caseDir(caseId)
        let stamp = Date()
        let name = "\(task.id)_\(Int(stamp.timeIntervalSince1970)).json"
        guard let data = try? Self.encoder.encode(samples) else { return nil }
        do { try data.write(to: dir.appendingPathComponent(name)) } catch { return nil }
        let h = samples.first?.compassHeading ?? -1
        return MediaItem(taskId: task.id, taskTitle: task.title, kind: "artrack",
                         fileName: name, timestamp: stamp,
                         trueHeading: h, magneticHeading: loc.displayMagneticHeading,
                         mountain: h >= 0 ? CompassMath.mountain(for: h) : "",
                         latitude: loc.currentLocation?.coordinate.latitude,
                         longitude: loc.currentLocation?.coordinate.longitude)
    }

    // 保存 3D 户型扫描（USDZ 模型＋结构摘要 JSON）
    func saveScan(caseId: UUID, task: SurveyTask, tempUSDZ: URL, summary: Data?, loc: LocationManager, startHeading: Double) -> MediaItem? {
        let dir = caseDir(caseId)
        let stamp = Date()
        let base = "\(task.id)_\(Int(stamp.timeIntervalSince1970))"
        let name = "\(base).usdz"
        do { try FileManager.default.copyItem(at: tempUSDZ, to: dir.appendingPathComponent(name)) } catch { return nil }
        var extra = ""
        if let summary {
            extra = "\(base)_room.json"
            try? summary.write(to: dir.appendingPathComponent(extra))
        }
        return MediaItem(taskId: task.id, taskTitle: task.title, kind: "scan3d",
                         fileName: name, timestamp: stamp,
                         trueHeading: startHeading, magneticHeading: loc.displayMagneticHeading,
                         mountain: startHeading >= 0 ? CompassMath.mountain(for: startHeading) : "",
                         latitude: loc.currentLocation?.coordinate.latitude,
                         longitude: loc.currentLocation?.coordinate.longitude,
                         extraFile: extra)
    }

    // 导出 ZIP 数据包：媒体原件＋data.json＋勘察摘要.txt
    func exportZip(caseData: CaseData) -> URL? {
        let sc = caseData.surveyCase
        let safeName = sc.name.isEmpty ? "勘察" : sc.name
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("Export_\(sc.id.uuidString)", isDirectory: true)
        try? FileManager.default.removeItem(at: tmp)
        do {
            try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            let src = caseDir(sc.id)
            for m in caseData.media {
                for f in [m.fileName, m.stampedFileName, m.samplesFileName].compactMap({ $0 }) {
                    let from = src.appendingPathComponent(f)
                    if FileManager.default.fileExists(atPath: from.path) {
                        try FileManager.default.copyItem(at: from, to: tmp.appendingPathComponent(f))
                    }
                }
            }
            let pkg = ExportPackage(surveyCase: sc, headings: caseData.headings,
                                    media: caseData.media, taskNotes: caseData.taskNotes)
            try Self.encoder.encode(pkg).write(to: tmp.appendingPathComponent("data.json"))
            try summaryText(caseData).write(to: tmp.appendingPathComponent("勘察摘要.txt"),
                                             atomically: true, encoding: .utf8)
            let zipURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(safeName)-勘察数据包.zip")
            try? FileManager.default.removeItem(at: zipURL)
            try FileManager.default.zipItem(at: tmp, to: zipURL)
            return zipURL
        } catch { return nil }
    }

    func summaryText(_ cd: CaseData) -> String {
        let sc = cd.surveyCase
        var s = "勘察数据包摘要\n================\n"
        s += "名称：\(sc.name)\n类型：\(sc.type.rawValue)\n地点：\(sc.locationNote)\n"
        s += "建成年：\(sc.builtYear) 入住年：\(sc.movedInYear) 大装修年：\(sc.renovatedYear)\n"
        for r in sc.residents { s += "居住者：\(r.label) \(r.birthYear)年 \(r.gender)\n" }
        s += "\n罗盘读数（真北为准）\n----------------\n"
        for h in cd.headings {
            s += "\(h.pointName)：真北 \(CompassMath.format(h.trueNorth))（\(h.mountain)山·\(h.palace)宫）磁北 \(CompassMath.format(h.magnetic)) 精度±\(Int(h.headingAccuracy))° 倾斜\(h.tiltDegrees >= 0 ? String(format: "%.1f°", h.tiltDegrees) : "—") 集中度\(h.sampleSpread >= 0 ? String(format: "%.2f", h.sampleSpread) : "—") \(Self.timeFormatter.string(from: h.timestamp))\n"
        }
        s += "\n媒体清单\n----------------\n"
        for m in cd.media {
            s += "[\(m.kind == "photo" ? "照片" : "视频")] \(m.taskTitle)｜真北 \(CompassMath.format(m.trueHeading)) \(m.mountain)｜\(m.fileName)\(m.note.isEmpty ? "" : "｜备注：\(m.note)")\n"
        }
        return s
    }

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; return f
    }()
}

// 照片烙印：在底部压一条半透明黑条，写时间/方位/GPS
enum StampDrawer {
    static func stamped(image: UIImage, lines: [String]) -> UIImage {
        let w = image.size.width
        let barH = max(90, image.size.height * 0.085)
        let newSize = CGSize(width: w, height: image.size.height + barH)
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: newSize))
            image.draw(at: .zero)
            let fontSize = max(26, w * 0.026)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .medium),
                .foregroundColor: UIColor.white
            ]
            var y = image.size.height + barH * 0.10
            for line in lines {
                (line as NSString).draw(at: CGPoint(x: w * 0.03, y: y), withAttributes: attrs)
                y += fontSize * 1.35
            }
        }
    }
}

// MARK: - 定位与罗盘

@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var magneticHeading: Double = -1
    @Published var trueHeading: Double = -1
    @Published var headingAccuracy: Double = -1
    @Published var currentLocation: CLLocation?
    @Published var authorized = false

    private let manager = CLLocationManager()

    var displayTrueHeading: Double { trueHeading >= 0 ? trueHeading : magneticHeading }
    var displayMagneticHeading: Double { magneticHeading }
    var declination: Double? {
        guard trueHeading >= 0, magneticHeading >= 0 else { return nil }
        var d = trueHeading - magneticHeading
        if d > 180 { d -= 360 }; if d < -180 { d += 360 }
        return d
    }
    var coordinateText: String {
        guard let l = currentLocation else { return "GPS 未定位" }
        return String(format: "%.6f, %.6f", l.coordinate.latitude, l.coordinate.longitude)
    }
    var accuracyWarning: String? {
        if headingAccuracy < 0 { return "罗盘未就绪：请远离钢筋、电器、汽车，原地画 8 字校准" }
        if headingAccuracy > 25 { return "精度偏低（±\(Int(headingAccuracy))°）：请远离金属与电器后重测" }
        return nil
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.headingFilter = 1
        manager.requestWhenInUseAuthorization()
    }

    func start() {
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
    }
    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorized = (manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways)
            if self.authorized { self.start() }
        }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let loc = locations.last
        Task { @MainActor in self.currentLocation = loc }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let m = newHeading.magneticHeading
        let t = newHeading.trueHeading
        let a = newHeading.headingAccuracy
        Task { @MainActor in
            self.magneticHeading = m
            self.trueHeading = t
            self.headingAccuracy = a
        }
    }
}

// MARK: - 水平仪（CoreMotion 重力向量）
//
// 罗盘准不准，一半看放没放平：手机倾斜时磁力计读数会漂。
// 本类给出两种倾斜角：
// - flatTilt：手机平放（测罗盘时）偏离水平的夹角，0° 为完全放平；
// - horizonTilt：手机竖举（拍照时）地平线的倾斜角，0° 为地平线端正。
// 另给气泡位置（bubbleX/bubbleY，-1…1）供界面画气泡。

@MainActor
final class MotionManager: ObservableObject {
    @Published var flatTilt: Double = 90
    @Published var horizonTilt: Double = 0
    @Published var bubbleX: Double = 0
    @Published var bubbleY: Double = 0

    private let motion = CMMotionManager()
    var isLevelForCompass: Bool { flatTilt <= 3 }
    var isLevelForCamera: Bool { abs(horizonTilt) <= 2 }

    func start() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 0.1
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] dm, _ in
            guard let g = dm?.gravity else { return }
            let len = (g.x * g.x + g.y * g.y + g.z * g.z).squareRoot()
            guard len > 0 else { return }
            let gx = g.x / len, gy = g.y / len, gz = g.z / len
            let flat = acos(min(1, max(-1, -gz))) * 180 / .pi
            let horizon = atan2(gx, -gy) * 180 / .pi
            Task { @MainActor in
                self?.flatTilt = flat
                self?.horizonTilt = horizon
                self?.bubbleX = gx
                self?.bubbleY = gy
            }
        }
    }
}

// MARK: - 相机（AVFoundation：拍照＋录像，取景框由 SwiftUI 叠罗盘）

final class CameraManager: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var photoCompletion: ((Data?) -> Void)?
    private var movieCompletion: ((URL?) -> Void)?
    @Published var isRecording = false
    private var configured = false

    func configure() {
        guard !configured else { return }
        configured = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .high
            if let cam = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
               let input = try? AVCaptureDeviceInput(device: cam),
               self.session.canAddInput(input) { self.session.addInput(input) }
            if let mic = AVCaptureDevice.default(for: .audio),
               let input = try? AVCaptureDeviceInput(device: mic),
               self.session.canAddInput(input) { self.session.addInput(input) }
            if self.session.canAddOutput(self.photoOutput) { self.session.addOutput(self.photoOutput) }
            if self.session.canAddOutput(self.movieOutput) { self.session.addOutput(self.movieOutput) }
            self.session.commitConfiguration()
            self.session.startRunning()
        }
    }

    func capturePhoto(completion: @escaping (Data?) -> Void) {
        photoCompletion = completion
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func startRecording() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rec_\(Int(Date().timeIntervalSince1970)).mov")
        movieOutput.startRecording(to: url, recordingDelegate: self)
        DispatchQueue.main.async { self.isRecording = true }
    }

    func stopRecording(completion: @escaping (URL?) -> Void) {
        movieCompletion = completion
        movieOutput.stopRecording()
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        let c = photoCompletion; photoCompletion = nil
        DispatchQueue.main.async { c?(data) }
    }
}

extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async { self.isRecording = false }
        let ok = (error == nil)
        let c = movieCompletion; movieCompletion = nil
        DispatchQueue.main.async { c?(ok ? outputFileURL : nil) }
    }
}

final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewUIView {
        let v = PreviewUIView()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        if let conn = v.previewLayer.connection, conn.isVideoOrientationSupported {
            conn.videoOrientation = .portrait
        }
        return v
    }
    func updateUIView(_ uiView: PreviewUIView, context: Context) {}
}

// MARK: - AR 轨迹（ARKit 真北对齐：自动记录位置＋朝向）
//
// ARKit 世界坐标设为 .gravityAndHeading 后，坐标轴直接对齐真北：
// +X 东、+Y 上、−Z 北。相机姿态 60fps 融合罗盘/陀螺/视觉里程计，
// 比手工 0.5 秒采样密得多、稳得多；每点另存同期罗盘读数互校漂移。

struct ARTrackSample: Codable {
    var t: Double                  // 秒（自开始）
    var x: Double                  // 米，相对起点（东+）
    var y: Double                  // 米（上+）
    var z: Double                  // 米（北−，即向北为负）
    var arHeading: Double          // 相机姿态推算朝向（真北系，度）
    var compassHeading: Double     // 同期罗盘真北读数（度，互校）
}

final class ARTrackRecorder: NSObject, ObservableObject, ARSessionDelegate {
    let session = ARSession()
    @Published var isRunning = false
    @Published var currentHeading: Double = -1
    @Published var distance: Double = 0
    private(set) var samples: [ARTrackSample] = []
    private var startDate: Date?
    private var lastLog = Date.distantPast
    private weak var loc: LocationManager?

    static var supported: Bool { ARWorldTrackingConfiguration.isSupported }

    func start(loc: LocationManager) {
        guard Self.supported else { return }
        self.loc = loc
        samples = []; distance = 0
        let cfg = ARWorldTrackingConfiguration()
        cfg.worldAlignment = .gravityAndHeading
        session.delegate = self
        session.run(cfg, options: [.resetTracking, .removeExistingAnchors])
        startDate = Date(); lastLog = .distantPast; isRunning = true
    }

    func stop() { session.pause(); isRunning = false }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let now = Date()
        guard let start = startDate, now.timeIntervalSince(lastLog) >= 0.1 else { return }
        lastLog = now
        let tr = frame.camera.transform
        let pos = tr.columns.3
        // 相机前向 = −Z 列；正北时前向 (0,0,−1)：atan2(0, +1)=0° ✓；正东 (1,0,0)：90° ✓
        var heading = atan2(Double(-tr.columns.2.x), Double(tr.columns.2.z)) * 180 / .pi
        if heading < 0 { heading += 360 }
        let s = ARTrackSample(t: now.timeIntervalSince(start),
                              x: Double(pos.x), y: Double(pos.y), z: Double(pos.z),
                              arHeading: heading,
                              compassHeading: loc?.displayTrueHeading ?? -1)
        if let prev = samples.last {
            let dx = s.x - prev.x, dy = s.y - prev.y, dz = s.z - prev.z
            distance += (dx * dx + dy * dy + dz * dz).squareRoot()
        }
        samples.append(s)
        let h = heading, d = distance
        DispatchQueue.main.async { self.currentHeading = h; self.distance = d }
    }
}

struct ARPreviewView: UIViewRepresentable {
    let session: ARSession
    func makeUIView(context: Context) -> ARSCNView {
        let v = ARSCNView()
        v.session = session
        v.automaticallyUpdatesLighting = true
        return v
    }
    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}

struct ARTrackView: View {
    @EnvironmentObject var store: SurveyStore
    @EnvironmentObject var location: LocationManager
    @Environment(\.dismiss) var dismiss
    let task: SurveyTask
    @Binding var draft: CaseData
    @StateObject private var recorder = ARTrackRecorder()
    @State private var savedTip = false

    var body: some View {
        ZStack {
            if ARTrackRecorder.supported {
                ARPreviewView(session: recorder.session).ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }
            VStack {
                VStack(spacing: 4) {
                    Text("真北 \(CompassMath.format(recorder.currentHeading)) · 已走 \(String(format: "%.1f", recorder.distance)) 米 · \(recorder.samples.count) 点")
                        .font(.callout).fontWeight(.medium).foregroundStyle(.white)
                    if recorder.isRunning {
                        Text("轨迹记录中：匀速走，别停太久；遮挡多会漂移").font(.caption).foregroundStyle(.white.opacity(0.85))
                    } else {
                        Text(ARTrackRecorder.supported ? task.instruction : "本机型不支持 AR 追踪")
                            .font(.caption).foregroundStyle(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(10).background(.black.opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: 10)).padding()
                Spacer()
                Button {
                    if recorder.isRunning {
                        recorder.stop()
                        if let item = store.saveARTrack(caseId: draft.surveyCase.id, task: task, samples: recorder.samples, loc: location) {
                            draft.media.append(item)
                            draft.taskDone[task.id] = true
                            savedTip = true
                        }
                    } else {
                        recorder.start(loc: location)
                    }
                } label: {
                    ZStack {
                        Circle().fill(recorder.isRunning ? .gray : .red).frame(width: 68, height: 68)
                        if recorder.isRunning { RoundedRectangle(cornerRadius: 4).fill(.white).frame(width: 26, height: 26) }
                    }
                }
                .disabled(!ARTrackRecorder.supported)
                .padding(.bottom, 28)
                if savedTip { Text("✓ 轨迹已保存").foregroundStyle(.green).padding(.bottom, 10) }
            }
        }
        .navigationTitle(task.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { location.start() }
        .onDisappear { recorder.stop() }
    }
}

// MARK: - 3D 户型扫描（RoomPlan：激光雷达，需 Pro 机型）

final class RoomScanController: NSObject, ObservableObject, RoomCaptureSessionDelegate {
    let captureView = RoomCaptureView(frame: .zero)
    @Published var finished = false
    @Published var failedText = ""
    private(set) var capturedRoom: CapturedRoom?

    override init() {
        super.init()
        captureView.captureSession.delegate = self
    }
    func start() {
        finished = false; failedText = ""
        captureView.captureSession.run(configuration: RoomCaptureSession.Configuration())
    }
    func stop() { captureView.captureSession.stop() }
    func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoom, error: (any Error)?) {
        if let error { failedText = "扫描失败：\(error.localizedDescription)"; return }
        capturedRoom = data
        finished = true
    }
    // 结构摘要：墙/门/窗/开口的尺寸（米）与家具类别，回传后用于户型核对与九宫量算
    func summaryJSON(startHeading: Double) -> Data? {
        guard let room = capturedRoom else { return nil }
        func surf(_ s: CapturedRoom.Surface) -> [String: Any] {
            ["category": "\(s.category)", "length": Double(s.dimensions.x), "height": Double(s.dimensions.y)]
        }
        let dict: [String: Any] = [
            "startTrueHeading": startHeading,
            "walls": room.walls.map(surf),
            "doors": room.doors.map(surf),
            "windows": room.windows.map(surf),
            "openings": room.openings.map(surf),
            "objects": room.objects.map { ["category": "\($0.category)", "dx": Double($0.dimensions.x), "dy": Double($0.dimensions.y), "dz": Double($0.dimensions.z)] }
        ]
        return try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted])
    }
}

struct RoomCaptureRepresentable: UIViewRepresentable {
    let controller: RoomScanController
    func makeUIView(context: Context) -> RoomCaptureView { controller.captureView }
    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}
}

struct RoomScanView: View {
    @EnvironmentObject var store: SurveyStore
    @EnvironmentObject var location: LocationManager
    @Environment(\.dismiss) var dismiss
    let task: SurveyTask
    @Binding var draft: CaseData
    @StateObject private var controller = RoomScanController()
    @State private var scanning = false
    @State private var startHeading: Double = -1
    @State private var savedTip = false

    var body: some View {
        VStack(spacing: 0) {
            if RoomCaptureSession.isSupported {
                RoomCaptureRepresentable(controller: controller)
                    .ignoresSafeArea(edges: .horizontal)
                VStack(spacing: 8) {
                    Text(task.instruction).font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(.horizontal)
                    if !controller.failedText.isEmpty {
                        Text(controller.failedText).font(.caption).foregroundStyle(.red)
                    }
                    if controller.finished {
                        Button("保存这个房间的模型") { save() }
                            .buttonStyle(.borderedProminent)
                    } else if scanning {
                        Button("完成扫描") { controller.stop(); scanning = false }
                            .buttonStyle(.bordered)
                    } else {
                        Button("开始扫描（先站门口朝屋内站直）") {
                            startHeading = location.displayTrueHeading
                            controller.start(); scanning = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    if savedTip { Text("✓ 已保存，可继续扫下一间").foregroundStyle(.green).font(.caption) }
                }
                .padding()
            } else {
                ContentUnavailableView("本机型没有激光雷达",
                                       systemImage: "cube.transparent.slash",
                                       description: Text("3D 户型扫描需要带 LiDAR 的 iPhone Pro 机型；普通机型请用照片＋手绘平面代替，本项可跳过。"))
            }
        }
        .navigationTitle(task.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { location.start() }
        .onDisappear { controller.stop() }
    }

    private func save() {
        guard let room = controller.capturedRoom else { return }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("room-\(UUID().uuidString).usdz")
        do {
            try room.export(to: tmp, exportOptions: .parametric)
        } catch {
            controller.failedText = "导出模型失败：\(error.localizedDescription)"
            return
        }
        if let item = store.saveScan(caseId: draft.surveyCase.id, task: task, tempUSDZ: tmp,
                                     summary: controller.summaryJSON(startHeading: startHeading),
                                     loc: location, startHeading: startHeading) {
            draft.media.append(item)
            draft.taskDone[task.id] = true
            savedTip = true
            controller.finished = false
        }
    }
}

// MARK: - 界面

@main
struct KanyuSurveyApp: App {
    @StateObject private var store = SurveyStore()
    @StateObject private var location = LocationManager()
    @StateObject private var motion = MotionManager()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(location)
                .environmentObject(motion)
                .onAppear { location.start(); motion.start() }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var store: SurveyStore
    @State private var showingNew = false
    var body: some View {
        NavigationStack {
            Group {
                if store.cases.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "compass.drawing").font(.system(size: 44)).foregroundStyle(.secondary)
                        Text("还没有勘察案件").font(.headline)
                        Text("点右上角 ＋ 新建一个案件，按任务单一步步拍，\n最后导出数据包发回即可。")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.padding()
                } else {
                    List {
                        ForEach(store.cases) { cd in
                            NavigationLink {
                                CaseDetailView(caseId: cd.surveyCase.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(cd.surveyCase.name).font(.headline)
                                    Text("\(cd.surveyCase.type.rawValue) · \(cd.surveyCase.locationNote) · 已拍 \(cd.media.count) 项 · 罗盘 \(cd.headings.count) 个")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { store.deleteCase(at: $0) }
                    }
                }
            }
            .navigationTitle("堪舆勘察")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingNew = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingNew) { NewCaseView() }
        }
    }
}

struct NewCaseView: View {
    @EnvironmentObject var store: SurveyStore
    @Environment(\.dismiss) var dismiss
    @State private var c = SurveyCase()
    var body: some View {
        NavigationStack {
            Form {
                Section("案件") {
                    TextField("名称（如：案例001 临街自建房）", text: $c.name)
                    Picker("类型", selection: $c.type) {
                        ForEach(CaseType.allCases) { t in Text(t.rawValue).tag(t) }
                    }
                    TextField("所在乡镇/小区（粗略即可）", text: $c.locationNote)
                }
                Section("年份（定运要用，务必准）") {
                    TextField("建成年（如 2016）", text: $c.builtYear).keyboardType(.numberPad)
                    TextField("入住年", text: $c.movedInYear).keyboardType(.numberPad)
                    TextField("大装修年（没有留空）", text: $c.renovatedYear).keyboardType(.numberPad)
                }
                Section("常住人（八宅命卦用）") {
                    ForEach($c.residents) { $r in
                        HStack {
                            TextField("称谓", text: $r.label)
                            TextField("出生年", text: $r.birthYear).keyboardType(.numberPad)
                            Picker("", selection: $r.gender) { Text("男").tag("男"); Text("女").tag("女") }
                                .pickerStyle(.segmented).frame(width: 90)
                        }
                    }
                    .onDelete { c.residents.remove(atOffsets: $0) }
                    Button("＋ 添加常住人") { c.residents.append(Resident()) }
                }
            }
            .navigationTitle("新建勘察")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("建立") {
                        if c.name.isEmpty { c.name = "勘察 \(SurveyStore.timeFormatter.string(from: c.createdAt))" }
                        store.addCase(c)
                        dismiss()
                    }
                }
            }
        }
    }
}

struct CaseDetailView: View {
    @EnvironmentObject var store: SurveyStore
    @EnvironmentObject var location: LocationManager
    let caseId: UUID
    @State private var draft: CaseData?
    @State private var exportURL: URL?

    var body: some View {
        Group {
            if let d = draft {
                List {
                    Section("基本信息") {
                        LabeledContent("类型", value: d.surveyCase.type.rawValue)
                        LabeledContent("地点", value: d.surveyCase.locationNote)
                        LabeledContent("建成 / 入住 / 装修", value: "\(d.surveyCase.builtYear) / \(d.surveyCase.movedInYear) / \(d.surveyCase.renovatedYear)")
                        ForEach(d.surveyCase.residents) { r in
                            LabeledContent("常住人", value: "\(r.label) \(r.birthYear)年 \(r.gender)")
                        }
                    }
                    Section("罗盘读数（\(d.headings.count)）") {
                        NavigationLink {
                            CompassView(draft: binding)
                        } label: { Label("去测罗盘 / 记录方位", systemImage: "location.north.circle") }
                        ForEach(d.headings) { h in
                            HStack {
                                Text(h.pointName)
                                Spacer()
                                Text("真北 \(CompassMath.format(h.trueNorth)) \(h.mountain)山")
                                    .foregroundStyle(.secondary).font(.callout)
                            }
                        }
                        .onDelete { idx in
                            draft?.headings.remove(atOffsets: idx); commit()
                        }
                    }
                    Section("任务单") {
                        ForEach(TaskFactory.tasks(for: d.surveyCase.type)) { task in
                            NavigationLink {
                                TaskDetailView(task: task, draft: binding)
                            } label: {
                                HStack {
                                    Image(systemName: (draft?.taskDone[task.id] ?? false) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle((draft?.taskDone[task.id] ?? false) ? .green : .secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(task.title).font(.body)
                                        Text(kindText(task.kind)).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    Section("导出") {
                        Button {
                            if let dd = draft { exportURL = store.exportZip(caseData: dd) }
                        } label: { Label("生成数据包（ZIP）", systemImage: "square.and.arrow.up") }
                        if let url = exportURL {
                            ShareLink(item: url) { Label("发送数据包", systemImage: "paperplane") }
                            Text("数据包含：原图＋烙印图＋视频＋罗盘轨迹＋data.json＋勘察摘要。用聊天软件发回即可。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .navigationTitle(d.surveyCase.name)
                .navigationBarTitleDisplayMode(.inline)
            } else {
                Text("案件不存在").foregroundStyle(.secondary)
            }
        }
        .onAppear {
            if draft == nil { draft = store.cases.first(where: { $0.surveyCase.id == caseId }) }
        }
    }

    private var binding: Binding<CaseData> {
        Binding(get: { draft ?? CaseData(surveyCase: SurveyCase()) },
                set: { draft = $0; commit() })
    }
    private func commit() { if let d = draft { store.update(d) } }
    private func kindText(_ k: TaskKind) -> String {
        switch k { case .photo: return "拍照"; case .video: return "录像"; case .heading: return "罗盘"; case .scan3D: return "3D扫描"; case .arTrack: return "AR轨迹" }
    }
}

struct CompassView: View {
    @EnvironmentObject var location: LocationManager
    @EnvironmentObject var motion: MotionManager
    @Binding var draft: CaseData
    @State private var pointName = "大门外朝外"
    @State private var customPoint = ""
    @State private var justSaved = false
    @State private var collecting = false
    @State private var trueSamples: [Double] = []
    @State private var magSamples: [Double] = []
    @State private var collectTicks = 0
    @State private var collectHint = ""
    @State private var collectTask: Task<Void, Never>? = nil
    private let presetPoints = ["大门外朝外", "大门外朝内", "主阳台朝外", "房后朝外", "碑向朝外", "院门朝外"]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                dial.frame(width: 260, height: 260).padding(.top, 8)
                // 水平仪：气泡进小圈（倾斜≤3°）才算放平
                HStack(spacing: 14) {
                    ZStack {
                        Circle().stroke(Color.secondary.opacity(0.5), lineWidth: 1.5).frame(width: 76, height: 76)
                        Circle().stroke(Color.green.opacity(0.7), lineWidth: 1.5).frame(width: 26, height: 26)
                        Circle().fill(motion.isLevelForCompass ? Color.green : Color.orange)
                            .frame(width: 18, height: 18)
                            .offset(x: bubbleOffset.0, y: bubbleOffset.1)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("水平仪：倾斜 \(String(format: "%.1f°", motion.flatTilt))")
                            .font(.callout).fontWeight(.medium)
                        Text(motion.isLevelForCompass ? "已放平，可以记录" : "把手机平放，气泡稳进绿圈")
                            .font(.caption)
                            .foregroundStyle(motion.isLevelForCompass ? .green : .orange)
                        Text("倾斜时罗盘会漂，记录只采放平时的读数并取平均。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                VStack(spacing: 4) {
                    Text("真北 \(CompassMath.format(location.displayTrueHeading))")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    let d = location.displayTrueHeading
                    Text(d >= 0 ? "\(CompassMath.mountain(for: d))山 · \(CompassMath.palace(for: d))宫" : "等待罗盘…")
                        .font(.headline).foregroundStyle(.secondary)
                    Text("磁北 \(CompassMath.format(location.displayMagneticHeading))" +
                         (location.declination != nil ? " · 磁偏角 \(String(format: "%+.1f°", location.declination!))（系统按定位自动校正）" : ""))
                        .font(.caption).foregroundStyle(.secondary)
                    Text("GPS：\(location.coordinateText)").font(.caption).foregroundStyle(.secondary)
                    if let warn = location.accuracyWarning {
                        Text(warn).font(.caption).foregroundStyle(.orange).multilineTextAlignment(.center)
                    }
                }
                Picker("测点", selection: $pointName) {
                    ForEach(presetPoints, id: \.self) { Text($0).tag($0) }
                    Text("自定义…").tag("__custom__")
                }.pickerStyle(.menu)
                if pointName == "__custom__" {
                    TextField("测点名称", text: $customPoint).textFieldStyle(.roundedBorder)
                }
                Button {
                    guard !collecting else { return }
                    startCollect()
                } label: {
                    Text(justSaved ? "✓ 已记录" : (collecting ? "采样中…（\(trueSamples.count)/8）" : "记录这个方位（放平自动采样）"))
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                if !collectHint.isEmpty {
                    Text(collectHint).font(.caption).foregroundStyle(.secondary)
                }
                Text("测法：手机端平、远离汽车钢筋电器；每个测点原地慢转半圈等读数稳定后再记录。坐向以真北读数为准入盘，磁北读数留作互校。")
                    .font(.caption).foregroundStyle(.secondary)
                if !draft.headings.isEmpty {
                    Divider()
                    ForEach(draft.headings) { h in
                        HStack {
                            Text(h.pointName).font(.callout)
                            Spacer()
                            Text("\(CompassMath.format(h.trueNorth)) \(h.mountain)山").font(.callout).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity)
                    }
                }
            }.padding()
        }
        .navigationTitle("罗盘定向")
        .onAppear { location.start(); motion.start() }
        .onDisappear { collectTask?.cancel() }
    }

    // 采样循环用 Task 驱动（v1.3 用视图层 Timer 发布者，真机上不触发导致永远 0/8，已改）
    private func startCollect() {
        collecting = true; trueSamples = []; magSamples = []; collectTicks = 0
        collectHint = "采样中：把气泡稳在绿圈里…"
        collectTask?.cancel()
        collectTask = Task { @MainActor in
            while collecting && trueSamples.count < 8 && collectTicks < 80 {
                if motion.isLevelForCompass && location.displayTrueHeading >= 0 {
                    trueSamples.append(location.displayTrueHeading)
                    magSamples.append(location.displayMagneticHeading)
                    collectHint = "采样中：已采 \(trueSamples.count)/8，保持放平…"
                } else {
                    collectHint = "没放平，不采样：把气泡稳进绿圈（当前倾斜 \(String(format: "%.1f°", motion.flatTilt))）"
                }
                if trueSamples.count >= 8 { finishCollect(); return }
                collectTicks += 1
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
            if collecting {
                collecting = false
                collectHint = "这次没采够：放平后再点一次记录。"
            }
        }
    }

    private var bubbleOffset: (Double, Double) {
        let dx = min(1, max(-1, motion.bubbleX / 0.25)) * 27
        let dy = min(1, max(-1, -motion.bubbleY / 0.25)) * 27
        return (dx, dy)
    }

    private func finishCollect() {
        collecting = false
        let (meanT, r) = CompassMath.circularMean(trueSamples)
        let (meanM, _) = CompassMath.circularMean(magSamples)
        guard meanT >= 0 else { collectHint = "读数无效，请重试"; return }
        let name = pointName == "__custom__" ? (customPoint.isEmpty ? "自定义测点" : customPoint) : pointName
        draft.headings.append(HeadingReading(
            pointName: name,
            magnetic: meanM,
            trueNorth: meanT,
            mountain: CompassMath.mountain(for: meanT),
            palace: CompassMath.palace(for: meanT),
            latitude: location.currentLocation?.coordinate.latitude,
            longitude: location.currentLocation?.coordinate.longitude,
            headingAccuracy: location.headingAccuracy,
            tiltDegrees: motion.flatTilt,
            sampleSpread: r))
        justSaved = true
        collectHint = "已记录：8 次采样平均，集中度 \(String(format: "%.2f", r))（越接近 1 越稳）"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { justSaved = false }
    }

    private var dial: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.4), lineWidth: 2)
            ForEach(0..<8, id: \.self) { i in
                let bearing = Double(i) * 45
                let ang = (bearing - location.displayTrueHeading) * .pi / 180
                Text(CompassMath.palaces[i])
                    .font(i % 2 == 0 ? .headline : .subheadline)
                    .foregroundStyle(i == 0 ? .red : .primary)
                    .position(x: 130 + 104 * sin(ang), y: 130 - 104 * cos(ang))
            }
            Image(systemName: "arrow.up").font(.system(size: 30, weight: .bold)).foregroundStyle(.red)
        }
    }
}

struct TaskDetailView: View {
    @EnvironmentObject var store: SurveyStore
    let task: SurveyTask
    @Binding var draft: CaseData
    var body: some View {
        List {
            Section("怎么做") { Text(task.instruction) }
            Section("备注") {
                TextField("补充说明（可选）", text: noteBinding, axis: .vertical).lineLimit(2...5)
            }
            Section {
                if task.kind == .heading {
                    NavigationLink {
                        CompassView(draft: $draft)
                    } label: { Label("打开罗盘记录", systemImage: "location.north.circle") }
                } else if task.kind == .scan3D {
                    NavigationLink {
                        RoomScanView(task: task, draft: $draft)
                    } label: { Label("开始 3D 扫描", systemImage: "cube.transparent") }
                } else if task.kind == .arTrack {
                    NavigationLink {
                        ARTrackView(task: task, draft: $draft)
                    } label: { Label("开始记录轨迹", systemImage: "point.topleft.down.curvedto.point.bottomright.up") }
                } else {
                    NavigationLink {
                        CaptureView(task: task, draft: $draft)
                    } label: {
                        Label(task.kind == .photo ? "去拍照" : "去录像", systemImage: task.kind == .photo ? "camera" : "video")
                    }
                }
                Toggle("标记完成", isOn: doneBinding)
            }
            let items = draft.media.filter { $0.taskId == task.id }
            if !items.isEmpty {
                Section("本项已采集（\(items.count)）") {
                    ForEach(items) { m in
                        Text("\(m.kind == "photo" ? "照片" : "视频") · 真北 \(CompassMath.format(m.trueHeading)) \(m.mountain) · \(SurveyStore.timeFormatter.string(from: m.timestamp))")
                            .font(.caption)
                    }
                }
            }
        }
        .navigationTitle(task.title)
        .navigationBarTitleDisplayMode(.inline)
    }
    private var noteBinding: Binding<String> {
        Binding(get: { draft.taskNotes[task.id] ?? "" },
                set: { draft.taskNotes[task.id] = $0 })
    }
    private var doneBinding: Binding<Bool> {
        Binding(get: { draft.taskDone[task.id] ?? false },
                set: { draft.taskDone[task.id] = $0 })
    }
}

struct CaptureView: View {
    @EnvironmentObject var store: SurveyStore
    @EnvironmentObject var location: LocationManager
    @EnvironmentObject var motion: MotionManager
    @Environment(\.dismiss) var dismiss
    let task: SurveyTask
    @Binding var draft: CaseData
    @StateObject private var camera = CameraManager()
    @State private var samples: [HeadingSample] = []
    @State private var recordStart: Date?
    @State private var savedTip = false
    @State private var sweepStart: Double = -1   // 环拍引导：起始方位
    @State private var sweepAccum: Double = 0     // 环拍引导：已转角度（带符号累计）
    @State private var sweepLast: Double = -1

    // 本任务的「对准目标」：拍某些照片时应朝向已测过的某个方位（目标箭头引导）
    private var targetInfo: (label: String, bearing: Double)? {
        let source: String?
        switch task.id {
        case "p_front": source = "大门外朝内"        // 站在门前拍正立面＝朝房子方向
        case "p_mingtang": source = "大门外朝外"     // 门前向外看＝大门朝向
        case "p_backland": source = "房后朝外"       // 房后向外看＝房后朝向
        default: source = nil
        }
        guard let s = source,
              let h = draft.headings.last(where: { $0.pointName == s && $0.trueNorth >= 0 }) else { return nil }
        return (s, h.trueNorth)
    }
    private var isPanoramic: Bool {
        ["v_front_env", "v_back_env", "v_all", "v_yuan"].contains(task.id)
    }

    var body: some View {
        ZStack {
            CameraPreview(session: camera.session).ignoresSafeArea()
            VStack {
                // 罗盘叠加条（录像时同样可见；视频轨迹同步写入数据包）
                HStack(spacing: 10) {
                    Image(systemName: "location.north.fill").foregroundStyle(.red)
                    Text("真北 \(CompassMath.format(location.displayTrueHeading))")
                        .font(.headline)
                    if location.displayTrueHeading >= 0 {
                        Text("\(CompassMath.mountain(for: location.displayTrueHeading))山")
                            .font(.headline)
                    }
                    Spacer()
                    if camera.isRecording { Circle().fill(.red).frame(width: 10, height: 10) }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.black.opacity(0.45)).foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding()
                // 水平指示：地平线倾斜角，绿字≤2° 为端正；倾斜值会随照片/视频存进数据包
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(motion.isLevelForCamera ? Color.green : Color.orange)
                        .frame(width: 64, height: 3)
                        .rotationEffect(.degrees(motion.horizonTilt))
                    Text("地平线 \(String(format: "%+.1f°", motion.horizonTilt))")
                        .font(.caption)
                        .foregroundStyle(motion.isLevelForCamera ? .green : .orange)
                    Text(motion.isLevelForCamera ? "端正" : "把手机转正一点")
                        .font(.caption).foregroundStyle(.white.opacity(0.85))
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.black.opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                // 目标箭头：跟着箭头转，对准已测方位变绿（拍正立面/明堂/房后向外时出现）
                if let t = targetInfo, !camera.isRecording {
                    let cur = location.displayTrueHeading
                    let rel = cur >= 0 ? CompassMath.shortestDiff(from: cur, to: t.bearing) : 0
                    let aligned = cur >= 0 && abs(rel) <= 5
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(aligned ? .green : .white)
                            .rotationEffect(.degrees(rel))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("对准「\(t.label)」\(CompassMath.format(t.bearing))")
                                .font(.callout).fontWeight(.medium).foregroundStyle(.white)
                            Text(cur < 0 ? "罗盘读数中…" : (aligned ? "方向对准了，就这样拍" : "跟着箭头转：还差 \(rel > 0 ? "右" : "左") \(String(format: "%.0f°", abs(rel)))"))
                                .font(.caption)
                                .foregroundStyle(aligned ? .green : .white.opacity(0.85))
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.black.opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.top, 8)
                }
                // 环拍引导：进度环＋回起点箭头，转满一圈提示停
                if camera.isRecording && isPanoramic {
                    let cur = location.displayTrueHeading
                    let relStart = (cur >= 0 && sweepStart >= 0) ? CompassMath.shortestDiff(from: cur, to: sweepStart) : 0
                    let done = abs(sweepAccum) >= 350
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().stroke(Color.white.opacity(0.3), lineWidth: 5).frame(width: 56, height: 56)
                            Circle().trim(from: 0, to: min(1, abs(sweepAccum) / 360))
                                .stroke(Color.green, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                .frame(width: 56, height: 56)
                                .rotationEffect(.degrees(-90))
                            Image(systemName: "arrow.up")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.white)
                                .rotationEffect(.degrees(relStart))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(done ? "已转满一圈，可以停了" : "环拍中：已转 \(String(format: "%.0f°", min(360, abs(sweepAccum)))) / 360°")
                                .font(.callout).fontWeight(.medium).foregroundStyle(done ? .green : .white)
                            Text("慢慢匀速转，箭头始终指着出发方向")
                                .font(.caption).foregroundStyle(.white.opacity(0.85))
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.black.opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.top, 8)
                }
                Spacer()
                if savedTip {
                    Text("✓ 已保存").padding(8).background(.black.opacity(0.6))
                        .foregroundStyle(.white).clipShape(Capsule())
                }
                if task.kind == .photo {
                    Button {
                        camera.capturePhoto { data in
                            guard let data else { return }
                            if let item = store.savePhoto(caseId: draft.surveyCase.id, task: task, imageData: data, loc: location, tilt: abs(motion.horizonTilt)) {
                                draft.media.append(item)
                                draft.taskDone[task.id] = true
                                flashTip()
                            }
                        }
                    } label: {
                        Circle().fill(.white).frame(width: 68, height: 68)
                            .overlay(Circle().stroke(.gray, lineWidth: 3).frame(width: 56, height: 56))
                    }.padding(.bottom, 28)
                } else {
                    Button {
                        if camera.isRecording {
                            camera.stopRecording { url in
                                guard let url else { return }
                                if let item = store.saveVideo(caseId: draft.surveyCase.id, task: task,
                                                              tempURL: url, samples: samples, loc: location, tilt: abs(motion.horizonTilt)) {
                                    draft.media.append(item)
                                    draft.taskDone[task.id] = true
                                    flashTip()
                                }
                                samples = []; recordStart = nil
                            }
                        } else {
                            samples = []; recordStart = Date()
                            sweepStart = location.displayTrueHeading
                            sweepLast = location.displayTrueHeading
                            sweepAccum = 0
                            camera.startRecording()
                        }
                    } label: {
                        ZStack {
                            Circle().fill(camera.isRecording ? .gray : .red).frame(width: 68, height: 68)
                            if camera.isRecording { RoundedRectangle(cornerRadius: 4).fill(.white).frame(width: 26, height: 26) }
                        }
                    }.padding(.bottom, 28)
                }
            }
        }
        .navigationTitle(task.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { camera.configure(); location.start(); motion.start() }
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { now in
            guard camera.isRecording, let start = recordStart else { return }
            if isPanoramic {
                let curH = location.displayTrueHeading
                if curH >= 0 {
                    if sweepLast >= 0 { sweepAccum += CompassMath.shortestDiff(from: sweepLast, to: curH) }
                    sweepLast = curH
                }
            }
            samples.append(HeadingSample(t: now.timeIntervalSince(start),
                                         trueNorth: location.displayTrueHeading,
                                         magnetic: location.displayMagneticHeading))
        }
    }
    private func flashTip() {
        savedTip = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { savedTip = false }
    }
}
