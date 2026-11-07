// CompassModule.swift — 独立罗盘页（G4 罗盘实测，2026-11-08）
// App 独立罗盘：CoreLocation（CLLocationManager heading）＋ CMMotionManager 融合取向；
// 磁北／真北切换、二十四山环随转动实时旋转、锁定后带入堪舆案件与户型压盘器。
// 磁偏角口径：首选设备自身真北（CLHeading.trueHeading，系统内建 WMM 校正），
// 实测磁偏角＝true−magnetic；仅当真北不可用时用本机 WMM2025 现算（CompassDeclination，
// 与 Web app/compass.py 同式，系数表见 CompassWMMTable，由生成器从 Python 引擎原样生成）。
// 梁平默认坐标 30.654°N、107.770°E（梁平区政府坐标，英文维基 Liangping District）。
// 坐向口径与 FengshuiEngine / CompassMath 同式：0°＝子山正北；坐山度数＝罗盘
// 「大门外朝内」真北读数；向山＝坐山＋12 山；锁定只输出真北坐山度数入盘。
// 传感器真机行为（CLLocationManager／CMMotionManager 采样、校准提示）本地无真机无法验证，
// 见本文件底部与汇报缺口段；采样门控与精度提示沿用案内 CompassView 同标准。
import SwiftUI
import CoreLocation
import CoreMotion

// MARK: - WMM2025 磁偏角现算（Swift 移植，与 Web app/compass.py 同式）
//
// 两个 a 不可混用：球谐展开用 WMM 地磁参考半径 a＝6,371,200 m（CompassWMMTable.referenceRadius），
// 大地纬度→地心纬度的椭球换算用 WGS84 长半轴 6,378,137 m。2026-11-08 Python 端实测教训：
// 误用 6378137 作展开半径，全场系统性偏大 (6378137/6371200)^(n+2)≈＋0.33%～＋0.55%，
// NOAA §1.5 例 D 差 0.039°、Z′ 差 −168 nT；改回 6371200 后 §1.5 例与 §1.4 两极点值均对至 ±0.1 nT。
enum CompassDeclination {
    static let liangpingLat = 30.654
    static let liangpingLon = 107.770
    static let maxDegree = 12
    static let referenceRadius = CompassWMMTable.referenceRadius
    static let wgs84A = CompassWMMTable.wgs84A
    static let wgs84F = CompassWMMTable.wgs84F

    /// Schmidt 半归一化勒让德函数 P[n][m] 及其对地心纬度的导数 dP[n][m]。
    /// 递推与 Python _legendre 同式（Ferrers 三项递推须乘 Schmidt 归一化比值，
    /// 否则算出的是未归一化的 Ferrers 函数）。
    static func legendre(sinPhi: Double, cosPhi: Double) -> (p: [[Double]], dp: [[Double]]) {
        let nmax = maxDegree
        var p = [[Double]](repeating: [Double](repeating: 0.0, count: nmax + 1), count: nmax + 1)
        var dp = [[Double]](repeating: [Double](repeating: 0.0, count: nmax + 1), count: nmax + 1)
        let s = sinPhi
        let c = cosPhi
        p[0][0] = 1.0
        p[1][0] = s
        p[1][1] = c
        dp[1][0] = c
        dp[1][1] = -s
        for n in 2...nmax {
            p[n][0] = (Double(2 * n - 1) * s * p[n - 1][0] - Double(n - 1) * p[n - 2][0]) / Double(n)
            dp[n][0] = (Double(2 * n - 1) * (s * dp[n - 1][0] + c * p[n - 1][0]) - Double(n - 1) * dp[n - 2][0]) / Double(n)
            for m in 1...n {
                if m == n {
                    let f = sqrt(Double(2 * n - 1) / Double(2 * n))
                    p[n][m] = c * p[n - 1][m - 1] * f
                    dp[n][m] = f * (c * dp[n - 1][m - 1] - s * p[n - 1][m - 1])
                } else {
                    let f1 = sqrt(Double(n - m) / Double(n + m))
                    let f2 = sqrt(Double(n - m) * Double(n - m - 1) / (Double(n + m) * Double(n + m - 1)))
                    p[n][m] = (Double(2 * n - 1) * s * p[n - 1][m] * f1 - Double(n + m - 1) * p[n - 2][m] * f2) / Double(n - m)
                    dp[n][m] = (Double(2 * n - 1) * (s * dp[n - 1][m] + c * p[n - 1][m]) * f1 - Double(n + m - 1) * dp[n - 2][m] * f2) / Double(n - m)
                }
            }
        }
        return (p, dp)
    }

