import SwiftUI

struct V6ExportFailureCard: View {
    let message: String
    let retry: @MainActor () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(message.scriptConverted, systemImage: "exclamationmark.triangle")
                .font(.body).foregroundStyle(Ky.cinnabar)
            Button("重新生成海报".scriptConverted, action: retry).buttonStyle(KyPrimaryButton())
        }
        .kyCard()
        .accessibilityElement(children: .contain)
    }
}

struct V6PosterSkinPicker: View {
    @Binding var style: PosterStyle
    var body: some View {
        Picker("海报款式".scriptConverted, selection: $style) {
            ForEach(PosterStyle.allCases.filter { $0 != .yuceDan }, id: \.self) { option in
                Text(option.rawValue.scriptConverted).tag(option)
            }
        }.pickerStyle(.menu)
    }
}
