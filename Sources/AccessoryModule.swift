// 配饰材质结构化库（Insight 第 2 批 G7，2026-11-09）
// 条目覆盖：PosterModule:691–699 真迹五项所涉材质（玉石／翡翠／玛瑙／水晶／珍珠／金银／木质工艺品，
// 另含同五项原文中的石头工艺品、金属类工艺品、红色中国结）＋ LibraryModule id 49／id 56 第 3、4 层
// 提及的材质（id 49 补五行建议中的玉石、中国结；id 56 第 4 层「水晶饰物对应」）。
// 每条必有五字段：名称／对应五行／来源／可信度／备注；0 条无来源。
// 来源只取四档之一：五典原文／流派应用／民间象征／本系统回测纪律。
// 真迹原文只作引用，不得把真迹原文直接升格为库条目（见各条 source 的「仅作引用」标注）。
// 整体只进民间象征层，页内醒目标注「不代表功效主张」。
// 可信度三档与名人库同档（高／中／低）：高＝五典原文有载且多源一致；中＝流派应用多源一致；
// 低＝民间象征单源引用。本库全部条目均为民间象征层，故可信度均为「低」，如实标注，不拔高。
// 绝不接电商：无购买入口、无价格、无购买引导。
import SwiftUI

/// 配饰材质库条目（五字段齐全，无默认值缺失；调用处按字段全量传参）。
struct AccessoryItem {
    let name: String
    let wuxing: String
    let source: String
    let trust: String
    let note: String
}

enum AccessoryData {
    static let all: [AccessoryItem] = [
        AccessoryItem(
            name: "木质工艺品",
            wuxing: "木",
            source: "民间象征｜《易辰取名社八字预测单》手写单真迹措辞引用（PosterModule:691–699 第 1 项），仅作引用",
            trust: "低",
            note: "真迹原文举例绿檀、紫檀、黄花梨手串；原文只作引用，不升格为库口径。"
        ),
        AccessoryItem(
            name: "中国结（棉麻绳结）",
            wuxing: "火",
            source: "民间象征｜手写单真迹措辞引用（PosterModule:691–699 第 2 项），仅作引用；知识库 id 49 补五行建议亦列红衣中国结（民间应用层）",
            trust: "低",
            note: "真迹原文：床头挂红色中国结；红色为火行配色通说，绳结本身只作民间象征。"
        ),
        AccessoryItem(
            name: "玉石",
            wuxing: "土",
            source: "民间象征｜手写单真迹措辞引用（PosterModule:691–699 第 3 项），仅作引用；知识库 id 49 补五行建议亦列玉石（民间应用层）",
            trust: "低",
            note: "真迹原文列于补土一行；玉石无五典治疗学出处，只进民间象征层。"
        ),
        AccessoryItem(
            name: "翡翠",
            wuxing: "土",
            source: "民间象征｜手写单真迹措辞引用（PosterModule:691–699 第 3 项），仅作引用",
            trust: "低",
            note: "真迹原文列于补土一行，与玉石、玛瑙并列；只作引用，不升格为库口径。"
        ),
        AccessoryItem(
            name: "玛瑙",
            wuxing: "土",
            source: "民间象征｜手写单真迹措辞引用（PosterModule:691–699 第 3 项），仅作引用",
            trust: "低",
            note: "真迹原文列于补土一行，与玉石、翡翠并列；只作引用，不升格为库口径。"
        ),
        AccessoryItem(
            name: "石头工艺品",
            wuxing: "土",
            source: "民间象征｜手写单真迹措辞引用（PosterModule:691–699 第 3 项，摆放石头工艺品），仅作引用",
            trust: "低",
            note: "真迹原文列于补土一行；摆放类条目，与佩戴类同属民间象征层。"
        ),
        AccessoryItem(
            name: "金银饰品",
            wuxing: "金",
            source: "民间象征｜手写单真迹措辞引用（PosterModule:691–699 第 4 项），仅作引用",
            trust: "低",
            note: "真迹原文列于补金一行；只作引用，不升格为库口径。"
        ),
        AccessoryItem(
            name: "金属类工艺品",
            wuxing: "金",
            source: "民间象征｜手写单真迹措辞引用（PosterModule:691–699 第 4 项，摆放金属类工艺品），仅作引用",
            trust: "低",
            note: "真迹原文列于补金一行；摆放类条目，与佩戴类同属民间象征层。"
        ),
        AccessoryItem(
            name: "水晶",
            wuxing: "水",
            source: "民间象征｜手写单真迹措辞引用（PosterModule:691–699 第 5 项），仅作引用；知识库 id 56 第 4 层「水晶饰物对应」亦属民间象征层",
            trust: "低",
            note: "真迹原文列于补水一行，与珍珠并列；id 56 第 4 层明确定为民间象征，须标注民间说法。"
        ),
        AccessoryItem(
            name: "珍珠",
            wuxing: "水",
            source: "民间象征｜手写单真迹措辞引用（PosterModule:691–699 第 5 项），仅作引用",
            trust: "低",
            note: "真迹原文列于补水一行，与水晶并列；只作引用，不升格为库口径。"
        ),
    ]

