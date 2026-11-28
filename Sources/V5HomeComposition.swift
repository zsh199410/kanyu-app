import SwiftUI

struct V5PersonHero: View {
    let chart: BaziChart?
    @State private var creating = false
    @EnvironmentObject private var people: PeopleStore
    @Environment(\.dynamicTypeSize) private var typeSize
    private var theme: V5Theme { V5ThemeStore.shared.theme }
    var body: some View {
        let p = theme.palette
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("当前命主").font(.caption.weight(.medium)).tracking(1)
                    if let person = people.currentPerson, !person.relation.isEmpty {
                        Text(person.relation).font(.caption2.weight(.medium)).padding(.horizontal, 8).padding(.vertical, 3)
                            .overlay(Capsule().stroke(V5Palette.color(p.ornament).opacity(0.6), lineWidth: 0.6))
                    }
                }.foregroundStyle(V5Palette.color(p.heroSecondary))
                if let person = people.currentPerson {
                    HStack(alignment: .center, spacing: 4) {
                        Text(person.name).font(V5Typography.song(.title2, emphasis: true))
                            .fixedSize(horizontal: false, vertical: true)
                        V5PersonPickerButton { Image(systemName: "chevron.down").font(.caption).frame(width: 48, height: 48) }
                    }
                    Text(V5DisplayText.dateTime(person.birthDate)).font(.subheadline.monospacedDigit())
                        .fixedSize(horizontal: false, vertical: true)
                    Text("北京时间 · \(person.gender == "M" ? "男" : "女")").font(.caption)
                        .foregroundStyle(V5Palette.color(p.heroSecondary))
                } else {
                    Text("添加第一位家人或命主档案").font(.headline)
                    Text("记录生辰，建立个人命书。").font(.subheadline)
                    Button("建立档案") { creating = true }.font(.body.weight(.medium)).frame(minHeight: V5Metric.target)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if !typeSize.isAccessibilitySize {
                V5ArtworkLayer(role: .personObject, theme: theme) { object in
                Image(uiImage: object).resizable().scaledToFit().frame(width: 112, height: 126).accessibilityHidden(true)
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(V5Palette.color(p.heroInk))
        .background {
            V5PanelSilhouette(theme: theme).fill(V5Palette.color(p.heroSurface))
                .overlay {
                    V5ArtworkLayer(role: .texture, theme: theme) { texture in
                        Image(uiImage: texture).resizable(resizingMode: .tile).opacity(0.10).clipShape(V5PanelSilhouette(theme: theme))
                    }
                }
                .overlay(V5PanelSilhouette(theme: theme).stroke(V5Palette.color(p.ornament).opacity(0.65), lineWidth: 0.7))
                .shadow(color: V5Palette.color(p.ink).opacity(0.08), radius: 8, x: 0, y: 4)
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
            VStack(spacing: 7) {
                V5FeatureGlyph(kind: glyph, size: 44)
                Text(title).font(.subheadline.weight(.semibold))
                if typeSize.isAccessibilitySize {
                    Text(subtitle).font(.footnote).fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(V5Palette.color(theme.palette.secondary))
                }
            }.padding(.horizontal, 4).padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 96)
                .foregroundStyle(V5Palette.color(theme.palette.ink))
                .background(V5FeaturePlaque(arched: theme == .song || theme == .night).fill(V5Palette.color(theme.palette.surface)))
                .overlay(V5FeaturePlaque(arched: theme == .song || theme == .night).stroke(V5Palette.color(theme.palette.ornament).opacity(0.7), lineWidth: 0.7))
                .contentShape(Rectangle())
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
        VStack(alignment: .leading, spacing: 8) {
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
    @ViewBuilder private func bookFace(_ person: Person) -> some View {
        if let latest { V5WorkThumbnail(url: latest.url, modifiedAt: latest.generatedAt) }
        else { V5BookCover(personName: person.name) }
    }
    @ViewBuilder private func content(_ person: Person) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) { bookFace(person).frame(width: 90); details(person) }
        } else {
            HStack(spacing: 16) { bookFace(person).frame(width: 82); details(person) }
        }
    }
    private func details(_ person: Person) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("三术合参 · 综合解读").font(.caption).foregroundStyle(V5Palette.color(theme.palette.ornamentText))
            Text(person.name + " · 个人卷").font(V5Typography.song(.headline, emphasis: true)).fixedSize(horizontal: false, vertical: true)
            Text("八字 · 紫微 · 手相 · 面相").font(.subheadline)
            if let latest { Text(V5DisplayText.date(latest.generatedAt)).font(.caption) }
            else { Text("按当前档案生成与阅读").font(.caption) }
            Image(systemName: "arrow.up.right").frame(minWidth: 48, minHeight: 48, alignment: .leading).accessibilityHidden(true)
        }.foregroundStyle(V5Palette.color(theme.palette.ink))
    }
}
