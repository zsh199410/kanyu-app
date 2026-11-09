// 全家盘＋合盘分享卡片（G10，2026-11-08）
// 口径与 Web 端 app/family.py 同源，只复用现有引擎，不另造合参算法：
// - 每人四柱＋喜忌定论：BaziEngine.cachedPaipan 现算＋InterpretEngine.posterXiJi 定论；
//   大运当年要点：YearEngine.report(chart, 当年) 原文。
// - 三人之间两两合盘：喜用互补／日柱判语逐式复用 SynastryModule.swift（合婚四看）原式，
//   本文件只做同款复述，不改 SynastryModule 口径。
// - 四维交叉裁决：BaziZiweiCrossEngine.verdicts（八字×紫微）每人原文并置；
//   裁决句（同频相催／互补制化／分期应验）取引擎原文，不另造新裁决。
// - 合盘分享卡片总评一句：只报互补计数事实（双向／单向／不显＋天干五合对数＋地支
//   合／冲／刑／穿／破计数），不编新断语（G2 已定口径，Web 端同款）。
// - 二维码：系统内置 CIQRCodeGenerator 生成，不调外部在线二维码服务。
//   注意：App 本地人物 id（UUID）与 Web 档案 id 不是同一套，App 端二维码链接在 Web 端
//   打开时会提示人物不在档案库；可直接扫码打开的正式分享链接请在 Web 端合盘页生成。
import SwiftUI
import CoreImage.CIFilterBuiltins

struct FamilyChartView: View {
    @EnvironmentObject var store: PeopleStore
    @State private var aId: UUID?
    @State private var bId: UUID?
    @State private var cId: UUID?
    @State private var posterURL: URL?
    @State private var posterImage: UIImage?
    @State private var saveMessage: String?

    private var year: Int { Calendar.current.component(.year, from: Date()) }
    private let wxNames = ["木", "火", "土", "金", "水"]

    private func chart(of p: Person) -> BaziChart {
        BaziEngine.cachedPaipan(clock: p.birthDate, gender: p.gender,
                                longitude: p.useLongitude ? p.longitude : nil)
    }
    private func ziwei(of p: Person) -> ZiweiChart {
        ZiweiEngine.cachedChart(clock: p.birthDate, gender: p.gender,
                        longitude: p.useLongitude ? p.longitude : nil)
    }
    private func selected(_ id: UUID?) -> Person? { store.people.first { $0.id == id } }
    private var picked: [Person] {
        [aId, bId, cId].compactMap { selected($0) }
    }
    private var pickedDistinct: [Person]? {
        let ps = picked
        guard ps.count == 3, Set(ps.map { $0.id }).count == 3 else { return nil }
        return ps
    }

