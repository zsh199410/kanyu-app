// AskModule.swift — 约束式 AI 问答（G6，2026-11-08）
// 与 Web POST /api/ask 同口径：先由本机引擎现算事实包，再调 NAS 免费模型池
// （FreeLLMAPI，OpenAI 兼容接口）组织回答；回答只许引用事实包内容，
// 事实包里没有的明说“盘上无据”，不许编造、不许落病名、不许做寿数断语。
// App 端只调 Web 接口，不在本机调模型；离线／模型不可用时同款降级提示
// （后端返回 degraded=true＋事实包原文）。问答记录只存本机 UserDefaults，
// 问题原文不出设备、不写服务端。
// 命主用 App 本地人物（PeopleStore）：传出生时间／性别／经度给 Web 端临时现算，
// 不在 Web 端建档、不落库。
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

    enum CodingKeys: String, CodingKey {
        case answer
        case degraded
        case degradedReason = "degraded_reason"
        case refused
        case model
        case facts
        case caveats
    }
}

struct AskHistoryItem: Codable, Identifiable {
    var id: String { at + question }
    let question: String
    let answer: String
    let degraded: Bool
    let at: String
}

enum AskClient {
    static let endpoint = "https://bazi.vip668.xin/api/ask"

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
                TextField("例如：今年换工作合适吗", text: $question)
                    .textFieldStyle(.roundedBorder)
                Button {
                    Task { await submit() }
                } label: {
                    Label(busy ? "问答中…" : "提问", systemImage: "bubble.left.and.text.bubble.right.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy || question.trimmingCharacters(in: .whitespaces).count < 2)
                if busy {
                    KyLoadingState(title: "本机引擎现算事实，再请模型组织回答…")
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
                                history = []
                                AskView.saveHistory([])
                            }
                            .font(.callout)
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
                            }
                            .padding(.vertical, 4)
                            Divider()
                        }
                    }
                }
                Text("依据与金标准：系统提示词硬约束＋逐句后校验（未通过则降级返回事实包原文）；模型不可用时同样降级。问题原文不写入服务端。奇门值使／天盘星／天德口径待裁决，现行引擎按旧口径输出，问答中如实标注。金标准见 Web test_ask.py。".scriptConverted)
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
            let item = AskHistoryItem(question: q, answer: r.answer, degraded: r.degraded, at: formatter.string(from: Date()))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
