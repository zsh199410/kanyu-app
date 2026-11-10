import SwiftUI
import ZIPFoundation
import UniformTypeIdentifiers

/// 数据备份与恢复中心：本地 ZIP 导出／导入＋ iCloud 云端同步。
/// 备份内容：人物档案 people.json、前瞻验真账本 forecasts.json、手相面相记录 palm_records.json、
/// 勘察案件 AppData/index.json、验真打标 verify-marks.json。照片原件不在包内（体积大，另行导出）。
struct BackupView: View {
    @EnvironmentObject var peopleStore: PeopleStore
    @StateObject private var forecastStore = ForecastStore()
    @StateObject private var palmStore = PalmRecordStore()
    @State private var exportURL: URL?
    @State private var importing = false
    @State private var note = ""
    @State private var icloudNote = ""

    private var docs: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    private var dateStr: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        return f.string(from: Date())
    }
    private var sourceFiles: [(name: String, url: URL)] {
        [
            ("people.json", docs.appendingPathComponent("people.json")),
            ("forecasts.json", docs.appendingPathComponent("forecasts.json")),
            ("palm_records.json", docs.appendingPathComponent("palm_records.json")),
            ("index.json", docs.appendingPathComponent("AppData/index.json")),
        ]
    }
    private var icloudAvailable: Bool { FileManager.default.ubiquityIdentityToken != nil }
    private var lastICloudBackup: String {
        let t = NSUbiquitousKeyValueStore.default.double(forKey: "kanyu.lastBackup")
        guard t > 0 else { return "尚未备份到 iCloud" }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; f.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        return "上次 iCloud 备份：" + f.string(from: Date(timeIntervalSince1970: t))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("本地备份".scriptConverted).font(.system(.headline, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
                    Text("人物 \(peopleStore.people.count) 位 · 前瞻 \(forecastStore.entries.count) 条 · 手相面相 \(palmStore.records.count) 条记录".scriptConverted)
                        .font(.caption).foregroundStyle(Ky.sub)
                    Text("导出为 Kanyu-Backup-日期.zip，可存入系统「文件」或发微信；换机后从文件导入一键恢复。照片原件不在包内。".scriptConverted)
                        .font(.caption).foregroundStyle(Ky.sub)
                    HStack(spacing: 10) {
                        Button {
                            if let u = makeBackup() { exportURL = u; note = "备份包已生成，可分享保存。" }
                            else { note = "备份失败：没有可备份的数据，或文件复制/打包失败。请检查存储空间。" }
                        } label: {
                            Label("导出备份（ZIP）".scriptConverted, systemImage: "square.and.arrow.up")
                                .font(.subheadline).fontWeight(.semibold)
                        }.buttonStyle(KyPrimaryButton())
                        if let u = exportURL {
                            ShareLink(item: u) { Label("分享".scriptConverted, systemImage: "square.and.arrow.up.on.square") }
                                .font(.subheadline).fontWeight(.semibold).foregroundStyle(Ky.qingdai)
                        }
                        Button { importing = true } label: {
                            Label("导入恢复".scriptConverted, systemImage: "square.and.arrow.down")
                                .font(.subheadline).fontWeight(.semibold)
                        }.buttonStyle(.plain).foregroundStyle(Ky.qingdai)
                    }
                    if !note.isEmpty { Text(note.scriptConverted).font(.caption).foregroundStyle(Ky.jade) }
                }.kyCard()

                VStack(alignment: .leading, spacing: 8) {
                    Text("iCloud 同步".scriptConverted).font(.system(.headline, design: .serif)).fontWeight(.bold).foregroundStyle(Ky.ink)
                    Text(icloudAvailable ? lastICloudBackup : "当前设备未登录 iCloud，云端备份不可用（先在系统设置里登录 iCloud）。".scriptConverted)
                        .font(.caption).foregroundStyle(Ky.sub)
                    HStack(spacing: 10) {
                        Button("备份到 iCloud".scriptConverted) { icloudNote = backupToICloud() }
                            .font(.subheadline).fontWeight(.semibold).foregroundStyle(Ky.qingdai)
                            .disabled(!icloudAvailable)
                        Button("从 iCloud 恢复".scriptConverted) { icloudNote = restoreFromICloud() }
                            .font(.subheadline).fontWeight(.semibold).foregroundStyle(Ky.qingdai)
                            .disabled(!icloudAvailable)
                    }
                    if !icloudNote.isEmpty { Text(icloudNote.scriptConverted).font(.caption).foregroundStyle(Ky.jade) }
                }.kyCard()

                Text("口径：备份只含本机 JSON 数据与验真打标，不含照片原件与账号证书；恢复时同 ID 记录自动跳过，不会重复导入。".scriptConverted)
                    .font(.caption2).foregroundStyle(Ky.sub)
            }
            .padding(16).padding(.bottom, 100)
        }
        .background(Ky.bg)
        .navigationTitle("数据备份与恢复".scriptConverted).navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.zip]) { r in
            if case .success(let url) = r, url.startAccessingSecurityScopedResource() {
                note = restore(from: url)
                url.stopAccessingSecurityScopedResource()
            }
        }
    }

    // MARK: - 本地 ZIP
    private func makeBackup() -> URL? {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("Kanyu-Backup-\(dateStr)", isDirectory: true)
        try? fm.removeItem(at: tmp)
        do {
            try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
            var count = 0
            for f in sourceFiles where fm.fileExists(atPath: f.url.path) {
                try fm.copyItem(at: f.url, to: tmp.appendingPathComponent(f.name))
                count += 1
            }
            if let marks = UserDefaults.standard.dictionary(forKey: "kanyu.verifyMarks.v1") {
                let data = try JSONSerialization.data(withJSONObject: marks)
                try data.write(to: tmp.appendingPathComponent("verify-marks.json"), options: .atomic)
                count += 1
            }
            guard count > 0 else {
                try? fm.removeItem(at: tmp)
                return nil
            }
        } catch {
            try? fm.removeItem(at: tmp)
            return nil
        }
        let zipURL = fm.temporaryDirectory.appendingPathComponent("Kanyu-Backup-\(dateStr).zip")
        do {
            if fm.fileExists(atPath: zipURL.path) { try fm.removeItem(at: zipURL) }
            try fm.zipItem(at: tmp, to: zipURL)
            try fm.removeItem(at: tmp)
            return zipURL
        } catch {
            try? fm.removeItem(at: tmp)
            try? fm.removeItem(at: zipURL)
            return nil
        }
    }

    private func restore(from zipURL: URL) -> String {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("Kanyu-Restore-\(Int(Date().timeIntervalSince1970))", isDirectory: true)
        do {
            try fm.unzipItem(at: zipURL, to: tmp)
        } catch {
            return "解压失败：不是有效的备份包。"
        }
        let result = importFiles(from: tmp)
        try? fm.removeItem(at: tmp)
        return result
    }

    /// 从已解开的目录导入四类数据；供 ZIP 恢复与 iCloud 恢复共用。
    private func importFiles(from dir: URL) -> String {
        let fm = FileManager.default
        var parts: [String] = []
        if let d = try? Data(contentsOf: dir.appendingPathComponent("people.json")) {
            let n = peopleStore.importData(d)
            parts.append("人物 \(n) 位")
        }
        if let d = try? Data(contentsOf: dir.appendingPathComponent("forecasts.json")) {
            let n = forecastStore.importData(d)
            parts.append("前瞻 \(n) 条")
        }
        if let d = try? Data(contentsOf: dir.appendingPathComponent("palm_records.json")) {
            var list: [PalmRecord]? = try? JSONDecoder().decode([PalmRecord].self, from: d)
            if list == nil, let w = try? JSONDecoder().decode(PalmExport.self, from: d) { list = w.records }
            if let list = list {
                var n = 0
                for r in list where !palmStore.records.contains(where: { $0.id == r.id }) {
                    palmStore.records.append(r); n += 1
                }
                if n > 0 { palmStore.save() }
                parts.append("手相面相 \(n) 条")
            }
        }
        if let d = try? Data(contentsOf: dir.appendingPathComponent("index.json")) {
            let dest = docs.appendingPathComponent("AppData/index.json")
            do {
                try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                try d.write(to: dest, options: .atomic)
                parts.append("勘察案件已恢复（重启 App 后生效）")
            } catch {
                parts.append("勘察案件恢复失败：\(error.localizedDescription)")
            }
        }
        if let d = try? Data(contentsOf: dir.appendingPathComponent("verify-marks.json")),
           let marks = try? JSONSerialization.jsonObject(with: d) as? [String: Bool] {
            UserDefaults.standard.set(marks, forKey: "kanyu.verifyMarks.v1")
            parts.append("验真打标已恢复")
        }
        return parts.isEmpty ? "包里没有可识别的数据文件。" : "已恢复：" + parts.joined(separator: " · ")
    }

    // MARK: - iCloud
    private func icloudDir() -> URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents")
    }

    private func backupToICloud() -> String {
        guard let dir = icloudDir() else { return "未登录 iCloud 或容器不可用。" }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            var n = 0
            for f in sourceFiles where fm.fileExists(atPath: f.url.path) {
                let target = dir.appendingPathComponent(f.name)
                let staging = dir.appendingPathComponent(f.name + ".pending")
                if fm.fileExists(atPath: staging.path) { try fm.removeItem(at: staging) }
                try fm.copyItem(at: f.url, to: staging)
                if fm.fileExists(atPath: target.path) {
                    _ = try fm.replaceItemAt(target, withItemAt: staging)
                } else {
                    try fm.moveItem(at: staging, to: target)
                }
                n += 1
            }
            guard n > 0 else { return "本地没有可备份的数据文件。" }
            NSUbiquitousKeyValueStore.default.set(Date().timeIntervalSince1970, forKey: "kanyu.lastBackup")
            NSUbiquitousKeyValueStore.default.synchronize()
            return "已备份 \(n) 个数据文件到 iCloud。"
        } catch {
            return "iCloud 备份未完成：\(error.localizedDescription)"
        }
     }

    private func restoreFromICloud() -> String {
        guard let dir = icloudDir() else { return "未登录 iCloud 或容器不可用。" }
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.appendingPathComponent("people.json").path)
            || fm.fileExists(atPath: dir.appendingPathComponent("forecasts.json").path) else {
            return "iCloud 里还没有备份文件。"
        }
        return importFiles(from: dir)
    }
}