    /// WMM2025 地磁场分量（大地系 X 北向、Y 东向、Z 向下，单位 nT）。
    /// 与 Python _field 同式；极点附近 cosφ′≈0 时返回 nil（罗盘不在极点用，不编造）。
    static func field(latitude: Double, longitude: Double, year: Double, height: Double = 0) -> (x: Double, y: Double, z: Double)? {
        let phi = latitude * Double.pi / 180
        let lam = longitude * Double.pi / 180
        let dt = year - CompassWMMTable.epoch
        let sinPhi = sin(phi)
        let cosPhi = cos(phi)
        let e2 = wgs84F * (2 - wgs84F)
        let rc = wgs84A / sqrt(1 - e2 * sinPhi * sinPhi)
        let p = (rc + height) * cosPhi
        let z = ((1 - e2) * rc + height) * sinPhi
        let r = hypot(p, z)
        let sinPP = z / r
        let cosPP = p / r
        let phiP = atan2(z, p)
        if abs(cosPP) < 1e-9 {
            return nil
        }
        let (P, dP) = legendre(sinPhi: sinPP, cosPhi: cosPP)
        var gTable = [[Double]](repeating: [Double](repeating: 0.0, count: maxDegree + 1), count: maxDegree + 1)
        var hTable = [[Double]](repeating: [Double](repeating: 0.0, count: maxDegree + 1), count: maxDegree + 1)
        for c in CompassWMMTable.coeffs {
            gTable[c.n][c.m] = c.g + dt * c.gDot
            hTable[c.n][c.m] = c.h + dt * c.hDot
        }
        var xp = 0.0
        var yp = 0.0
        var zp = 0.0
        let ar = referenceRadius / r
        for n in 1...maxDegree {
            let arn = pow(ar, Double(n + 2))
            for m in 0...n {
                let g = gTable[n][m]
                let h = hTable[n][m]
                let gc = g * cos(Double(m) * lam) + h * sin(Double(m) * lam)
                let gs = g * sin(Double(m) * lam) - h * cos(Double(m) * lam)
                xp -= arn * gc * dP[n][m]
                zp -= arn * Double(n + 1) * gc * P[n][m]
                if m > 0 {
                    yp += arn * Double(m) * gs * P[n][m] / cosPP
                }
            }
        }
        let delta = phi - phiP
        let cd = cos(delta)
        let sd = sin(delta)
        let x = xp * cd + zp * sd
        let y = yp
        let z = zp * cd - xp * sd
        return (x, y, z)
    }

    /// 磁偏角与场量（度，东偏为正）；模型期外或极点返回 nil（不外推、不编造）。
    static func magneticField(latitude: Double, longitude: Double, year: Double) -> (declination: Double, inclination: Double, total: Double, horizontal: Double)? {
        if year < CompassWMMTable.epoch || year > CompassWMMTable.validUntil {
            return nil
        }
        guard let f = field(latitude: latitude, longitude: longitude, year: year) else {
            return nil
        }
        let x = f.x
        let y = f.y
        let z = f.z
        let horizontal = hypot(x, y)
        if horizontal < 1e-9 {
            return nil
        }
        let declination = atan2(y, x) * 180 / Double.pi
        let inclination = atan2(z, horizontal) * 180 / Double.pi
        let total = sqrt(x * x + y * y + z * z)
        return (declination, inclination, total, horizontal)
    }

    /// 磁偏角（度，东偏为正，西偏为负）；模型期外或极点返回 nil。
    static func declination(latitude: Double, longitude: Double, year: Double) -> Double? {
        guard let f = magneticField(latitude: latitude, longitude: longitude, year: year) else {
            return nil
        }
        return f.declination
    }

