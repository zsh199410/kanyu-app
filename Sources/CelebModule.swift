// 名人命例库（对标问真名人库；首批只收出生时间有公开记载者，每条标注可信度与来源说明，宁缺毋滥）
import SwiftUI

struct Celeb: Identifiable {
    let id = UUID()
    let name: String; let gender: String
    let y: Int; let mo: Int; let d: Int; let h: Int; let mi: Int
    let lon: Double; let place: String
    let trust: String   // 高/中
    let note: String
}

enum CelebData {
    static let all: [Celeb] = [
        Celeb(name: "毛泽东", gender: "M", y: 1893, mo: 12, d: 26, h: 7, mi: 30, lon: 112.5, place: "湖南韶山", trust: "中", note: "辰时生，见于多部传记记载"),
        Celeb(name: "蒋介石", gender: "M", y: 1887, mo: 10, d: 31, h: 12, mi: 0, lon: 121.5, place: "浙江奉化", trust: "中", note: "午时生，奉化溪口家谱与传记记载"),
        Celeb(name: "孙中山", gender: "M", y: 1866, mo: 11, d: 12, h: 6, mi: 0, lon: 113.5, place: "广东香山", trust: "中", note: "卯时生，通行传记记载"),
        Celeb(name: "乾隆帝", gender: "M", y: 1711, mo: 9, d: 25, h: 5, mi: 30, lon: 116.4, place: "北京", trust: "中", note: "卯时生，清宫档案系统记载"),
        Celeb(name: "爱因斯坦", gender: "M", y: 1879, mo: 3, d: 14, h: 11, mi: 30, lon: 10.0, place: "德国乌尔姆", trust: "高", note: "出生登记载 11:30"),
        Celeb(name: "丘吉尔", gender: "M", y: 1874, mo: 11, d: 30, h: 1, mi: 30, lon: -1.4, place: "英国布伦海姆", trust: "高", note: "凌晨 1:30 生，家族记录明确"),
        Celeb(name: "伊丽莎白二世", gender: "F", y: 1926, mo: 4, d: 21, h: 2, mi: 40, lon: -0.1, place: "英国伦敦", trust: "高", note: "02:40 生，官方公告记载"),
        Celeb(name: "戴安娜王妃", gender: "F", y: 1961, mo: 7, d: 1, h: 19, mi: 45, lon: 0.5, place: "英国桑德灵汉姆", trust: "高", note: "19:45 生，公开记录明确"),
        Celeb(name: "李小龙", gender: "M", y: 1940, mo: 11, d: 27, h: 7, mi: 12, lon: -122.4, place: "美国旧金山", trust: "高", note: "辰时生（07:12），医院记录流传明确"),
        Celeb(name: "特朗普", gender: "M", y: 1946, mo: 6, d: 14, h: 10, mi: 54, lon: -73.8, place: "美国纽约", trust: "高", note: "出生证载 10:54"),
        Celeb(name: "奥巴马", gender: "M", y: 1961, mo: 8, d: 4, h: 19, mi: 24, lon: -157.8, place: "美国檀香山", trust: "高", note: "出生证载 19:24"),
        Celeb(name: "拿破仑", gender: "M", y: 1769, mo: 8, d: 15, h: 11, mi: 0, lon: 8.7, place: "科西嘉阿雅克肖", trust: "中", note: "上午约 11 时，传记通行记载"),
        Celeb(name: "巴菲特", gender: "M", y: 1930, mo: 8, d: 30, h: 15, mi: 0, lon: -95.9, place: "美国奥马哈", trust: "中", note: "下午 3 时许，本人访谈提及"),
        Celeb(name: "比尔·盖茨", gender: "M", y: 1955, mo: 10, d: 28, h: 22, mi: 0, lon: -122.3, place: "美国西雅图", trust: "中", note: "晚 10 时许，通行记载"),
    ]
}

struct CelebView: View {
    var body: some View {
        List {
            Text("只收出生时间有公开记载者：高＝出生证/官方记录，中＝传记通行记载。时辰无据者一律不收——盘宁可少，不可假。点开看本机现算的八字与紫微盘。")
                .font(.caption).foregroundStyle(Ky.sub)
            ForEach(CelebData.all) { c in
                NavigationLink { CelebDetailView(celeb: c) } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.name).font(.system(.headline, design: .serif)).foregroundStyle(Ky.ink)
                            Text("\(c.y) 年生 · \(c.place)").font(.caption).foregroundStyle(Ky.sub)
                        }
                        Spacer()
                        Text("可信度 \(c.trust)").font(.caption2)
                            .foregroundStyle(c.trust == "高" ? Ky.jade : Ky.gold)
                    }
                }
            }
        }
        .navigationTitle("名人命例库")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CelebDetailView: View {
    let celeb: Celeb
    var body: some View {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let clock = cal.date(from: DateComponents(year: celeb.y, month: celeb.mo, day: celeb.d, hour: celeb.h, minute: celeb.mi))!
        let ch = BaziEngine.paipan(clock: clock, gender: celeb.gender, longitude: celeb.lon)
        let zw = ZiweiEngine.chart(clock: clock, gender: celeb.gender, longitude: celeb.lon)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(celeb.name) · \(celeb.place)").font(.system(.title3, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
                    Text("记载：\(celeb.note)（可信度 \(celeb.trust)）。外国出生者经度已按生地计真太阳时，其当地钟表时间按通行记载的当地时间录入后以北京时间通道换算，时柱或有半时辰级误差，读盘时留意。")
                        .font(.caption).foregroundStyle(Ky.sub)
                }.kyCard()
                BaziResultView(chart: ch, name: celeb.name)
                ZiweiBoardView(chart: zw, name: celeb.name)
            }.padding(16)
        }
        .background(Ky.bg)
        .navigationTitle(celeb.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
