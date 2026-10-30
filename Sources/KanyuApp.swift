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
import os

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
    var analysisText: String = ""   // 本地排盘断宅结论文本（随包回传）
    var id: UUID { surveyCase.id }

    init(surveyCase: SurveyCase) { self.surveyCase = surveyCase }
    enum CodingKeys: String, CodingKey { case surveyCase, headings, media, taskDone, taskNotes, analysisText }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        surveyCase = try c.decode(SurveyCase.self, forKey: .surveyCase)
        headings = try c.decodeIfPresent([HeadingReading].self, forKey: .headings) ?? []
        media = try c.decodeIfPresent([MediaItem].self, forKey: .media) ?? []
        taskDone = try c.decodeIfPresent([String: Bool].self, forKey: .taskDone) ?? [:]
        taskNotes = try c.decodeIfPresent([String: String].self, forKey: .taskNotes) ?? [:]
        analysisText = try c.decodeIfPresent(String.self, forKey: .analysisText) ?? ""
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(surveyCase, forKey: .surveyCase)
        try c.encode(headings, forKey: .headings)
        try c.encode(media, forKey: .media)
        try c.encode(taskDone, forKey: .taskDone)
        try c.encode(taskNotes, forKey: .taskNotes)
        try c.encode(analysisText, forKey: .analysisText)
    }
}

struct ExportPackage: Codable {
    var exportedAt = Date()
    var surveyCase: SurveyCase
    var headings: [HeadingReading]
    var media: [MediaItem]
    var taskNotes: [String: String]
    var analysisText: String = ""
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
    // 媒体类型中文名（导出摘要/列表共用）
    static func kindLabel(_ kind: String) -> String {
        switch kind {
        case "photo": return "照片"
        case "video": return "视频"
        case "scan3d": return "3D扫描"
        case "artrack": return "AR轨迹"
        default: return kind
        }
    }
}

// MARK: - 本地勘测引擎（离线排盘：玄空飞星＋八宅＋流年）
//
// 规则均经回源核对（2026-10-30）：
// 玄空：飞行轨迹 中→乾→兑→艮→离→坎→坤→震→巽；运盘一概顺飞；山/向盘以运盘坐/向宫星入中，
//      按坐/向山三元龙阴阳定顺逆（阳顺阴逆）。二十四山阴阳：阳＝乾坤艮巽·甲庚丙壬·寅申巳亥，阴＝余。
// 八宅：《八宅明镜》变爻口诀——不变伏位、变上爻生气、变下爻祸害、变中爻绝命、变下中爻天医、
//      变中上爻五鬼、变上下爻六煞、三爻全变延年（已用坎宅八方表逐项验过）。
// 本引擎为「下卦」盘（不替卦），结论属流派应用层，正式断宅仍以回传数据包复核为准。

enum FengshuiEngine {
    static let displayPalaces = ["巽", "离", "坤", "震", "中", "兑", "艮", "坎", "乾"] // 南上北下
    static let flightPath = ["中", "乾", "兑", "艮", "离", "坎", "坤", "震", "巽"]
    static let palaceDirection = ["坎": "正北", "艮": "东北", "震": "正东", "巽": "东南",
                                  "离": "正南", "坤": "西南", "兑": "正西", "乾": "西北", "中": "中宫"]
    static let yangMountains: Set<String> = ["乾", "坤", "艮", "巽", "甲", "庚", "丙", "壬", "寅", "申", "巳", "亥"]
    static let starNames = ["", "一白", "二黑", "三碧", "四绿", "五黄", "六白", "七赤", "八白", "九紫"]

    static func period(forYear year: Int) -> Int {
        let idx = ((year - 1864) / 20) % 9
        return (idx + 9) % 9 + 1
    }
    static func periodRange(_ p: Int) -> (Int, Int) {
        // 找 1864 起第 p 运在 1800–2200 内的最近一轮起止年
        var start = 1864 + (p - 1) * 20
        while start + 20 <= 2000 { start += 180 }
        return (start, start + 19)
    }
    // 飞星：中宫星沿轨迹布九宫，forward 顺飞递增、逆飞递减，返回 宫→星
    static func fly(center: Int, forward: Bool) -> [String: Int] {
        var out: [String: Int] = [:]
        for (i, palace) in flightPath.enumerated() {
            var v = forward ? center + i : center - i
            v = ((v - 1) % 9 + 9) % 9 + 1
            out[palace] = v
        }
        return out
    }
    struct Chart { var base: [String: Int]; var mtn: [String: Int]; var face: [String: Int] }
    static func chart(period p: Int, sitMountain: String, sitPalace: String, faceMountain: String, facePalace: String) -> Chart {
        let base = fly(center: p, forward: true)
        let mtn = fly(center: base[sitPalace] ?? 5, forward: yangMountains.contains(sitMountain))
        let face = fly(center: base[facePalace] ?? 5, forward: yangMountains.contains(faceMountain))
        return Chart(base: base, mtn: mtn, face: face)
    }
    static func annualStar(year: Int) -> Int {
        let s = (9 - ((year - 2024) % 9 + 9) % 9)
        return s == 0 ? 9 : s
    }
    // 旺衰（以当运论，流派应用层口径）
    static func vigor(_ star: Int, period p: Int) -> (label: String, good: Int) {
        if star == p { return ("旺气", 2) }
        if star == p % 9 + 1 { return ("生气", 1) }
        if star == (p + 7) % 9 + 1 { return ("退气", -1) }
        if star == 5 { return ("五黄煞", -2) }
        if star == 2 { return ("病符", -1) }
        return ("平稳", 0)
    }
    static let comboNotes: [String: String] = [
        "2-5": "二五交加：病符遇五黄，此宫忌动土久坐，健康留意",
        "5-2": "二五交加：病符遇五黄，此宫忌动土久坐，健康留意",
        "5-5": "五黄重临：此宫大忌动土与红色火源，宜静不宜动",
        "2-2": "病符叠加：此宫宜保持通风洁净，病人房慎选",
        "6-7": "交剑煞：口舌争竞，此宫慎置利器与争吵位",
        "7-6": "交剑煞：口舌争竞，此宫慎置利器与争吵位",
        "2-7": "二七火曜：防厨房火源与失盗，此宫慎明火",
        "7-9": "七九火旺：此宫慎火源电器，心血管人群慎居",
        "9-7": "七九火旺：此宫慎火源电器，心血管人群慎居",
        "1-6": "一六共宗：文昌官星，此宫宜书桌与办公位",
        "6-8": "六八武财：此宫宜财位与动线，利武职生意",
        "8-9": "八九喜庆财星：此宫宜客厅与门位，喜用",
        "8-6": "六八武财：此宫宜财位与动线，利武职生意",
        "9-9": "九紫重临：喜庆旺气，此宫宜门与客厅",
        "1-9": "一九桃花文昌：宜书房，桃花位慎处理",
        "9-1": "一九桃花文昌：宜书房，桃花位慎处理",
    ]

