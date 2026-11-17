import SwiftUI
import CryptoKit
import UniformTypeIdentifiers
import UIKit

// Opt-in sideload update UI. No automatic installation, certificate handling, or forced updates.
// Release manifest example is documented in docs/IN_APP_UPDATE_MANIFEST.md.
struct KanyuUpdateManifest: Decodable {
    let version: String
    let build: Int
    let minimumIOS: String
    let notes: String
    let ipaURL: URL
    let sha256: String
    let channel: String
}

enum KanyuUpdateError: LocalizedError {
    case insecureURL, invalidManifest, hashMismatch, invalidIPA, unsupportedOS, http(Int)
    var errorDescription: String? {
        switch self {
        case .insecureURL: return "仅允许 HTTPS 下载"
        case .invalidManifest: return "更新清单无效"
        case .hashMismatch: return "下载文件校验失败，已删除"
        case .invalidIPA: return "下载内容不是有效的 IPA ZIP 文件"
        case .unsupportedOS: return "当前 iOS 版本不满足更新要求"
        case .http(let code): return "服务器返回 HTTP \(code)"
        }
    }
}

@MainActor
final class KanyuUpdateModel: ObservableObject {
    @Published private(set) var release: KanyuUpdateManifest?
    @Published private(set) var downloadedIPA: URL?
    @Published private(set) var busy = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasUpdate = false

    // Set a dedicated, operator-controlled HTTPS endpoint before enabling this feature.
    private let manifestURL: URL
    init(manifestURL: URL) { self.manifestURL = manifestURL }

    func check() async {
        busy = true
        defer { busy = false }
        errorMessage = nil
        do {
            guard manifestURL.scheme?.lowercased() == "https" else { throw KanyuUpdateError.insecureURL }
            var request = URLRequest(url: manifestURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 20
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw KanyuUpdateError.invalidManifest }
            guard (200...299).contains(http.statusCode) else { throw KanyuUpdateError.http(http.statusCode) }
            guard data.count <= 64_000 else { throw KanyuUpdateError.invalidManifest }
            let candidate = try JSONDecoder().decode(KanyuUpdateManifest.self, from: data)
            guard candidate.ipaURL.scheme?.lowercased() == "https",
                  candidate.channel == "release" || candidate.channel == "beta",
                  candidate.sha256.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil,
                  candidate.build > 0 else { throw KanyuUpdateError.invalidManifest }
            let currentBuild = Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0
            guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= (Int(candidate.minimumIOS.split(separator: ".").first ?? "") ?? Int.max) else {
                throw KanyuUpdateError.unsupportedOS
            }
            release = candidate
            hasUpdate = candidate.build > currentBuild
            downloadedIPA = nil
        } catch { errorMessage = error.localizedDescription }
    }

    func download() async {
        guard let release, hasUpdate else { return }
        busy = true
        defer { busy = false }
        errorMessage = nil
        do {
            let (temporary, response) = try await URLSession.shared.download(from: release.ipaURL)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw KanyuUpdateError.invalidIPA
            }
            defer { try? FileManager.default.removeItem(at: temporary) }
            let bytes = try Data(contentsOf: temporary)
            guard bytes.count >= 4, bytes.prefix(2) == Data([0x50, 0x4b]) else { throw KanyuUpdateError.invalidIPA }
            let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            guard digest.caseInsensitiveCompare(release.sha256) == .orderedSame else { throw KanyuUpdateError.hashMismatch }
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent("Kanyu-\(release.version)-\(release.build).ipa")
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: temporary, to: destination)
            downloadedIPA = destination
        } catch {
            downloadedIPA = nil
            errorMessage = error.localizedDescription
        }
    }
}

struct KanyuUpdateCenterView: View {
    @StateObject private var model: KanyuUpdateModel
    @State private var showingShare = false

    init(manifestURL: URL) {
        _model = StateObject(wrappedValue: KanyuUpdateModel(manifestURL: manifestURL))
    }

    var body: some View {
        Form {
            Section("当前版本") {
                Text("\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"))")
            }
            Section("检查更新") {
                Button("检查新版本") { Task { await model.check() } }
                    .disabled(model.busy)
                if model.busy { ProgressView() }
                if let release = model.release {
                    Text("最新版本：\(release.version) (\(release.build))")
                    Text(release.notes)
                    if model.hasUpdate {
                        Button("下载 IPA") { Task { await model.download() } }.disabled(model.busy)
                    } else {
                        Text("当前已是最新版本").foregroundStyle(.secondary)
                    }
                }
                if let message = model.errorMessage { Text(message).foregroundStyle(.red) }
            }
            if model.downloadedIPA != nil {
                Section("导出安装包") {
                    Button("分享 IPA 至签名工具") { showingShare = true }
                    Text("使用系统分享面板选择签名工具或保存到文件。iOS 不允许本应用自行静默安装 IPA。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("版本更新")
        .sheet(isPresented: $showingShare) {
            if let file = model.downloadedIPA {
                KanyuUpdateShareSheet(items: [file])
            }
        }
    }
}

private struct KanyuUpdateShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
