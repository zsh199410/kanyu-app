// 合盘（2026-10-30）：按《合婚四看》流程的 App 化第一版——双盘各自先立，
// 再看喜用互补、日柱（干合/支合冲）、配偶星落点；生肖只作民间末位参。结论全带依据链。
import SwiftUI

struct SynastryView: View {
    @StateObject private var store = PeopleStore()
    @State private var aId: UUID?
    @State private var bId: UUID?

    private func chart(of p: Person) -> BaziChart {
        BaziEngine.paipan(clock: p.birthDate, gender: p.gender,
                          longitude: p.useLongitude ? p.longitude : nil)
    }
    // 喜用初判（与解盘同口径：同党占比定强弱，调候另注）
    private func xiYong(of ch: BaziChart) -> (level: String, xi: [String]) {
        let names = ["木", "火", "土", "金", "水"]
        let dayWx: Int = { switch ch.rizhu { case "甲", "乙": return 0; case "丙", "丁": return 1
            case "戊", "己": return 2; case "庚", "辛": return 3; default: return 4 } }()
        let shengWo = (dayWx + 4) % 5
        let tong = ch.wuxingPercents[dayWx] + ch.wuxingPercents[shengWo]
        if tong >= 55 { return ("偏强", [(dayWx + 1) % 5, (dayWx + 2) % 5, (dayWx + 3) % 5].map { names[$0] }) }
        if tong <= 40 { return ("偏弱", [shengWo, dayWx].map { names[$0] }) }
        return ("中和", [])
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                pickerCard
                if let a = selected(aId), let b = selected(bId), a.id != b.id {
                    resultCards(a: a, b: b)
                } else {
                    Text("从人物档案里选两个人。档案里不足两人时，先去「人物档案」建档。")
                        .font(.callout).foregroundStyle(Ky.sub)
                }
                Text("流程按合婚四看：双盘先各自立 → 喜用互补 → 日柱 → 配偶星；生肖合冲只作民间末位参，不入主断。")
                    .font(.caption2).foregroundStyle(Ky.sub)
            }.padding(16)
        }
        .background(Ky.bg)
        .navigationTitle("合盘")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func selected(_ id: UUID?) -> Person? { store.people.first { $0.id == id } }

    private var pickerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            personPicker("甲方", selection: $aId)
            personPicker("乙方", selection: $bId)
        }
        .padding(14).background(Ky.card).clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func personPicker(_ label: String, selection: Binding<UUID?>) -> some View {
        Picker(label, selection: selection) {
            Text("未选").tag(UUID?.none)
            ForEach(store.people) { p in Text(p.name).tag(UUID?.some(p.id)) }
        }.pickerStyle(.menu).tint(Ky.ink)
    }

    @ViewBuilder private func resultCards(a: Person, b: Person) -> some View {
        let ca = chart(of: a); let cb = chart(of: b)
        let xa = xiYong(of: ca); let xb = xiYong(of: cb)
        let names = ["木", "火", "土", "金", "水"]
        let strongA = names[ca.wuxingPercents.indices.max(by: { ca.wuxingPercents[$0] < ca.wuxingPercents[$1] })!]
        let strongB = names[cb.wuxingPercents.indices.max(by: { cb.wuxingPercents[$0] < cb.wuxingPercents[$1] })!]
        card("喜用互补",
             conclusion: "\(a.name)\(xa.level)，喜 \(xa.xi.isEmpty ? "流通（中和局不预设）" : xa.xi.joined(separator: "、"))；\(b.name)\(xb.level)，喜 \(xb.xi.isEmpty ? "流通" : xb.xi.joined(separator: "、"))。\(互补判语(a: a, b: b, xa: xa, xb: xb, strongA: strongA, strongB: strongB))",
             facts: "\(a.name)最旺 \(strongA)，\(b.name)最旺 \(strongB)")
        card("日柱关系",
             conclusion: 日柱判语(ca: ca, cb: cb),
             facts: "\(a.name)日柱 \(ca.dayPillar)，\(b.name)日柱 \(cb.dayPillar)")
        card("配偶星落点",
             conclusion: 配偶星判语(a: a, ca: ca, b: b, cb: cb),
             facts: "男以财为妻星、女以官杀为夫星（通说）")
    }

    private func 互补判语(a: Person, b: Person, xa: (level: String, xi: [String]),
                          xb: (level: String, xi: [String]), strongA: String, strongB: String) -> String {
        var parts: [String] = []
        if xa.xi.contains(strongB) { parts.append("\(b.name)的旺气（\(strongB)）正落在\(a.name)所喜之内，补益在\(a.name)这边") }
        if xb.xi.contains(strongA) { parts.append("\(a.name)的旺气（\(strongA)）正落在\(b.name)所喜之内，补益在\(b.name)这边") }
        if parts.isEmpty { return "两盘旺气未直接落入对方喜用，互补不显——要回到日柱与全局互动细看，不硬凑互补。" }
        return parts.joined(separator: "；") + "。"
    }

    private func 日柱判语(ca: BaziChart, cb: BaziChart) -> String {
        let ganHe: [Character: Character] = ["甲": "己", "己": "甲", "乙": "庚", "庚": "乙", "丙": "辛",
                                             "辛": "丙", "丁": "壬", "壬": "丁", "戊": "癸", "癸": "戊"]
        var parts: [String] = []
        if ganHe[ca.dayPillar.first!] == cb.dayPillar.first! {
            parts.append("日干五合：两人天干相合，天然亲近、易有黏性")
        }
        if let rel = BaziTables.relationFull(ca.dayPillar.last!, cb.dayPillar.last!) {
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

    private func 配偶星判语(a: Person, ca: BaziChart, b: Person, cb: BaziChart) -> String {
        func spouseStars(of ch: BaziChart, gender: String) -> [String] {
            let targets = gender == "M" ? ["正财", "偏财"] : ["正官", "七杀"]
            var found: [String] = []
            for ss in ch.stemShiShen where targets.contains(ss) { found.append(ss) }
            for row in ch.hideShiShen { for ss in row where targets.contains(ss) { found.append(ss) } }
            return found
        }
        let sa = spouseStars(of: ca, gender: a.gender)
        let sb = spouseStars(of: cb, gender: b.gender)
        return "\(a.name)盘中配偶星\(sa.isEmpty ? "不现（藏亦无）——配偶缘须靠岁运引动，晚定或淡定型参" : "见 \(Set(sa).joined(separator: "、"))（透藏合计 \(sa.count) 处）")；\(b.name)盘中配偶星\(sb.isEmpty ? "不现（藏亦无），同上参" : "见 \(Set(sb).joined(separator: "、"))（透藏合计 \(sb.count) 处）")。星现不等于缘至，还要看星落宫位与岁运引动，此处只报落点。"
    }

    private func card(_ title: String, conclusion: String, facts: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(.subheadline, design: .serif)).fontWeight(.semibold).foregroundStyle(Ky.ink)
            EvidenceChainView(conclusion: conclusion, links: [("盘面", facts)])
        }
        .padding(14).background(Ky.card).clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
