// 盲测模式（Insight 第 3 批 G15，2026-11-09）
// 题目一律运行时调自有 Web 端盲测接口获取（GET /api/blindtest/quiz），
// 交卷走 POST /api/blindtest/submit 服务端判分；App 包内不内置任何题库明文。
// 计分口径与 BaziQA eval/score.py 一致：只认裸选项字母，未作答按错计，
// 多答案题任一命中即对；得分只计当轮，离线总账基线 194/555 不改写。
// 得分与最近一次结果只存本机 UserDefaults（键 kanyu-blindtest-last），不落库。
// 出题响应不含答案：App 在交卷前拿不到任何标准答案，解析只在交卷后展示。
import SwiftUI

// MARK: - 服务端模型（字段名与接口 JSON 一字一致）

struct BlindOption: Decodable {
    let letter: String
    let text: String
}

struct BlindBirth: Decodable {
    let year: Int?
    let month: Int?
    let day: Int?
    let hour: Int?
    let minute: Int?
    let place: String
    let time_raw: String
}

struct BlindSetter: Decodable {
    let name: String
    let method: String
}

struct BlindPerson: Decodable {
    let person_id: String
    let name: String
    let birth: BlindBirth
    let context: [String]
    let setter: BlindSetter
}

struct BlindQuestion: Decodable, Identifiable {
    let question_id: String
    let year: Int
    let edition: Int?
    let person: BlindPerson
    let question: String
    let options: [BlindOption]
    let option_count: Int

    var id: String { question_id }
}

struct BlindBaseline: Decodable {
    let score: Int
    let total: Int
    let accuracy: Double
}

struct BlindQuizResponse: Decodable {
    let count: Int
    let total: Int
    let baseline: BlindBaseline
    let questions: [BlindQuestion]
}

struct BlindResultItem: Decodable, Identifiable {
    let question_id: String
    let year: Int
    let question: String
    let person_name: String
    let your: String
    let correct_answers: [String]
    let correct: Bool
    let note: String

    var id: String { question_id }
}

struct BlindSubmitResponse: Decodable {
    let score: Int
    let total: Int
    let accuracy: Double
    let unanswered: Int
    let baseline: BlindBaseline
    let results: [BlindResultItem]
}

// MARK: - 客户端（只调自有 Web API，与 AskClient 同式）

enum BlindTestError: LocalizedError {
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .httpStatus(let code):
            return "服务器返回 \(code)"
        }
    }
}

enum BlindTestClient {
    static let quizEndpoint = "https://bazi.vip668.xin/api/blindtest/quiz"
    static let submitEndpoint = "https://bazi.vip668.xin/api/blindtest/submit"

    static func fetchQuiz(count: Int) async throws -> BlindQuizResponse {
        let urlString = "\(quizEndpoint)?n=\(count)"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 60
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            throw BlindTestError.httpStatus(code)
        }
        return try JSONDecoder().decode(BlindQuizResponse.self, from: data)
    }

    static func submit(answers: [String: String]) async throws -> BlindSubmitResponse {
        guard let url = URL(string: submitEndpoint) else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 60
        req.httpBody = try JSONSerialization.data(withJSONObject: ["answers": answers])
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            throw BlindTestError.httpStatus(code)
        }
        return try JSONDecoder().decode(BlindSubmitResponse.self, from: data)
    }
}

// MARK: - 盲测页

enum BlindPhase {
    case setup
    case answering
    case result
}

struct BlindTestView: View {
    private static let lastKey = "kanyu-blindtest-last"

    @State private var phase: BlindPhase = .setup
    @State private var countChoice = 10
    @State private var quiz: BlindQuizResponse?
    @State private var answers: [String: String] = [:]
    @State private var currentIndex = 0
    @State private var result: BlindSubmitResponse?
    @State private var busy = false
    @State private var errorText = ""

    private var questions: [BlindQuestion] {
        if let q = quiz {
            return q.questions
        }
        return []
    }

    private var unansweredCount: Int {
        var n = 0
        for q in questions {
            if answers[q.question_id] == nil {
                n += 1
            }
        }
        return n
    }

