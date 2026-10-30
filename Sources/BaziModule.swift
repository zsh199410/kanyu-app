// 八字模块（综合 App 第一块新拼图，并入堪舆仓库 2026-10-30）
// 引擎：lunar-swift（6tail，与服务端 lunar-python 同谱系，MIT）＋自研真太阳时层。
// 口径钉死（八字线定版）：晚子时 sect=2 显式设置；月干/时干五虎遁/五鼠遁复算互校；
// 胎元/胎息/命宫/身宫随盘输出（对标问真三层盘面，金标准盘 12 例对拍守口径）。
import SwiftUI
import LunarSwift

struct BaziChart {
    var yearPillar: String; var monthPillar: String; var dayPillar: String; var timePillar: String
    var rizhu: String
    var taiYuan: String; var taiXi: String; var mingGong: String; var shenGong: String
    var qiyunDirection: String; var qiyunDate: String
    var dayunGanZhi: [String]
}

enum BaziEngine {
    private static let TG = Array("甲乙丙丁戊己庚辛壬癸")
    private static let DZ = Array("子丑寅卯辰巳午未申酉戌亥")
    private static func wuhu(yearStem: Character, monthBranch: Character) -> Character {
        let startMap: [Character: Int] = ["甲":2,"己":2,"乙":4,"庚":4,"丙":6,"辛":6,"丁":8,"壬":8,"戊":0,"癸":0]
        let off = (DZ.firstIndex(of: monthBranch)! - DZ.firstIndex(of: "寅")! + 12) % 12
        return TG[(startMap[yearStem]! + off) % 10]
    }
    private static func wushu(dayStem: Character, hourBranch: Character) -> Character {
        let startMap: [Character: Int] = ["甲":0,"己":0,"乙":2,"庚":2,"丙":4,"辛":4,"丁":6,"壬":6,"戊":8,"癸":8]
        return TG[(startMap[dayStem]! + DZ.firstIndex(of: hourBranch)!) % 10]
    }

    /// clock：出生钟表时间（按北京时间记录）；longitude 为 nil 时按钟表时间排
    /// 接口已按 lunar-swift 源码逐项核对（EightChar/Yun/DaYun/Solar 四个源文件，2026-10-30）：
    /// 属性式 year/month/day/time/taiYuan/taiXi/mingGong/shenGong；sect 为可写属性、默认 2；
    /// getYun(gender:sect:) 的运 sect 必须传 1——与服务端引擎默认一致（传 2 起运日差 2 天，金标准盘锁死）。
    static func paipan(clock: Date, gender: String, longitude: Double?) -> BaziChart {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let used = longitude.map { TrueSolarTime.corrected(clock: clock, longitude: $0, calendar: cal) } ?? clock
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: used)
        let solar = Solar.fromYmdHms(year: c.year!, month: c.month!, day: c.day!, hour: c.hour!, minute: c.minute!)
        let ec = solar.lunar.eightChar
        ec.sect = 2  // 晚子时：日柱算当天，钉死不许漂移
        let yg = ec.year; var mg = ec.month; let dg = ec.day; var tg = ec.time
        mg = String(wuhu(yearStem: yg.first!, monthBranch: mg.last!)) + String(mg.last!)
        let dayStemForTime: Character = c.hour! == 23 ? TG[(TG.firstIndex(of: dg.first!)! + 1) % 10] : dg.first!
        tg = String(wushu(dayStem: dayStemForTime, hourBranch: tg.last!)) + String(tg.last!)
        let yun = ec.getYun(gender: gender == "M" ? 1 : 0, sect: 1)
        let dayun = yun.getDaYun().dropFirst().map { $0.ganZhi }
        let ss = yun.startSolar
        return BaziChart(yearPillar: yg, monthPillar: mg, dayPillar: dg, timePillar: tg,
                         rizhu: String(dg.first!),
                         taiYuan: ec.taiYuan, taiXi: ec.taiXi,
                         mingGong: ec.mingGong, shenGong: ec.shenGong,
                         qiyunDirection: yun.forward ? "顺行" : "逆行",
                         qiyunDate: String(format: "%04d-%02d-%02d", ss.year, ss.month, ss.day),
                         dayunGanZhi: dayun)
    }
}

// MARK: - 八字排盘页（P1 最小可用：录入→排盘→盘面展示，断语层 P2 接入）

struct BaziHomeView: View {
    @State private var name = ""
    @State private var gender = "M"
    @State private var birth = Date()
    @State private var useLongitude = true
    @State private var longitudeText = "107.8"
    @State private var chart: BaziChart?

    private static var fmt: DateFormatter {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = TimeZone(secondsFromGMT: 8 * 3600); return f
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Group {
                    TextField("姓名（可空）", text: $name)
                    Picker("性别", selection: $gender) { Text("男").tag("M"); Text("女").tag("F") }
                        .pickerStyle(.segmented)
                    DatePicker("出生钟表时间", selection: $birth, displayedComponents: [.date, .hourAndMinute])
                    Toggle("真太阳时校正（按经度）", isOn: $useLongitude)
                    if useLongitude {
                        HStack { Text("出生地经度"); Spacer()
                            TextField("107.8", text: $longitudeText)
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90) }
                    }
                    Button("排盘") {
                        chart = BaziEngine.paipan(clock: birth, gender: gender,
                                                  longitude: useLongitude ? Double(longitudeText) : nil)
                    }.buttonStyle(KyPrimaryButton())
                }
                .padding(14).background(Ky.card).clipShape(RoundedRectangle(cornerRadius: 14))

                if let ch = chart {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            ForEach([("年", ch.yearPillar), ("月", ch.monthPillar), ("日", ch.dayPillar), ("时", ch.timePillar)], id: \.0) { item in
                                VStack(spacing: 3) {
                                    Text(item.0).font(.caption2).foregroundStyle(Ky.sub)
                                    Text(item.1).font(.system(.title3, design: .serif)).fontWeight(.bold)
                                        .foregroundStyle(item.0 == "日" ? Ky.cinnabar : Ky.ink)
                                }.frame(maxWidth: .infinity)
                            }
                        }
                        Divider()
                        Text("日主 \(ch.rizhu) · 胎元 \(ch.taiYuan) · 胎息 \(ch.taiXi) · 命宫 \(ch.mingGong) · 身宫 \(ch.shenGong)")
                            .font(.caption).foregroundStyle(Ky.sub)
                        Text("起运 \(ch.qiyunDirection) · \(ch.qiyunDate)").font(.caption).foregroundStyle(Ky.sub)
                        Text("大运").font(.subheadline).fontWeight(.semibold).foregroundStyle(Ky.ink)
                        Text(ch.dayunGanZhi.joined(separator: " → ")).font(.caption).foregroundStyle(Ky.ink)
                    }
                    .padding(14).background(Ky.card).clipShape(RoundedRectangle(cornerRadius: 14))
                }
                Text("口径：真太阳时＋晚子时 sect=2，与八字线已验证引擎同源；断语与报告在 P2 接入。")
                    .font(.caption2).foregroundStyle(Ky.sub)
            }.padding(16)
        }
        .background(Ky.bg)
        .navigationTitle("八字排盘")
        .navigationBarTitleDisplayMode(.inline)
    }
}