    /// 来源覆盖率自查：全部条目 source 非空且以四档之一开头。
    static var sourcedCount: Int {
        all.filter { item in
            item.source.hasPrefix("五典原文｜")
                || item.source.hasPrefix("流派应用｜")
                || item.source.hasPrefix("民间象征｜")
                || item.source.hasPrefix("本系统回测纪律｜")
        }.count
    }
}

struct AccessoryListView: View {
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                Text("民间象征层 · 不代表功效主张——本库只收传统说法与引用，不卖开运物，无购买入口、无价格。".scriptConverted)
                    .font(.callout).fontWeight(.semibold).foregroundStyle(Ky.cinnabar)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Ky.cinnabar.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                KySectionTitle(title: "配饰材质", trailing: "共 \(AccessoryData.all.count) 条 · 全部有来源")
                VStack(spacing: 10) {
                    ForEach(AccessoryData.all, id: \.name) { item in
                        NavigationLink {
                            AccessoryDetailView(item: item)
                        } label: {
                            accessoryRow(item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("口径说明：每条均有来源与可信度字段；真迹原文只作引用，不得升格为库口径；全部条目只进民间象征层。".scriptConverted)
                    .font(.caption2).foregroundStyle(Ky.sub)
            }
            .padding(.horizontal, KyV6.pageHorizontalMargin)
            .padding(.top, 6)
            .padding(.bottom, 100)
        }
        .background(Ky.bg)
        .navigationTitle("配饰库".scriptConverted)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func accessoryRow(_ item: AccessoryItem) -> some View {
        HStack(spacing: 12) {
            Text(item.wuxing.scriptConverted)
                .font(.system(size: 16, weight: .bold, design: .serif))
                .foregroundStyle(Ky.qingdai)
                .frame(width: 36, height: 36)
                .background(Ky.qingdai.opacity(0.13))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name.scriptConverted)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(Ky.ink)
                Text("对应五行 \(item.wuxing) · 可信度 \(item.trust)".scriptConverted)
                    .font(.caption2)
                    .foregroundStyle(Ky.sub)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Ky.sub)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Ky.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Ky.line.opacity(0.9), lineWidth: 0.8))
    }
}

struct AccessoryDetailView: View {
    let item: AccessoryItem

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                Text("民间象征层 · 不代表功效主张".scriptConverted)
                    .font(.callout).fontWeight(.semibold).foregroundStyle(Ky.cinnabar)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Ky.cinnabar.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 10) {
                    detailRow(label: "名称", text: item.name)
                    Divider()
                    detailRow(label: "对应五行", text: item.wuxing)
                    Divider()
                    detailRow(label: "来源", text: item.source)
                    Divider()
                    detailRow(label: "可信度", text: item.trust)
                    Divider()
                    detailRow(label: "备注", text: item.note)
                }
                .kyCard()
                Text("本库无购买入口、无价格；典籍里没有「后天佩戴／摆放补命局」的治疗学（知识库 id 56 第 1 层），佩饰只作民间象征。".scriptConverted)
                    .font(.caption2).foregroundStyle(Ky.sub)
            }
            .padding(.horizontal, KyV6.pageHorizontalMargin)
            .padding(.top, 6)
            .padding(.bottom, 100)
        }
        .background(Ky.bg)
        .navigationTitle(item.name.scriptConverted)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detailRow(label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.scriptConverted)
                .font(.callout).fontWeight(.semibold).foregroundStyle(Ky.gold)
            Text(text)
                .font(.callout).foregroundStyle(Ky.ink)
        }
    }
}
