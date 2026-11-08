// 名人命例库（对标问真名人库；首批只收出生时间有公开记载者，每条标注可信度与来源说明，宁缺毋滥）
// G9 扩到 50 条：可信度三档——高＝出生证/官方记录明确到分钟且多源一致；
// 中＝单一公开来源或来源间有小分歧（分歧写清）；低＝仅网络流传未经核实（≤5 条，页面显著标注“仅供参考”）。
import SwiftUI

struct Celeb: Identifiable {
    let id = UUID()
    let name: String; let gender: String
    let y: Int; let mo: Int; let d: Int; let h: Int; let mi: Int
    let lon: Double; let place: String
    let trust: String   // 高/中/低
    let note: String
    let source: String   // 公开来源出处
}

enum CelebData {
    static let all: [Celeb] = [
        Celeb(name: "毛泽东", gender: "M", y: 1893, mo: 12, d: 26, h: 7, mi: 30, lon: 112.5, place: "湖南韶山", trust: "中", note: "辰时生，见于多部传记记载", source: "多部传记通行记载"),
        Celeb(name: "蒋介石", gender: "M", y: 1887, mo: 10, d: 31, h: 12, mi: 0, lon: 121.5, place: "浙江奉化", trust: "中", note: "午时生，奉化溪口家谱与传记记载", source: "奉化溪口家谱与传记记载"),
        Celeb(name: "孙中山", gender: "M", y: 1866, mo: 11, d: 12, h: 6, mi: 0, lon: 113.5, place: "广东香山", trust: "中", note: "卯时生，通行传记记载", source: "通行传记记载"),
        Celeb(name: "乾隆帝", gender: "M", y: 1711, mo: 9, d: 25, h: 5, mi: 30, lon: 116.4, place: "北京", trust: "中", note: "卯时生，清宫档案系统记载", source: "清宫档案系统记载"),
        Celeb(name: "爱因斯坦", gender: "M", y: 1879, mo: 3, d: 14, h: 11, mi: 30, lon: 10.0, place: "德国乌尔姆", trust: "高", note: "出生登记载 11:30", source: "德国乌尔姆出生登记"),
        Celeb(name: "丘吉尔", gender: "M", y: 1874, mo: 11, d: 30, h: 1, mi: 30, lon: -1.4, place: "英国布伦海姆", trust: "高", note: "凌晨 1:30 生，家族记录明确", source: "家族记录"),
        Celeb(name: "伊丽莎白二世", gender: "F", y: 1926, mo: 4, d: 21, h: 2, mi: 40, lon: -0.1, place: "英国伦敦", trust: "高", note: "02:40 生，官方公告记载", source: "王室官方公告"),
        Celeb(name: "戴安娜王妃", gender: "F", y: 1961, mo: 7, d: 1, h: 19, mi: 45, lon: 0.5, place: "英国桑德灵汉姆", trust: "高", note: "19:45 生，公开记录明确", source: "公开记录"),
        Celeb(name: "李小龙", gender: "M", y: 1940, mo: 11, d: 27, h: 7, mi: 12, lon: -122.4, place: "美国旧金山", trust: "高", note: "辰时生（07:12），医院记录流传明确", source: "医院记录流传"),
        Celeb(name: "特朗普", gender: "M", y: 1946, mo: 6, d: 14, h: 10, mi: 54, lon: -73.8, place: "美国纽约", trust: "高", note: "出生证载 10:54", source: "出生证"),
        Celeb(name: "奥巴马", gender: "M", y: 1961, mo: 8, d: 4, h: 19, mi: 24, lon: -157.8, place: "美国檀香山", trust: "高", note: "出生证载 19:24", source: "出生证"),
        Celeb(name: "拿破仑", gender: "M", y: 1769, mo: 8, d: 15, h: 11, mi: 0, lon: 8.7, place: "科西嘉阿雅克肖", trust: "中", note: "上午约 11 时，传记通行记载", source: "传记通行记载"),
        Celeb(name: "巴菲特", gender: "M", y: 1930, mo: 8, d: 30, h: 15, mi: 0, lon: -95.9, place: "美国奥马哈", trust: "中", note: "下午 3 时许，本人访谈提及", source: "本人访谈提及"),
        Celeb(name: "比尔·盖茨", gender: "M", y: 1955, mo: 10, d: 28, h: 22, mi: 0, lon: -122.3, place: "美国西雅图", trust: "中", note: "晚 10 时许，通行记载", source: "通行记载"),
        Celeb(name: "玛丽莲·梦露", gender: "F", y: 1926, mo: 6, d: 1, h: 9, mi: 30, lon: -118.2, place: "美国洛杉矶", trust: "高", note: "09:30 生，多源一致；另有一 12:30 推测版未采", source: "出生证（Astro-Databank AA 评级，多源一致）"),
        Celeb(name: "猫王埃尔维斯·普雷斯利", gender: "M", y: 1935, mo: 1, d: 8, h: 4, mi: 35, lon: -88.7, place: "美国图珀洛", trust: "中", note: "04:35 生，产科医生日志记载；异说：本人自报 03:30，Rudhyar 推运修正为 03:34", source: "Astro-Databank AA（产科医生日志）"),
        Celeb(name: "约翰·列侬", gender: "M", y: 1940, mo: 10, d: 9, h: 18, mi: 30, lon: -3.0, place: "英国利物浦", trust: "高", note: "18:30 生（BST），多源一致", source: "多源公开记载（astrotheme 等）"),
        Celeb(name: "迈克尔·杰克逊", gender: "M", y: 1958, mo: 8, d: 29, h: 19, mi: 33, lon: -87.35, place: "美国加里", trust: "高", note: "19:33 生，家人证实源自出生证；个别低质页作 5:30 未采", source: "出生证（家人证实，Astro-Databank A）"),
        Celeb(name: "麦当娜", gender: "F", y: 1958, mo: 8, d: 16, h: 7, mi: 5, lon: -83.9, place: "美国贝城", trust: "中", note: "07:05 生，多源一致；另有 07:00 取整版；本人自称水瓶座上升（暗示另一时间）", source: "多源公开记载（astrotheme 等）"),
        Celeb(name: "保罗·麦卡特尼", gender: "M", y: 1942, mo: 6, d: 18, h: 14, mi: 0, lon: -3.0, place: "英国利物浦", trust: "中", note: "14:00 生；异说凌晨 2:00；1942 年夏英国实行双夏令时 GMT+2", source: "Astro-Databank A（据回忆／自传）"),
        Celeb(name: "约翰·F·肯尼迪", gender: "M", y: 1917, mo: 5, d: 29, h: 15, mi: 0, lon: -71.1, place: "美国布鲁克莱恩", trust: "高", note: "15:00 生，马萨诸塞州布鲁克莱恩 Beals 街 83 号；故居时钟停在 3:00", source: "美国国家档案馆 JFK 100 文"),
        Celeb(name: "史蒂夫·乔布斯", gender: "M", y: 1955, mo: 2, d: 24, h: 19, mi: 15, lon: -122.4, place: "美国旧金山", trust: "高", note: "19:15 生", source: "出生证（Astro-Databank AA）"),
        Celeb(name: "比尔·克林顿", gender: "M", y: 1946, mo: 8, d: 19, h: 8, mi: 51, lon: -93.6, place: "美国霍普", trust: "中", note: "08:51 生；另有 8:53（2 分钟差）与 8:41 两版", source: "母亲经 Shelley Ackerman 转述（主流多源）"),
        Celeb(name: "玛格丽特·撒切尔", gender: "F", y: 1925, mo: 10, d: 13, h: 9, mi: 0, lon: -0.6, place: "英国格兰瑟姆", trust: "中", note: "09:00 生，多源一致，但为整点、单一源头", source: "多源公开记载"),
        Celeb(name: "穆罕默德·阿里", gender: "M", y: 1942, mo: 1, d: 17, h: 18, mi: 35, lon: -85.8, place: "美国路易斯维尔", trust: "高", note: "18:35 生", source: "出生证在手（Astro-Databank Rodden AA）"),
        Celeb(name: "萨尔瓦多·达利", gender: "M", y: 1904, mo: 5, d: 11, h: 8, mi: 45, lon: 3.0, place: "西班牙菲格雷斯", trust: "高", note: "08:45 生；维基称 8:45 am GMT，西班牙当时为 CET，当地钟表或差 1 小时", source: "维基百科＋传记＋Astro-Databank AA"),
        Celeb(name: "弗里达·卡罗", gender: "F", y: 1907, mo: 7, d: 6, h: 8, mi: 30, lon: -99.2, place: "墨西哥科约阿坎", trust: "高", note: "08:30 生（LMT）；她本人谎称生于 1910 年，出生证为 1907 年", source: "出生证（Astro-Databank AA）"),
        Celeb(name: "查尔斯三世", gender: "M", y: 1948, mo: 11, d: 14, h: 21, mi: 14, lon: -0.1, place: "英国伦敦", trust: "高", note: "21:14 生", source: "王室官方公告（维基百科正文）"),
        Celeb(name: "惠特妮·休斯顿", gender: "F", y: 1963, mo: 8, d: 9, h: 20, mi: 55, lon: -74.2, place: "美国纽瓦克", trust: "高", note: "20:55 生，多源一致", source: "出生证（Astro-Databank AA）"),
        Celeb(name: "大卫·鲍伊", gender: "M", y: 1947, mo: 1, d: 8, h: 9, mi: 0, lon: -0.1, place: "英国伦敦布里克斯顿", trust: "中", note: "09:00 生；本人自认约 9:30，另有 9:04／9:08／9:15 版，均在巳时内，四柱相同", source: "多部传记（astrotheme）"),
        Celeb(name: "鲍勃·马利", gender: "M", y: 1945, mo: 2, d: 6, h: 2, mi: 30, lon: -77.1, place: "牙买加九英里", trust: "中", note: "02:30 生；无出生证；另有 9:30 版无明确来源；本人曾质疑日期", source: "传记《Catch a Fire》（Timothy White）"),
        Celeb(name: "奥黛丽·赫本", gender: "F", y: 1929, mo: 5, d: 4, h: 3, mi: 0, lon: 4.4, place: "比利时伊克塞尔", trust: "高", note: "03:00 生，多源一致；个别自动生成站称未记录，已以 AA 为准", source: "Astro-Databank AA（引出生证／登记）"),
        Celeb(name: "弗兰克·辛纳屈", gender: "M", y: 1915, mo: 12, d: 12, h: 3, mi: 0, lon: -74.0, place: "美国霍博肯", trust: "中", note: "03:00 生；另有 3:10 版", source: "父亲记忆（Astro-Databank A）"),
        Celeb(name: "格蕾丝·凯利", gender: "F", y: 1929, mo: 11, d: 12, h: 5, mi: 31, lon: -75.2, place: "美国费城", trust: "高", note: "05:31 生，多源一致", source: "Astro-Databank Rodden AA"),
        Celeb(name: "詹姆斯·迪恩", gender: "M", y: 1931, mo: 2, d: 8, h: 9, mi: 0, lon: -85.7, place: "美国马里恩", trust: "中", note: "09:00 生；出生地纪念牌作凌晨 2:00，另有 2:10 版，分歧涉及时柱，已以出生证版为准", source: "出生证（Astro-Databank）"),
        Celeb(name: "马龙·白兰度", gender: "M", y: 1924, mo: 4, d: 3, h: 23, mi: 0, lon: -95.9, place: "美国奥马哈", trust: "高", note: "23:00 生，晚子时边界", source: "出生证（Astro-Databank AA）"),
        Celeb(name: "伊丽莎白·泰勒", gender: "F", y: 1932, mo: 2, d: 27, h: 2, mi: 15, lon: -0.1, place: "英国伦敦", trust: "高", note: "02:15 生；另有 2:30 版，两版均在丑时内，四柱相同", source: "出生证（Astro-Databank AA，IMDb 亦作 2:15）"),
        Celeb(name: "朱迪·嘉兰", gender: "F", y: 1922, mo: 6, d: 10, h: 6, mi: 0, lon: -93.5, place: "美国大急流城（明尼苏达）", trust: "中", note: "06:00 生，多源一致；个别站称时间未记录", source: "多源公开记载"),
        Celeb(name: "凯瑟琳·赫本", gender: "F", y: 1907, mo: 5, d: 12, h: 17, mi: 47, lon: -72.7, place: "美国哈特福德", trust: "高", note: "17:47 生，哈特福德 Hudson 街 22 号；她曾谎报生年 1909，真为 1907 年", source: "Astro-Databank Rodden AA"),
        Celeb(name: "克拉克·盖博", gender: "M", y: 1901, mo: 2, d: 1, h: 5, mi: 30, lon: -81.0, place: "美国卡迪兹", trust: "中", note: "05:30 生，家中出生，无出生证引文；horos.me 作 3:30 未确认，未采", source: "出生地博物馆／传记通行记载"),
        Celeb(name: "贝蒂·戴维斯", gender: "F", y: 1908, mo: 4, d: 5, h: 21, mi: 0, lon: -71.3, place: "美国洛厄尔", trust: "中", note: "21:00 生，多源一致", source: "多源公开记载（astrotheme 等）"),
        Celeb(name: "理查德·尼克松", gender: "M", y: 1913, mo: 1, d: 9, h: 21, mi: 35, lon: -117.8, place: "美国约巴林达", trust: "中", note: "21:35 生；地方史称传记作 9:30 P.M.（5 分钟差，同在亥时，四柱相同）", source: "多源公开记载"),
        Celeb(name: "罗纳德·里根", gender: "M", y: 1911, mo: 2, d: 6, h: 4, mi: 16, lon: -89.8, place: "美国坦皮科", trust: "低", note: "04:16 生；另有据传记推断的下午 2 点版（涉及时柱：寅时 vs 未时），仅供参考", source: "占星师 Ralph Kraum 流传版（经 Lois Rodden／Marc Edmund Jones）；horos.me 评 DD 冲突未核实"),
        Celeb(name: "马丁·路德·金", gender: "M", y: 1929, mo: 1, d: 15, h: 12, mi: 0, lon: -84.4, place: "美国亚特兰大", trust: "中", note: "12:00 生，正午出生；futurepointindia 作 11:21（低质），两版均在午时内，四柱相同", source: "King Center 传记等多源"),
        Celeb(name: "希拉里·克林顿", gender: "F", y: 1947, mo: 10, d: 26, h: 20, mi: 0, lon: -87.6, place: "美国芝加哥", trust: "低", note: "20:00 生；本人先后自述 8pm 与 8am 两版（涉及时柱：辰时 vs 戌时），仅供参考", source: "本人自述（WSJ 2016 年报道，竞选团队拒绝澄清）"),
        Celeb(name: "阿娃·加德纳", gender: "F", y: 1922, mo: 12, d: 24, h: 19, mi: 10, lon: -78.3, place: "美国格拉布敦", trust: "高", note: "19:10 生；其自传误忆为晚上 10 点，已以出生证为准", source: "原始出生证（Johnston 县登记处，2022 年移交博物馆）"),
        Celeb(name: "鲍勃·迪伦", gender: "M", y: 1941, mo: 5, d: 24, h: 21, mi: 5, lon: -92.1, place: "美国德卢斯", trust: "高", note: "21:05 生，多源一致", source: "Astro-Databank AA"),
        Celeb(name: "普林斯", gender: "M", y: 1958, mo: 6, d: 7, h: 18, mi: 17, lon: -93.3, place: "美国明尼阿波利斯", trust: "高", note: "18:17 生，多源一致", source: "出生记录（Astro-Databank Rodden AA）"),
        Celeb(name: "卡尔·萨根", gender: "M", y: 1934, mo: 11, d: 9, h: 17, mi: 5, lon: -73.9, place: "美国布鲁克林", trust: "高", note: "17:05 生，多源一致", source: "出生证在手（Astro-Databank AA）"),
        Celeb(name: "安迪·沃霍尔", gender: "M", y: 1928, mo: 8, d: 6, h: 6, mi: 30, lon: -80.0, place: "美国匹兹堡", trust: "中", note: "06:30 生，多源一致", source: "回忆录《Famous For Fifteen Minutes》p.38（Ultraviolet）"),
    ]
}

