import SwiftUI
import UIKit

// MARK: - 命盘海报（道教墨金风：八卦环＋太极＋金线框＋朱砂印；ImageRenderer 高清导出分享/保存）

private let pBg0 = Color(red: 0.05, green: 0.07, blue: 0.10)
private let pBg1 = Color(red: 0.10, green: 0.13, blue: 0.18)
private let pGold = Color(red: 0.78, green: 0.64, blue: 0.36)
private let pGoldHi = Color(red: 0.90, green: 0.79, blue: 0.52)
private let pPaper = Color(red: 0.94, green: 0.91, blue: 0.83)
private let pSub = Color(red: 0.66, green: 0.62, blue: 0.54)
private let pCin = Color(red: 0.66, green: 0.20, blue: 0.15)
private let wxColor: [String: Color] = [
    "木": Color(red: 0.42, green: 0.66, blue: 0.45), "火": Color(red: 0.80, green: 0.38, blue: 0.28),
    "土": Color(red: 0.80, green: 0.66, blue: 0.38), "金": Color(red: 0.86, green: 0.83, blue: 0.74),
    "水": Color(red: 0.36, green: 0.55, blue: 0.72),
]

struct BaguaRingView: View {
    let size: CGFloat
    private let grams = ["☰", "☱", "☲", "☳", "☴", "☵", "☶", "☷"]
    var body: some View {
        ZStack {
            Circle().stroke(pGold.opacity(0.55), lineWidth: 1)
            Circle().stroke(pGold.opacity(0.30), lineWidth: 1).padding(size * 0.085)
            ForEach(0..<8, id: \.self) { i in
                Text(grams[i])
                    .font(.system(size: size * 0.115))
                    .foregroundStyle(pGoldHi)
                    .frame(width: size, height: size, alignment: .top)
                    .rotationEffect(.degrees(Double(i) * 45))
            }
            Text("☯").font(.system(size: size * 0.44)).foregroundStyle(pGold)
        }
        .frame(width: size, height: size)
    }
}

struct PosterView: View {
    let chart: BaziChart
    let name: String

    private var items: [InterpretItem] { InterpretEngine.interpret(chart: chart) }
    private var headline: String { items.first(where: { $0.title == "命局风景" })?.conclusion ?? "" }
    private var yunLine: String { items.first(where: { $0.title == "岁运要点" })?.conclusion ?? "" }

