// 无障碍基础标注（B-9）＋统一错误呈现（B-10），2026-11-04：
// B-9：纯图标按钮此前只有系统符号，VoiceOver 只能靠默认推断；本文件不改任何按钮行为，
// 各纯图标按钮的 accessibilityLabel 就近标在其按钮处（见各模块改动），盘面文本等价物见 BaziModule.plateGrid。
// B-10：人物／前瞻／手相／勘察四处关键存档的 save() 此前用 try? 静默吞错，写盘失败用户无从得知；
// 现改为 do/catch，失败时经 AppErrorCenter 在根 Tab 栏顶部亮一条可关闭的提示（不弹系统 alert、不阻断操作）。
// 导出／分享／上传失败已有行内 status 文案，不在本批范围内，仍走原有文案通道。
import SwiftUI

@MainActor
final class AppErrorCenter: ObservableObject {
    static let shared = AppErrorCenter()
    @Published var message: String?
    func report(_ message: String) { self.message = message }
    func dismiss() { message = nil }
}

struct AppErrorBanner: View {
    var message: String
    var onDismiss: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Ky.cinnabar)
            Text(message.scriptConverted).font(.subheadline).foregroundStyle(Ky.ink).lineLimit(3)
            Spacer()
            Button("知道了", action: onDismiss).font(.subheadline).fontWeight(.semibold).foregroundStyle(Ky.qingdai)
        }
        .padding(12)
        .background(Ky.card)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Ky.cinnabar.opacity(0.5), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("保存失败提示：\(message)，点知道了关闭")
    }
}
