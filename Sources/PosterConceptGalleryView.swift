import SwiftUI
import UIKit

/// Approved visual references; sample text and numbers are not personalized results.
/// The real poster exporters remain independently sourced from chart/measurement data.
private enum PosterConcept: String, CaseIterable, Identifiable {
    case palm, bazi, ziwei, premium
    var id: String { rawValue }
    var title: String {
        switch self {
        case .palm: return "手相 · 个人指南"
        case .bazi: return "八字 · 古风长卷"
        case .ziwei: return "紫微 · 星曜图鉴"
        case .premium: return "尊享预测单"
        }
    }
    var subtitle: String {
        switch self {
        case .palm: return "青黛金线 · 掌纹导览 · 道家山水"
        case .bazi: return "宋纸画卷 · 四柱大运 · 古风漫画"
        case .ziwei: return "玄夜星图 · 十二宫位 · 天文仪象"
        case .premium: return "详批预测单 · 朱砂印记 · 典雅册页"
        }
    }
    var imageName: String {
        switch self {
        case .palm: return "PosterConceptPalm"
        case .bazi: return "PosterConceptBazi"
        case .ziwei: return "PosterConceptZiwei"
        case .premium: return "PosterConceptPremium"
        }
    }
    var symbol: String {
        switch self {
        case .palm: return "hand.raised"
        case .bazi: return "scroll"
        case .ziwei: return "moon.stars"
        case .premium: return "doc.richtext"
        }
    }
    func image() -> UIImage? {
        if let image = UIImage(named: imageName) { return image }
        let url = Bundle.main.url(forResource: imageName, withExtension: "jpg", subdirectory: "PosterDesignPreviews")
            ?? Bundle.main.url(forResource: imageName, withExtension: "jpg")
        return url.flatMap { UIImage(contentsOfFile: $0.path) } ?? PosterEmbeddedThumbnails.image(for: imageName)
    }
}

/// Gallery only. The flat generative design examples are never exported as a user's results.
struct PosterConceptGalleryView: View {
    var person: Person? = nil
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Text("四境 · 四卷")
                    .font(.system(.title2, design: .serif, weight: .bold))
                    .foregroundStyle(Ky.ink)
                Text("四种独立视觉语言。画面含设计示例数据，正式报告将使用当前人物真实计算结果重新排版。")
                    .font(.subheadline)
                    .foregroundStyle(Ky.sub)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("poster.gallery.sampleNotice")
                ForEach(PosterConcept.allCases) { concept in
                    NavigationLink {
                        detail(concept)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            thumb(concept)
                                .frame(width: 122, height: 215)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 9) {
                                Image(systemName: concept.symbol).foregroundStyle(Ky.qingdai)
                                Text(concept.title).font(.headline).foregroundStyle(Ky.ink)
                                Text(concept.subtitle).font(.footnote).foregroundStyle(Ky.sub)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                Label("查看样张", systemImage: "arrow.up.right")
                                    .font(.caption.weight(.semibold)).foregroundStyle(Ky.qingdai)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 210)
                        }
                        .padding(12)
                        .background(Ky.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Ky.line.opacity(0.6)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("poster.gallery.open.\(concept.rawValue)")
                }
            }
            .padding(16)
        }
        .background(Ky.bg)
        .navigationTitle("海报作品库")
        .navigationBarTitleDisplayMode(.inline)
    }
    @ViewBuilder private func thumb(_ c: PosterConcept) -> some View {
        if let image = c.image() {
            Image(uiImage: image)
                .resizable().scaledToFill().frame(width: 122, height: 215).clipped()
                .overlay(alignment: .topLeading) {
                    Text("视觉样张").font(.caption2.weight(.bold)).padding(5)
                        .background(.regularMaterial).clipShape(RoundedRectangle(cornerRadius: 6)).padding(6)
                }
                .accessibilityLabel("\(c.title)设计预览")
        } else {
            ZStack {
                Ky.bg
                VStack(spacing: 8) {
                    Image(systemName: c.symbol).font(.title)
                    Text("素材待导入").font(.caption)
                }.foregroundStyle(Ky.qingdai)
            }
            .accessibilityLabel("\(c.title)的预览图尚未打包")
        }
    }
    private func detail(_ c: PosterConcept) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(c.title).font(.system(.title2, design: .serif, weight: .bold))
                    .foregroundStyle(Ky.ink)
                Text("设计样张 · 非本人报告：画面中的示例出生时间、测量值及解读不得用于真实导出。")
                    .font(.footnote.weight(.semibold)).foregroundStyle(Ky.cinnabar)
                    .fixedSize(horizontal: false, vertical: true)
                if let image = c.image() {
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(alignment: .topLeading) {
                            Text("仅供设计预览").font(.caption.weight(.bold)).padding(8)
                                .background(.regularMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 8)).padding(12)
                        }
                } else {
                    Label("请导入四款 JPG 预览图资源。", systemImage: "photo.badge.exclamationmark")
                        .foregroundStyle(Ky.sub)
                }
                if (c == .bazi || c == .premium), let person {
                    NavigationLink {
                        PosterDynamicTemplateView(snapshot: PosterDynamicSnapshot.bazi(
                            person: person,
                            chart: BaziEngine.cachedPaipan(
                                clock: person.birthDate, gender: person.gender,
                                longitude: person.useLongitude ? person.longitude : nil),
                            premium: c == .premium))
                    } label: {
                        Label("查看当前人物重点海报", systemImage: "doc.text.image")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(Ky.qingdai)
                    .accessibilityIdentifier("poster.gallery.dynamic.\(c.rawValue)")
                }
                exportLink(c)
                Text("设计图里的姓名、命盘、数值仅供欣赏；重点海报只使用当前命主已有数据，可分页导出 ZIP；完整版仍在 App 或 PDF 中查看。")
                    .font(.caption).foregroundStyle(Ky.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
        .background(Ky.bg)
        .navigationTitle("画风预览")
        .navigationBarTitleDisplayMode(.inline)
    }
    @ViewBuilder private func exportLink(_ c: PosterConcept) -> some View {
        switch c {
        case .palm:
            NavigationLink {
                PalmHomeView()
            } label: {
                Label("前往手相测量与原生海报", systemImage: "hand.raised")
            }.buttonStyle(KyPrimaryButton())
        case .ziwei:
            NavigationLink {
                ZiweiHomeView()
            } label: {
                Label("前往紫微排盘与原生海报", systemImage: "moon.stars")
            }.buttonStyle(KyPrimaryButton())
        case .bazi, .premium:
            if let p = person {
                NavigationLink {
                    PosterSheetView(chart: BaziEngine.cachedPaipan(
                        clock: p.birthDate, gender: p.gender,
                        longitude: p.useLongitude ? p.longitude : nil), name: p.name)
                } label: {
                    Label(c == .premium ? "前往现有尊享预测单" : "前往八字原生海报",
                          systemImage: "photo")
                }.buttonStyle(KyPrimaryButton())
            } else {
                Label("请先选择人物档案，再生成真实八字海报。", systemImage: "person.crop.circle.badge.questionmark")
                    .font(.footnote).foregroundStyle(Ky.sub)
            }
        }
    }
}
