import SwiftUI

struct V5SettingsPage: View {
    @StateObject private var speaker = Speaker()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: V5Metric.gap) {
                V5ArtHeader(eyebrow: "外观 · 口径 · 研习", title: "设置与研习", subtitle: "从显示、口径，到每一份本机记录")
                group("显示与阅读", number: "01", subtitle: "四时外观 · 简繁文字") {
                    NavigationLink { V5AppearanceView() } label: { row("四时外观", "当前：\(V5ThemeStore.shared.theme.title)", "circle.lefthalf.filled") }
                    Divider()
                    ScriptSettingsView()
                }
                group("排盘与智能解读", number: "02", subtitle: "先明确口径，再阅读结果") {
                    NavigationLink { CaliberSettingsView() } label: { row("排盘口径与证书日期记录", "八字晚子时、紫微闰月及既有侧载到期提醒", "slider.horizontal.3") }
                    Divider()
                    NavigationLink { AskView() } label: { row("AI 问答与历史", "按需联网；以本机引擎事实包为依据", "bubble.left.and.bubble.right") }
                    Text("AI 问答沿用应用现有服务。本版本没有可配置的自定义模型或 API 密钥入口。")
                        .font(.footnote).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
                }
                group("本机语音", number: "03", subtitle: "设备朗读 · 不上传声音") { InterpretNarrationControls(speaker: speaker) }
                group("数据与通知", number: "04", subtitle: "保全档案 · 按需提醒") {
                    NavigationLink { BackupView() } label: { row("数据备份与恢复", "沿用完整备份校验与恢复流程", "externaldrive") }
                    Divider()
                    NavigationLink { PeopleView() } label: { row("人物 JSON 导入与导出", "保留原有档案交换格式", "person.2") }
                    Divider()
                    V5LibraryNotificationSettings()
                }
                group("古籍与来源", number: "05", subtitle: "原文、出处与可复核依据") {
                    NavigationLink { ClassicsView() } label: { row("古籍原文检索", "公有领域原文逐句对照与检索", "books.vertical") }
                    Divider()
                    NavigationLink { LibraryView() } label: { row("五典与实务断语库", "既有 100 条文本与出处", "text.book.closed") }
                    Divider()
                    NavigationLink { AcademyView() } label: { row("研习与验证依据", "排盘口径、收据说明与自测入口", "graduationcap") }
                    Divider()
                    NavigationLink { ShaHandbookView() } label: { row("风水知识与解煞手册", "原有测法与分层化解说明", "house") }
                }
                group("应用", number: "06", subtitle: "版本、文件与隐私") {
                    NavigationLink { V5UpdatePage() } label: { row("版本与 IPA 文件", "查看本机版本，检查并分享自备安装包", "shippingbox") }
                    Divider()
                    NavigationLink { AboutView() } label: { row("关于三术合参", "版本、隐私、致谢与使用说明", "info.circle") }
                }
            }.padding(V5Metric.page)
        }
        .background { V5SceneBackground() }.foregroundStyle(V5Palette.color(V5Palette.current.ink))
        .navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
        .onDisappear { speaker.stop() }
    }
    private func row(_ title: String, _ detail: String, _ icon: String) -> some View {
        V5LibraryRow(title: title, detail: detail, icon: icon)
    }
    private func group<Content: View>(_ title: String, number: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(number).font(.caption.monospacedDigit()).foregroundStyle(V5Palette.color(V5Palette.current.ornamentText))
                V5SectionHeading(title: title, subtitle: subtitle)
            }.padding(.top, 12)
            V5Card { VStack(alignment: .leading, spacing: 12) { content() } }
        }
    }
}


private struct V5LibraryNotificationSettings: View {
    @EnvironmentObject private var people: PeopleStore
    @AppStorage("todayNotify.enabled") private var enabled = false
    @AppStorage("todayNotify.hour") private var hour = 7
    @AppStorage("todayNotify.minute") private var minute = 30
    @State private var notice = ""
    private var notificationPerson: Person? {
        people.people.first(where: { $0.relation == "本人" }) ?? people.people.first
    }
    private var time: Binding<Date> {
        Binding(get: {
            var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            components.hour = hour; components.minute = minute
            return Calendar.current.date(from: components) ?? Date()
        }, set: { date in
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            hour = components.hour ?? 7; minute = components.minute ?? 30
            if enabled { TodayNotificationManager.scheduleDaily(person: notificationPerson) }
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("每日推送今日运势", isOn: $enabled)
                .frame(minHeight: V5Metric.target)
                .onChange(of: enabled) { _, value in
                    notice = ""
                    if value {
                        TodayNotificationManager.requestAuthorization { granted in
                            Task { @MainActor in
                                guard enabled else { return }
                                if granted {
                                    TodayNotificationManager.scheduleDaily(person: notificationPerson)
                                } else {
                                    enabled = false
                                    notice = "系统尚未允许通知，可在 iPhone 系统设置中为三术合参开启通知权限。"
                                }
                            }
                        }
                    } else { TodayNotificationManager.cancel() }
                }
            if enabled {
                DatePicker("推送时间", selection: time, displayedComponents: .hourAndMinute)
                    .frame(minHeight: V5Metric.target)
                Text("按设备本地时间提醒。沿用既有通知规则：本人档案优先，其次为第一位档案。")
                    .font(.footnote)
                if let person = notificationPerson {
                    Text("提醒命主：\(person.name) · 档案 \(person.id.uuidString.prefix(8))").font(.caption)
                } else {
                    Text("尚无档案，当前不会安排提醒；添加人物后请重新开启通知。上方开关仅保存提醒偏好。")
                        .font(.footnote)
                }
            }
            if !notice.isEmpty { Text(notice).font(.footnote).accessibilityIdentifier("v5.settings.notificationStatus") }
            Text("默认关闭；每天一条本机通知，不走服务端。可随时关闭取消排期。")
                .font(.footnote).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
        }
    }
}