struct CelebView: View {
    var body: some View {
        List {
            Text("只收出生时间有公开记载者：高＝出生证/官方记录明确到分钟且多源一致，中＝单一公开来源或来源间有小分歧（分歧写清），低＝仅网络流传未经核实（≤5 条，页面显著标注“仅供参考”）。时辰无据者一律不收——盘宁可少，不可假。点开看本机现算的八字与紫微盘。".scriptConverted)
                .font(.caption).foregroundStyle(Ky.sub)
            ForEach(CelebData.all) { c in
                NavigationLink { CelebDetailView(celeb: c) } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.name).font(.system(.headline, design: .serif)).foregroundStyle(Ky.ink)
                            Text("\(c.y) 年生 · \(c.place)".scriptConverted).font(.caption).foregroundStyle(Ky.sub)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("可信度 \(c.trust)".scriptConverted).font(.caption2)
                                .foregroundStyle(c.trust == "高" ? Ky.jade : (c.trust == "低" ? Color.red : Ky.gold))
                            if c.trust == "低" {
                                Text("仅供参考".scriptConverted).font(.caption2).foregroundStyle(Color.red)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("名人命例库".scriptConverted)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CelebDetailView: View {
    let celeb: Celeb
    private var clock: Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return cal.date(from: DateComponents(year: celeb.y, month: celeb.mo, day: celeb.d, hour: celeb.h, minute: celeb.mi))!
    }
    var body: some View {
        let ch = BaziEngine.cachedPaipan(clock: clock, gender: celeb.gender, longitude: celeb.lon)
        let zw = ZiweiEngine.cachedChart(clock: clock, gender: celeb.gender, longitude: celeb.lon)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(celeb.name) · \(celeb.place)").font(.system(.title3, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
                    if celeb.trust == "低" {
                        Text("低可信度条目，仅供参考：出生时间未经核实，分歧见下。".scriptConverted).font(.caption).foregroundStyle(Color.red)
                    }
                    Text("记载：\(celeb.note)（可信度 \(celeb.trust)）。外国出生者经度已按生地计真太阳时，其当地钟表时间按通行记载的当地时间录入后以北京时间通道换算，时柱或有半时辰级误差，读盘时留意。".scriptConverted)
                        .font(.caption).foregroundStyle(Ky.sub)
                    Text("来源：\(celeb.source)".scriptConverted).font(.caption).foregroundStyle(Ky.sub)
                }.kyCard()
                BaziResultView(chart: ch, name: celeb.name)
                ZiweiBoardView(chart: zw, name: celeb.name)
            }.padding(16).padding(.bottom, 100)
        }
        .background(Ky.bg)
        .navigationTitle(celeb.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
