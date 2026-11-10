// AskModule.swift — 约束式 AI 问答（G6，2026-11-08）
// 与 Web POST /api/ask 同口径：先由本机引擎现算事实包，再调 NAS 免费模型池
// （FreeLLMAPI，OpenAI 兼容接口）组织回答；回答只许引用事实包内容，
// 事实包里没有的明说“盘上无据”，不许编造、不许落病名、不许做寿数断语。
// App 端只调 Web 接口，不在本机调模型；离线／模型不可用时同款降级提示
// （后端返回 degraded=true＋事实包原文）。问答记录只存本机 UserDefaults，
// 使用问答时会发送问题原文和所选人物字段；服务端留存/日志策略需单独核验。
// 命主字段来自 PeopleStore，连同问题原文发往服务端。
// 本仓库不含该后端，无法从客户端确认是否建档、落库或记录日志。
import SwiftUI

struct AskFact: Decodable, Identifiable {
    var id: String { engine + "·" + field }
    let engine: String
    let field: String
    let text: String
}

struct AskResponse: Decodable {
    let answer: String
    let degraded: Bool
    let degradedReason: String?
    let refused: Bool
    let model: String?
    let facts: [AskFact]
    let caveats: [String]
    // G5 可信度标签（与 Web ask.py _confidence 同口径，封闭集合：高／中／降级／拒绝）：
    // 服务端有值时直接采用；缺失（旧响应）时按 refused／degraded／答案是否含
    // “盘上无据”同口径推导，绝不把降级答案包装成高可信。
    let confidence: String?
    let confidenceReason: String?

    enum CodingKeys: String, CodingKey {
        case answer
        case degraded
        case degradedReason = "degraded_reason"
        case refused
        case model
        case facts
        case caveats
        case confidence
        case confidenceReason = "confidence_reason"
    }

    var confidenceLabel: String {
        if refused { return "拒绝" }
        if degraded { return "降级" }
        if let c = confidence, ["高", "中", "降级", "拒绝"].contains(c) { return c }
        return "未标注"
    }

    var confidenceDetail: String {
        if let r = confidenceReason, !r.isEmpty { return r }
        if refused { return "健康落病名／寿数断语类问题，调模型前直接拒绝，不作答。" }
        if degraded { return "降级原因：" + (degradedReason ?? "未注明") + "；答案为事实包原文或提示语，非模型组织结论。" }
        return "服务端未提供逐句校验说明；请核对下方盘面事实。可信度标签不代表现实事件发生概率。"
    }
}

struct AskHistoryItem: Codable, Identifiable {
    var id: String { at + question }
    let question: String
    let answer: String
    let degraded: Bool
    let at: String
    // G5：提问当时服务端给的可信度标签＋定档依据（旧记录无此二键，解码为 nil，显示“未标注”）
    let confidence: String?
    let confidenceDetail: String?
    init(question: String, answer: String, degraded: Bool, at: String, confidence: String? = nil, confidenceDetail: String? = nil) {
        self.question = question
        self.answer = answer
        self.degraded = degraded
        self.at = at
        self.confidence = confidence
        self.confidenceDetail = confidenceDetail
    }
}

enum AskClient {
    static let endpoint = "https://bazi.vip668.xin/api/ask"
    static let transmissionNotice = "点击发送会通过 HTTPS 将问题原文发送到 bazi.vip668.xin；选中人物时，还会发送姓名、出生日期时间、性别、经度和真太阳时选项。服务端的保存期限、日志与模型转发策略无法由此客户端核实。"

