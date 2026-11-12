#if DEBUG
import SwiftUI

/// Research-based iOS export layout study. No export code, data stores or navigation are modified.
/// Static content is explicitly labeled as a design placeholder, never a computed reading.
private enum ExportStudyPage: String, CaseIterable, Identifiable {
    case poster = "长图画报"
    case cover = "PDF 封面"
    case content = "PDF 正文"
    var id: String { rawValue }
}

struct KanyuPosterPDFLayoutStudy: View {
    @State private var selection: ExportStudyPage = .poster
    private let paper = Color(rgb: KanyuV6.Hex.paper)
    private let card = Color(rgb: KanyuV6.Hex.ivory)
    private let ink = Color(rgb: KanyuV6.Hex.ink)
    private let indigo = Color(rgb: KanyuV6.Hex.indigo)
    private let muted = Color(rgb: KanyuV6.Hex.secondaryLight)
    private let border = Color(rgb: KanyuV6.Hex.ruleLight)
    private let cinnabar = Color(rgb: KanyuV6.Hex.cinnabar)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("导出排版样张", selection: $selection) {
                        ForEach(ExportStudyPage.allCases) { page in
                            Text(page.rawValue).tag(page)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("export.study.mode")
                    Text("独立设计预览 · 合成文字与数据占位 · 不参与正式导出")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Group {
                        switch selection {
                        case .poster: posterStudy
                        case .cover: pdfCoverStudy
                        case .content: pdfContentStudy
                        }
                    }
                    .accessibilityIdentifier("export.study.preview")
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("画报与 PDF 版式研究")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func sectionTitle(_ number: String, _ title: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(number)
                .font(.system(size: 13, design: .serif).weight(.semibold))
                .foregroundStyle(cinnabar)
            Text(title)
                .font(.system(size: 18, design: .serif).weight(.semibold))
                .foregroundStyle(indigo)
            Rectangle().fill(border).frame(height: 0.7)
        }
    }

    private var posterStudy: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("三 术 合 参")
                        .font(.system(size: 26, design: .serif).weight(.semibold))
                        .tracking(3)
                        .foregroundStyle(indigo)
                    Text("宋纸青黛 · 唯一画报款式")
                        .font(.system(size: 12))
                        .foregroundStyle(muted)
                }
                Spacer()
                Text("研习")
                    .font(.system(size: 16, design: .serif).weight(.bold))
                    .foregroundStyle(cinnabar)
                    .padding(9)
                    .overlay(Rectangle().stroke(cinnabar, lineWidth: 1))
                    .accessibilityLabel("装饰性研习印记，不是认证")
            }
            Rectangle().fill(border).frame(height: 1)
            VStack(alignment: .leading, spacing: 8) {
                Text("命盘解读 · 视觉样张")
                    .font(.system(size: 23, design: .serif).weight(.semibold))
                    .foregroundStyle(ink)
                Text("示例档案  ｜  2000-01-01 08:00  ｜  北京时间")
                    .font(.system(size: 12))
                    .foregroundStyle(muted)
                    .fixedSize(horizontal: false, vertical: true)
                Text("日期、时区、经度和人物 ID 应由现有模型提供")
                    .font(.system(size: 11))
                    .foregroundStyle(muted)
            }
            sectionTitle("壹", "命盘速览")
            HStack(spacing: 6) {
                ForEach(["年柱", "月柱", "日柱", "时柱"], id: \.self) { name in
                    VStack(spacing: 10) {
                        Text(name).font(.system(size: 12)).foregroundStyle(muted)
                        Text("—").font(.system(size: 27, design: .serif)).foregroundStyle(indigo)
                        Text("数据占位").font(.system(size: 10)).foregroundStyle(muted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(card)
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(border, lineWidth: 0.7))
                }
            }
            sectionTitle("贰", "先看结论")
            VStack(alignment: .leading, spacing: 9) {
                Text("一句话理解本项含义")
                    .font(.system(size: 18, design: .serif).weight(.semibold))
                    .foregroundStyle(ink)
                Text("此处引用解盘的白话导语；不编造新测算结果，也不删减原始解读。")
                    .font(.system(size: 14))
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("依据层级：盘面数据／传统规则／来源未核实")
                    .font(.system(size: 11))
                    .foregroundStyle(muted)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(card)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            sectionTitle("叁", "分项精读")
            ForEach(["原始解读全文", "岁运与时间范围", "传统依据与口径"], id: \.self) { title in
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 15, design: .serif).weight(.semibold))
                        .foregroundStyle(indigo)
                    Text("完整内容来自现有报告模型。长文字必须增加卷长，不能使用省略号裁掉有效信息。")
                        .font(.system(size: 13))
                        .foregroundStyle(ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Rectangle().fill(border).frame(height: 1)
            VStack(alignment: .leading, spacing: 6) {
                Text("内容来源、生成时间与版本指纹")
                    .font(.system(size: 12))
                    .foregroundStyle(muted)
                Text("此印记仅用于检查内容版本，不代表预测已获客观验证。")
                    .font(.system(size: 11))
                    .foregroundStyle(muted)
            }
        }
        .padding(32)
        .frame(maxWidth: 540, alignment: .leading)
        .background(paper)
        .overlay(Rectangle().stroke(indigo.opacity(0.40), lineWidth: 0.5).padding(17.5))
        .accessibilityElement(children: .contain)
    }

    private var pdfCoverStudy: some View {
        VStack(spacing: 0) {
            Text("SANSHU HECAN")
                .font(.system(size: 11, design: .serif).weight(.semibold))
                .tracking(3)
                .foregroundStyle(indigo)
            Spacer(minLength: 30)
            Text("三 术 合 参")
                .font(.system(size: 28, design: .serif).weight(.semibold))
                .tracking(3)
                .foregroundStyle(indigo)
            Text("命 书 报 告")
                .font(.system(size: 21, design: .serif).weight(.semibold))
                .foregroundStyle(ink)
                .padding(.top, 24)
            Text("专业版 · A4 可搜索文本")
                .font(.system(size: 12))
                .foregroundStyle(muted)
                .padding(.top, 12)
            Rectangle().fill(border).frame(width: 90, height: 1)
                .padding(.vertical, 28)
            VStack(spacing: 8) {
                Text("示例档案（合成数据）")
                    .font(.system(size: 18, design: .serif).weight(.semibold))
                    .foregroundStyle(ink)
                Text("生辰、时间口径、报告档位与输入收据")
                    .font(.system(size: 12))
                    .foregroundStyle(muted)
                    .multilineTextAlignment(.center)
            }
            Spacer(minLength: 50)
            Text("传统文化解读 · 不构成现实事件保证")
                .font(.system(size: 11))
                .foregroundStyle(muted)
            Text("生成日期 · 内容指纹 · 算法口径版本（均由现有数据填充）")
                .font(.system(size: 10))
                .foregroundStyle(muted)
                .padding(.top, 12)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 35)
        .frame(maxWidth: 595)
        .frame(height: 500)
        .background(card)
        .overlay(Rectangle().stroke(border, lineWidth: 1).padding(16))
        .accessibilityElement(children: .contain)
    }

    private var pdfContentStudy: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Text("三术合参  /  专业命书")
                Spacer()
                Text("CHAPTER 01")
            }
            .font(.system(size: 10))
            .foregroundStyle(muted)
            Rectangle().fill(border).frame(height: 1)
            Text("第一章  命盘与依据")
                .font(.system(size: 20, design: .serif).weight(.semibold))
                .foregroundStyle(indigo)
            Text("先读结论")
                .font(.system(size: 14, design: .serif).weight(.semibold))
                .foregroundStyle(ink)
            Text("此处显示原始结论的完整文字。正文以可搜索文本形式导出，而非将手机截图拼成 PDF。")
                .font(.system(size: 13))
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("盘面事实")
                .font(.system(size: 14, design: .serif).weight(.semibold))
                .foregroundStyle(indigo)
            Text("原始干支、时区、流派与图表数据由已有模型提供。本样张不用假数据填补空字段。")
                .font(.system(size: 13))
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("传统规则与出处")
                .font(.system(size: 14, design: .serif).weight(.semibold))
                .foregroundStyle(indigo)
            Text("只在真正完成逐字校对时标为原文；其余标注为现代整理或传统推演。")
                .font(.system(size: 13))
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 50)
            Rectangle().fill(border).frame(height: 0.7)
            Text("三术合参 · 命书  /  第 n 页")
                .font(.system(size: 10))
                .foregroundStyle(muted)
                .frame(maxWidth: .infinity)
        }
        .padding(36)
        .frame(maxWidth: 595)
        .frame(height: 520)
        .background(card)
        .accessibilityElement(children: .contain)
    }
}

#Preview("导出版式 · 浅色 App") {
    KanyuPosterPDFLayoutStudy()
        .preferredColorScheme(.light)
}
#Preview("导出版式 · 深色 App") {
    KanyuPosterPDFLayoutStudy()
        .preferredColorScheme(.dark)
}
#endif
