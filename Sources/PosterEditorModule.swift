import SwiftUI
import UIKit
import Photos

// MARK: - 海报编辑器基础版（G13，Insight 第 3 批；2026-11-09 精简：只留宋纸青黛一款）
// 换字（标题／落款副标文案）＋换色（品牌色板内 4 档强调色）；款式选择器已随砍款去掉，编辑器只出宋纸青黛。
// 导出走 PosterSheetView 同款渲染路径（ImageRenderer，scale 2.0，540pt 画布 → 1080 宽 PNG），
// 文件名后缀走 PosterStyle.fileSuffix，与既有海报同规格；结论内容只取 PosterView 既有解盘，一字不动。
// 入口：PosterSheetView 内「打开海报编辑器」按钮，以 .sheet 弹出（禁 fullScreenCover）。
// 文案须经「应用并预览」才进入渲染，避免每敲一字重渲染一次长图。

/// 品牌强调色（只取既有品牌色板内的 4 档，不引入新色、不加阴影）。
enum PosterAccent: String, CaseIterable, Identifiable {
    case cinnabar = "朱砂红"
    case qingdai = "青黛"
    case gold = "雅金"
    case ink = "墨色"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .cinnabar:
            return Color(red: 0.604, green: 0.165, blue: 0.133)
        case .qingdai:
            return Color(red: 0.153, green: 0.306, blue: 0.361)
        case .gold:
            return Color(red: 0.62, green: 0.47, blue: 0.18)
        case .ink:
            return Color(red: 0.18, green: 0.165, blue: 0.15)
        }
    }
}

struct PosterEditorView: View {
    let chart: BaziChart
    let name: String

    @Environment(\.dismiss) private var dismiss
    @State private var style: PosterStyle = .songQingdai
    @State private var accent: PosterAccent = .qingdai
    @State private var titleDraft: String = ""
    @State private var subtitleDraft: String = ""
    @State private var appliedTitle: String = ""
    @State private var appliedSubtitle: String = ""
    @State private var previewImage: UIImage?
    @State private var fileURL: URL?
    @State private var renderKey: String
    @State private var saveMessage: String?

    init(chart: BaziChart, name: String) {
        self.chart = chart
        self.name = name
        _renderKey = State(initialValue: PosterStyle.songQingdai.rawValue + "-" + PosterAccent.qingdai.rawValue + "--")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("海报款式", selection: $style) {
                        ForEach(PosterStyle.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: style) { _, _ in
                        fileURL = nil
                        previewImage = nil
                        saveMessage = nil
                        refreshRenderKey()
                    }
                    Text("换色：强调色（品牌色板内）")
                        .font(.headline)
                    Picker("强调色", selection: $accent) {
                        ForEach(PosterAccent.allCases) { a in
                            Text(a.rawValue).tag(a)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(style == .xuanye)
                    .onChange(of: accent) { _, _ in
                        fileURL = nil
                        previewImage = nil
                        refreshRenderKey()
                    }

                    Text("换字：标题与落款副标")
                        .font(.headline)
                    TextField("标题文案（留空则用人物名）", text: $titleDraft)
                        .textFieldStyle(.roundedBorder)
                    TextField("落款副标（留空则用既有副标）", text: $subtitleDraft)
                        .textFieldStyle(.roundedBorder)
                    Button("应用并预览") {
                        appliedTitle = titleDraft
                        appliedSubtitle = subtitleDraft
                        fileURL = nil
                        previewImage = nil
                        refreshRenderKey()
                    }
                    .buttonStyle(KyPrimaryButton())

                    Text("导出与既有海报同规格：1080 宽 PNG，scale 2.0；只改标题、副标与强调色，结论内容不动。")
                        .font(.caption)
                        .foregroundStyle(Ky.sub)

                    if let img = previewImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Ky.line, lineWidth: 0.8))
                    } else {
                        ProgressView("正在渲染海报…")
                            .frame(maxWidth: .infinity)
                    }

                    if fileURL != nil, let img = previewImage {
                        ShareLink(item: Image(uiImage: img), preview: SharePreview("编辑后海报", image: Image(uiImage: img))) {
                            Label("保存 / 分享编辑后海报（1080宽 PNG）", systemImage: "square.and.arrow.down")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(KyPrimaryButton())
                        Button {
                            PosterPhotoSaver.save(img) { saveMessage = $0 }
                        } label: {
                            Label("保存到相册", systemImage: "photo.badge.plus")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(KyPrimaryButton())
                        if let saveMessage {
                            Text(saveMessage)
                                .font(.caption).foregroundStyle(Ky.sub).multilineTextAlignment(.center)
                        }
                        Text("分享单点「存储图像」可存入相册，或点「保存到相册」直接存入；也可以直接转发微信。")
                            .font(.caption).foregroundStyle(Ky.sub).multilineTextAlignment(.center)
                    }
                }
                .padding(20)
            }
            .background(Ky.bg)
            .navigationTitle("海报编辑器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .task(id: renderKey) { render() }
        }
    }

    private func refreshRenderKey() {
        renderKey = "\(style.rawValue)-\(accent.rawValue)-\(appliedTitle)-\(appliedSubtitle)"
    }

    // 与 PosterSheetView.render 同款渲染路径（ImageRenderer 在主线程渲染，完成后展示缓存图）
    private func render() {
        let chart = chart
        let name = name
        let style = style
        let accent = accent
        let appliedTitle = appliedTitle
        let appliedSubtitle = appliedSubtitle
        let expectedKey = renderKey
        Task { @MainActor in
            let titleValue: String? = appliedTitle.isEmpty ? nil : appliedTitle
            let subtitleValue: String? = appliedSubtitle.isEmpty ? nil : appliedSubtitle
            let view = PosterView(chart: chart, name: name, style: style, titleOverride: titleValue, subtitleOverride: subtitleValue, accentOverride: style == .xuanye ? nil : accent.color)
            let renderer = ImageRenderer(content: view.environment(\.colorScheme, .light))
            renderer.scale = 2.0
            guard let img = renderer.uiImage, let data = img.pngData() else { return }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("poster-\(ReportBuilder.exportName(name.isEmpty ? "chart" : name))\(style.fileSuffix).png")
            do { try data.write(to: url, options: .atomic) }
            catch {
                saveMessage = "海报保存失败，请检查剩余空间后重试。"
                return
            }
            guard self.renderKey == expectedKey else { return }
            previewImage = img
            fileURL = url
        }
    }
}
