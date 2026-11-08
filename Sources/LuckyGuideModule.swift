// 开运指南页（Insight 第 2 批 G6，2026-11-09）
// 内容全部复用 30 维引擎现算：InterpretEngine.interpret(chart:) 结论原文
// （幸运颜色与数字／适合方位／如何化解）＋ InterpretEngine.posterXiJi(chart:) 喜忌定论。
// 本页不新编任何口径、不新增断语；场景分级只收拢已在位的应用层建议。
// 层级：全页传统应用参考／民间象征层，图提醒与心安，不代表功效主张，别为它花高价买开运物。
// 收藏：UserDefaults 键 kanyu.lucky.favorites.v1（字符串数组），不写任何数据文件。
//
// —— 色卡 HEX/RGB 映射表（五行配色通说应用层色值对照）——
// 本表只给中文色名配一组应用层展示色值（取常见标准色板值，便于在界面上画出色块），
// 是「五行配色通说应用层色值对照」，不是典籍原文、不是唯一标准色值，不得伪造典籍出处。
//   木：青 #009688 RGB 0,150,136；绿 #43A047 RGB 67,160,71
//   火：红 #D32F2F RGB 211,47,47；紫 #7B1FA2 RGB 123,31,162
//   土：黄 #F9A825 RGB 249,168,37；棕 #795548 RGB 121,85,72
//   金：白 #FFFFFF RGB 255,255,255；金 #C9A227 RGB 201,162,39
//   水：黑 #212121 RGB 33,33,33；蓝 #1E88E5 RGB 30,136,229
// 色名与五行对应取 InterpretModule colorMap（木青绿、火红紫、土黄棕、金白金、水黑蓝），与引擎同源。
import SwiftUI

/// 单个中文色名的应用层色卡（色名／HEX／RGB 值／所属五行）。
struct LuckyColorSwatch {
    let name: String
    let hex: String
    let rgb: UInt32
    let wuxing: String

    var rgbText: String {
        let r = (rgb >> 16) & 0xFF
        let g = (rgb >> 8) & 0xFF
        let b = rgb & 0xFF
        return "\(r), \(g), \(b)"
    }
}

enum LuckyColorData {
    /// 五行配色通说应用层色值对照（见文件头注释；色名取引擎 colorMap，色值为应用层展示值）。
    static let all: [LuckyColorSwatch] = [
        LuckyColorSwatch(name: "青", hex: "#009688", rgb: 0x009688, wuxing: "木"),
        LuckyColorSwatch(name: "绿", hex: "#43A047", rgb: 0x43A047, wuxing: "木"),
        LuckyColorSwatch(name: "红", hex: "#D32F2F", rgb: 0xD32F2F, wuxing: "火"),
        LuckyColorSwatch(name: "紫", hex: "#7B1FA2", rgb: 0x7B1FA2, wuxing: "火"),
        LuckyColorSwatch(name: "黄", hex: "#F9A825", rgb: 0xF9A825, wuxing: "土"),
        LuckyColorSwatch(name: "棕", hex: "#795548", rgb: 0x795548, wuxing: "土"),
        LuckyColorSwatch(name: "白", hex: "#FFFFFF", rgb: 0xFFFFFF, wuxing: "金"),
        LuckyColorSwatch(name: "金", hex: "#C9A227", rgb: 0xC9A227, wuxing: "金"),
        LuckyColorSwatch(name: "黑", hex: "#212121", rgb: 0x212121, wuxing: "水"),
        LuckyColorSwatch(name: "蓝", hex: "#1E88E5", rgb: 0x1E88E5, wuxing: "水"),
    ]

    /// 引擎 colorMap 的色名分行（与 InterpretModule:1553 同源）。
    static let colorNamesByWuxing: [String: [String]] = [
        "木": ["青", "绿"],
        "火": ["红", "紫"],
        "土": ["黄", "棕"],
        "金": ["白", "金"],
        "水": ["黑", "蓝"],
    ]

    static func swatches(forWuxing wx: String) -> [LuckyColorSwatch] {
        let names = colorNamesByWuxing[wx] ?? []
        return all.filter { names.contains($0.name) }
    }
}

