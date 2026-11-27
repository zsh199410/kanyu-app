import SwiftUI

/// One real destination for profile management and global settings, shared by all tabs.
struct V5ProfileCenterView: View {
    @EnvironmentObject private var people: PeopleStore
    @EnvironmentObject private var router: V5Router
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                V5ArtHeader(eyebrow: "三术合参 · 档案与设置", title: people.currentPerson?.name ?? "尚未建档", subtitle: "人物、阅读与本机资料，在这里统一整理。")
                V5Card {
                    NavigationLink { PeopleView() } label: {
                        V5LibraryRow(title: "人物档案", detail: "新建、编辑、导入导出及归属管理", icon: "person.2")
                    }.accessibilityIdentifier("profile.people")
                }
                V5Card {
                    VStack(alignment: .leading, spacing: 20) {
                        NavigationLink { V5AppearanceView() } label: {
                            V5LibraryRow(title: "外观", detail: V5ThemeStore.shared.theme.title, icon: "circle.lefthalf.filled")
                        }.accessibilityIdentifier("外观")
                        Divider()
                        NavigationLink { V5SettingsPage() } label: {
                            V5LibraryRow(title: "设置与研习", detail: "口径、AI、语音、通知、备份与古籍", icon: "slider.horizontal.3")
                        }
                        Divider()
                        NavigationLink { V5UpdatePage() } label: {
                            V5LibraryRow(title: "版本与 IPA", detail: "本机版本、文件校验与自签交接", icon: "shippingbox")
                        }
                    }
                }
                Button { router.open(.tools) } label: {
                    V5Card { V5LibraryRow(title: "全部功能", detail: "排盘、择吉、合参与专业工具", icon: "square.grid.2x2") }
                }.buttonStyle(.plain)
            }.padding(V5Metric.page)
        }.background { V5SceneBackground() }.foregroundStyle(V5Palette.color(V5Palette.current.ink))
            .navigationTitle("档案与设置").navigationBarTitleDisplayMode(.inline)
    }
}

struct V5HomeUtilityShelf: View {
    @EnvironmentObject private var people: PeopleStore
    @EnvironmentObject private var router: V5Router
    @State private var revision = 0
    var body: some View {
        let _ = revision
        let recent = AllToolsData.recentEntries(people: people.people)
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { shortcuts }
                VStack(alignment: .leading, spacing: 12) { shortcuts }
            }
            if !recent.isEmpty {
                Text("最近使用").font(V5Typography.section)
                ForEach(recent.prefix(4)) { item in
                    switch item {
                    case .tool(let tool):
                        Button { router.open(.tool(tool.id)) } label: {
                            HStack { Text(tool.title); Spacer(); Image(systemName: "arrow.up.right") }.frame(minHeight: V5Metric.target)
                        }.accessibilityIdentifier("home.recent." + tool.id)
                    case .person(let person):
                        Button { people.setCurrentPerson(person) } label: {
                            Text(person.name + " · 档案 " + String(person.id.uuidString.prefix(8))).frame(minHeight: V5Metric.target)
                        }
                    }
                }
            }
        }.onAppear { revision += 1 }
    }
    @ViewBuilder private var shortcuts: some View {
        Button { router.open(.tool("astro")) } label: { Label("星命合参", systemImage: "circle.hexagongrid").frame(minHeight: V5Metric.target) }.accessibilityIdentifier("home.astro")
        Button { router.open(.palm) } label: { Label("手相面相", systemImage: "hand.raised").frame(minHeight: V5Metric.target) }
        Button { router.open(.tools) } label: { Label("全部工具", systemImage: "square.grid.2x2").frame(minHeight: V5Metric.target) }.accessibilityIdentifier("home.alltools")
    }
}
