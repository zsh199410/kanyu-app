// 系统级历史案例回测页（G16，Insight 第 3 批，2026-11-09）
//
// 数据只调自有 Web API（GET /api/backtest，与 AskModule 同款直连
// bazi.vip668.xin，不新增第三方请求、不触碰凭据、不写任何数据文件）。
// 两部分：
//   1. BaziQA 离线总账卡：194/555（比赛十七届 2010–2026 全量，
//      逐年准确率条由服务端逐年表现算，不在本机重算、不改口径）；
//   2. 个人前瞻验真汇总：本 Web 作用域前瞻登记的聚合（总数／命中／
//      未中／部分／待验／按年／按人物）＋验真打标汇总。
// 准确率口径与服务端一致：命中／（命中＋未中），「部分」单列不计
// 入分母，分母为 0 时显示「—」不冒充有结论。
// 注意：App 端请求不带 Web 登录会话，个人汇总反映的是 App 游客
// 作用域（App 端前瞻登记存在本机，不计入此处）；BaziQA 总账为离线
// 历史总账，不受作用域影响。Web 账号打通另立项，不在本批做。
// 口径：只报历史验真统计，不作未来确定性断语；C 类词 0 命中。
import SwiftUI

// MARK: - 回测接口模型（与 /api/backtest 同形，snake_case 由解码器转换）

struct BacktestGroupRow: Decodable, Identifiable {
    let key: String
    let total: Int
    let hit: Int
    let miss: Int
    let partial: Int
    let pending: Int
    let other: Int
    let decided: Int
    let accuracy: Double?
    var id: String { key }
}

struct BacktestPersonRow: Decodable, Identifiable {
    let personId: String
    let personName: String
    let total: Int
    let hit: Int
    let miss: Int
    let partial: Int
    let pending: Int
    let other: Int
    let decided: Int
    let accuracy: Double?
    var id: String { personId }
}

struct BacktestForecasts: Decodable {
    let total: Int
    let hit: Int
    let miss: Int
    let partial: Int
    let pending: Int
    let other: Int
    let decided: Int
    let accuracy: Double?
    let byYear: [BacktestGroupRow]
    let byPerson: [BacktestPersonRow]
}

struct BacktestMarks: Decodable {
    let total: Int
    let verified: Int
    let unverified: Int
    let rate: Double?
}

struct BacktestYearRow: Decodable, Identifiable {
    let year: Int
    let correct: Int
    let total: Int
    let accuracy: Double?
    var id: Int { year }
}

struct BacktestBaziqa: Decodable {
    let track: String
    let source: String
    let correct: Int
    let total: Int
    let accuracy: Double?
    let macroAccuracy: Double?
    let perYear: [BacktestYearRow]
    let randomBaselineNote: String
}

struct BacktestResponse: Decodable {
    let forecasts: BacktestForecasts
    let verifyMarks: BacktestMarks
    let baziqa: BacktestBaziqa
    let note: String
}

// MARK: - 回测接口客户端（AskModule 同款直连自有 Web API）

enum BacktestError: LocalizedError {
    case invalidURL
    case httpStatus(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "回测接口地址无效"
        case .httpStatus(let code):
            return "回测接口返回异常（\(code)），请稍后重试"
        case .invalidResponse:
            return "回测数据解析失败，请稍后重试"
        }
    }
}

enum BacktestClient {
    static let endpoint = "https://bazi.vip668.xin/api/backtest"

    static func fetch() async throws -> BacktestResponse {
        guard let url = URL(string: endpoint) else {
            throw BacktestError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 30
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            throw BacktestError.httpStatus(code)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(BacktestResponse.self, from: data)
        } catch {
            throw BacktestError.invalidResponse
        }
    }
}

// MARK: - 准确率条（一行：标题＋明细＋横条，系统动态字体、无阴影）

struct BacktestBarRow: View {
    let title: String
    let detail: String
    let accuracy: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title.scriptConverted).font(.subheadline).foregroundStyle(Ky.ink)
                Spacer()
                Text(detail.scriptConverted).font(.caption).foregroundStyle(Ky.sub)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Ky.elevated)
                    if let acc = accuracy {
                        Capsule().fill(Ky.qingdai).frame(width: geo.size.width * CGFloat(acc))
                    }
                }
            }
            .frame(height: 8)
        }
    }
}

// MARK: - 历史回测页

struct BacktestView: View {
    @State private var data: BacktestResponse?
    @State private var errorText: String?
    @State private var isLoading = false

    private func percentText(_ value: Double?) -> String {
        if let value = value {
            return String(format: "%.1f%%", value * 100)
        }
        return "—"
    }