struct LuckyGuideView: View {
    let person: Person
    let chart: BaziChart

    private static let favoritesKey = "kanyu.lucky.favorites.v1"
    @State private var favorites: Set<String> = []

    private var items: [InterpretItem] { InterpretEngine.interpret(chart: chart) }
    private var xj: (xi: [Int], ji: [Int], neutral: [Int], level: String, tongDang: Double, tiaoHou: [Int]) {
        InterpretEngine.posterXiJi(chart: chart)
    }

    private var wxNames: [String] { ["木", "火", "土", "金", "水"] }
    private var xiNames: String { xj.xi.map { wxNames[$0] }.joined(separator: "、") }
    private var jiNames: String { xj.ji.map { wxNames[$0] }.joined(separator: "、") }
    private var xiSwatches: [LuckyColorSwatch] {
        xj.xi.flatMap { LuckyColorData.swatches(forWuxing: wxNames[$0]) }
    }
    private var jiSwatches: [LuckyColorSwatch] {
        xj.ji.flatMap { LuckyColorData.swatches(forWuxing: wxNames[$0]) }
    }

    private var luckyColorText: String {
        InterpretEngine.conclusion(items: items, titles: "幸运颜色与数字")
    }
    private var directionText: String {
        InterpretEngine.conclusion(items: items, titles: "适合方位")
    }
    private var resolveText: String {
        InterpretEngine.conclusion(items: items, titles: "如何化解（破局调理）")
    }
    private var careerText: String {
        InterpretEngine.conclusion(items: items, titles: "事业方向")
    }
    private var resolveTimeRange: String? {
        items.first(where: { $0.title == "如何化解（破局调理）" })?.timeRange
    }