    var body: some View {
        ZStack {
            LinearGradient(colors: [pBg1, pBg0], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [pGold.opacity(0.16), .clear], center: .init(x: 0.5, y: 0.16), startRadius: 10, endRadius: 300)
            RoundedRectangle(cornerRadius: 10).stroke(pGold.opacity(0.65), lineWidth: 1.2).padding(18)
            RoundedRectangle(cornerRadius: 6).stroke(pGold.opacity(0.30), lineWidth: 0.7).padding(24)
            HStack(spacing: 0) {
                Spacer()
                VStack(spacing: 6) {
                    ForEach(Array("道法自然".enumerated()), id: \.offset) { _, ch in
                        Text(String(ch)).font(.system(size: 15, design: .serif)).foregroundStyle(pGold.opacity(0.75))
                    }
                }
                .padding(.trailing, 34).padding(.top, 90)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            VStack(spacing: 0) {
                BaguaRingView(size: 148).padding(.top, 46)
                Text("三 术 合 参").font(.system(size: 15, design: .serif)).tracking(2).foregroundStyle(pGoldHi).padding(.top, 16)
                Text("命 盘 海 报").font(.system(size: 11, design: .serif)).foregroundStyle(pSub).padding(.top, 4)

                Text(name.isEmpty ? "命盘" : name)
                    .font(.system(size: 42, weight: .semibold, design: .serif)).foregroundStyle(pPaper).padding(.top, 26)
                Text("日主 \(chart.rizhu) · 命宫 \(chart.mingGong) · 身宫 \(chart.shenGong)")
                    .font(.system(size: 12.5)).foregroundStyle(pSub).padding(.top, 6)
                Rectangle().fill(pGold.opacity(0.5)).frame(width: 120, height: 0.8).padding(.vertical, 18)

                // 四柱
                HStack(spacing: 10) {
                    ForEach(0..<4, id: \.self) { i in
                        let gz = Array(chart.pillars[i])
                        VStack(spacing: 5) {
                            Text(["年柱", "月柱", "日柱", "时柱"][i]).font(.system(size: 11)).foregroundStyle(pSub)
                            Text(String(gz[0])).font(.system(size: 33, weight: .medium, design: .serif)).foregroundStyle(i == 2 ? pGoldHi : pPaper)
                            Text(String(gz[1])).font(.system(size: 33, weight: .medium, design: .serif)).foregroundStyle(i == 2 ? pGoldHi : pPaper)
                            Text(chart.stemShiShen[i]).font(.system(size: 10.5)).foregroundStyle(pGold)
                        }
                        .frame(width: 74, height: 128)
                        .background(Color.white.opacity(0.04))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(i == 2 ? pGold.opacity(0.8) : pGold.opacity(0.28), lineWidth: i == 2 ? 1.1 : 0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

                // 五行
                VStack(spacing: 7) {
                    ForEach(Array(["木", "火", "土", "金", "水"].enumerated()), id: \.offset) { idx, e in
                        let v = chart.wuxingPercents[idx]
                        HStack(spacing: 8) {
                            Text(e).font(.system(size: 12, design: .serif)).foregroundStyle(pPaper).frame(width: 14)
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Rectangle().fill(Color.white.opacity(0.08))
                                    Rectangle().fill(wxColor[e] ?? pGold).frame(width: g.size.width * CGFloat(v) / 40.0)
                                }
                            }.frame(height: 7)
                            Text("\(Int(v.rounded()))%").font(.system(size: 11)).foregroundStyle(pSub).frame(width: 34, alignment: .trailing)
                        }
                    }
                }
                .padding(.horizontal, 52).padding(.top, 22)

                if !headline.isEmpty {
                    Text(headline)
                        .font(.system(size: 15.5, design: .serif)).foregroundStyle(pPaper)
                        .multilineTextAlignment(.center).lineSpacing(5)
                        .padding(.horizontal, 46).padding(.top, 24)
                }
                if !yunLine.isEmpty {
                    Text(yunLine)
                        .font(.system(size: 12)).foregroundStyle(pSub)
                        .multilineTextAlignment(.center).lineSpacing(4)
                        .padding(.horizontal, 52).padding(.top, 10)
                }

                // 大运
                HStack(spacing: 6) {
                    ForEach(0..<min(6, chart.dayunGanZhi.count), id: \.self) { i in
                        VStack(spacing: 2) {
                            Text(chart.dayunGanZhi[i]).font(.system(size: 12.5, design: .serif)).foregroundStyle(pPaper)
                            Text("\(chart.dayunStartYear(i))").font(.system(size: 9)).foregroundStyle(pSub)
                        }
                        .padding(.horizontal, 7).padding(.vertical, 5)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(pGold.opacity(0.3), lineWidth: 0.6))
                    }
                }.padding(.top, 22)

                Spacer()
                HStack(alignment: .bottom) {
                    VStack(spacing: 1) {
                        HStack(spacing: 1) {
                            Text("三").font(.system(size: 15, weight: .semibold, design: .serif))
                            Text("术").font(.system(size: 15, weight: .semibold, design: .serif))
                        }
                        HStack(spacing: 1) {
                            Text("合").font(.system(size: 15, weight: .semibold, design: .serif))
                            Text("参").font(.system(size: 15, weight: .semibold, design: .serif))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(pCin)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("据五典而断 · 盘面为据").font(.system(size: 11, design: .serif)).foregroundStyle(pSub)
                        Text(Date.now.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 10)).foregroundStyle(pSub.opacity(0.8))
                    }
                }
                .padding(.horizontal, 44).padding(.bottom, 40)
            }
        }
        .frame(width: 540, height: 960)
    }
}

struct PosterSheetView: View {
    let chart: BaziChart
    let name: String
    @State private var fileURL: URL?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PosterView(chart: chart, name: name)
                    .scaleEffect(0.62)
                    .frame(width: 540 * 0.62, height: 960 * 0.62)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
                if let u = fileURL {
                    ShareLink(item: u) {
                        Label("下载 / 分享海报", systemImage: "square.and.arrow.down")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent).tint(Ky.cinnabar)
                    Text("在分享菜单里选「存储图像」即存进相册；也可以直接发微信。海报为 1080×1920 高清图。")
                        .font(.caption).foregroundStyle(Ky.sub).multilineTextAlignment(.center)
                } else {
                    ProgressView("正在生成高清海报…")
                }
            }
            .padding(20)
        }
        .background(Ky.bg)
        .navigationTitle("命盘海报")
        .navigationBarTitleDisplayMode(.inline)
        .task { render() }
    }

    private func render() {
        let renderer = ImageRenderer(content: PosterView(chart: chart, name: name))
        renderer.scale = 2.0
        if let img = renderer.uiImage, let data = img.pngData() {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("poster-\(name.isEmpty ? "chart" : name).png")
            try? data.write(to: url, options: .atomic)
            fileURL = url
        }
    }
}
