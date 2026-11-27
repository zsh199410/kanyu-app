import SwiftUI
import UniformTypeIdentifiers
import CryptoKit
import ZIPFoundation

/// A local IPA inspector, never an installer or signing service.
struct V5UpdatePage: View {
    @State private var importing = false
    @State private var inspecting = false
    @State private var package: V5LibraryIPAReceipt?
    @State private var status = "尚未选择安装包。"
    @State private var worker: Task<Void, Never>?
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未提供" }
    private var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "未提供" }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: V5Metric.gap) {
                V5Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("版本与安装包").font(.system(.largeTitle, design: .serif))
                        Text("本机版本 \(version) · 构建 \(build)").font(.headline)
                        Text("当前没有配置可验证的更新源，无法判断是否存在新版本。这里不会显示未经验证的更新提示。")
                    }
                }
                V5Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("自备 IPA · 交给 LCsign").font(.title2)
                        Text("从文件中选择你信任的 IPA。本机会创建独立临时副本，流式计算 SHA-256，并检查 ZIP 校验及主应用信息。通过后可用系统分享交给已安装且支持接收文件的 LCsign，或保存到文件再手动导入。")
                        Button { importing = true } label: { Label("选择 IPA 文件", systemImage: "folder").frame(minHeight: V5Metric.target) }.disabled(inspecting)
                        if inspecting {
                            ProgressView("正在复制与检查文件")
                            Button("取消检查") { worker?.cancel() }.frame(minHeight: V5Metric.target)
                        }
                        Text(status).font(.subheadline).accessibilityIdentifier("v5.update.status")
                    }
                }
                if let package {
                    V5Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(package.name).font(.title2)
                            Text("版本 \(package.version) · 构建 \(package.build)")
                            Text(package.bundleID).font(.subheadline).textSelection(.enabled)
                            Text("\(package.bytes.formatted()) 字节").font(.caption)
                            Text("SHA-256\n\(package.sha256)").font(.caption.monospaced()).textSelection(.enabled)
                            Text("ZIP 内容校验通过。哈希只用于核对文件一致性，不证明来源可信、签名有效或适合当前设备。")
                                .font(.footnote)
                            ShareLink(item: package.url) { Label("分享 IPA 文件", systemImage: "square.and.arrow.up").frame(minHeight: V5Metric.target) }
                        }
                    }
                }
                Text("本页不签名、不读取证书，也不会直接安装应用。覆盖安装前请先使用数据备份功能保存档案。临时副本由系统管理，重新进入后需重新选择文件。")
                    .font(.footnote).foregroundStyle(V5Palette.color(V5Palette.current.secondary))
            }.padding(V5Metric.page)
        }
        .background(V5Palette.color(V5Palette.current.paper)).foregroundStyle(V5Palette.color(V5Palette.current.ink))
        .navigationTitle("版本与 IPA").navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "ipa") ?? .data]) { result in
            switch result {
            case .failure(let error): status = "未导入：\(error.localizedDescription)"
            case .success(let url): inspect(url)
            }
        }
        .onDisappear { worker?.cancel() }
    }
    private func inspect(_ url: URL) {
        worker?.cancel()
        package = nil; inspecting = true; status = "正在检查，请保持本页打开。"
        worker = Task {
            let background = Task.detached(priority: .utility) { try V5LibraryIPAInspector.inspect(url) }
            do {
                let receipt = try await withTaskCancellationHandler(operation: { try await background.value }, onCancel: { background.cancel() })
                guard !Task.isCancelled else { try? FileManager.default.removeItem(at: receipt.url.deletingLastPathComponent()); inspecting = false; return }
                package = receipt; status = "已完成本机文件检查，可核对版本后分享。"; inspecting = false
            } catch {
                inspecting = false
                status = error is CancellationError ? "已取消，未完成的副本已清理。" : "检查未通过：\(error.localizedDescription)"
            }
        }
    }
}

struct V5LibraryIPAReceipt {
    let url: URL
    let name: String
    let version: String
    let build: String
    let bundleID: String
    let bytes: Int64
    let sha256: String
}

