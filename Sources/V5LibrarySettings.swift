import SwiftUI

struct V5SettingsPage: View {
    @StateObject private var speaker = Speaker()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: V5Metric.gap) {
                Text("设置与研习").font(.system(.largeTitle, design: .serif)).padding(.vertical, 12)
                group("显示与阅读") {
                    NavigationLink { V5AppearanceView() } label: { row("四时外观", "当前：\(V5ThemeStore.shared.theme.title)", "circle.lefthalf.filled") }
                    ScriptSettingsView()
                }
                group("排盘与智能解读") {
                    NavigationLink { CaliberSettingsView() } label: { row("排盘口径与证书日期记录", "八字晚子时、紫微闰月及既有侧载到期提醒", "slider.horizontal.3") }
                    NavigationLink { AskView() } label: { row("AI 问答与历史", "按需联网；以本机引擎事实包为依据", "bubble.left.and.bubble.right") }
                    Text("AI 问答沿用应用现有服务。本版本没有可配置的自定义模型或 API 密钥入口。")
                        .font(.footnote).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
                }
                group("本机语音") { InterpretNarrationControls(speaker: speaker) }
                group("数据与通知") {
                    NavigationLink { BackupView() } label: { row("数据备份与恢复", "沿用完整备份校验与恢复流程", "externaldrive") }
                    NavigationLink { PeopleView() } label: { row("人物 JSON 导入与导出", "保留原有档案交换格式", "person.2") }
                    NavigationLink { MyView() } label: { row("本地通知与原有偏好", "每日运势提醒、推送时间及全部原有设置", "bell") }
                }
                group("古籍与来源") {
                    NavigationLink { ClassicsView() } label: { row("古籍原文检索", "公有领域原文逐句对照与检索", "books.vertical") }
                    NavigationLink { LibraryView() } label: { row("五典与实务断语库", "既有 100 条文本与出处", "text.book.closed") }
                    NavigationLink { AcademyView() } label: { row("研习与验证依据", "排盘口径、收据说明与自测入口", "graduationcap") }
                    NavigationLink { ShaHandbookView() } label: { row("风水知识与解煞手册", "原有测法与分层化解说明", "house") }
                }
                group("应用") {
                    NavigationLink { V5UpdatePage() } label: { row("版本与 IPA 文件", "查看本机版本，检查并分享自备安装包", "shippingbox") }
                    NavigationLink { AboutView() } label: { row("关于三术合参", "版本、隐私、致谢与使用说明", "info.circle") }
                }
            }.padding(V5Metric.page)
        }
        .background(V5Palette.color(V5Palette.current.paper)).foregroundStyle(V5Palette.color(V5Palette.current.ink))
        .navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
        .onDisappear { speaker.stop() }
    }
    private func row(_ title: String, _ detail: String, _ icon: String) -> some View {
        V5LibraryRow(title: title, detail: detail, icon: icon)
    }
    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        V5Card {
            VStack(alignment: .leading, spacing: V5Metric.gap) {
                Text(title).font(.title2.bold())
                content()
            }
        }
    }
}
