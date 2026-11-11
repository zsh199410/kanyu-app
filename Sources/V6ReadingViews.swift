import SwiftUI

/// Reading categories only: every paragraph still comes from the existing interpretation engine.
enum V6ReadingTopic: String, CaseIterable, Identifiable {
    case overview = "综合", career = "事业", wealth = "财富", relationships = "关系", wellbeing = "身心"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: return "circle.grid.2x2"
        case .career: return "briefcase"
        case .wealth: return "chart.bar"
        case .relationships: return "person.2"
        case .wellbeing: return "leaf"
        }
    }
    var titles: Set<String> {
        switch self {
        case .overview: return ["命局风景", "月令格局（候选）", "喜忌（扶抑初判）", "十神看点", "岁运要点"]
        case .career: return ["事业方向", "工作形态", "学业与文凭", "学业文书", "名声声誉", "行业赛道深断"]
        case .wealth: return ["财运形态", "财富量级蓄水池", "置业田宅"]
        case .relationships: return ["婚姻感情", "子女", "子女缘分", "父母缘分", "兄弟同辈", "兄弟姐妹", "贵人与人际", "六亲情境深读"]
        case .wellbeing: return ["健康倾向", "中老年守年", "晚年光景"]
        }
    }
}

struct V6ReadingTopicLinks: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("主题解读").font(KanyuV6.Typography.cardTitle).foregroundStyle(Ky.ink)
            Text("基于当前命主本命盘，按主题阅读已有解读。")
                .font(.footnote).foregroundStyle(Ky.sub)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(V6ReadingTopic.allCases) { topic in
                        NavigationLink { V6ReadingTopicView(topic: topic) } label: {
                            VStack(spacing: 8) {
                                Image(systemName: topic.symbol).font(.title3)
                                Text(topic.rawValue).font(.subheadline.weight(.semibold))
                            }
                            .foregroundStyle(Ky.qingdai)
                            .padding(12).frame(minWidth: 64, minHeight: 72)
                            .background(Ky.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Ky.line, lineWidth: 0.7).allowsHitTesting(false))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(topic.rawValue + "主题解读")
                    }
                }
            }
        }
    }
}

struct V6ReadingTopicView: View {
    let topic: V6ReadingTopic
    @EnvironmentObject private var peopleStore: PeopleStore
    var body: some View {
        Group {
            if let person = peopleStore.currentPerson {
                let chart = BaziEngine.cachedPaipan(clock: person.birthDate, gender: person.gender,
                    longitude: person.useLongitude ? person.longitude : nil)
                let items = InterpretEngine.interpret(chart: chart, verificationOwnerID: "person:\(person.id.uuidString)").filter { topic.titles.contains($0.title) }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: KanyuV6.Metric.cardGap) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(person.name).font(KanyuV6.Typography.pageTitle)
                            Text("先读结论，再展开本盘依据；时间范围和适用条件以条目原文为准。")
                                .font(.subheadline).foregroundStyle(Ky.sub)
                        }
                        if items.isEmpty {
                            Text("当前盘暂无这一主题的条目，可进入完整解读查看其他内容。")
                                .font(.body).foregroundStyle(Ky.sub).kyCard()
                        }
                        ForEach(items.indices, id: \.self) { index in
                            let item = items[index]
                            VStack(alignment: .leading, spacing: 12) {
                                Text(item.title).font(KanyuV6.Typography.cardTitle)
                                Text(item.conclusion).font(.body).lineSpacing(5).textSelection(.enabled)
                                if let time = item.timeRange, !time.isEmpty {
                                    Label(time, systemImage: "calendar").font(.footnote).foregroundStyle(Ky.sub)
                                }
                                if let advice = item.advice, !advice.isEmpty {
                                    Text(advice).font(.body).lineSpacing(5).textSelection(.enabled)
                                }
                                DisclosureGroup("依据与原文") {
                                    VStack(alignment: .leading, spacing: 12) {
                                        ForEach(item.links.indices, id: \.self) { linkIndex in
                                            let link = item.links[linkIndex]
                                            Text(link.label).font(.subheadline.weight(.semibold))
                                            Text(link.text).font(.body).lineSpacing(5).textSelection(.enabled)
                                        }
                                        if item.links.isEmpty { Text("当前条目未收录对应原文。") }
                                    }.padding(.top, 12)
                                }.tint(Ky.qingdai)
                            }.kyCard()
                        }
                        NavigationLink("查看完整解读") {
                            InterpretView(chart: chart, name: person.name, verificationOwnerID: "person:\(person.id.uuidString)")
                        }.buttonStyle(KyPrimaryButton())
                    }
                    .padding(KanyuV6.Metric.pageInset)
                    .padding(.bottom, 32)
                }
            } else {
                ContentUnavailableView {
                    Label("请先选择人物", systemImage: "person.crop.circle")
                } description: {
                    Text("建档或选择真实人物资料后，查看对应主题的解读。")
                } actions: {
                    NavigationLink("人物档案") { PeopleView() }.buttonStyle(KyPrimaryButton())
                }
            }
        }
        .background(Ky.bg)
        .foregroundStyle(Ky.ink)
        .navigationTitle(topic.rawValue + "解读")
        .navigationBarTitleDisplayMode(.inline)
    }
}
