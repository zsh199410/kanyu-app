import SwiftUI

/// An editorial reader of existing engine output. It does not reinterpret, score,
/// truncate or replace the professional evidence and verification workbench.
struct V5InterpretBookView: View {
    let person: Person
    let chart: BaziChart
    @State private var chapters: [InterpretItem] = []
    @State private var readingChapter: Int?
    @StateObject private var speaker = Speaker()
    @State private var voiceOptions = false
    @EnvironmentObject private var people: PeopleStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var p: V5Palette { V5Palette.current }
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    opening
                    if chapters.isEmpty { ProgressView("正在整理命书章节").frame(minHeight: 100) }
                    ForEach(Array(chapters.enumerated()), id: \.offset) { index, item in
                        chapter(item, index: index).id(index)
                    }
                    V5Card {
                        VStack(alignment: .leading, spacing: 16) {
                            V5SectionHeading(title: "原盘与完整命书", subtitle: "回到真实命盘核对，再保存完整内容。")
                            NavigationLink {
                                InterpretView(chart: chart, name: person.name, verificationOwnerID: "person:\(person.id.uuidString)")
                            } label: { V5LibraryRow(title: "专业依据与反馈", detail: "分类检索、术语、反向定位及原有校验功能", icon: "text.magnifyingglass") }
                            NavigationLink { PersonDetailView(person: person, store: people) } label: {
                                V5LibraryRow(title: "生成与导出完整命书", detail: "沿用本人的报告、PDF及归档流程", icon: "doc.richtext")
                            }
                        }
                    }
                    Text("传统民俗参考。内容是既有规则的结构化解读，不构成疾病诊断、投资建议或保证性预测。")
                        .font(.footnote).foregroundStyle(V5Palette.color(p.secondary))
                }.padding(.horizontal, V5Metric.page).padding(.vertical, 18)
            }
            .background { V5SceneBackground() }
            .foregroundStyle(V5Palette.color(p.ink))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(Array(chapters.enumerated()), id: \.offset) { index, item in
                            Button("\(index+1) · \(item.title)") {
                                if reduceMotion { proxy.scrollTo(index, anchor: .top) }
                                else { withAnimation(V5Motion.press) { proxy.scrollTo(index, anchor: .top) } }
                            }
                        }
                    } label: { Image(systemName: "list.bullet").frame(width: 48, height: 48) }
                    .accessibilityLabel("命书章节目录")
                }
            }
        }
        .navigationTitle(person.name + " · 命书初读").navigationBarTitleDisplayMode(.inline)
        .task(id: person) {
            speaker.stop();readingChapter = nil;chapters = []
            await Task.yield()
            guard !Task.isCancelled else { return }
            let actual = InterpretEngine.interpret(chart: chart)
            guard !Task.isCancelled else { return }
            chapters = actual
        }
        .sheet(isPresented: $voiceOptions) {
            NavigationStack {
                ScrollView { InterpretNarrationControls(speaker: speaker).padding(24) }
                    .background { V5SceneBackground() }.navigationTitle("本机朗读")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { voiceOptions = false } } }
            }
        }
        .onDisappear { speaker.stop() }
    }
    private var opening: some View {
        VStack(alignment: .leading, spacing: 20) {
            V5ArtHeader(eyebrow: "三术合参 · 个人命书", title: person.name + "的命书", subtitle: "先读结论，再看依据；以自己的真实命盘为线索。")
            HStack(alignment: .top, spacing: 20) {
                if !typeSize.isAccessibilitySize { V5BookCover(personName: person.name).frame(width: 90) }
                VStack(alignment: .leading, spacing: 12) {
                    Text(chart.lunarText).font(.system(.headline, design: .serif))
                    Text(DisplayTimeReceipt.beijing(person.birthDate)).font(.subheadline)
                    Text(chart.pillars.joined(separator: "　")).font(.system(.subheadline, design: .serif))
                    Text("档案 " + String(person.id.uuidString.prefix(8))).font(.caption.monospaced())
                        .accessibilityIdentifier("v5.reader.owner").accessibilityValue(person.id.uuidString)
                    Button { voiceOptions = true } label: { Label("朗读设置", systemImage: "waveform").frame(minHeight: 48) }
                }
            }
            Rectangle().fill(V5Palette.color(p.ornament).opacity(0.5)).frame(height: 1)
        }
    }
    private func chapter(_ item: InterpretItem, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(String(format: "%02d", index+1)).font(.system(.title, design: .serif)).monospacedDigit()
                    .foregroundStyle(V5Palette.color(p.ornamentText))
                Text(item.title).font(V5Typography.section).fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
            }
            Text(item.conclusion).font(.system(.body, design: .serif)).lineSpacing(7)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            if let time = item.timeRange, !time.isEmpty { marginNote("时间范围", text: time) }
            if let advice = item.advice, !advice.isEmpty { marginNote("生活参考", text: advice) }
            if item.title.contains("健康") {
                Text("这一章仅介绍传统类象，不能用于判断或治疗疾病；身体不适请咨询正规医疗机构。")
                    .font(.footnote).foregroundStyle(V5Palette.color(p.secondary))
            }
            HStack {
                Button {
                    if readingChapter == index && speaker.speaking { speaker.stop();readingChapter = nil }
                    else { speaker.stop();readingChapter = index;speaker.read(item.title + "。" + item.conclusion) }
                } label: {
                    Label(readingChapter == index && speaker.speaking ? "停止朗读" : "朗读本章", systemImage: readingChapter == index && speaker.speaking ? "stop.circle" : "speaker.wave.2")
                        .font(.subheadline).frame(minHeight: V5Metric.target)
                }
                Spacer(minLength: 0)
                if let confidence = item.confidence { Text(confidence).font(.caption).foregroundStyle(V5Palette.color(p.secondary)) }
            }
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 16) {
                    if let mechanism = item.mechanism, !mechanism.isEmpty { marginNote("推导机制", text: mechanism) }
                    ForEach(Array(item.links.enumerated()), id: \.offset) { _, link in
                        marginNote(link.label, text: link.text)
                    }
                }.padding(.top, 12)
            } label: { Text("规则与来源").font(.subheadline).frame(minHeight: V5Metric.target) }
            Rectangle().fill(V5Palette.color(p.ornament).opacity(0.25)).frame(height: 0.6).padding(.top, 8)
        }.padding(.vertical, 8)
    }
    private func marginNote(_ label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.caption.weight(.medium)).foregroundStyle(V5Palette.color(p.ornamentText))
            Text(text).font(.subheadline).lineSpacing(5).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
    }
}