    /// 梁平默认坐标（30.654°N，107.770°E）的 WMM2025 磁偏角（度，东偏为正）。
    static func liangpingDeclination(year: Double) -> Double? {
        return declination(latitude: liangpingLat, longitude: liangpingLon, year: year)
    }
}

// MARK: - 罗盘锁定（Codable，UserDefaults 持久化）

/// 一次罗盘锁定的全部信息。锁定只输出一个真北坐山度数：sitDegree = trueNorth（入盘只用真北）。
struct CompassLock: Codable, Equatable {
    var magnetic: Double
    var trueNorth: Double
    var declination: Double
    var declinationSource: String // device（设备真北）／wmm2025（WMM2025 现算）／manual（手动填入）
    var mountain: String
    var palace: String
    var accuracy: Double
    var tilt: Double
    var latitude: Double?
    var longitude: Double?
    var timestamp: Date
    var samples: Int
    var spread: Double

    /// 真北坐山度数（入盘只用它，与手动输入同度数走同一条 FengshuiEngine 路径）。
    var sitDegree: Double { trueNorth }

    /// 坐向（与 AnalysisView 同式：坐山＝锁定山，向山＝坐山＋12 山；坐宫／向宫取山中心度数所落之宫）。
    func sitFace() -> (sit: String, face: String, sitPalace: String, facePalace: String) {
        let idx = CompassMath.mountains.firstIndex(of: mountain) ?? 0
        let face = CompassMath.mountains[(idx + 12) % 24]
        let sitPalace = CompassMath.palace(for: Double(idx) * 15)
        let facePalace = CompassMath.palace(for: Double((idx + 12) % 24) * 15)
        return (mountain, face, sitPalace, facePalace)
    }

    /// 转成勘察案件的 HeadingReading（测点名固定为「大门外朝内」，AnalysisView 的
    /// sitReading 逻辑会直接取用，无需改 FengshuiEngine）。
    func headingReading(pointName: String = "大门外朝内") -> HeadingReading {
        return HeadingReading(
            pointName: pointName,
            magnetic: magnetic,
            trueNorth: trueNorth,
            mountain: mountain,
            palace: palace,
            latitude: latitude,
            longitude: longitude,
            headingAccuracy: accuracy,
            tiltDegrees: tilt,
            sampleSpread: spread)
    }

    /// 坐向中文（如「午山子向 · 坐离宫向坎宫」）。
    var sitFaceText: String {
        let sf = sitFace()
        return sf.sit + "山" + sf.face + "向 · 坐" + sf.sitPalace + "宫向" + sf.facePalace + "宫"
    }

    /// 磁偏角来源中文。
    var declinationSourceText: String {
        if declinationSource == "device" {
            return "设备真北（系统内建校正）"
        }
        if declinationSource == "manual" {
            return "手动填入"
        }
        return "WMM2025 现算"
    }
}