    private func load() async {
        isLoading = true
        errorText = nil
        do {
            data = try await BacktestClient.fetch()
        } catch {
            errorText = error.localizedDescription
        }
        isLoading = false
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if isLoading && data == nil {
                    ProgressView("正在汇总回测…".scriptConverted)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 24)
                }
                if let errorText = errorText, data == nil {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("回测暂未取到".scriptConverted)
                            .font(.headline).foregroundStyle(Ky.ink)
                        Text(errorText.scriptConverted)
                            .font(.callout).foregroundStyle(Ky.sub)
                        Button("重试".scriptConverted) {
                            Task { await load() }
                        }
                        .buttonStyle(.bordered)
                    }
                    .kyCard()
                }
                if let data = data {
                    baziqaCard(data.baziqa)
                    forecastCard(data.forecasts)
                    marksCard(data.verifyMarks)
                    yearCard(data.forecasts.byYear)
                    personCard(data.forecasts.byPerson)
                    baziqaYearCard(data.baziqa.perYear, note: data.baziqa.randomBaselineNote)
                    Text(data.note.scriptConverted)
                        .font(.caption).foregroundStyle(Ky.sub)
                    Text("个人汇总反映 App 游客作用域；App 端前瞻登记存在本机，不计入此处。BaziQA 总账为离线历史总账，不受作用域影响。".scriptConverted)
                        .font(.caption).foregroundStyle(Ky.sub)
                }
            }
            .padding(.horizontal, KyV6.pageHorizontalMargin)
            .padding(.top, 6)
            .padding(.bottom, 100)
        }
        .navigationTitle("历史回测".scriptConverted)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("刷新".scriptConverted) {
                    Task { await load() }
                }
                .disabled(isLoading)
            }
        }
        .task {
            await load()
        }
    }

    private func baziqaCard(_ baziqa: BacktestBaziqa) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("BaziQA 离线总账".scriptConverted)
                    .font(.headline).foregroundStyle(Ky.ink)
                Spacer()
                Text("\(baziqa.correct) / \(baziqa.total)".scriptConverted)
                    .font(.headline).foregroundStyle(Ky.gold)
            }
            HStack(spacing: 16) {
                statItem(title: "准确率", value: percentText(baziqa.accuracy))
                statItem(title: "年均准确率", value: percentText(baziqa.macroAccuracy))
                statItem(title: "届次", value: "\(baziqa.perYear.count) 届")
            }
            Text(baziqa.source.scriptConverted)
                .font(.caption).foregroundStyle(Ky.sub)
        }
        .kyCard()
    }

    private func forecastCard(_ forecasts: BacktestForecasts) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("前瞻验真汇总".scriptConverted)
                    .font(.headline).foregroundStyle(Ky.ink)
                Spacer()
                Text("共 \(forecasts.total) 条".scriptConverted)
                    .font(.caption).foregroundStyle(Ky.sub)
            }
            if forecasts.total == 0 {
                Text("本作用域暂无前瞻登记。".scriptConverted)
                    .font(.callout).foregroundStyle(Ky.sub)
            } else {
                HStack(spacing: 16) {
                    statItem(title: "命中", value: "\(forecasts.hit)")
                    statItem(title: "未中", value: "\(forecasts.miss)")
                    statItem(title: "部分", value: "\(forecasts.partial)")
                    statItem(title: "待验", value: "\(forecasts.pending)")
                }
                HStack {
                    Text("准确率（命中／已决断）".scriptConverted)
                        .font(.callout).foregroundStyle(Ky.ink)
                    Spacer()
                    Text(percentText(forecasts.accuracy).scriptConverted)
                        .font(.callout).fontWeight(.semibold).foregroundStyle(Ky.qingdai)
                }
                if forecasts.other > 0 {
                    Text("另有 \(forecasts.other) 条已核对未分命中与否，不计入准确率。".scriptConverted)
                        .font(.caption).foregroundStyle(Ky.sub)
                }
            }
        }
        .kyCard()
    }

    private func marksCard(_ marks: BacktestMarks) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("验真打标汇总".scriptConverted)
                    .font(.headline).foregroundStyle(Ky.ink)
                Spacer()
                Text("已验 \(marks.verified) / 共 \(marks.total) 条".scriptConverted)
                    .font(.caption).foregroundStyle(Ky.sub)
            }
            HStack {
                Text("已验占比".scriptConverted)
                    .font(.callout).foregroundStyle(Ky.ink)
                Spacer()
                Text(percentText(marks.rate).scriptConverted)
                    .font(.callout).fontWeight(.semibold).foregroundStyle(Ky.qingdai)
            }
        }
        .kyCard()
    }

    private func yearCard(_ rows: [BacktestGroupRow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            KySectionTitle(title: "前瞻 · 按年份".scriptConverted, trailing: "共 \(rows.count) 组")
            if rows.isEmpty {
                Text("暂无按年份分组。".scriptConverted)
                    .font(.callout).foregroundStyle(Ky.sub)
            } else {
                ForEach(rows) { row in
                    BacktestBarRow(
                        title: "\(row.key) 年",
                        detail: "命中 \(row.hit) · 未中 \(row.miss) · 共 \(row.total) 条 · \(percentText(row.accuracy))",
                        accuracy: row.accuracy
                    )
                }
            }
        }
        .kyCard()
    }

    private func personCard(_ rows: [BacktestPersonRow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            KySectionTitle(title: "前瞻 · 按人物".scriptConverted, trailing: "共 \(rows.count) 组")
            if rows.isEmpty {
                Text("暂无按人物分组。".scriptConverted)
                    .font(.callout).foregroundStyle(Ky.sub)
            } else {
                ForEach(rows) { row in
                    BacktestBarRow(
                        title: row.personName,
                        detail: "命中 \(row.hit) · 未中 \(row.miss) · 共 \(row.total) 条 · \(percentText(row.accuracy))",
                        accuracy: row.accuracy
                    )
                }
            }
        }
        .kyCard()
    }

    private func baziqaYearCard(_ rows: [BacktestYearRow], note: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            KySectionTitle(title: "BaziQA · 按年份".scriptConverted, trailing: "共 \(rows.count) 届")
            ForEach(rows) { row in
                BacktestBarRow(
                    title: "\(row.year) 年",
                    detail: "\(row.correct) / \(row.total) · \(percentText(row.accuracy))",
                    accuracy: row.accuracy
                )
            }
            Text(note.scriptConverted)
                .font(.caption).foregroundStyle(Ky.sub)
        }
        .kyCard()
    }

    private func statItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value.scriptConverted)
                .font(.headline).foregroundStyle(Ky.ink)
            Text(title.scriptConverted)
                .font(.caption).foregroundStyle(Ky.sub)
        }
    }
}