    private var lastLine: String {
        let rec = UserDefaults.standard.dictionary(forKey: Self.lastKey)
        if let rec = rec {
            let score = rec["score"] as? Int ?? 0
            let total = rec["total"] as? Int ?? 0
            let at = rec["at"] as? String ?? ""
            if total > 0 {
                return "上次：\(score) / \(total)（\(at)）"
            }
        }
        return ""
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("盲测模式".scriptConverted)
                    .font(.title2)
                    .fontWeight(.bold)
                Text("从 BaziQA 离线题库（555 题公开竞赛真题）随机抽题，逐题作答后交卷，服务端按同一计分口径判分。作答时看不到答案与解析，解析只在交卷后展示。".scriptConverted)
                    .font(.callout)
                    .foregroundStyle(Ky.sub)
                if busy {
                    KyLoadingState(title: "正在出题…")
                }
                if errorText.isEmpty == false {
                    Text(errorText.scriptConverted)
                        .font(.callout)
                        .foregroundStyle(Ky.cinnabar)
                }
                switch phase {
                case .setup:
                    setupSection
                case .answering:
                    answeringSection
                case .result:
                    resultSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 100)
        }
        .background(Ky.bg)
        .navigationTitle("盲测模式".scriptConverted)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var setupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("每轮题数".scriptConverted)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Ky.ink)
            Picker("每轮题数".scriptConverted, selection: $countChoice) {
                Text("5 题".scriptConverted).tag(5)
                Text("10 题".scriptConverted).tag(10)
                Text("20 题".scriptConverted).tag(20)
            }
            .pickerStyle(.segmented)
            Text("题库共 555 题 · 离线总账基线 194/555（约 35%），本轮得分只计当轮。".scriptConverted)
                .font(.callout)
                .foregroundStyle(Ky.sub)
            if lastLine.isEmpty == false {
                Text(lastLine.scriptConverted)
                    .font(.callout)
                    .foregroundStyle(Ky.sub)
            }
            Button {
                Task { await startRound() }
            } label: {
                Label(busy ? "出题中…" : "开始盲测", systemImage: "eye.slash.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(busy)
        }
        .padding(14)
        .background(Ky.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Ky.line, lineWidth: 0.8))
    }

    @ViewBuilder
    private var answeringSection: some View {
        if questions.isEmpty {
            KyEmptyState(icon: "questionmark.circle", title: "还没有题目", message: "请返回重新出题。")
        } else {
            let q = questions[currentIndex]
            VStack(alignment: .leading, spacing: 10) {
                Text("第 \(currentIndex + 1) / \(questions.count) 题 · \(String(q.year)) 年")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Ky.gold)
                Text(personLine(q.person))
                    .font(.callout)
                    .foregroundStyle(Ky.sub)
                ForEach(q.person.context, id: \.self) { line in
                    Text(line.scriptConverted)
                        .font(.callout)
                        .foregroundStyle(Ky.sub)
                }
                Text(q.question.scriptConverted)
                    .font(.headline)
                    .foregroundStyle(Ky.ink)
                ForEach(q.options, id: \.letter) { opt in
                    Button {
                        answers[q.question_id] = opt.letter
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Text(opt.letter)
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundStyle(Ky.gold)
                                .frame(width: 24, height: 24)
                                .background(Ky.gold.opacity(0.13))
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            Text(opt.text.scriptConverted)
                                .font(.callout)
                                .foregroundStyle(Ky.ink)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            if answers[q.question_id] == opt.letter {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Ky.qingdai)
                            }
                        }
                        .padding(12)
                        .background(Ky.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(borderColor(q, opt), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(Ky.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Ky.line, lineWidth: 0.8))
            HStack(spacing: 12) {
                Button("上一题".scriptConverted) {
                    if currentIndex > 0 {
                        currentIndex -= 1
                    }
                }
                .buttonStyle(.bordered)
                .disabled(currentIndex == 0)
                Button("下一题".scriptConverted) {
                    if currentIndex < questions.count - 1 {
                        currentIndex += 1
                    }
                }
                .buttonStyle(.bordered)
                .disabled(currentIndex >= questions.count - 1)
                Spacer()
            }
            Button {
                Task { await submitRound() }
            } label: {
                Label(submitLabel, systemImage: "paperplane.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(busy || questions.isEmpty)
        }
    }

    private var submitLabel: String {
        if unansweredCount == 0 {
            return "交卷"
        }
        return "交卷（还有 \(unansweredCount) 题未答，未答按错计）"
    }

    private func borderColor(_ q: BlindQuestion, _ opt: BlindOption) -> Color {
        if answers[q.question_id] == opt.letter {
            return Ky.qingdai
        }
        return Ky.line
    }

    private func personLine(_ p: BlindPerson) -> String {
        var line = p.name
        let b = p.birth
        if let year = b.year {
            line += " · \(year)年"
            if let month = b.month {
                line += String(month) + "月"
                if let day = b.day {
                    line += String(day) + "日"
                }
            }
            if b.time_raw.isEmpty == false {
                line += " " + b.time_raw
            }
        }
        if b.place.isEmpty == false {
            line += " · " + b.place
        }
        if p.setter.method.isEmpty == false {
            line += " · 出题方法：" + p.setter.method
        }
        return line
    }

    @ViewBuilder
    private var resultSection: some View {
        if let r = result {
            VStack(alignment: .leading, spacing: 10) {
                Text("得分：\(r.score) / \(r.total)")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(Ky.ink)
                Text("本轮正确率 \(percentText(r.accuracy)) · 离线总账基线 194/555（约 35%），本轮得分只计当轮。")
                    .font(.callout)
                    .foregroundStyle(Ky.sub)
                if r.unanswered > 0 {
                    Text("其中 \(r.unanswered) 题未作答，按错计。")
                        .font(.callout)
                        .foregroundStyle(Ky.sub)
                }
                Button("再测一轮") {
                    phase = .setup
                    quiz = nil
                    answers = [:]
                    currentIndex = 0
                    result = nil
                    errorText = ""
                }
                .buttonStyle(.bordered)
            }
            .padding(14)
            .background(Ky.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Ky.line, lineWidth: 0.8))
            ForEach(r.results) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.correct ? "答对" : "答错")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(item.correct ? Ky.jade : Ky.cinnabar)
                    Text(item.question.scriptConverted)
                        .font(.subheadline)
                        .foregroundStyle(Ky.ink)
                    Text("命主：\(item.person_name) · \(String(item.year)) 年")
                        .font(.caption)
                        .foregroundStyle(Ky.sub)
                    Text("你的答案：\(yourText(item))　正确答案：\(item.correct_answers.joined(separator: "、"))")
                        .font(.callout)
                        .foregroundStyle(Ky.ink)
                    if item.note.isEmpty == false {
                        Text("附注：" + item.note)
                            .font(.callout)
                            .foregroundStyle(Ky.sub)
                    }
                }
                .padding(14)
                .background(Ky.card)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Ky.line, lineWidth: 0.8))
            }
        }
    }

    private func yourText(_ item: BlindResultItem) -> String {
        if item.your.isEmpty {
            return "未作答"
        }
        return item.your
    }

    private func percentText(_ accuracy: Double) -> String {
        let value = accuracy * 100
        return String(format: "%.1f%%", value)
    }

    private func startRound() async {
        busy = true
        errorText = ""
        do {
            let out = try await BlindTestClient.fetchQuiz(count: countChoice)
            quiz = out
            answers = [:]
            currentIndex = 0
            result = nil
            phase = .answering
        } catch {
            errorText = error.localizedDescription
        }
        busy = false
    }

    private func submitRound() async {
        busy = true
        errorText = ""
        do {
            let out = try await BlindTestClient.submit(answers: answers)
            result = out
            phase = .result
            let rec: [String: Any] = ["score": out.score, "total": out.total, "at": ISO8601DateFormatter().string(from: Date())]
            UserDefaults.standard.set(rec, forKey: Self.lastKey)
        } catch {
            errorText = error.localizedDescription
        }
        busy = false
    }
}