@MainActor
final class CompassLockStore: ObservableObject {
    @Published private(set) var lock: CompassLock?
    private let key = "compass.lock.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: key) {
            if let decoded = try? JSONDecoder().decode(CompassLock.self, from: data) {
                lock = decoded
            }
        }
    }

    func setLock(_ value: CompassLock) {
        lock = value
        save()
    }

    func clear() {
        lock = nil
        UserDefaults.standard.removeObject(forKey: key)
    }

    private func save() {
        guard let lock else {
            return
        }
        if let data = try? JSONEncoder().encode(lock) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - 独立罗盘页（不依赖案件：测哪都行，锁定后带入堪舆／户型压盘）

struct CompassStandaloneView: View {
    @EnvironmentObject var location: LocationManager
    @EnvironmentObject var motion: MotionManager
    @EnvironmentObject var lockStore: CompassLockStore
    @EnvironmentObject var store: SurveyStore
    @State private var northMode = 0 // 0 真北，1 磁北
    @State private var manualDeclination = "" // 手动磁偏角（度，东偏为正），留空＝自动
    @State private var collecting = false
    @State private var trueSamples: [Double] = []
    @State private var magSamples: [Double] = []
    @State private var weakTrue: [Double] = []
    @State private var weakMag: [Double] = []
    @State private var collectTicks = 0
    @State private var collectHint = ""
    @State private var collectTask: Task<Void, Never>? = nil
    @State private var justLocked = false
    @State private var createdCaseName = ""

    // 磁偏角解析（优先级：手动填入 ＞ 设备真北实测 ＞ 按定位经纬度 WMM2025 现算 ＞ 梁平默认坐标现算）。
    private var declinationInfo: (value: Double, source: String) {
        if let manual = Double(manualDeclination) {
            return (manual, "manual")
        }
        if let d = location.declination {
            return (d, "device")
        }
        let year = currentYearDecimal()
        if let loc = location.currentLocation {
            if let d = CompassDeclination.declination(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude, year: year) {
                return (d, "wmm2025")
            }
        }
        if let d = CompassDeclination.liangpingDeclination(year: year) {
            return (d, "wmm2025")
        }
        return (0, "none")
    }

    private func currentYearDecimal() -> Double {
        let now = Date()
        let cal = Calendar(identifier: .gregorian)
        let y = cal.component(.year, from: now)
        let day = cal.ordinality(of: .day, in: .year, for: now) ?? 1
        return Double(y) + Double(day - 1) / 365.25
    }

    // 真北读数：有系统真北直接用；无真北时磁北＋磁偏角推算（与 Web 同口径）。
    private var trueDisplay: Double {
        if location.trueHeading >= 0 {
            return location.trueHeading
        }
        if location.magneticHeading >= 0 {
            return CompassMath.normalize(location.magneticHeading + declinationInfo.value)
        }
        return -1
    }

    private var displayHeading: Double {
        if northMode == 0 {
            return trueDisplay
        }
        return location.displayMagneticHeading
    }

    private var declinationText: String {
        let info = declinationInfo
        if info.source == "none" {
            return "磁偏角未知"
        }
        let src: String
        if info.source == "device" {
            src = "设备真北实测"
        } else if info.source == "manual" {
            src = "手动填入"
        } else {
            src = "WMM2025 现算"
        }
        return "磁偏角 " + String(format: "%+.1f°", info.value) + "（" + src + "）"
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                dial.frame(width: 260, height: 260).padding(.top, 8)
                levelRow
                readoutCard
                northModeRow
                if location.accuracyWarning != nil || motion.fieldAbnormal {
                    calibrationCard
                }
                lockButtonRow
                if let lock = lockStore.lock {
                    lockCard(lock)
                }
                basisText
            }.padding()
        }
        .background(Ky.instBg)
        .preferredColorScheme(.dark)
        .navigationTitle("罗盘实测")
        .onAppear {
            location.start()
            motion.start()
        }
        .onDisappear {
            collectTask?.cancel()
            location.stop()
            motion.stop()
        }
    }

    // 水平仪：气泡进小圈（倾斜≤3°）才算放平（与案内 CompassView 同标准）。
    private var levelRow: some View {
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
                Text(motion.isLevelForCompass ? "已放平，可以锁定" : "把手机平放，气泡稳进绿圈")
                    .font(.caption)
                    .foregroundStyle(motion.isLevelForCompass ? .green : .orange)
                Text("倾斜时罗盘会漂，锁定只采放平时的读数并取平均。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var readoutCard: some View {
        VStack(spacing: 4) {
            let d = displayHeading
            Text(northMode == 0 ? "真北 \(CompassMath.format(d))" : "磁北 \(CompassMath.format(d))")
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Text(d >= 0 ? "\(CompassMath.mountain(for: d))山 · \(CompassMath.palace(for: d))宫" : "等待罗盘…")
                .font(.headline).foregroundStyle(.secondary)
            Text("磁北 \(CompassMath.format(location.displayMagneticHeading)) · \(declinationText)")
                .font(.caption).foregroundStyle(.secondary)
            if northMode == 0 && location.trueHeading < 0 && location.magneticHeading >= 0 {
                Text("系统真北未就绪：当前真北为磁北＋磁偏角推算值")
                    .font(.caption).foregroundStyle(.orange)
            }
            if northMode == 1 {
                Text("磁北模式仅供互校：入盘一律用真北坐山度数")
                    .font(.caption).foregroundStyle(.orange)
            }
            Text("定位：\(location.coordinateText)").font(.caption).foregroundStyle(.secondary)
            if let warn = location.accuracyWarning {
                Text(warn).font(.caption).foregroundStyle(.orange).multilineTextAlignment(.center)
            }
            if motion.fieldMicroTesla >= 0 {
                Text("磁场强度 \(String(format: "%.0f", motion.fieldMicroTesla)) 微特（地磁场正常 25–65）\(motion.fieldAbnormal ? "：异常，附近有磁干扰" : "")")
                    .font(.caption)
                    .foregroundStyle(motion.fieldAbnormal ? .red : .secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .kyGlass(corner: 16)
    }

    private var northModeRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("北向", selection: $northMode) {
                Text("真北").tag(0)
                Text("磁北").tag(1)
            }.pickerStyle(.segmented)
            HStack(spacing: 8) {
                Text("手动磁偏角（度，东偏为正）").font(.caption).foregroundStyle(.secondary)
                TextField("留空＝自动", text: $manualDeclination)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)
            }
            Text("真北＝磁北＋磁偏角（东偏为正，西偏为负）；梁平 2026 年约 −3.3°（西偏）。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var calibrationCard: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("精度自检（校准好后可达 ±5° 左右）").font(.caption).fontWeight(.semibold)
            Text("1. 摘掉磁吸手机壳、磁吸支架（能让读数偏几十度）\n2. 离汽车、钢筋、电器 2 米以上\n3. 手腕画 8 字三圈校准\n4. 设置 → 隐私与安全性 → 定位服务 → 系统服务：打开「指南针校准」和「运动校准与距离」")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .kyGlass(corner: 12)
    }

    private var lockButtonRow: some View {
        VStack(spacing: 8) {
            Button {
                if !collecting {
                    startCollect()
                }
            } label: {
                Text(justLocked ? "✓ 已锁定" : (collecting ? "采样中…（\(trueSamples.count)/8）" : "锁定当前度数／山向（放平自动采样）"))
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(KyPrimaryButton())
            if !collectHint.isEmpty {
                Text(collectHint).font(.caption).foregroundStyle(.secondary)
            }
            Text("测法：手机端平、远离汽车钢筋电器；原地慢转半圈等读数稳定后再锁定。坐向以真北读数为准入盘，磁北读数留作互校。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func lockCard(_ lock: CompassLock) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("已锁定").font(.headline)
                Spacer()
                Text(lock.sitFaceText).font(.subheadline).foregroundStyle(.secondary)
            }
            let fmt = lockDateFormatter
            VStack(alignment: .leading, spacing: 3) {
                Text("真北 \(CompassMath.format(lock.trueNorth)) \(lock.mountain)山 · 磁北 \(CompassMath.format(lock.magnetic))")
                    .font(.subheadline)
                Text("磁偏角 \(String(format: "%+.1f°", lock.declination))（\(lock.declinationSourceText)）")
                    .font(.caption).foregroundStyle(.secondary)
                Text("精度 ±\(Int(lock.accuracy))° · 倾斜 \(String(format: "%.1f°", lock.tilt)) · \(lock.samples) 次采样平均 · 集中度 \(String(format: "%.2f", lock.spread))")
                    .font(.caption).foregroundStyle(.secondary)
                Text("锁定时间 \(fmt.string(from: lock.timestamp))")
                    .font(.caption).foregroundStyle(.secondary)
                if lock.spread >= 0 && lock.spread < 0.9 {
                    Text("集中度偏低（<0.90）：这条不太稳，建议重测。")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            HStack(spacing: 10) {
                Button("新建勘察（用锁定坐向）") {
                    createCaseFromLock()
                }
                .buttonStyle(.borderedProminent)
                NavigationLink {
                    FloorPlanOverlayView()
                } label: {
                    Text("带入户型压盘器")
                }
                .buttonStyle(.bordered)
            }
            if !createdCaseName.isEmpty {
                Text("已新建勘察「\(createdCaseName)」：坐向已预填「大门外朝内」，进案件点「分析」即见罗盘定盘。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("清除锁定") {
                lockStore.clear()
                createdCaseName = ""
            }
            .font(.caption).foregroundStyle(.red)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .kyGlass(corner: 16)
    }

    private var lockDateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        return f
    }

    private var basisText: some View {
        Text("依据与金标准：磁偏角按 WMM2025（NOAA NCEI＋英国地质调查局，Chulliat et al. 2025，doi:10.25923/prbcs316）现算，优先取设备真北（系统内建校正），无真北时按定位经纬度现算；梁平默认 30.654°N、107.770°E。二十四山与 FengshuiEngine 同口径（子起顺时针，每山 15°，＋7.5° 偏置，0°＝子山正北）；坐山度数＝罗盘「大门外朝内」真北读数，向山＝坐山＋12 山。金标准见 Web test_compass.py（NOAA §1.5 数值例逐项对拍，284 断言全过）与 test_compass_swift_table.py（Swift 系数表逐项对拍）。传感器精度约 ±5°（校准良好时）；远离磁铁／金属，出现校准提示时按系统提示画 8 字。")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var bubbleOffset: (Double, Double) {
        let dx = min(1, max(-1, motion.bubbleX / 0.25)) * 27
        let dy = min(1, max(-1, -motion.bubbleY / 0.25)) * 27
        return (dx, dy)
    }

    // 采样循环用 Task 驱动（与案内 CompassView 同门控：精度 ±20° 以内才算正式样本；
    // ±20–35° 只进备选桶；磁场异常／未放平／精度更差不采；8 次满即锁，超时 4 次以上亦锁）。
    private func startCollect() {
        collecting = true
        trueSamples = []
        magSamples = []
        weakTrue = []
        weakMag = []
        collectTicks = 0
        collectHint = "采样中：把气泡稳在绿圈里…"
        collectTask?.cancel()
        collectTask = Task { @MainActor in
            while collecting && trueSamples.count < 8 && collectTicks < 90 {
                let acc = location.headingAccuracy
                if motion.fieldAbnormal {
                    collectHint = "磁场异常（\(String(format: "%.0f", motion.fieldMicroTesla)) 微特）：附近有磁干扰，换个位置再测"
                } else if !motion.isLevelForCompass {
                    collectHint = "没放平，不采样：把气泡稳进绿圈（当前倾斜 \(String(format: "%.1f°", motion.flatTilt))）"
                } else if trueDisplay >= 0 && acc >= 0 {
                    if acc <= 20 {
                        appendSample(&trueSamples, &magSamples)
                        collectHint = "采样中：已采 \(trueSamples.count)/8（精度 ±\(Int(acc))°），保持放平…"
                    } else if acc <= 35 {
                        appendSample(&weakTrue, &weakMag)
                        collectHint = "当前精度差（±\(Int(acc))°），只作备选采样：先按上方自检校准一遍…"
                    } else {
                        collectHint = "精度太低（±\(Int(acc))°）不采样：按上方自检做一遍再测"
                    }
                }
                if trueSamples.count >= 8 {
                    finishCollect()
                    return
                }
                collectTicks += 1
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
            if collecting {
                if trueSamples.count >= 4 {
                    finishCollect()
                } else if weakTrue.count >= 4 {
                    trueSamples = weakTrue
                    magSamples = weakMag
                    finishCollect(lowAccuracy: true)
                } else {
                    collecting = false
                    collectHint = "这次没采够：按上方精度自检做一遍，换个位置再测。"
                }
            }
        }
    }

    // 尖峰剔除：与已采样本圆周均值偏差 >15° 的读数丢弃（防干扰毛刺污染平均）。
    private func appendSample(_ t: inout [Double], _ m: inout [Double]) {
        if t.count >= 3 {
            let (mean, _) = CompassMath.circularMean(t)
            if abs(CompassMath.shortestDiff(from: mean, to: trueDisplay)) > 15 {
                return
            }
        }
        t.append(trueDisplay)
        m.append(location.displayMagneticHeading)
    }

    private func finishCollect(lowAccuracy: Bool = false) {
        collecting = false
        let (meanT, r) = CompassMath.circularMean(trueSamples)
        let (meanM, _) = CompassMath.circularMean(magSamples)
        if meanT < 0 {
            collectHint = "读数无效，请重试"
            return
        }
        let info = declinationInfo
        let lock = CompassLock(
            magnetic: meanM,
            trueNorth: meanT,
            declination: info.value,
            declinationSource: info.source,
            mountain: CompassMath.mountain(for: meanT),
            palace: CompassMath.palace(for: meanT),
            accuracy: location.headingAccuracy,
            tilt: motion.flatTilt,
            latitude: location.currentLocation?.coordinate.latitude,
            longitude: location.currentLocation?.coordinate.longitude,
            timestamp: Date(),
            samples: trueSamples.count,
            spread: r)
        lockStore.setLock(lock)
        justLocked = true
        collectHint = lowAccuracy
            ? "已锁定（低精度备选样本 \(trueSamples.count) 次平均，精度 ±\(Int(location.headingAccuracy))°，已标注；能重测尽量重测）"
            : "已锁定：\(trueSamples.count) 次采样平均，集中度 \(String(format: "%.2f", r))（越接近 1 越稳）"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { justLocked = false }
    }

    // 新建勘察案件并预填一条「大门外朝内」读数：AnalysisView 的 sitReading 逻辑会直接取用。
    private func createCaseFromLock() {
        guard let lock = lockStore.lock else {
            return
        }
        let sf = lock.sitFace()
        let sc = SurveyCase(name: "罗盘锁定 " + sf.sit + "山" + sf.face + "向", type: .yangzhai)
        store.addCase(sc)
        if let idx = store.cases.firstIndex(where: { $0.surveyCase.id == sc.id }) {
            var cd = store.cases[idx]
            cd.headings.append(lock.headingReading())
            store.update(cd)
        }
        createdCaseName = sc.name
    }

    // 仪器盘面（墨金恒深）：Canvas 金线刻度环＋二十四山（金）＋八宫（内圈）＋定盘针；
    // 与案内 CompassView 同画法，盘面随所选北向读数实时旋转。
    private var dial: some View {
        ZStack {
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let r = size.width / 2 - 6
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                           with: .color(Ky.instGold.opacity(0.55)), lineWidth: 1.5)
                let rIn = r - 34
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - rIn, y: c.y - rIn, width: 2 * rIn, height: 2 * rIn)),
                           with: .color(Ky.instGold.opacity(0.25)), lineWidth: 1)
                for i in 0..<72 {
                    let a = Double(i) * 5 * Double.pi / 180
                    let isLong = i % 3 == 0
                    let r1 = r - (isLong ? 11 : 6)
                    var p = Path()
                    p.move(to: CGPoint(x: c.x + r * sin(a), y: c.y - r * cos(a)))
                    p.addLine(to: CGPoint(x: c.x + r1 * sin(a), y: c.y - r1 * cos(a)))
                    ctx.stroke(p, with: .color(Ky.instGold.opacity(isLong ? 0.9 : 0.35)), lineWidth: isLong ? 1.4 : 1)
                }
            }
            ForEach(0..<24, id: \.self) { i in
                let bearing = Double(i) * 15
                let ang = (bearing - displayHeading) * Double.pi / 180
                Text(CompassMath.mountains[i])
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(i == 0 ? Ky.instCinnabar : Ky.instGold)
                    .position(x: 130 + 97 * sin(ang), y: 130 - 97 * cos(ang))
            }
            ForEach(0..<8, id: \.self) { i in
                let bearing = Double(i) * 45
                let ang = (bearing - displayHeading) * Double.pi / 180
                Text(CompassMath.palaces[i])
                    .font(i % 2 == 0 ? .headline : .subheadline)
                    .foregroundStyle(i == 0 ? Ky.instCinnabar : Ky.instInk)
                    .position(x: 130 + 62 * sin(ang), y: 130 - 62 * cos(ang))
            }
            Image(systemName: "arrowtriangle.up.fill")
                .font(.system(size: 17)).foregroundStyle(Ky.instGold)
                .offset(y: -26)
            Circle().fill(Ky.instCinnabar).frame(width: 7, height: 7).offset(y: 24)
            Circle().fill(Ky.instGold).frame(width: 9, height: 9)
        }
    }
}