    static func ask(question: String, person: Person?) async throws -> AskResponse {
        guard let url = URL(string: endpoint) else {
            throw URLError(.badURL)
        }
        var body: [String: Any] = ["question": question]
        if let p = person {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
            body["person"] = [
                "name": p.name,
                "birth": formatter.string(from: p.birthDate),
                "gender": p.gender,
                "lon": p.longitude,
                "useLongitude": p.useLongitude,
            ] as [String: Any]
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 60
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 429 {
            throw AskError.rateLimited
        }
        if code == 400 {
            throw AskError.badQuestion
        }
        guard code == 200 else {
            throw AskError.httpStatus(code)
        }
        return try JSONDecoder().decode(AskResponse.self, from: data)
    }
}

enum AskError: LocalizedError {
    case rateLimited
    case badQuestion
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .rateLimited:
            return "问得太快了，请稍等一分钟再问（每分钟最多 10 问）"
        case .badQuestion:
            return "问题须为 2–200 字"
        case .httpStatus(let code):
            return "服务器返回 \(code)"
        }
    }
}

struct AskView: View {
    @EnvironmentObject var peopleStore: PeopleStore
    @State private var selectedPerson: Person?
    @State private var question = ""
    @State private var result: AskResponse?
    @State private var busy = false
    @State private var errorText = ""
    @State private var history: [AskHistoryItem] = AskView.loadHistory()
    // UI 2.1 第6批：清空全部问答记录须确认（无导出／恢复入口）
    @State private var showClearConfirm = false

    private static let historyKey = "kanyu.ask.history.v1"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("AI 问答 · 只引引擎事实".scriptConverted)
                    .font(.title2)
                    .fontWeight(.bold)
                Text("回答只引用本机引擎现算的事实（八字／紫微／合参／奇门／梅花／称骨／五运六气／堪舆流年紫白／星命），事实包里没有的明说“盘上无据”，不编造、不落病名、不做寿数断语。".scriptConverted)
                    .font(.callout)
                    .foregroundStyle(Ky.sub)
                Picker("命主".scriptConverted, selection: $selectedPerson) {
                    Text("不选命主（通用问题）".scriptConverted).tag(nil as Person?)
                    ForEach(peopleStore.people) { p in
                        Text(p.name).tag(p as Person?)
                    }
                }
                .pickerStyle(.menu)
                Text(AskClient.transmissionNotice.scriptConverted)
                    .font(.callout).foregroundStyle(Ky.sub).lineSpacing(4)
                TextField("例如：今年换工作合适吗", text: $question)
                    .textFieldStyle(.roundedBorder)
                Button {
                    Task { await submit() }
                } label: {
                    Label(busy ? "问答中…" : "发送问题", systemImage: "bubble.left.and.text.bubble.right.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy || question.trimmingCharacters(in: .whitespaces).count < 2)
                if busy {
                    KyLoadingState(title: "正在请求问答服务，等待盘面事实与解释…")
                }
                if errorText.isEmpty == false {
                    Text(errorText.scriptConverted)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .padding(10)
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                if let r = result {
                    AskResultCard(result: r)
                }
                if history.isEmpty == false {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("本机问答记录（只存本机）".scriptConverted)
                                .font(.headline)
                            Spacer()
                            Button("清空".scriptConverted) {
                                showClearConfirm = true
                            }
                            .font(.callout)
                            .confirmationDialog("清空问答记录？".scriptConverted, isPresented: $showClearConfirm) {
                                Button("全部清空".scriptConverted, role: .destructive) {
                                    history = []
                                    AskView.saveHistory([])
                                }
                                Button("取消".scriptConverted, role: .cancel) {}
                            } message: {
                                Text("将一键清空全部本地问答记录，无导出与恢复入口；问题可重问再生。".scriptConverted)
                            }
                        }
                        ForEach(history.prefix(10)) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("问：".scriptConverted + item.question)
                                    .font(.callout)
                                    .fontWeight(.semibold)
                                Text(item.answer)
                                    .font(.callout)
                                    .foregroundStyle(Ky.sub)
                                    .lineLimit(3)
                                // G5：历史每条展示提问当时的可信度标签（旧记录显示“未标注”）
                                Text(("服务端可信度标记：" + (item.confidence ?? "未标注")).scriptConverted)
                                    .font(.caption2)
                                    .foregroundStyle(Ky.sub)
                            }
                            .padding(.vertical, 4)
                            Divider()
                        }
                    }
                }
                Text("回答、事实包和校验标签由服务端返回。请对照实际盘面核查；本客户端不能仅凭一段回答确认后端已完成校验，也不能核实服务端是否记录请求。离线或请求失败时会明确提示，不生成虚假回答。".scriptConverted)
                    .font(.caption)
                    .foregroundStyle(Ky.sub)
            }
            .padding()
        }
        .background(Ky.bg)
        .navigationTitle("AI 问答".scriptConverted)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func submit() async {
        let q = question.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return }
        busy = true
        errorText = ""
        result = nil
        do {
            let r = try await AskClient.ask(question: q, person: selectedPerson)
            result = r
            let formatter = ISO8601DateFormatter()
            let item = AskHistoryItem(question: q, answer: r.answer, degraded: r.degraded, at: formatter.string(from: Date()), confidence: r.confidenceLabel, confidenceDetail: r.confidenceDetail)
            history.insert(item, at: 0)
            history = Array(history.prefix(20))
            AskView.saveHistory(history)
        } catch {
            errorText = "提问失败：" + error.localizedDescription + "。离线时请稍后再试。"
        }
        busy = false
    }

    private static func loadHistory() -> [AskHistoryItem] {
        guard let data = UserDefaults.standard.data(forKey: historyKey) else {
            return []
        }
        return (try? JSONDecoder().decode([AskHistoryItem].self, from: data)) ?? []
    }

    private static func saveHistory(_ items: [AskHistoryItem]) {
        guard let data = try? JSONEncoder().encode(items) else {
            return
        }
        UserDefaults.standard.set(data, forKey: historyKey)
    }
}

