import SwiftUI

struct V5PersonHero: View {
    let chart: BaziChart?
    @State private var creating = false
    @EnvironmentObject private var people: PeopleStore
    @EnvironmentObject private var router: V5Router
    @Environment(\.dynamicTypeSize) private var typeSize
    private var theme: V5Theme { V5ThemeStore.shared.theme }
    var body: some View {
        let p = theme.palette
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Text("当前命主").font(.caption.weight(.medium)).tracking(2)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .overlay(Capsule().stroke(V5Palette.color(p.ornament), lineWidth: 0.6))
                    Spacer(minLength: 8)
                    Button { creating = true } label: { Image(systemName: "person.badge.plus").frame(width: 48, height: 48) }
                        .accessibilityLabel("快速新建档案")
                }
                if let person = people.currentPerson {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(person.name).font(.system(.largeTitle, design: .serif).weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        V5PersonPickerButton { Image(systemName: "chevron.right").font(.caption).frame(width: 48, height: 48) }
                    }
                    if let chart, !typeSize.isAccessibilitySize {
                        Text(chart.pillars.joined(separator: "　")).font(.system(.subheadline, design: .serif))
                            .fixedSize(horizontal: false, vertical: true)
                    } else { Text(DisplayTimeReceipt.beijing(person.birthDate)).font(.subheadline) }
                    Text("\(person.relation.isEmpty ? "已建档" : person.relation) · \(person.gender == "M" ? "男" : "女")")
                        .font(.subheadline).foregroundStyle(V5Palette.color(p.heroSecondary))
                } else {
                    Text("一人一命书").font(.system(.title, design: .serif))
                    Text("建立真实档案，贯通命盘与解读。").font(.subheadline)
                    Button("添加第一位家人或命主档案") { creating = true }.frame(minHeight: V5Metric.target)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if !typeSize.isAccessibilitySize, let object = V5ArtworkRegistry.image(.personObject) {
                Image(uiImage: object).resizable().scaledToFit().frame(width: 128, height: 160).accessibilityHidden(true)
            }
        }
        .padding(20).frame(maxWidth: .infinity, minHeight: 155, alignment: .leading)
        .foregroundStyle(V5Palette.color(p.heroInk))
        .background {
            V5PanelSilhouette(theme: theme).fill(V5Palette.color(p.heroSurface))
                .overlay {
                    if let texture = V5ArtworkRegistry.image(.texture) {
                        Image(uiImage: texture).resizable(resizingMode: .tile).opacity(0.12).clipShape(V5PanelSilhouette(theme: theme))
                    }
                }
                .overlay(V5PanelSilhouette(theme: theme).stroke(V5Palette.color(p.ornament), lineWidth: 0.8))
                .shadow(color: V5Palette.color(p.ink).opacity(0.13), radius: 12, x: 0, y: 8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workspace.workbench")
        .accessibilityValue(people.currentPerson?.name ?? "未建档")
        .sheet(isPresented: $creating) {
            PersonFormView(store: people, person: Person(name: "", birthEpoch: Date().timeIntervalSince1970))
        }

    }
}
private struct V5FeaturePlaque: Shape {
    let arched: Bool
    func path(in rect: CGRect) -> Path {
        guard arched else { return RoundedRectangle(cornerRadius: 15).path(in: rect) }
        var p = Path(); let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: w*0.16, y: 10))
        p.addQuadCurve(to: CGPoint(x: w*0.5, y: 0), control: CGPoint(x: w*0.27, y: -2))
        p.addQuadCurve(to: CGPoint(x: w*0.84, y: 10), control: CGPoint(x: w*0.73, y: -2))
        p.addQuadCurve(to: CGPoint(x: w, y: 23), control: CGPoint(x: w, y: 10))
        p.addLine(to: CGPoint(x: w, y: h-21)); p.addQuadCurve(to: CGPoint(x: w*0.8, y: h-8), control: CGPoint(x: w, y: h-8))
        p.addQuadCurve(to: CGPoint(x: w*0.5, y: h), control: CGPoint(x: w*0.65, y: h+1))
        p.addQuadCurve(to: CGPoint(x: w*0.2, y: h-8), control: CGPoint(x: w*0.35, y: h+1))
        p.addQuadCurve(to: CGPoint(x: 0, y: h-21), control: CGPoint(x: 0, y: h-8))
        p.addLine(to: CGPoint(x: 0, y: 23));p.addQuadCurve(to: CGPoint(x: w*0.16, y: 10), control: CGPoint(x: 0, y: 10));p.closeSubpath();return p
    }
}
struct V5PrimaryFeatureDeck: View {
    @EnvironmentObject private var router: V5Router
    @Environment(\.dynamicTypeSize) private var typeSize
    private var theme: V5Theme { V5ThemeStore.shared.theme }
    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 6), count: typeSize.isAccessibilitySize ? 1 : (typeSize > .large ? 3 : 5)) }
    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            entry("八字", "命局精解", .bazi, .bazi)
            entry("紫微", "命盘星曜", .ziwei, .ziwei)
            entry("手相", "掌纹特征", .palm, .palm)
            entry("面相", "五官气色", .face, .face)
            entry("风水", "环境布局", .survey, .survey)
        }.padding(.vertical, 6)
    }
    private func entry(_ title: String, _ subtitle: String, _ glyph: V5FeatureKind, _ route: V5Route) -> some View {
        Button { router.open(route) } label: {
            VStack(spacing: 9) {
                V5FeatureGlyph(kind: glyph, size: typeSize.isAccessibilitySize ? 40 : 35)
                Text(title).font(.system(.title3, design: .serif).weight(.medium))
                Text(subtitle).font(.caption2).fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(V5Palette.color(theme.palette.secondary))
            }.padding(.horizontal, 4).padding(.vertical, 18)
                .frame(maxWidth: .infinity, minHeight: 128)
                .foregroundStyle(V5Palette.color(theme.palette.ink))
                .background(V5FeaturePlaque(arched: theme == .song || theme == .night).fill(V5Palette.color(theme.palette.surface)))
                .overlay(V5FeaturePlaque(arched: theme == .song || theme == .night).stroke(V5Palette.color(theme.palette.ornament).opacity(0.7), lineWidth: 0.7))
        }.buttonStyle(.plain).accessibilityLabel((glyph == .palm ? "手相面相" : title) + "，" + subtitle).accessibilityIdentifier("v5.home.entry." + glyph.rawValue)
    }
}
struct V5HomeBookEntry: View {
    @EnvironmentObject private var people: PeopleStore
    @EnvironmentObject private var router: V5Router
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var latest: ReportHistoryEntry?
    private var theme: V5Theme { V5ThemeStore.shared.theme }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("个人命书").font(V5Typography.section)
                Spacer()
                Button("全部命书") { router.tab = 2 }.font(.subheadline).frame(minHeight: V5Metric.target)
            }
            if let person = people.currentPerson {
                NavigationLink { PersonDetailView(person: person, store: people) } label: {
                    V5Card { content(person) }
                }.buttonStyle(.plain).accessibilityLabel("\(person.name)的个人命书")
            } else {
                Button { router.tab = 3 } label: {
                    V5Card { HStack { V5BookCover(personName: nil, compact: true).frame(width: 72); Text("为家人留下一本命书").font(V5Typography.section) } }
                }.buttonStyle(.plain)
            }
        }
        .task(id: people.currentPerson?.id) {
            let selected = people.currentPerson?.id
            latest = nil
            guard let selected else { return }
            let result = await Task.detached(priority: .utility) {
                ReportHistory.scan().map(V5ReportOwnership.verified).first { $0.personID == selected && $0.url.pathExtension.lowercased() == "pdf" }
            }.value
            guard !Task.isCancelled, people.currentPerson?.id == selected else { return }
            latest = result
        }
    }
    @ViewBuilder private func content(_ person: Person) -> some View {
        if typeSize.isAccessibilitySize || theme == .collection {
            VStack(alignment: .leading, spacing: 18) { V5BookCover(personName: person.name).frame(width: 122); details(person) }
        } else {
            HStack(spacing: 20) { V5BookCover(personName: person.name).frame(width: 98); details(person) }
        }
    }
    private func details(_ person: Person) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("三术合参 · 综合解读").font(.caption).foregroundStyle(V5Palette.color(theme.palette.ornamentText))
            Text(person.name + "的命书").font(.system(.title2, design: .serif).weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            Text("八字 · 紫微 · 手相 · 面相").font(.subheadline)
            if let latest { Text(latest.generatedAt, format: .dateTime.year().month().day()).font(.caption) }
            else { Text("按当前档案生成与阅读").font(.caption) }
            Image(systemName: "arrow.up.right").frame(minWidth: 48, minHeight: 48, alignment: .leading).accessibilityHidden(true)
        }.foregroundStyle(V5Palette.color(theme.palette.ink))
    }
}