    private var favoriteSections: [(id: String, title: String)] {
        [
            ("色卡", "幸运色卡"),
            ("数字方位", "幸运数字与方位"),
            ("服装", "服装"),
            ("家居", "家居"),
            ("办公", "办公"),
            ("化解", "化解五路"),
        ].filter { favorites.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                banner
                if favoriteSections.isEmpty == false {
                    favoritesCard
                }
                overviewCard
                colorCard
                numberDirectionCard
                sceneCard(id: "服装", title: "服装", rows: clothingRows)
                sceneCard(id: "家居", title: "家居", rows: homeRows)
                sceneCard(id: "办公", title: "办公", rows: officeRows)
                resolveCard
                sourceNote
            }
            .padding(.horizontal, KyV6.pageHorizontalMargin)
            .padding(.top, 6)
            .padding(.bottom, 100)
        }
        .background(Ky.bg)
        .navigationTitle("开运指南".scriptConverted)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let stored = UserDefaults.standard.stringArray(forKey: Self.favoritesKey) ?? []
            favorites = Set(stored)
        }
    }

    // MARK: - 顶部层级标注（每页必带）

    private var banner: some View {
        Text("传统应用参考／民间象征层——本页内容图提醒与心安，不代表功效主张，别为它花高价买开运物。".scriptConverted)
            .font(.callout).fontWeight(.semibold).foregroundStyle(Ky.cinnabar)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Ky.cinnabar.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - 收藏

    private var favoritesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            KySectionTitle(title: "我的收藏", trailing: "存在本机，不写数据文件")
            ForEach(favoriteSections, id: \.id) { section in
                HStack(spacing: 8) {
                    Image(systemName: "star.fill")
                        .font(.caption).foregroundStyle(Ky.gold)
                    Text(section.title.scriptConverted)
                        .font(.callout).foregroundStyle(Ky.ink)
                    Spacer()
                    Button {
                        toggleFavorite(section.id)
                    } label: {
                        Text("取消收藏".scriptConverted)
                            .font(.caption).foregroundStyle(Ky.sub)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .kyCard()
    }

    private func toggleFavorite(_ id: String) {
        if favorites.contains(id) {
            favorites.remove(id)
        } else {
            favorites.insert(id)
        }
        UserDefaults.standard.set(Array(favorites), forKey: Self.favoritesKey)
    }

    private func favoriteButton(_ id: String) -> some View {
        Button {
            toggleFavorite(id)
        } label: {
            Image(systemName: favorites.contains(id) ? "star.fill" : "star")
                .font(.callout).foregroundStyle(Ky.gold)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 喜用总览（引擎现算）

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            KySectionTitle(title: "喜用总览", trailing: "30 维引擎现算")
            if xj.level == "中和" {
                Text("本盘身中和，无固定喜忌（posterXiJi 定论：扶抑中和）。色卡按下表五行通说全列，仅作传统应用参考。".scriptConverted)
                    .font(.callout).foregroundStyle(Ky.ink)
            } else {
                Text("身\(xj.level)，喜用五行 \(xiNames)。忌向 \(jiNames.isEmpty ? "无" : jiNames)。".scriptConverted)
                    .font(.callout).foregroundStyle(Ky.ink)
                Text("喜忌定论：扶抑初判＋调候优先（InterpretEngine.posterXiJi，与预测单同口径）。".scriptConverted)
                    .font(.caption2).foregroundStyle(Ky.sub)
            }
        }
        .kyCard()
    }

    // MARK: - 幸运色卡

    private var colorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                KySectionTitle(title: "幸运色卡", trailing: "五行配色通说应用层色值对照")
                Spacer()
                favoriteButton("色卡")
            }
            if xj.level == "中和" {
                Text("中和盘无固定喜色，下表为五行通说全表，按需取用。".scriptConverted)
                    .font(.caption).foregroundStyle(Ky.sub)
                ForEach(LuckyColorData.all, id: \.name) { swatch in
                    swatchRow(swatch)
                }
            } else {
                Text("喜色（按喜用五行取）：".scriptConverted)
                    .font(.callout).fontWeight(.semibold).foregroundStyle(Ky.ink)
                ForEach(xiSwatches, id: \.name) { swatch in
                    swatchRow(swatch)
                }
                if jiSwatches.isEmpty == false {
                    Text("忌向色（大面积长期使用少一些，见「幸运颜色与数字」条原文）：".scriptConverted)
                        .font(.callout).fontWeight(.semibold).foregroundStyle(Ky.ink)
                    ForEach(jiSwatches, id: \.name) { swatch in
                        swatchRow(swatch)
                    }
                }
            }
            Text("色值说明：HEX／RGB 为本系统应用层对照值（见页首映射表），不是典籍原文色值。".scriptConverted)
                .font(.caption2).foregroundStyle(Ky.sub)
        }
        .kyCard()
    }

    private func swatchRow(_ swatch: LuckyColorSwatch) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(rgb: swatch.rgb))
                .frame(width: 44, height: 44)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Ky.line, lineWidth: 0.8))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(swatch.name) · \(swatch.wuxing)行".scriptConverted)
                    .font(.callout).fontWeight(.semibold).foregroundStyle(Ky.ink)
                Text("HEX \(swatch.hex) · RGB \(swatch.rgbText)".scriptConverted)
                    .font(.caption).foregroundStyle(Ky.sub)
            }
            Spacer()
        }
    }

    // MARK: - 幸运数字与方位（引擎结论原文）

    private var numberDirectionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                KySectionTitle(title: "幸运数字与方位", trailing: "30 维引擎现算")
                Spacer()
                favoriteButton("数字方位")
            }
            if luckyColorText.isEmpty == false {
                Text(luckyColorText)
                    .font(.callout).foregroundStyle(Ky.ink)
            }
            Divider()
            if directionText.isEmpty == false {
                Text(directionText)
                    .font(.callout).foregroundStyle(Ky.ink)
            }
            Text("来源：30 维详批「幸运颜色与数字」「适合方位」两条结论原文；颜色与数字为民间象征层，方位为流派应用层。".scriptConverted)
                .font(.caption2).foregroundStyle(Ky.sub)
        }
        .kyCard()
    }

    // MARK: - 场景分级（只收拢已在位的应用层建议，不新增断语）

    private var clothingRows: [(label: String, text: String)] {
        var rows: [(label: String, text: String)] = []
        if xiSwatches.isEmpty == false {
            let names = xiSwatches.map { $0.name }.joined(separator: "、")
            rows.append(("服色", "喜色 \(names)，点缀到位即可，不必全身只穿一色（见「幸运颜色与数字」条现算结论）。"))
        } else {
            rows.append(("服色", "中和盘无固定喜色，服色按五行通说全表取用，仅作传统应用参考。"))
        }
        rows.append(("佩饰", "佩饰材质见配饰库（民间象征层），按喜用五行取，不代表功效主张。"))
        return rows
    }

    private var homeRows: [(label: String, text: String)] {
        var rows: [(label: String, text: String)] = []
        if xiSwatches.isEmpty == false {
            let names = xiSwatches.map { $0.name }.joined(separator: "、")
            rows.append(("点缀色", "家居点缀用喜色 \(names)，手机壳、车色、家居点缀都可用（见「幸运颜色与数字」条现算结论）。"))
        }
        rows.append(("摆放", "真迹五项原文引用（传统应用参考，喜忌取舍以本页喜用总览为准，逐项取舍见预测单海报）：宜养花草、穿绿色衣服、佩戴或摆放木质工艺品；宜穿红色衣服，床头挂红色中国结；宜穿黄色、咖啡色、灰色衣服，佩戴玉石类、翡翠、玛瑙，摆放石头工艺品；宜穿白色衣服，佩戴金银饰品，摆放金属类工艺品；宜养鱼，挂山水画，穿黑色、蓝色衣服，佩戴水晶、珍珠饰品，摆放水晶类工艺品。"))
        rows.append(("朝向", "书桌与床头方向优先朝喜用方位（见「适合方位」条现算结论）；屋内门床灶吉凶另有八宅与飞星法，不拿这一条代替。"))
        rows.append(("饮食", "五行补救四向之一（行业／方位／服色／饮食），见知识库 id 56 第 3 层；本页不另列具体食谱。"))
        return rows
    }

    private var officeRows: [(label: String, text: String)] {
        var rows: [(label: String, text: String)] = []
        if careerText.isEmpty == false {
            rows.append(("行业", careerText))
        }
        rows.append(("方位", "办公位朝向优先朝喜用方位（见「适合方位」条现算结论）。"))
        return rows
    }

    private func sceneCard(id: String, title: String, rows: [(label: String, text: String)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                KySectionTitle(title: title, trailing: "场景分级 · 应用层建议")
                Spacer()
                favoriteButton(id)
            }
            ForEach(rows.indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: 4) {
                    Text(rows[i].label.scriptConverted)
                        .font(.callout).fontWeight(.semibold).foregroundStyle(Ky.gold)
                    Text(rows[i].text)
                        .font(.callout).foregroundStyle(Ky.ink)
                }
                if i < rows.count - 1 {
                    Divider()
                }
            }
            if id == "服装" {
                NavigationLink {
                    AccessoryListView()
                } label: {
                    HStack(spacing: 6) {
                        Text("打开配饰库".scriptConverted)
                            .font(.callout).fontWeight(.semibold).foregroundStyle(Ky.qingdai)
                        Image(systemName: "chevron.right")
                            .font(.caption).foregroundStyle(Ky.qingdai)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .kyCard()
    }

    // MARK: - 化解五路（引擎结论原文）

    private var resolveCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                KySectionTitle(title: "化解五路", trailing: "破局五层法 · 引擎现算")
                Spacer()
                favoriteButton("化解")
            }
            if resolveText.isEmpty == false {
                Text(resolveText)
                    .font(.callout).foregroundStyle(Ky.ink)
            }
            if let range = resolveTimeRange {
                Text("时间范围：\(range)".scriptConverted)
                    .font(.caption).foregroundStyle(Ky.sub)
            }
            Text("来源：30 维详批「如何化解（破局调理）」条结论原文；其中颜色、数字、佩饰一路为民间象征层，图提醒与心安。".scriptConverted)
                .font(.caption2).foregroundStyle(Ky.sub)
        }
        .kyCard()
    }

    private var sourceNote: some View {
        Text("口径说明：本页全部内容复用 30 维引擎现算与已在位的应用层建议，不新编口径；色卡 HEX／RGB 为五行配色通说应用层色值对照（见页首映射表），不冒充典籍出处。".scriptConverted)
            .font(.caption2).foregroundStyle(Ky.sub)
    }
}