    // 组合化解要点（与知识库 09 号手册同源，L1 优先、L2 流派、L3 民俗须分清）
    static let comboRemedies: [String: String] = [
        "2-5": "化解：此宫当年忌动土钻敲、忌久坐久卧；保持通风干燥；以金泄土——置一口金属钟或一串铜钱即可（忌堆砌），宫内忌红、黄助土。",
        "5-2": "化解：此宫当年忌动土钻敲、忌久坐久卧；保持通风干燥；以金泄土——置一口金属钟或一串铜钱即可（忌堆砌），宫内忌红、黄助土。",
        "5-5": "化解：此宫大忌动土与装修，保持安静洁净，能空置最好；金属钟泄土，忌红黄；流年五黄再叠临此宫时尤其慎之。",
        "2-2": "化解：此宫保持通风采光与干燥（卫生层即正解）；不作病人久卧房；金属小件泄土为辅。",
        "6-7": "化解：此宫不放利器、不作争吵对峙位；以水通关——置静水或蓝黑色织物（流派层）；家人沟通问题回到沟通本身。",
        "7-6": "化解：此宫不放利器、不作争吵对峙位；以水通关——置静水或蓝黑色织物（流派层）；家人沟通问题回到沟通本身。",
        "2-7": "化解：此宫若为厨房，先做燃气报警、灭火器、电路复核（结构层真化解）；忌再添红色火色助势，宜金属色平衡。",
        "7-9": "化解：此宫慎大功率电器久置与明火；忌红黄助火土；保持清爽通风。",
        "9-7": "化解：此宫慎大功率电器久置与明火；忌红黄助火土；保持清爽通风。",
    ]

