// 真太阳时校正层（自研共用层）
// 与服务端引擎 paipan.py 逐行同公式，保证端/服口径一致：
// 校正分钟 = (出生地经度 − 标准经线 120°) × 4 + 均时差(Equation of Time)
// 均时差公式与 paipan.py eot_minutes 完全一致（同一近似式），金标准盘对拍覆盖此层。
import Foundation

enum TrueSolarTime {
    /// 均时差（分钟），入参为钟表时间
    static func equationOfTimeMinutes(_ date: Date, calendar: Calendar = .current) -> Double {
        let n = Double(calendar.ordinality(of: .day, in: .year, for: date) ?? 1)
        let b = (360.0 / 365.0 * (n - 81.0)) * Double.pi / 180.0
        return 9.87 * sin(2 * b) - 7.53 * cos(b) - 1.5 * sin(b)
    }

    /// 钟表时间 → 真太阳时。standardMeridian 默认 120（北京时间）
    static func corrected(clock: Date, longitude: Double, standardMeridian: Double = 120.0,
                          calendar: Calendar = .current) -> Date {
        let corr = (longitude - standardMeridian) * 4.0 + equationOfTimeMinutes(clock, calendar: calendar)
        return clock.addingTimeInterval(corr * 60.0)
    }
}
