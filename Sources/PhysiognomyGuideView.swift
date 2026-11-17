import SwiftUI

/// An illustrated cultural glossary; never reads a user's photograph or measurement.
struct PhysiognomyGuideView: View {
    let kind: PhysiognomyGuideKind
    @State private var group = ""
    @State private var selectedID: String?

    private var entries: [PhysiognomyGuideEntry] { PhysiognomyGuideContent.entries(for: kind) }
    private var groups: [String] {
        entries.reduce(into: []) { result, entry in
            if !result.contains(entry.group) { result.append(entry.group) }
        }
    }
    private var visible: [PhysiognomyGuideEntry] {
        entries.filter { $0.group == (group.isEmpty ? (groups.first ?? "") : group) }
    }
    private var selected: PhysiognomyGuideEntry? {
        visible.first { $0.id == selectedID } ?? visible.first
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    introduction
                    Picker("图解章节".scriptConverted, selection: $group) {
                        ForEach(groups, id: \.self) { name in Text(name.scriptConverted).tag(name) }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("physiognomy.guide.group")
                    PhysiognomyIllustration(
                        kind: kind.rawValue,
                        selectedID: selected?.id,
                        markers: visible.map {
                            PhysiognomyMarker(id: $0.id, label: $0.title,
                                               x: CGFloat($0.point.x), y: CGFloat($0.point.y))
                        },
                        onSelect: { selectedID = $0 }
                    )
                    Text("点图上编号查看说明，也可从下方列表选择。示意位置用于认识名称，不是你的测量结果。".scriptConverted)
                        .font(.footnote).foregroundStyle(Ky.sub)
                    if let entry = selected {
                        explanation(entry).id("guide.explanation")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("本章图例".scriptConverted).font(.headline)
                        ForEach(Array(visible.enumerated()), id: \.element.id) { index, entry in
                            Button {
                                selectedID = entry.id
                                proxy.scrollTo("guide.explanation", anchor: .top)
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Text(String(index + 1)).monospacedDigit()
                                        .frame(minWidth: 24)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.title.scriptConverted).fontWeight(.semibold)
                                        Text(entry.region.scriptConverted).font(.subheadline)
                                    }
                                    Spacer(minLength: 0)
                                    if selected?.id == entry.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .accessibilityLabel("已选中".scriptConverted)
                                    }
                                }
                                .foregroundStyle(selected?.id == entry.id ? Ky.qingdai : Ky.ink)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .padding(12).background(Ky.card)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("physiognomy.legend.\(entry.id)")
                        }
                    }
                    Text("资料说明：本页整理传统相学的名称与位置，不是已核验古籍引文。不同相书的叫法与分区可能不同，图中不标注所谓必然应验的年龄。".scriptConverted)
                        .font(.footnote).foregroundStyle(Ky.sub)
                }
                .padding(KanyuV6.Metric.pageInset)
                .padding(.bottom, 24)
            }
            .background(Ky.bg)
            .navigationTitle((kind == .hand ? "道家手相图解" : "面相十二宫图解").scriptConverted)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { if group.isEmpty { group = groups.first ?? "" } }
            .onChange(of: group) { _, _ in selectedID = nil }
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("观图识名 · 循序读懂".scriptConverted)
                .font(.system(.title2, design: .serif).weight(.semibold))
                .foregroundStyle(Ky.ink)
            Text((kind == .hand
                ? "先认识手掌上的线与部位，再进入照片测量。名称里的“生命”“财运”是传统用语，不等于实际寿命或收入。"
                : "从正面示意图认识十二宫与三停。“宫”是传统分区名称，不是人体器官；位置与比例不能证明一个人的性格、健康或命运。"
            ).scriptConverted)
                .font(.body).foregroundStyle(Ky.sub).fixedSize(horizontal: false, vertical: true)
        }.kyCard()
    }

    private func explanation(_ entry: PhysiognomyGuideEntry) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(entry.title.scriptConverted)
                .font(.system(.title2, design: .serif).weight(.semibold))
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("physiognomy.explanation.title")
            paragraph("在哪个位置", entry.region)
            paragraph("用白话说", entry.plainMeaning)
            VStack(alignment: .leading, spacing: 8) {
                Text("跟着图看".scriptConverted).font(.headline)
                ForEach(Array(entry.observationSteps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1). ").monospacedDigit()
                        Text(step.scriptConverted).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            paragraph("容易误解", entry.commonMisread)
        }
        .foregroundStyle(Ky.ink).frame(maxWidth: .infinity, alignment: .leading).kyCard()
        // Keep the title's accessibilityIdentifier visible to UI tests and VoiceOver.
        // A parent identifier propagates to all child StaticText nodes in SwiftUI.
    }

    private func paragraph(_ heading: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(heading.scriptConverted).font(.headline)
            Text(text.scriptConverted).font(.body).fixedSize(horizontal: false, vertical: true)
        }
    }
}