    // MARK: 八宅
    // 爻位自下而上 [初, 中, 上]，1=阳 0=阴
    static let trigramBits: [String: [Int]] = [
        "乾": [1, 1, 1], "坤": [0, 0, 0], "坎": [0, 1, 0], "离": [1, 0, 1],
        "震": [1, 0, 0], "巽": [0, 1, 1], "艮": [0, 0, 1], "兑": [1, 1, 0],
    ]
    static let bitsToTrigram: [[Int]: String] = Dictionary(uniqueKeysWithValues: trigramBits.map { ($0.value, $0.key) })
    // 变爻型（初/中/上哪几爻不同）→ 游年星，《八宅明镜》口诀
    static func youNianStar(diff: [Int]) -> String {
        switch diff {
        case [0, 0, 0]: return "伏位"
        case [0, 0, 1]: return "生气"
        case [1, 0, 0]: return "祸害"
        case [0, 1, 0]: return "绝命"
        case [1, 1, 0]: return "天医"
        case [0, 1, 1]: return "五鬼"
        case [1, 0, 1]: return "六煞"
        case [1, 1, 1]: return "延年"
        default: return ""
        }
    }
    static let goodStars: Set<String> = ["生气", "天医", "延年", "伏位"]
    // 宅卦（坐宫卦）→ 八方游年（键为方位宫卦名）
    static func youNian(house: String) -> [String: String] {
        guard let hb = trigramBits[house] else { return [:] }
        var out: [String: String] = [:]
        for (palace, bits) in trigramBits {
            let diff = zip(hb, bits).map { $0 == $1 ? 0 : 1 }
            out[palace] = youNianStar(diff: diff)
        }
        return out
    }
    static func mingGua(birthYear: Int, gender: String) -> String {
        let yy = birthYear % 100
        var r = gender == "男" ? (100 - yy) % 9 : (yy - 4) % 9
        r = ((r % 9) + 9) % 9
        switch r {
        case 1: return "坎"; case 2: return "坤"; case 3: return "震"; case 4: return "巽"
        case 6: return "乾"; case 7: return "兑"; case 8: return "艮"; case 0, 9: return "离"
        case 5: return gender == "男" ? "坤" : "艮"
        default: return ""
        }
    }
    static let eastFour: Set<String> = ["坎", "震", "巽", "离"]
    static func group(of gua: String) -> String { eastFour.contains(gua) ? "东四" : "西四" }
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
    func saveARTrack(caseId: UUID, task: SurveyTask, samples: [ARTrackSample], loc: LocationManager, note: String = "") -> MediaItem? {
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
                         longitude: loc.currentLocation?.coordinate.longitude,
                         note: note)
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
                for f in [m.fileName, m.stampedFileName, m.samplesFileName, m.extraFile.isEmpty ? nil : m.extraFile].compactMap({ $0 }) {
                    let from = src.appendingPathComponent(f)
                    if FileManager.default.fileExists(atPath: from.path) {
                        try FileManager.default.copyItem(at: from, to: tmp.appendingPathComponent(f))
                    }
                }
            }
            let pkg = ExportPackage(surveyCase: sc, headings: caseData.headings,
                                    media: caseData.media, taskNotes: caseData.taskNotes,
                                    analysisText: caseData.analysisText)
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
            s += "[\(CompassMath.kindLabel(m.kind))] \(m.taskTitle)｜真北 \(CompassMath.format(m.trueHeading)) \(m.mountain)｜\(m.fileName)\(m.extraFile.isEmpty ? "" : "｜附 \(m.extraFile)")\(m.tilt >= 0 ? "｜倾斜 \(String(format: "%.1f°", m.tilt))" : "")\(m.note.isEmpty ? "" : "｜备注：\(m.note)")\n"
        }
        if !cd.taskNotes.isEmpty {
            s += "\n任务备注\n----------------\n"
            for (tid, note) in cd.taskNotes where !note.isEmpty {
                s += "\(tid)：\(note)\n"
            }
        }
        if !cd.analysisText.isEmpty {
            s += "\n本地排盘结论（App 离线推演，流派层口径）\n----------------\n\(cd.analysisText)\n"
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
        let barH = max(120, image.size.height * 0.105)
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
    // 线程安全快照：ARKit 委托回调在非主线程读罗盘值走这里（类本身是 MainActor，直读会编译报错）
    private let headingBox = OSAllocatedUnfairLock(initialState: (mag: -1.0, tru: -1.0))
    nonisolated var currentTrueHeadingSnapshot: Double {
        headingBox.withLock { $0.tru >= 0 ? $0.tru : $0.mag }
    }

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
        headingBox.withLock { $0 = (mag: m, tru: t) }
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
    @Published var fieldMicroTesla: Double = -1   // 总磁场强度 µT（地磁场正常 25–65）
    @Published var cameraPitch: Double = 0        // 镜头俯仰角（度，+ 仰拍 / − 俯拍，水平正对为 0）

    private let motion = CMMotionManager()
    var isLevelForCompass: Bool { flatTilt <= 3 }
    var isLevelForCamera: Bool { abs(horizonTilt) <= 2 }
    // 磁场强度明显超出地磁场范围＝附近有磁干扰（汽车/钢筋/磁吸壳/电器）
    var fieldAbnormal: Bool { fieldMicroTesla >= 0 && (fieldMicroTesla < 20 || fieldMicroTesla > 80) }

    func start() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 0.1
        // 用真北参考系（重力读数与参考系无关，另可拿到校准磁场强度做干扰检测）
        let frames = CMMotionManager.availableAttitudeReferenceFrames()
        let frame: CMAttitudeReferenceFrame = frames.contains(.xTrueNorthZVertical) ? .xTrueNorthZVertical : .xArbitraryZVertical
        motion.startDeviceMotionUpdates(using: frame, to: .main) { [weak self] dm, _ in
            guard let dm else { return }
            let g = dm.gravity
            let len = (g.x * g.x + g.y * g.y + g.z * g.z).squareRoot()
            guard len > 0 else { return }
            let gx = g.x / len, gy = g.y / len, gz = g.z / len
            let flat = acos(min(1, max(-1, -gz))) * 180 / .pi
            let horizon = atan2(gx, -gy) * 180 / .pi
            let pitch = asin(min(1, max(-1, gz))) * 180 / .pi
            let f = dm.magneticField.field
            let mag = (f.x * f.x + f.y * f.y + f.z * f.z).squareRoot()
            Task { @MainActor in
                self?.flatTilt = flat
                self?.horizonTilt = horizon
                self?.cameraPitch = pitch
                self?.bubbleX = gx
                self?.bubbleY = gy
                if dm.magneticField.accuracy.rawValue >= 0 { self?.fieldMicroTesla = mag }  // 精度有效（非 invalid=-1）才更新磁场强度
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

    @Published var zoomFactor: CGFloat = 1

    // 变焦（拍远处案山/来龙/对面建筑用，1–5 倍，硬件上限内）
    func setZoom(_ f: CGFloat) {
        guard let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { return }
        let clamped = min(max(f, 1), min(5, dev.activeFormat.videoMaxZoomFactor))
        do {
            try dev.lockForConfiguration()
            dev.videoZoomFactor = clamped
            dev.unlockForConfiguration()
            DispatchQueue.main.async { self.zoomFactor = clamped }
        } catch {}
    }

    func capturePhoto(completion: @escaping (Data?) -> Void) {
        photoCompletion = completion
        if let conn = photoOutput.connection(with: .video), conn.isVideoOrientationSupported {
            conn.videoOrientation = .portrait
        }
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func startRecording() {
        // 固定竖屏方向，避免录像回放时画面躺倒
        if let conn = movieOutput.connection(with: .video), conn.isVideoOrientationSupported {
            conn.videoOrientation = .portrait
        }
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
                              compassHeading: loc?.currentTrueHeadingSnapshot ?? -1)
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
                        // 质量自评：AR 与罗盘的平均偏差（漂移指标）＋首尾距离（绕圈任务看闭合）
                        let ss = recorder.samples
                        let devs = ss.compactMap { $0.compassHeading >= 0 ? abs(CompassMath.shortestDiff(from: $0.compassHeading, to: $0.arHeading)) : nil }
                        let meanDev = devs.isEmpty ? -1 : devs.reduce(0, +) / Double(devs.count)
                        var note = "轨迹点 \(ss.count) 个 · 总长 \(String(format: "%.1f", recorder.distance)) 米"
                        if meanDev >= 0 { note += " · AR/罗盘平均偏差 \(String(format: "%.1f°", meanDev))" }
                        if let f = ss.first, let l = ss.last, ss.count > 20 {
                            let dx = l.x - f.x, dz = l.z - f.z
                            note += " · 首尾相距 \(String(format: "%.1f", (dx * dx + dz * dz).squareRoot())) 米"
                        }
                        if let item = store.saveARTrack(caseId: draft.surveyCase.id, task: task, samples: ss, loc: location, note: note) {
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
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let error { self.failedText = "扫描失败：\(error.localizedDescription)"; return }
            self.capturedRoom = data
            self.finished = true
        }
    }
    func reset() { capturedRoom = nil; finished = false; failedText = "" }
    // 结构摘要：墙/门/窗/开口的尺寸（米）与家具类别，回传后用于户型核对与九宫量算
    func summaryJSON(startHeading: Double) -> Data? {
        guard let room = capturedRoom else { return nil }
        func surf(_ s: CapturedRoom.Surface) -> [String: Any] {
            ["category": "\(s.category)", "length": Double(s.dimensions.x), "height": Double(s.dimensions.y)]
        }
        let dict: [String: Any] = [
            "startTrueHeading": startHeading,
            "units": "meters",
            "note": "RoomPlan 激光雷达扫描生成，供户型量算参考；关键尺寸请现场复核（平面直角假设，异形/曲面可能失真）",
            "walls": room.walls.map(surf),
            "doors": room.doors.map(surf),
            "windows": room.windows.map(surf),
            "openings": room.openings.map(surf),
            "floors": room.floors.map(surf),
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
            controller.reset()
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

// App 图标（定盘针 Logo，B 版）：空状态页品牌图，文件缺失时回退系统符号
struct AppLogoView: View {
    var size: CGFloat = 84
    var body: some View {
        if let path = Bundle.main.path(forResource: "AppIcon", ofType: "png"),
           let ui = UIImage(contentsOfFile: path) {
            Image(uiImage: ui).resizable().scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
        } else {
            Image(systemName: "compass.drawing").font(.system(size: size * 0.55)).foregroundStyle(.secondary)
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
                        AppLogoView()
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
                                    let total = TaskFactory.tasks(for: cd.surveyCase.type).count
                                    let done = TaskFactory.tasks(for: cd.surveyCase.type).filter { cd.taskDone[$0.id] == true }.count
                                    Text("\(cd.surveyCase.type.rawValue) · \(cd.surveyCase.locationNote) · 任务 \(done)/\(total) · 媒体 \(cd.media.count) 项 · 罗盘 \(cd.headings.count) 个")
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
                    Section("采集进度") {
                        let tasks = TaskFactory.tasks(for: d.surveyCase.type)
                        let done = tasks.filter { d.taskDone[$0.id] == true }.count
                        ProgressView(value: Double(done), total: Double(max(1, tasks.count)))
                        Text("任务 \(done)/\(tasks.count) 已完成 · 罗盘 \(d.headings.count) 个 · 已采集媒体 \(d.media.count) 项")
                            .font(.caption).foregroundStyle(.secondary)
                    }
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
                        crossCheckNote(d)
                    }
                    Section("本地勘测（离线）") {
                        NavigationLink {
                            AnalysisView(draft: binding)
                        } label: { Label("排盘断宅：玄空＋八宅＋流年", systemImage: "square.grid.3x3.square") }
                        NavigationLink {
                            KnowledgeView()
                        } label: { Label("风水知识卡（速查）", systemImage: "books.vertical") }
                        if !d.analysisText.isEmpty {
                            Text("已存本地结论：\(d.analysisText.components(separatedBy: "\n").first ?? "")…")
                                .font(.caption).foregroundStyle(.secondary)
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

    // 互校提示：大门「朝外」与「朝内」两读数应相差约 180°，偏差大说明其一受了干扰
    @ViewBuilder private func crossCheckNote(_ d: CaseData) -> some View {
        if let out = d.headings.last(where: { $0.pointName == "大门外朝外" }),
           let inn = d.headings.last(where: { $0.pointName == "大门外朝内" }) {
            let dev = abs(abs(CompassMath.shortestDiff(from: out.trueNorth, to: inn.trueNorth)) - 180)
            if dev > 10 {
                Text("互校提醒：大门朝外/朝内应差 180°，实差偏差 \(String(format: "%.0f°", dev))——其中一个测点多半受了磁干扰，建议换位置重测。")
                    .font(.caption).foregroundStyle(.orange)
            } else {
                Text("互校通过：大门朝外/朝内互差 180° 偏差仅 \(String(format: "%.0f°", dev))，坐向可信。")
                    .font(.caption).foregroundStyle(.green)
            }
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
    @State private var weakTrue: [Double] = []
    @State private var weakMag: [Double] = []
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
                    if motion.fieldMicroTesla >= 0 {
                        Text("磁场强度 \(String(format: "%.0f", motion.fieldMicroTesla)) µT（地磁场正常 25–65）\(motion.fieldAbnormal ? "：异常，附近有磁干扰" : "")")
                            .font(.caption)
                            .foregroundStyle(motion.fieldAbnormal ? .red : .secondary)
                    }
                }
                if location.accuracyWarning != nil || motion.fieldAbnormal {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("精度自检（校准好后可达 ±5° 左右）").font(.caption).fontWeight(.semibold)
                        Text("1. 摘掉磁吸手机壳、磁吸支架（能让读数偏几十度）\n2. 离汽车、钢筋、电器 2 米以上\n3. 手腕画 8 字三圈校准\n4. 设置 → 隐私与安全性 → 定位服务 → 系统服务：打开「指南针校准」和「运动校准与距离」")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.orange.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
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
                        VStack(alignment: .leading, spacing: 1) {
                            HStack {
                                Text(h.pointName).font(.callout)
                                Spacer()
                                Text("\(CompassMath.format(h.trueNorth)) \(h.mountain)山").font(.callout).foregroundStyle(.secondary)
                            }
                            if h.headingAccuracy >= 0 || h.tiltDegrees >= 0 || h.sampleSpread >= 0 {
                                Text("精度 ±\(Int(h.headingAccuracy))° · 倾斜 \(h.tiltDegrees >= 0 ? String(format: "%.1f°", h.tiltDegrees) : "—") · 集中度 \(h.sampleSpread >= 0 ? String(format: "%.2f", h.sampleSpread) : "—")\((h.sampleSpread >= 0 && h.sampleSpread < 0.9) || h.headingAccuracy > 15 ? "（这条不太稳，建议重测）" : "")")
                                    .font(.caption2)
                                    .foregroundStyle((h.sampleSpread >= 0 && h.sampleSpread < 0.9) || h.headingAccuracy > 15 ? .orange : .secondary)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }.padding()
        }
        .navigationTitle("罗盘定向")
        .onAppear { location.start(); motion.start() }
        .onDisappear { collectTask?.cancel() }
    }

    // 采样循环用 Task 驱动（v1.3 用视图层 Timer 发布者，真机上不触发导致永远 0/8，已改）
    // 采样门控：精度 ±20° 以内才算正式样本；±20–35° 只进备选桶；磁场异常/精度更差不采。
    private func startCollect() {
        collecting = true; trueSamples = []; magSamples = []; weakTrue = []; weakMag = []; collectTicks = 0
        collectHint = "采样中：把气泡稳在绿圈里…"
        collectTask?.cancel()
        collectTask = Task { @MainActor in
            while collecting && trueSamples.count < 8 && collectTicks < 90 {
                let acc = location.headingAccuracy
                if motion.fieldAbnormal {
                    collectHint = "磁场异常（\(String(format: "%.0f", motion.fieldMicroTesla)) µT）：附近有磁干扰，换个位置再测"
                } else if !motion.isLevelForCompass {
                    collectHint = "没放平，不采样：把气泡稳进绿圈（当前倾斜 \(String(format: "%.1f°", motion.flatTilt))）"
                } else if location.displayTrueHeading >= 0 && acc >= 0 {
                    if acc <= 20 {
                        appendSample(&trueSamples, &magSamples)
                        collectHint = "采样中：已采 \(trueSamples.count)/8（精度 ±\(Int(acc))°），保持放平…"
                    } else if acc <= 35 {
                        appendSample(&weakTrue, &weakMag)
                        collectHint = "当前精度差（±\(Int(acc))°），只作备选采样：先按下方自检校准一遍…"
                    } else {
                        collectHint = "精度太低（±\(Int(acc))°）不采样：按下方自检做一遍再测"
                    }
                }
                if trueSamples.count >= 8 { finishCollect(); return }
                collectTicks += 1
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
            if collecting {
                if trueSamples.count >= 4 {
                    finishCollect()
                } else if weakTrue.count >= 4 {
                    trueSamples = weakTrue; magSamples = weakMag
                    finishCollect(lowAccuracy: true)
                } else {
                    collecting = false
                    collectHint = "这次没采够：按下方精度自检做一遍，换个位置再测。"
                }
            }
        }
    }

    // 尖峰剔除：与已采样本圆周均值偏差 >15° 的读数丢弃（防干扰毛刺污染平均）
    private func appendSample(_ t: inout [Double], _ m: inout [Double]) {
        if t.count >= 3 {
            let (mean, _) = CompassMath.circularMean(t)
            if abs(CompassMath.shortestDiff(from: mean, to: location.displayTrueHeading)) > 15 { return }
        }
        t.append(location.displayTrueHeading)
        m.append(location.displayMagneticHeading)
    }

    private var bubbleOffset: (Double, Double) {
        let dx = min(1, max(-1, motion.bubbleX / 0.25)) * 27
        let dy = min(1, max(-1, -motion.bubbleY / 0.25)) * 27
        return (dx, dy)
    }

    private func finishCollect(lowAccuracy: Bool = false) {
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
        collectHint = lowAccuracy
            ? "已记录（低精度备选样本 \(trueSamples.count) 次平均，精度 ±\(Int(location.headingAccuracy))°，已标注；能重测尽量重测）"
            : "已记录：\(trueSamples.count) 次采样平均，集中度 \(String(format: "%.2f", r))（越接近 1 越稳）"
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

// MARK: - 本地勘测界面（离线排盘断宅＋知识卡）

struct AnalysisView: View {
    @Binding var draft: CaseData
    @State private var manualMountain = "子"
    @State private var periodOverride = 0          // 0=按建成年自动，1–9 手动
    @State private var annualYear = 2026
    @State private var savedTip = false

    private var sitReading: HeadingReading? { draft.headings.last(where: { $0.pointName == "大门外朝内" && $0.trueNorth >= 0 }) }
    private var sitMountain: String {
        if let r = sitReading { return CompassMath.mountain(for: r.trueNorth) }
        return manualMountain
    }
    private var faceMountain: String {
        let i = CompassMath.mountains.firstIndex(of: sitMountain) ?? 0
        return CompassMath.mountains[(i + 12) % 24]
    }
    private var sitPalace: String { CompassMath.palace(for: Double(CompassMath.mountains.firstIndex(of: sitMountain) ?? 0) * 15) }
    private var facePalace: String { CompassMath.palace(for: Double(CompassMath.mountains.firstIndex(of: faceMountain) ?? 12) * 15) }
    private var buildYear: Int { Int(draft.surveyCase.builtYear) ?? Int(draft.surveyCase.movedInYear) ?? 0 }
    private var period: Int { periodOverride > 0 ? periodOverride : (buildYear > 0 ? FengshuiEngine.period(forYear: buildYear) : 9) }
    private var chart: FengshuiEngine.Chart {
        FengshuiEngine.chart(period: period, sitMountain: sitMountain, sitPalace: sitPalace, faceMountain: faceMountain, facePalace: facePalace)
    }

    var body: some View {
        List {
            Section("定盘") {
                if let r = sitReading {
                    LabeledContent("坐向来源", value: "罗盘实测「大门外朝内」\(CompassMath.format(r.trueNorth))")
                } else {
                    Picker("坐山（未测罗盘时手选）", selection: $manualMountain) {
                        ForEach(CompassMath.mountains, id: \.self) { Text($0).tag($0) }
                    }
                    Text("提示：先在罗盘页记录「大门外朝内」再回来，定盘以实测为准。").font(.caption).foregroundStyle(.orange)
                }
                LabeledContent("坐向", value: "\(sitMountain)山\(faceMountain)向 · 坐\(sitPalace)宫向\(facePalace)宫")
                LabeledContent("建成年", value: buildYear > 0 ? "\(buildYear)" : "未填（暂按九运）")
                Picker("元运", selection: $periodOverride) {
                    Text("自动（\(period)运）").tag(0)
                    ForEach(1...9, id: \.self) { Text("\($0)运").tag($0) }
                }
                let (ps, pe) = FengshuiEngine.periodRange(period)
                LabeledContent("本运区间", value: "\(ps)–\(pe) 年")
            }
            Section("玄空飞星盘（\(period)运 · 下卦）左上山星 右上向星 下运星") {
                chartGrid
                patternNote
                ForEach(comboLines, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
            }
            Section("流年飞星（入中星沿洛书顺飞）") {
                Stepper("年份：\(annualYear)（\(FengshuiEngine.starNames[FengshuiEngine.annualStar(year: annualYear)])入中）", value: $annualYear, in: 2000...2050)
                annualGrid
            }
            Section("八宅（宅卦 \(sitPalace) · \(FengshuiEngine.group(of: sitPalace))宅）") {
                let yn = FengshuiEngine.youNian(house: sitPalace)
                ForEach(FengshuiEngine.displayPalaces.filter { $0 != "中" }, id: \.self) { p in
                    HStack {
                        Text("\(p)宫 · \(FengshuiEngine.palaceDirection[p] ?? "")")
                        Spacer()
                        let star = yn[p] ?? ""
                        Text(star).foregroundStyle(FengshuiEngine.goodStars.contains(star) ? .green : .red)
                    }
                }
                ForEach(draft.surveyCase.residents) { r in
                    if let y = Int(r.birthYear) {
                        let g = FengshuiEngine.mingGua(birthYear: y, gender: r.gender)
                        let match = FengshuiEngine.group(of: g) == FengshuiEngine.group(of: sitPalace)
                        Text("\(r.label.isEmpty ? "住户" : r.label)：命卦 \(g)（\(FengshuiEngine.group(of: g))命），与宅 \(match ? "相配" : "不配——床位优先取其命卦四吉方")")
                            .font(.caption).foregroundStyle(match ? .secondary : .orange)
                    }
                }
            }
            Section("本地结论（分层）") {
                ForEach(conclusionLines, id: \.self) { Text($0).font(.callout) }
                Button {
                    draft.analysisText = conclusionLines.joined(separator: "\n")
                    savedTip = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { savedTip = false }
                } label: { Label(savedTip ? "✓ 已存入案件（随数据包回传）" : "把结论存入案件", systemImage: "square.and.arrow.down") }
                Text("口径：本地推演为流派应用层规则计算，现场先行参考；正式断宅以数据包回传复核为准（见工作手册分工）。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("本地排盘断宅")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var chartGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            ForEach(FengshuiEngine.displayPalaces, id: \.self) { p in
                if p == "中" {
                    VStack(spacing: 2) {
                        Text("中宫").font(.caption).foregroundStyle(.secondary)
                        Text("\(period)").font(.title3).fontWeight(.bold)
                        Text("\(period)运").font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 74)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    let m = chart.mtn[p] ?? 5, f = chart.face[p] ?? 5, b = chart.base[p] ?? 5
                    VStack(spacing: 2) {
                        HStack {
                            Text("\(m)").foregroundStyle(FengshuiEngine.vigor(m, period: period).good > 0 ? .green : (FengshuiEngine.vigor(m, period: period).good < 0 ? .red : .primary))
                            Spacer()
                            Text("\(f)").foregroundStyle(FengshuiEngine.vigor(f, period: period).good > 0 ? .green : (FengshuiEngine.vigor(f, period: period).good < 0 ? .red : .primary))
                        }.font(.headline)
                        Text("\(p) · \(FengshuiEngine.palaceDirection[p] ?? "")").font(.caption).fontWeight(.medium)
                        Text("运 \(b)").font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, minHeight: 74)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
    }

    private var annualGrid: some View {
        let c = FengshuiEngine.annualStar(year: annualYear)
        let grid = FengshuiEngine.fly(center: c, forward: true)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            ForEach(FengshuiEngine.displayPalaces, id: \.self) { p in
                VStack(spacing: 1) {
                    Text(p == "中" ? "\(c)" : "\(grid[p] ?? 5)")
                        .font(.headline)
                        .foregroundStyle((grid[p] ?? 5) == 5 ? .red : .primary)
                    Text(p).font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
    }

    @ViewBuilder private var patternNote: some View {
        let mSit = chart.mtn[sitPalace] ?? 0, fFace = chart.face[facePalace] ?? 0
        let mFace = chart.mtn[facePalace] ?? 0, fSit = chart.face[sitPalace] ?? 0
        if mSit == period && fFace == period {
            Text("格局：旺山旺向——坐方山星当旺、向方水星当旺，坐后见山、向前见水为上局。").font(.callout).foregroundStyle(.green)
        } else if mFace == period && fSit == period {
            Text("格局：上山下水——旺星错位：坐方宜见水、向方宜见山（或以动线/门路化解），断语须结合峦头。").font(.callout).foregroundStyle(.orange)
        } else if fFace == period && fSit == period {
            Text("格局：双星到向——向首旺气集中，利财利门面，坐后宜实不宜虚。").font(.callout)
        } else if mSit == period && mFace == period {
            Text("格局：双星到坐——坐山旺气集中，利丁利健康，向前宜开阔。").font(.callout)
        } else {
            Text("格局：无成格——按各宫山向星旺衰逐宫论，重点看向首、坐宫与门位所在宫。").font(.callout).foregroundStyle(.secondary)
        }
    }

    private var comboLines: [String] {
        var out: [String] = []
        for p in FengshuiEngine.displayPalaces where p != "中" {
            let key = "\(chart.mtn[p] ?? 0)-\(chart.face[p] ?? 0)"
            if let note = FengshuiEngine.comboNotes[key] {
                var line = "\(p)宫（\(FengshuiEngine.palaceDirection[p] ?? "")）：\(note)"
                if let rem = FengshuiEngine.comboRemedies[key] { line += "\n" + rem }
                out.append(line)
            }
        }
        return out
    }

    private var conclusionLines: [String] {
        var lines: [String] = []
        lines.append("【实测层】坐向：\(sitMountain)山\(faceMountain)向（坐\(sitPalace)向\(facePalace)）\(sitReading != nil ? "，罗盘实测入盘" : "，手选坐山（未实测，仅供预演）")；元运：\(period)运（建成年 \(buildYear > 0 ? String(buildYear) : "未填")）。")
        let mSit = chart.mtn[sitPalace] ?? 0, fFace = chart.face[facePalace] ?? 0
        lines.append("【流派层·玄空】坐宫山星 \(mSit)（\(FengshuiEngine.vigor(mSit, period: period).label)），向首水星 \(fFace)（\(FengshuiEngine.vigor(fFace, period: period).label)）；五黄到 \(FengshuiEngine.displayPalaces.first(where: { chart.face[$0] == 5 }) ?? "—") 宫（向星）宜静。")
        for c in comboLines { lines.append("【流派层·玄空】\(c)") }
        let yn = FengshuiEngine.youNian(house: sitPalace)
        let good = FengshuiEngine.displayPalaces.filter { $0 != "中" && FengshuiEngine.goodStars.contains(yn[$0] ?? "") }.map { "\($0)（\(yn[$0] ?? "")）" }.joined(separator: "、")
        lines.append("【流派层·八宅】\(sitPalace)宅四吉方：\(good)。门、床、灶优先落四吉方，四凶方宜作卫浴、储物、楼梯。")
        lines.append("【流年】\(annualYear) 年 \(FengshuiEngine.starNames[FengshuiEngine.annualStar(year: annualYear)])入中：五黄在 \(FengshuiEngine.displayPalaces.first(where: { FengshuiEngine.fly(center: FengshuiEngine.annualStar(year: annualYear), forward: true)[$0] == 5 }) ?? "—") 宫，该方当年忌动土。")
        lines.append("【边界】以上为 App 本地规则推演（流派应用层）；形煞与 L1 结构问题以现场照片与回传复核为准。")
        return lines
    }
}

// MARK: - 犯煞解说与解煞手册（离线，与知识库 09 号同源）

struct ShaEntry: Identifiable {
    let id = UUID()
    let name: String, category: String, identify: String, why: String, impact: String, remedy: String
}

enum ShaLibrary {
    static let entries: [ShaEntry] = [
        ShaEntry(name: "路冲（枪煞）", category: "峦头形煞",
                 identify: "道路、长巷、走廊正对大门或主窗；路越宽长、车速越快、距离越近论越重。",
                 why: "实证：车流直冲带来噪声、尾气粉尘、夜间车灯直射与失控车辆的真实风险，正对感也造成心理压迫。流派：气直贯无回旋，称直来直去难聚。",
                 impact: "传统主应（流派层）：意外损伤、破财、家宅不宁。注：玄空有「冲在当旺方反吉、商铺喜冲」说，高层远离地面者降级。",
                 remedy: "L1 门内玄关/屏风折线、门前密植两层常绿绿植消能、正对窗换防噪窗＋遮光帘、能改门向最彻底。L2 按向盘旺衰定去留：旺向之冲可留、衰向之冲必改。L3 门前泰山石敢当、珠帘（民俗）。"),
        ShaEntry(name: "反弓煞", category: "峦头形煞",
                 identify: "道路、河流、高架呈弧形，弓背（凸面）对着宅；凹面环抱为「有情」不算。",
                 why: "实证：弯道外侧正是车辆易冲出、灯光扫射、噪声反射的方位。流派：水路无情反跳，财来财去。",
                 impact: "传统主应（流派层）：破财反复、离散、宅运不稳。",
                 remedy: "L1 能避则避：选位后缩、偏移弓背正对点；正对面密植高绿篱，临窗加遮光隔音。L2 落衰煞宫更须处理，落旺宫降调。L3 石敢当、阔叶大盆栽（民俗）。反弓大而急时布置作用有限，以避为先。"),
        ShaEntry(name: "天斩煞", category: "峦头形煞",
                 identify: "两栋高楼之间的窄缝，正对本宅窗户或阳台。",
                 why: "实证：窄缝风洞效应真实存在——缝口风速显著加大，直吹窗门、冬寒夏噪。流派：如刀劈中分，象意凶厉。",
                 impact: "传统主应（流派层）：伤灾手术、家宅争执。断到具体某病属流派语言，不采。",
                 remedy: "L1 正对窗以磨砂贴膜/百叶/厚帘遮断缝线，缝风直吹处不设床与久坐位，窗台高绿植挡风。L2 缝位落宫按飞星旺衰参断。L3 山海镇、葫芦对缝（民俗）。"),
        ShaEntry(name: "壁刀煞（墙角冲射）", category: "峦头形煞",
                 identify: "邻楼墙体侧面如刀刃、或墙角棱线正对本宅门窗、床位；刃越长、距离越近越重。",
                 why: "实证：棱线无直接物理伤害，但长期正对锐角的压迫与「切入」视觉象意明确。流派：形如刀切，主损伤割裂。",
                 impact: "传统主应（流派层）：意外割伤、手术、关系破裂。",
                 remedy: "L1 窗帘/百叶遮断刃线，床与座位移开正对线，墙边绿植软化。L2 落宫旺衰参断。L3 凸面镜、山海镇对刃（民俗；长壁刀慎用镜反射，防扰邻）。"),
        ShaEntry(name: "尖角煞", category: "峦头形煞",
                 identify: "屋檐角、三角构件、邻楼锐角、室内家具尖角正对门窗或床、沙发、书桌。",
                 why: "实证：室内尖角对床主要是碰撞安全与心理压迫；室外尖角为象意层。流派：尖冲如箭。",
                 impact: "传统主应（流派层）：口舌是非、眼目与筋骨小伤。",
                 remedy: "L1 家具换圆角/加防撞角、移床移桌避正对、绿植或布艺遮角；室外者以帘遮。L3 阔叶植物对冲（兼 L1 遮挡功能可用，不神化）。"),
        ShaEntry(name: "穿心煞 / 穿堂", category: "峦头形煞",
                 identify: "地面：大门直对后门或大窗一线贯通；地下：隧道、地铁、地下通道纵贯宅基。",
                 why: "实证：穿堂风速过强、不聚温、隐私一览无余；地下穿心可感的是振动与噪声。流派：气穿而不聚，主财来财去。",
                 impact: "传统主应（流派层）：破财难聚、家运起伏、关系松散。",
                 remedy: "L1 玄关、屏风、柜体、珠帘任一折线即解地面穿堂（首选）；地毯挂画辅助。地下穿心以减振隔音装修处理，余者降调，不恐吓。"),
        ShaEntry(name: "横梁压顶", category: "峦头形煞",
                 identify: "梁正压床头、沙发、书桌、灶台上方且净高低、压迫感实存。梁在过道、已包吊顶者不论。",
                 why: "实证：低梁的空间压迫与起身碰撞风险。流派：压顶主受压受制。",
                 impact: "传统主应（流派层）：事业受压、睡眠不佳、头颈不适（健康表述降调，实际不适请就医）。",
                 remedy: "L1 移床/移座避梁为第一解；不能移则吊顶包梁、梁下改过道或柜体。L3 挂葫芦为民俗末选，不首选。"),
        ShaEntry(name: "门冲（门对门）", category: "峦头形煞",
                 identify: "大门正对卧室门、厕门、厨房门；户内门对门且距离近。",
                 why: "实证：厕门对床/对厨的卫生气味、厨门对卧室的油烟、门对门的隐私与气流直冲，建筑学同样忌。流派：「门对门主口舌」属象征。",
                 impact: "传统主应（流派/民俗层）：口舌争执、隐私不安、卫生困扰。",
                 remedy: "L1 改门向或加软隔断、厕门常闭＋排气除味做到位、门帘缓冲。能做 L1 就不谈摆件。"),
        ShaEntry(name: "开门见灶 / 见厕", category: "峦头形煞",
                 identify: "入户门一开正对灶台，或正对厕所门、马桶。",
                 why: "实证：见厕是卫生观感与气味；见灶是油烟动线与视觉冲突。流派：灶为财库，见灶称财露白；见厕称秽气迎门。",
                 impact: "传统主应（流派层）：破财、家宅不洁之象。",
                 remedy: "L1 玄关遮挡、结构允许时移灶位、厕门内收或隐形门。L2 灶位最终以八宅/飞星宫位复核。"),
        ShaEntry(name: "房后无靠", category: "峦头形煞",
                 identify: "宅后地势下陷、空旷临空、紧临深沟低地，背后无地形或建筑依托。",
                 why: "实证：后坡排水回渗、土体流失、北风无遮、后墙根受潮，都是真问题。流派：靠山空，主根基不稳、贵人无助。",
                 impact: "传统主应（流派层）：事业根基不牢、宅运起伏、人丁单薄之象。",
                 remedy: "L1 后坡固土＋排水沟截水、后墙根防水防渗、宅后植一排常绿乔木作人工靠山、可筑后院墙。此煞以 L1 为正解，摆件无用。"),
        ShaEntry(name: "淋头水", category: "峦头形煞",
                 identify: "高处水体（屋顶水箱、高位排水、邻楼落水、山坡汇水）直冲宅顶或门窗上方。",
                 why: "实证：渗漏、潮湿、墙体霉变是实害。流派：水从上淋，主压制与湿寒。",
                 impact: "传统主应（流派层）：压制受困、湿病之象（降调表述）。",
                 remedy: "L1 改排水走向、加截水沟与防水层，根治渗漏。无 L1 不成解。"),
        ShaEntry(name: "反光煞", category: "峦头形煞",
                 identify: "玻璃幕墙、水面、光滑立面把强光反射进本宅窗内，随时段移动。",
                 why: "实证：光污染——眩光、室内过热、作息干扰，证据最硬的一类。流派：光煞如火，主躁动。",
                 impact: "传统主应（流派层）：情绪躁动、眼目不适、家宅不宁。",
                 remedy: "L1 遮光帘/百叶/磨砂膜、窗外绿植遮阳、与反射源单位协商改面层。纯 L1 可解，不必玄学化。"),
        ShaEntry(name: "孤高无护（孤阳）", category: "峦头形煞",
                 identify: "单栋明显高出四周、无左右护持建筑，前后空旷。",
                 why: "实证：风荷载与雷击风险、高层风噪、无遮阴。流派：孤高无依、风吹气散。",
                 impact: "传统主应（流派层）：人丁单薄、宅运飘摇。",
                 remedy: "L1 防雷抗风按建筑规范、周边补植乔木成护、围墙收束明堂。选址阶段能避则避。"),
        ShaEntry(name: "五黄煞（宅盘/流年）", category: "理气煞 · 玄空",
                 identify: "飞星盘中山星/向星五黄所到之宫；流年盘中五黄飞临之方（流年盘已标红）。纯体系推出，与形煞分栏。",
                 why: "流派：五黄廉贞属土，为煞中之重，特性宜静不宜动——动土、钻敲、久坐久卧于其宫皆忌；火生土、土助土，忌红与土黄助势。",
                 impact: "传统主应（流派层）：灾病破财、诸事阻滞。到门主门户之扰、到灶主家人健康之扰、到床主卧者之扰，皆象征语言，不作具体病断。",
                 remedy: "L1 该宫当年不装修不动土不钻孔，保持安静洁净；床灶能移则移，移不了减用。L2 以金泄土为正理路：金属钟、铜铃类会响的金属置其宫，用量宜少不宜多（一串铜钱或一口钟足矣），忌见红、黄。L3 五帝钱、铜葫芦为民俗载体，理路同 L2。"),
        ShaEntry(name: "二五交加", category: "理气煞 · 玄空",
                 identify: "同宫山星/向星见 2 与 5 组合（排盘页已自动标注并附化解）。",
                 why: "流派：二黑病符（土）与五黄（土）戊己相合，土势叠加，为飞星组合中健康口径最重的一条。",
                 impact: "传统主应（流派层）：疾病、久病、因病破财。断具体部位与病名属注家细法，本手册不采。",
                 remedy: "L1 此宫忌作病人房与久卧位、保持通风干燥（卫生层即成立）。L2 金泄：铜铃/金属钟置宫，忌红黄。L3 铜钱串为载体。"),
        ShaEntry(name: "交剑煞（六七同宫）", category: "理气煞 · 玄空",
                 identify: "同宫山向星 6 与 7 组合（排盘页已自动标注并附化解）。",
                 why: "流派：六白、七赤皆金，金与金交锋如剑刃相击，故名交剑。",
                 impact: "传统主应（流派层）：口舌官非、争竞损伤、盗失。",
                 remedy: "L1 此宫不放利器（刀具收纳本是安全常识）、不作争吵对峙位。L2 以水通关：置静水或蓝黑色织物（流派层）。沟通问题回到沟通本身。"),
        ShaEntry(name: "门、床、灶落凶方", category: "八宅应用",
                 identify: "以宅卦游年盘看：大门、床头、灶口落在绝命/五鬼/六煞/祸害方；门犯绝命、五鬼在通说中最重。",
                 why: "流派：四凶方为宅气不利之位；门为纳气口、床为久卧、灶为火口，落凶方称犯方。纯体系内推论。",
                 impact: "传统主应（流派层）：绝命主大耗、五鬼主虚火盗失、六煞主口舌桃花扰、祸害主小恙是非，皆象征口径。",
                 remedy: "L1 能移则移：床位、灶位调整成本最低、优先；门不可移时以玄关折线改纳气角度。L2 八宅正法——灶坐凶向吉：灶坐压凶方、灶口朝吉方本是正格，不必谈灶在凶方色变；厕压凶方为合用；床头朝住户命卦生气/延年方。L3 无摆件正法，不凑。"),
    ]
}

struct ShaHandbookView: View {
    var body: some View {
        List {
            Section {
                Text("每个煞讲清四件事：怎么识别、哪里不好（先讲可观察的实害）、传统主应什么（标注层级，不作病灾断言）、怎么化解（L1 结构→L2 流派→L3 民俗，禁止混卖）。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(ShaLibrary.entries) { e in
                NavigationLink {
                    ShaDetailView(entry: e)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.name).font(.headline)
                        Text("\(e.category) · \(e.identify)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
        .navigationTitle("犯煞解说与解煞手册")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ShaDetailView: View {
    let entry: ShaEntry
    var body: some View {
        List {
            Section("怎么识别") { Text(entry.identify).font(.callout) }
            Section("哪里不好") { Text(entry.why).font(.callout) }
            Section("有什么影响（传统主应）") { Text(entry.impact).font(.callout) }
            Section("怎么化解（分层）") { Text(entry.remedy).font(.callout) }
            Section { Text("层级说明：L1 结构/功能调整（可由建筑、卫生、人体工学独立解释，先做）；L2 流派应用（只在所据流派内成立）；L3 民俗/象征（心理安顿，不承诺效力）。").font(.caption).foregroundStyle(.secondary) }
        }
        .navigationTitle(entry.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct KnowledgeView: View {
    private let cards: [(String, String)] = [
        ("测法要点", "罗盘每点放平采样 8 次取圆周平均；磁场强度正常 25–65 µT，出界即磁干扰（汽车/钢筋/磁吸壳）；精度 ±20° 内才作正式样本；大门朝外/朝内两读数应差约 180°，偏差 >10° 必有一处受干扰，换位重测。坐向以真北为准入盘。"),
        ("玄空速记", "运盘：运星入中顺飞；山/向盘：运盘坐/向宫星入中，阳山顺飞、阴山逆飞。二十四山阴阳——阳：乾坤艮巽、甲庚丙壬、寅申巳亥；阴：子午卯酉、辰戌丑未、乙辛丁癸。飞行轨迹：中→乾→兑→艮→离→坎→坤→震→巽。本 App 为下卦盘，不替卦；兼线（两山界 ±3°）须在备注标注。"),
        ("八宅速记", "命卦：男 (100−生年后两位)÷9 余数、女 (生年后两位−4)÷9 余数定卦，5 男寄坤、女寄艮。游年变爻口诀：不变伏位、变上爻生气、变下爻祸害、变中爻绝命、变下中天医、变中上五鬼、变上下六煞、全变延年。四吉（生气/天医/延年/伏位）安门床灶，四凶（绝命/五鬼/六煞/祸害）置卫浴储物。东西四宅命须相配。"),
        ("形煞速查（峦头层）", "路冲、反弓、天斩（两楼夹缝）、穿心（路/廊直贯）、开门见灶、横梁压床、尖角冲门窗、明堂受压、房后无靠（地势下陷/空旷）、淋头水（高处水直冲）、孤高（独高无护）、探头山。只记事实与方位，不凭单煞下重断，与理气盘合参。"),
        ("调理分层", "L1 结构层（先做）：排水防渗、采光通风、动线与功能缺陷、房后固土排水。L2 流派层：玄空旺衰布门床灶、八宅四吉四凶安位。L3 民俗层：摆件、挂画等，只作心理安顿，不与 L1/L2 混卖、不承诺效力。顺序：先 L1，后 L2，L3 可有可无。"),
        ("阴宅（现代公墓）", "只做三件：环境品质（排水、坡面、挡墙、淋头水、噪音与冲射）、朝向微选（同排位内按碑向细选）、安葬择日。禁止「点中龙穴」式话术；传统峦头理气只作环境解读框架，不作吉凶承诺。"),
        ("占卜与择日层级", "择日：安葬、动土、入宅按通书层级择吉（建除/黄道/宅主年命参合），属民俗应用层。占卜只作辅助决疑（如两可选日难决时参酌），不得替代实勘、不得推翻实测事实（如坐向、排水），结论须标注层级。"),
        ("庭院要点", "理水：来水宜环抱、去水宜之玄收束，水口忌直冲院门；理石：置石忌尖锐对门窗、忌压宅心；植物：大树忌正对门窗与压屋，宜植吉位（生气/延年方参合）；影壁：挡冲兼聚气，高度与院门成比例；院墙宜完整、高度匀称，忌东缺西陷无据之说，皆回峦头与动线核实。"),
    ]
    var body: some View {
        List {
            Section {
                NavigationLink {
                    ShaHandbookView()
                } label: { Label("犯煞解说与解煞手册（17 条逐条详解）", systemImage: "shield.lefthalf.filled") }
            }
            ForEach(cards, id: \.0) { card in
                Section(card.0) { Text(card.1).font(.callout) }
            }
            Section("来源") {
                Text("本卡片为风水堪舆专窗知识库（00–08）的离线精简版，口径以工作手册五条定调为准；完整版与出处在知识库，随安装包升级更新。").font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("风水知识卡（离线）")
        .navigationBarTitleDisplayMode(.inline)
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
                        Text("\(CompassMath.kindLabel(m.kind)) · 真北 \(CompassMath.format(m.trueHeading)) \(m.mountain) · \(SurveyStore.timeFormatter.string(from: m.timestamp))")
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

// 九宫格构图线（淡，不抢眼）
struct GridOverlay: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                ForEach(1...2, id: \.self) { i in
                    Rectangle().fill(Color.white.opacity(0.13))
                        .frame(width: 1, height: h).position(x: w * Double(i) / 3, y: h / 2)
                    Rectangle().fill(Color.white.opacity(0.13))
                        .frame(width: w, height: 1).position(x: w / 2, y: h * Double(i) / 3)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// 中央水平仪（苹果相机式三段线）：两侧固定段是准绳，中间段随真实地平线反向旋转；
// 对齐成一条线（≤1°）时变绿——眼睛只需把三段拼成一条线，不用读数字。
struct CenterLevelView: View {
    let horizon: Double
    let pitch: Double
    private var locked: Bool { abs(horizon) <= 1 }
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                HStack(spacing: 118) {
                    Rectangle().frame(width: 46, height: 2)
                    Rectangle().frame(width: 46, height: 2)
                }
                .foregroundStyle(.white.opacity(0.55))
                Rectangle()
                    .fill(locked ? Color.green : Color.white)
                    .frame(width: 104, height: 2.5)
                    .rotationEffect(.degrees(-horizon))
                Circle().stroke(Color.white.opacity(0.7), lineWidth: 1)
                    .frame(width: 6, height: 6)
            }
            Text(locked ? "水平了 · 俯仰 \(String(format: "%+.0f°", pitch))" : "地平线 \(String(format: "%+.1f°", horizon)) · 俯仰 \(String(format: "%+.0f°", pitch))")
                .font(.caption2).fontWeight(.medium)
                .foregroundStyle(locked ? .green : .white)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(.black.opacity(0.4))
                .clipShape(Capsule())
        }
        .allowsHitTesting(false)
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
    @State private var sampleTask: Task<Void, Never>? = nil  // 录像罗盘采样（Task 驱动，勿用视图层 Timer，真机不触发）
    @State private var levelHapticArmed = true   // 水平达标震动反馈（出区后重新布防）
    @State private var tiltWarn = ""             // 拍下时倾斜过大提示

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
            GridOverlay().ignoresSafeArea()
            CenterLevelView(horizon: motion.horizonTilt, pitch: motion.cameraPitch)
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
                        .rotationEffect(.degrees(-motion.horizonTilt))
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
                if !tiltWarn.isEmpty {
                    Text(tiltWarn).font(.caption).padding(8).background(.black.opacity(0.6))
                        .foregroundStyle(.orange).clipShape(Capsule())
                }
                HStack(spacing: 10) {
                    ForEach([1.0, 2.0, 3.0], id: \.self) { z in
                        Button { camera.setZoom(CGFloat(z)) } label: {
                            Text("\(Int(z))×")
                                .font(.caption).fontWeight(.semibold)
                                .foregroundStyle(camera.zoomFactor == CGFloat(z) ? .black : .white)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(camera.zoomFactor == CGFloat(z) ? Color.yellow : Color.black.opacity(0.45))
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.bottom, 8)
                if task.kind == .photo {
                    Button {
                        let shotTilt = abs(motion.horizonTilt)
                        camera.capturePhoto { data in
                            guard let data else { return }
                            if let item = store.savePhoto(caseId: draft.surveyCase.id, task: task, imageData: data, loc: location, tilt: shotTilt) {
                                draft.media.append(item)
                                draft.taskDone[task.id] = true
                                flashTip()
                                warnTilt(shotTilt)
                            }
                        }
                    } label: {
                        Circle().fill(.white).frame(width: 68, height: 68)
                            .overlay(Circle().stroke(.gray, lineWidth: 3).frame(width: 56, height: 56))
                    }.padding(.bottom, 28)
                } else {
                    Button {
                        if camera.isRecording {
                            sampleTask?.cancel(); sampleTask = nil
                            let endTilt = abs(motion.horizonTilt)
                            camera.stopRecording { url in
                                guard let url else { return }
                                if let item = store.saveVideo(caseId: draft.surveyCase.id, task: task,
                                                              tempURL: url, samples: samples, loc: location, tilt: endTilt) {
                                    draft.media.append(item)
                                    draft.taskDone[task.id] = true
                                    flashTip()
                                    warnTilt(endTilt)
                                }
                                samples = []; recordStart = nil
                            }
                        } else {
                            samples = []; recordStart = Date()
                            sweepStart = location.displayTrueHeading
                            sweepLast = location.displayTrueHeading
                            sweepAccum = 0
                            camera.startRecording()
                            // Task 驱动采样：每 0.5 秒记一条罗盘轨迹，环拍同步累计转角
                            sampleTask = Task { @MainActor in
                                while !Task.isCancelled {
                                    try? await Task.sleep(nanoseconds: 500_000_000)
                                    if Task.isCancelled { break }
                                    guard camera.isRecording, let start = recordStart else { break }
                                    if isPanoramic {
                                        let curH = location.displayTrueHeading
                                        if curH >= 0 {
                                            if sweepLast >= 0 { sweepAccum += CompassMath.shortestDiff(from: sweepLast, to: curH) }
                                            sweepLast = curH
                                        }
                                    }
                                    samples.append(HeadingSample(t: Date().timeIntervalSince(start),
                                                                 trueNorth: location.displayTrueHeading,
                                                                 magnetic: location.displayMagneticHeading))
                                }
                            }
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
        .onDisappear { sampleTask?.cancel() }
        // 水平达标震动一下（苹果相机同款反馈）：进 ≤1° 触发，出到 >2° 重新布防
        .onChange(of: motion.horizonTilt) { _, newV in
            if abs(newV) <= 1 && levelHapticArmed {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                levelHapticArmed = false
            }
            if abs(newV) > 2 { levelHapticArmed = true }
        }
    }
    private func flashTip() {
        savedTip = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { savedTip = false }
    }
    private func warnTilt(_ t: Double) {
        guard t > 5 else { return }
        tiltWarn = "这张倾斜 \(String(format: "%.1f°", t))，已标注在数据里"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { tiltWarn = "" }
    }
}