    // 喜用初判：与 SynastryModule.xiYong 同式（同党占比 55／40 阈值）。
    private func xiYong(of ch: BaziChart) -> (level: String, xi: [String]) {
        let dayWx: Int = { switch ch.rizhu { case "甲", "乙": return 0; case "丙", "丁": return 1
            case "戊", "己": return 2; case "庚", "辛": return 3; default: return 4 } }()
        let shengWo = (dayWx + 4) % 5
        let tong = ch.wuxingPercents[dayWx] + ch.wuxingPercents[shengWo]
        if tong >= 55 { return ("偏强", [(dayWx + 1) % 5, (dayWx + 2) % 5, (dayWx + 3) % 5].map { wxNames[$0] }) }
        if tong <= 40 { return ("偏弱", [shengWo, dayWx].map { wxNames[$0] }) }
        return ("中和", [])
    }
    private func strongestWx(of ch: BaziChart) -> String {
        let idx = ch.wuxingPercents.indices.max(by: { ch.wuxingPercents[$0] < ch.wuxingPercents[$1] }) ?? 0
        return wxNames[idx]
    }
    // 互补判语：与 SynastryModule 互补判语同式（最旺行落对方喜用才算补益）。
    private func hubuText(a: Person, b: Person) -> String {
        let ca = chart(of: a)
        let cb = chart(of: b)
        let xa = xiYong(of: ca)
        let xb = xiYong(of: cb)
        let strongA = strongestWx(of: ca)
        let strongB = strongestWx(of: cb)
        var parts: [String] = []
        if xa.xi.contains(strongB) { parts.append("\(b.name)的旺气（\(strongB)）正落在\(a.name)所喜之内，补益在\(a.name)这边") }
        if xb.xi.contains(strongA) { parts.append("\(a.name)的旺气（\(strongA)）正落在\(b.name)所喜之内，补益在\(b.name)这边") }
        if parts.isEmpty { return "两盘旺气未直接落入对方喜用，互补不显——要回到日柱与全局互动细看，不硬凑互补。" }
        return parts.joined(separator: "；") + "。"
    }
    // 日柱判语：与 SynastryModule 日柱判语同式（天干五合＋日支合／冲／刑／穿）。
    private func dayPillarText(a: Person, b: Person) -> String {
        let ca = chart(of: a)
        let cb = chart(of: b)
        let ganHe: [Character: Character] = ["甲": "己", "己": "甲", "乙": "庚", "庚": "乙", "丙": "辛",
                                             "辛": "丙", "丁": "壬", "壬": "丁", "戊": "癸", "癸": "戊"]
        var parts: [String] = []
        if ganHe[ca.dayPillar.first ?? "甲"] == cb.dayPillar.first {
            parts.append("日干五合：两人天干相合，天然亲近、易有黏性")
        }
        if let rel = BaziTables.relationFull(ca.dayPillar.last ?? "子", cb.dayPillar.last ?? "子") {
            switch rel.0 {
            case "合": parts.append("日支六合：配偶宫相合，居家节奏易对拍")
            case "冲": parts.append("日支相冲：配偶宫对冲，节奏与习惯要磨，忌冷战硬碰")
            case "刑": parts.append("日支相刑：相处有纠缠点，规矩先立在前面")
            case "穿": parts.append("日支相穿：易有暗里误会，话要说透")
            default: break
            }
        }
        return parts.isEmpty ? "日柱无直接合冲：关系定性回到喜用与全局互动，不靠日柱一条下断。" : parts.joined(separator: "；") + "。"
    }
    private func hubuDirections(a: Person, b: Person) -> Int {
        let ca = chart(of: a)
        let cb = chart(of: b)
        let xa = xiYong(of: ca)
        let xb = xiYong(of: cb)
        var n = 0
        if xa.xi.contains(strongestWx(of: cb)) { n += 1 }
        if xb.xi.contains(strongestWx(of: ca)) { n += 1 }
        return n
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                Text("口径：每人盘面事实来源 BaziEngine 现算＋InterpretEngine 定论＋YearEngine 当年要点；两两合盘复用合婚四看；四维裁决复用八字×紫微 hecan 原文，不另造新裁决。".scriptConverted)
                    .font(.caption).foregroundStyle(Ky.sub)
                PersonQuickBar(store: store) { p in
                    if aId == nil { aId = p.id }
                    else if bId == nil { bId = p.id }
                    else if cId == nil { cId = p.id }
                    else { aId = p.id; bId = nil; cId = nil }
                }
                pickerCard
                if let ps = pickedDistinct {
                    memberCards(ps)
                    pairCards(ps)
                    crossCards(ps)
                    posterSection(ps)
                } else {
                    KyEmptyState(icon: "person.3.fill", title: "从人物档案里选三位不同的人", message: "档案里不足三人时，先去「人物档案」建档。")
                }
                Text("全家盘海报与 Web 端同款（1080 宽、左右 28px 零墨）；App 端海报由本页内容直接渲染导出。".scriptConverted)
                    .font(.caption2).foregroundStyle(Ky.sub)
            }.padding(16).padding(.bottom, 100)
        }
        .background(Ky.bg)
        .navigationTitle("全家盘".scriptConverted)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var pickerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            personPicker("其一".scriptConverted, selection: $aId)
            personPicker("其二".scriptConverted, selection: $bId)
            personPicker("其三".scriptConverted, selection: $cId)
        }
        .kyCard()
    }

    private func personPicker(_ label: String, selection: Binding<UUID?>) -> some View {
        Picker(label, selection: selection) {
            Text("未选".scriptConverted).tag(UUID?.none)
            ForEach(store.people) { p in Text(p.name).tag(UUID?.some(p.id)) }
        }.pickerStyle(.menu).tint(Ky.ink)
    }

    @ViewBuilder private func memberCards(_ ps: [Person]) -> some View {
        ForEach(ps) { p in
            let ch = chart(of: p)
            let xj = InterpretEngine.posterXiJi(chart: ch)
            let xiText = xj.xi.map { wxNames[$0] }.joined(separator: "、")
            let jiText = xj.ji.map { wxNames[$0] }.joined(separator: "、")
            let rep = YearEngine.report(chart: ch, year: year)
            let di = YearEngine.dayunIndex(chart: ch, year: year)
            let dayunText = di.map { ch.dayunGanZhi[$0] + "运" } ?? "童限"
            VStack(alignment: .leading, spacing: 8) {
                Text("\(p.name) · 四柱 \(ch.pillars.joined(separator: " "))").font(.system(.subheadline, design: .serif)).fontWeight(.semibold).foregroundStyle(Ky.ink)
                EvidenceChainView(conclusion: "日主\(ch.rizhu) · \(xj.level) · 喜\(xiText.isEmpty ? "流通" : xiText) · 忌\(jiText.isEmpty ? "待定" : jiText)。",
                                  links: [("盘面", "四柱 \(ch.pillars.joined(separator: " "))")])
                Text("\(year)年 \(rep.gz)年 · \(dayunText) · \(rep.level)：\((rep.lines.first ?? "").scriptConverted)")
                    .font(.callout).foregroundStyle(Ky.ink)
            }
            .kyCard()
        }
    }

    @ViewBuilder private func pairCards(_ ps: [Person]) -> some View {
        let pairs = [(ps[0], ps[1]), (ps[0], ps[2]), (ps[1], ps[2])]
        let both = pairs.filter { hubuDirections(a: $0.0, b: $0.1) >= 2 }.count
        let one = pairs.filter { hubuDirections(a: $0.0, b: $0.1) == 1 }.count
        let none = pairs.filter { hubuDirections(a: $0.0, b: $0.1) == 0 }.count
        VStack(alignment: .leading, spacing: 8) {
            Text("三对互补计数".scriptConverted).font(.system(.subheadline, design: .serif)).fontWeight(.semibold).foregroundStyle(Ky.ink)
            Text("三对合盘：双向互补 \(both) 对、单向互补 \(one) 对、互补不显 \(none) 对。".scriptConverted)
                .font(.callout).foregroundStyle(Ky.ink)
        }
        .kyCard()
        ForEach(0 ..< pairs.count, id: \.self) { i in
            let a = pairs[i].0
            let b = pairs[i].1
            VStack(alignment: .leading, spacing: 8) {
                Text(a.name + " × " + b.name + " · 喜用互补".scriptConverted).font(.system(.subheadline, design: .serif)).fontWeight(.semibold).foregroundStyle(Ky.ink)
                EvidenceChainView(conclusion: hubuText(a: a, b: b), links: [("盘面", "\(a.name)最旺 \(strongestWx(of: chart(of: a)))，\(b.name)最旺 \(strongestWx(of: chart(of: b)))")])
                Text(dayPillarText(a: a, b: b).scriptConverted).font(.callout).foregroundStyle(Ky.ink)
            }
            .kyCard()
        }
    }

    @ViewBuilder private func crossCards(_ ps: [Person]) -> some View {
        let dims = ["事业", "财富", "婚恋", "健康"]
        ForEach(dims, id: \.self) { dim in
            VStack(alignment: .leading, spacing: 8) {
                Text("\(dim) · 全家交叉裁决".scriptConverted).font(.system(.subheadline, design: .serif)).fontWeight(.semibold).foregroundStyle(Ky.ink)
                ForEach(ps) { p in
                    let v = BaziZiweiCrossEngine.verdicts(bazi: chart(of: p), ziwei: ziwei(of: p)).first { $0.title == dim }
                    Text("\(p.name)：\((v?.verdict ?? "").scriptConverted)（\((v?.kind.rawValue ?? "").scriptConverted)）")
                        .font(.callout).foregroundStyle(Ky.ink)
                }
                Text("裁决句取各自 hecan 原文（同频相催／互补制化／分期应验），本页不另造新裁决。".scriptConverted)
                    .font(.caption2).foregroundStyle(Ky.sub)
            }
            .kyCard()
        }
    }

    @ViewBuilder private func posterSection(_ ps: [Person]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                let renderer = ImageRenderer(content: FamilyPosterView(people: ps))
                renderer.scale = 2.0
                if let img = renderer.uiImage, let data = img.pngData() {
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("family-poster.png")
                    try? data.write(to: url, options: .atomic)
                    posterImage = img
                    posterURL = url
                }
            } label: {
                Label("导出全家盘海报 PNG（1080 宽）".scriptConverted, systemImage: "square.and.arrow.down")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .buttonStyle(KyPrimaryButton())
            if posterURL != nil, let img = posterImage {
                ShareLink(item: Image(uiImage: img), preview: SharePreview("全家盘海报", image: Image(uiImage: img))) {
                    Label("保存 / 分享全家盘海报".scriptConverted, systemImage: "square.and.arrow.up")
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
        .kyCard()
    }
}

// MARK: - 全家盘海报内容（供 ImageRenderer 导出，1080 宽：540 点 × scale 2）

struct FamilyPosterView: View {
    let people: [Person]
    private var year: Int { Calendar.current.component(.year, from: Date()) }
    private let wxNames = ["木", "火", "土", "金", "水"]

    private func chart(of p: Person) -> BaziChart {
        BaziEngine.cachedPaipan(clock: p.birthDate, gender: p.gender,
                                longitude: p.useLongitude ? p.longitude : nil)
    }
    private func ziwei(of p: Person) -> ZiweiChart {
        ZiweiEngine.cachedChart(clock: p.birthDate, gender: p.gender,
                        longitude: p.useLongitude ? p.longitude : nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("全家盘".scriptConverted)
                .font(.system(size: 44, weight: .bold, design: .serif)).foregroundStyle(Ky.ink)
            Text("三人盘并置 · 合参裁决".scriptConverted)
                .font(.subheadline).foregroundStyle(Ky.sub)
            ForEach(people) { p in
                let ch = chart(of: p)
                let xj = InterpretEngine.posterXiJi(chart: ch)
                let rep = YearEngine.report(chart: ch, year: year)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(p.name) · \(ch.pillars.joined(separator: " "))").font(.headline).foregroundStyle(Ky.ink)
                    Text("日主\(ch.rizhu) · \(xj.level) · 喜\(xj.xi.map { wxNames[$0] }.joined(separator: "、"))").font(.callout).foregroundStyle(Ky.ink)
                    Text("\(year)年 \(rep.gz)年 · \(rep.level)：\((rep.lines.first ?? "").scriptConverted)").font(.callout).foregroundStyle(Ky.ink)
                }
                .padding(12)
                .background(Ky.card)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            ForEach(["事业", "财富", "婚恋", "健康"], id: \.self) { dim in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(dim)·全家交叉".scriptConverted).font(.headline).foregroundStyle(Ky.ink)
                    ForEach(people) { p in
                        let v = BaziZiweiCrossEngine.verdicts(bazi: chart(of: p), ziwei: ziwei(of: p)).first { $0.title == dim }
                        Text("\(p.name)：\((v?.verdict ?? "").scriptConverted)").font(.callout).foregroundStyle(Ky.ink)
                    }
                }
                .padding(12)
                .background(Ky.card)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            Text("三术合参 · 每人盘面以真太阳时校正，晚子时 sect=2".scriptConverted)
                .font(.caption2).foregroundStyle(Ky.sub)
        }
        .padding(28)
        .frame(width: 540)
        .background(Ky.bg)
    }
}

// MARK: - 合盘分享卡片（双盘速览＋总评一句＋二维码回链）

struct SynastryShareCardView: View {
    @EnvironmentObject var store: PeopleStore
    @State private var aId: UUID?
    @State private var bId: UUID?
    @State private var copied = false

    private let wxNames = ["木", "火", "土", "金", "水"]
    private let ganHe: [Character: Character] = ["甲": "己", "己": "甲", "乙": "庚", "庚": "乙", "丙": "辛",
                                                 "辛": "丙", "丁": "壬", "壬": "丁", "戊": "癸", "癸": "戊"]

    private func chart(of p: Person) -> BaziChart {
        BaziEngine.cachedPaipan(clock: p.birthDate, gender: p.gender,
                                longitude: p.useLongitude ? p.longitude : nil)
    }
    private func selected(_ id: UUID?) -> Person? { store.people.first { $0.id == id } }

    private func xiYong(of ch: BaziChart) -> (level: String, xi: [String]) {
        let dayWx: Int = { switch ch.rizhu { case "甲", "乙": return 0; case "丙", "丁": return 1
            case "戊", "己": return 2; case "庚", "辛": return 3; default: return 4 } }()
        let shengWo = (dayWx + 4) % 5
        let tong = ch.wuxingPercents[dayWx] + ch.wuxingPercents[shengWo]
        if tong >= 55 { return ("偏强", [(dayWx + 1) % 5, (dayWx + 2) % 5, (dayWx + 3) % 5].map { wxNames[$0] }) }
        if tong <= 40 { return ("偏弱", [shengWo, dayWx].map { wxNames[$0] }) }
        return ("中和", [])
    }
    private func strongestWx(of ch: BaziChart) -> String {
        let idx = ch.wuxingPercents.indices.max(by: { ch.wuxingPercents[$0] < ch.wuxingPercents[$1] }) ?? 0
        return wxNames[idx]
    }
    private func shareURL(a: Person, b: Person) -> String {
        "https://bazi.vip668.xin/#/hepan?pair=\(a.id.uuidString),\(b.id.uuidString)"
    }
    // 总评一句：只报互补计数事实，不编新断语。
    private func summaryLine(a: Person, b: Person) -> String {
        let ca = chart(of: a)
        let cb = chart(of: b)
        let xa = xiYong(of: ca)
        let xb = xiYong(of: cb)
        var n = 0
        if xa.xi.contains(strongestWx(of: cb)) { n += 1 }
        if xb.xi.contains(strongestWx(of: ca)) { n += 1 }
        let hubuWord = n >= 2 ? "双向互补" : (n == 1 ? "单向互补" : "互补不显")
        var ganHeCount = 0
        for s1 in ca.pillars { for s2 in cb.pillars { if ganHe[s1.first ?? "甲"] == s2.first { ganHeCount += 1 } } }
        var counts: [String: Int] = ["合": 0, "冲": 0, "刑": 0, "穿": 0, "破": 0]
        for b1 in ca.pillars { for b2 in cb.pillars {
            if let rel = BaziTables.relationFull(b1.last ?? "子", b2.last ?? "子"), counts[rel.0] != nil {
                counts[rel.0, default: 0] += 1
            }
        } }
        let he = counts["合"] ?? 0
        let chong = counts["冲"] ?? 0
        let xing = counts["刑"] ?? 0
        let chuan = counts["穿"] ?? 0
        let po = counts["破"] ?? 0
        return "喜用互补：\(hubuWord)（\(n) 向补益）；天干五合 \(ganHeCount) 对；地支合 \(he)、冲 \(chong)、刑 \(xing)、穿 \(chuan)、破 \(po)。以上只报计数事实，不另作总评断语。"
    }
    private func qrImage(for string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                Text("双盘速览＋总评一句＋二维码回链。总评一句只报互补计数事实，不编新断语。".scriptConverted)
                    .font(.caption).foregroundStyle(Ky.sub)
                VStack(alignment: .leading, spacing: 10) {
                    personPicker("甲方".scriptConverted, selection: $aId)
                    personPicker("乙方".scriptConverted, selection: $bId)
                }
                .kyCard()
                if let a = selected(aId), let b = selected(bId), a.id != b.id {
                    let ca = chart(of: a)
                    let cb = chart(of: b)
                    let url = shareURL(a: a, b: b)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(a.name) · \(ca.pillars.joined(separator: " "))").font(.headline).foregroundStyle(Ky.ink)
                        Text("日主\(ca.rizhu) · \(xiYong(of: ca).level) · 喜\(xiYong(of: ca).xi.joined(separator: "、")) · 最旺\(strongestWx(of: ca))").font(.callout).foregroundStyle(Ky.ink)
                        Text("\(b.name) · \(cb.pillars.joined(separator: " "))").font(.headline).foregroundStyle(Ky.ink)
                        Text("日主\(cb.rizhu) · \(xiYong(of: cb).level) · 喜\(xiYong(of: cb).xi.joined(separator: "、")) · 最旺\(strongestWx(of: cb))").font(.callout).foregroundStyle(Ky.ink)
                        Text("总评一句（只报计数事实）：".scriptConverted + summaryLine(a: a, b: b).scriptConverted).font(.callout).foregroundStyle(Ky.ink)
                    }
                    .kyCard()
                    VStack(alignment: .leading, spacing: 10) {
                        Text("分享链接".scriptConverted).font(.system(.subheadline, design: .serif)).fontWeight(.semibold).foregroundStyle(Ky.ink)
                        Text(url).font(.caption).foregroundStyle(Ky.sub).textSelection(.enabled)
                        Button(copied ? "已复制" : "复制分享链接") {
                            UIPasteboard.general.string = url
                            copied = true
                        }
                        .buttonStyle(KyPrimaryButton())
                        if let img = qrImage(for: url) {
                            Image(uiImage: img)
                                .resizable()
                                .interpolation(.none)
                                .frame(width: 220, height: 220)
                                .background(Color.white)
                        }
                        Text("注意：App 本地人物 id（UUID）与 Web 档案 id 不是同一套，此二维码在 Web 端打开时会提示人物不在档案库；可直接扫码打开的正式分享链接请在 Web 端合盘页生成。".scriptConverted)
                            .font(.caption2).foregroundStyle(Ky.sub)
                    }
                    .kyCard()
                } else {
                    KyEmptyState(icon: "person.2.fill", title: "从人物档案里选两个人", message: "档案里不足两人时，先去「人物档案」建档。")
                }
            }.padding(16).padding(.bottom, 100)
        }
        .background(Ky.bg)
        .navigationTitle("合盘分享卡".scriptConverted)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func personPicker(_ label: String, selection: Binding<UUID?>) -> some View {
        Picker(label, selection: selection) {
            Text("未选".scriptConverted).tag(UUID?.none)
            ForEach(store.people) { p in Text(p.name).tag(UUID?.some(p.id)) }
        }.pickerStyle(.menu).tint(Ky.ink)
    }
}