enum V5LibraryIPAInspector {
    private struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    static func inspect(_ source: URL) throws -> V5LibraryIPAReceipt {
        let fm = FileManager.default
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        guard source.pathExtension.lowercased() == "ipa" else { throw Failure(message: "请选择 .ipa 文件。") }
        let attributes = try fm.attributesOfItem(atPath: source.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw Failure(message: "安装包必须是普通文件。") }
        let root = fm.temporaryDirectory.appendingPathComponent("V5-IPA-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        var completed = false
        defer { if !completed { try? fm.removeItem(at: root) } }
        let copy = root.appendingPathComponent("Package.ipa")
        // Copy in bounded chunks so large security-scoped providers never allocate the IPA in memory.
        guard fm.createFile(atPath: copy.path, contents: nil) else { throw Failure(message: "无法创建安装包副本。") }
        let input = try FileHandle(forReadingFrom: source)
        let output = try FileHandle(forWritingTo: copy)
        defer { try? input.close(); try? output.close() }
        var total: Int64 = 0
        var hash = SHA256()
        while true {
            try Task.checkCancellation()
            guard let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty else { break }
            total += Int64(chunk.count)
            guard total <= 2_147_483_648 else { throw Failure(message: "安装包超过本机检查上限（2 GB）。") }
            try output.write(contentsOf: chunk)
            hash.update(data: chunk)
        }
        try output.synchronize()
        try output.close()
        guard total > 0 else { throw Failure(message: "安装包为空。") }
        try fm.setAttributes([.posixPermissions: 0o400], ofItemAtPath: copy.path)
        let archive = try Archive(url: copy, accessMode: .read)
        var appInfo: Data?
        var unpacked: UInt64 = 0
        var streamed: UInt64 = 0
        var count = 0
        var paths = Set<String>()
        var executablePaths = Set<String>()
        var mainInfoPath: String?
        for entry in archive {
            try Task.checkCancellation()
            count += 1
            guard count <= 100_000, paths.insert(entry.path).inserted else { throw Failure(message: "ZIP 条目过多或包含重复路径。") }
            let components = entry.path.split(separator: "/", omittingEmptySubsequences: false)
            guard !entry.path.isEmpty, !entry.path.hasPrefix("/"), !entry.path.contains("\\"), !components.contains(".."), !components.contains("."), !components.dropLast().contains("") else { throw Failure(message: "ZIP 包含不安全的路径。") }
            let expanded = unpacked.addingReportingOverflow(UInt64(entry.uncompressedSize))
            guard !expanded.overflow, expanded.partialValue <= 4_294_967_296 else { throw Failure(message: "展开内容超过检查上限（4 GB）。") }
            unpacked = expanded.partialValue
            let isMainInfo = components.count == 3 && components[0] == "Payload" && components[1].hasSuffix(".app") && components[2] == "Info.plist"
            if isMainInfo {
                guard appInfo == nil, entry.type == .file, entry.uncompressedSize <= 2_097_152 else { throw Failure(message: "主应用 Info.plist 缺失、重复或过大。") }
            }
            var info = Data()
            var entryBytes: UInt64 = 0
            let crc = try archive.extract(entry, bufferSize: 65_536, skipCRC32: false) { chunk in
                try Task.checkCancellation()
                let nextEntry = entryBytes.addingReportingOverflow(UInt64(chunk.count))
                let nextTotal = streamed.addingReportingOverflow(UInt64(chunk.count))
                guard !nextEntry.overflow, nextEntry.partialValue <= UInt64(entry.uncompressedSize),
                      !nextTotal.overflow, nextTotal.partialValue <= 4_294_967_296 else {
                    throw Failure(message: "实际展开内容超过声明大小或检查上限。")
                }
                entryBytes = nextEntry.partialValue
                streamed = nextTotal.partialValue
                if isMainInfo {
                    guard info.count + chunk.count <= 2_097_152 else { throw Failure(message: "应用信息过大。") }
                    info.append(chunk)
                }
            }
            guard entryBytes == UInt64(entry.uncompressedSize) else { throw Failure(message: "ZIP 实际内容大小与声明不符。") }
            guard crc == entry.checksum else { throw Failure(message: "ZIP 内容 CRC 校验失败。") }
            if entry.type == .file && entry.uncompressedSize > 0 { executablePaths.insert(entry.path) }
            if isMainInfo { appInfo = info; mainInfoPath = entry.path }
        }
        guard let data = appInfo,
              let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let identifier = plist["CFBundleIdentifier"] as? String, !identifier.isEmpty,
              let executable = plist["CFBundleExecutable"] as? String, !executable.isEmpty,
              plist["CFBundlePackageType"] as? String == "APPL" else { throw Failure(message: "未发现有效的 Payload 主应用信息。") }
        guard !executable.contains("/"), !executable.contains("\\"), executable != "..", executable != ".",
              let mainInfoPath,
              executablePaths.contains(String(mainInfoPath.dropLast("Info.plist".count)) + executable) else {
            throw Failure(message: "主应用可执行文件缺失或路径不合法。")
        }
        try Task.checkCancellation()
        completed = true
        return V5LibraryIPAReceipt(url: copy, name: plist["CFBundleDisplayName"] as? String ?? plist["CFBundleName"] as? String ?? "IPA 应用",
            version: plist["CFBundleShortVersionString"] as? String ?? "未提供", build: plist["CFBundleVersion"] as? String ?? "未提供",
            bundleID: identifier, bytes: total, sha256: hash.finalize().map { String(format: "%02x", $0) }.joined())
    }
}
