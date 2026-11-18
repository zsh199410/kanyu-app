import SwiftUI
import AVFoundation

/// Device-local voice selection. This never records or uploads a person's voice.
struct InterpretNarrationControls: View {
    @ObservedObject var speaker: Speaker

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("普通话音色", selection: $speaker.selectedVoiceID) {
                Text("自动选择设备已安装的高品质声音").tag("")
                ForEach(speaker.mandarinVoices, id: \.identifier) { voice in
                    Text("\(voice.name) · \(qualityName(voice.quality))").tag(voice.identifier)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("interpret.voice.picker")
            HStack(spacing: 12) {
                Text("语速")
                    .font(.subheadline)
                Slider(value: $speaker.narrationRate, in: 0.42...0.58)
                    .accessibilityLabel("普通话朗读语速")
                    .accessibilityIdentifier("interpret.voice.rate")
                Text(String(format: "%.2f", speaker.narrationRate))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Ky.sub)
            }
            Text("当前：\(speaker.activeVoiceDescription)。高级音色需要先在 iPhone 系统中安装；没有时自动回退系统普通话。")
                .font(.caption)
                .foregroundStyle(Ky.sub)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                speaker.preview()
            } label: {
                Label("试听当前音色", systemImage: "waveform")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("interpret.voice.preview")
            Text("朗读由 iPhone 本机合成，不上传出生资料、文本或声音。声音自然程度因设备与已安装音色而异。")
                .font(.caption)
                .foregroundStyle(Ky.sub)
        }
        .padding(.vertical, 6)
    }

    private func qualityName(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .premium: return "高级"
        case .enhanced: return "增强"
        default: return "标准"
        }
    }
}