struct AskResultCard: View {
    let result: AskResponse

    // G5 可信度标签配色（只用已有令牌／系统色，不新增色值）：高＝玉色，中＝金色，降级＝橙，拒绝＝朱砂
    private var confidenceColor: Color {
        switch result.confidenceLabel {
        case "高": return Ky.jade
        case "中": return Ky.gold
        case "降级": return .orange
        case "拒绝": return Ky.cinnabar
        default: return Ky.sub
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // G5 可信度标签：标签值＋定档依据同行可见，来源可追溯（定档依据见下方文字与事实包）
            HStack(alignment: .top, spacing: 6) {
                Text(("服务端可信度标记：" + result.confidenceLabel).scriptConverted)
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(confidenceColor.opacity(0.13))
                    .foregroundStyle(confidenceColor)
                    .clipShape(Capsule())
                Text(result.confidenceDetail.scriptConverted)
                    .font(.caption)
                    .foregroundStyle(Ky.sub)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if result.refused {
                Text("本系统不作答：健康问题不落病名，寿数断语不在五典论命范围之内。".scriptConverted)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(10)
                    .background(Color.red.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else if result.degraded {
                Text("模型暂不可用或回答未通过依据校验，以下是本机引擎现算的事实原文，仅供参考。".scriptConverted)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(10)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            if result.answer.hasPrefix("盘上无据") {
                Text(result.answer)
                    .font(.body)
                    .padding(10)
                    .background(Color.yellow.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Text(result.answer)
                    .font(.body)
            }
            if let model = result.model {
                Text(("模型：" + model + "（FreeLLMAPI 免费池）").scriptConverted)
                    .font(.caption)
                    .foregroundStyle(Ky.sub)
            }
            ForEach(result.caveats, id: \.self) { c in
                Text(("口径提示：" + c).scriptConverted)
                    .font(.caption)
                    .foregroundStyle(Ky.sub)
            }
            if result.facts.isEmpty == false {
                DisclosureGroup("依据链（\(result.facts.count) 条事实）".scriptConverted) {
                    ForEach(result.facts) { f in
                        VStack(alignment: .leading, spacing: 2) {
                            Text((f.engine + " · " + f.field).scriptConverted)
                                .font(.caption)
                                .fontWeight(.semibold)
                            Text(f.text.scriptConverted)
                                .font(.callout)
                                .foregroundStyle(Ky.sub)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .padding()
        .background(Ky.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
