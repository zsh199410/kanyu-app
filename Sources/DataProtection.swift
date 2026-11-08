// 本地数据文件级保护（UI 2.0 P5）：不改存储结构、不改格式、不迁移、不重写数据。
// iOS 默认已对 App 沙盒文件做静态加密（completeUntilFirstUserAuthentication：首次解锁前不可读）；
// 本文件只在每次保存后把四份数据文件的文件保护属性抬到 .complete（设备锁定时不可读），
// 并在启动时对已存在的文件补一次属性。全部调用均为 try?：失败时静默保留默认保护，绝不阻断保存、不丢数据。
// 不做 CryptoKit 内容加密：那会改存储格式、要迁移旧数据、丢 Key 即丢数据，违反红线 5。
import Foundation

/// 四份本机数据文件的文件级保护（与 BackupModule 备份清单同一组）。
enum DataProtection {
    /// 四份数据文件。
    static var dataFileURLs: [URL] {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return [
            docs.appendingPathComponent("people.json"),
            docs.appendingPathComponent("forecasts.json"),
            docs.appendingPathComponent("palm_records.json"),
            docs.appendingPathComponent("AppData/index.json"),
        ]
    }

    /// 把单个文件保护属性抬到 .complete（失败静默）。
    static func applyComplete(to url: URL) {
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
    }

    /// 已存在的文件补一次保护属性（只改文件元数据，不读不写文件内容；不存在的文件跳过）。
    static func protectExistingFiles() {
        for url in dataFileURLs where FileManager.default.fileExists(atPath: url.path) {
            applyComplete(to: url)
        }
    }
}
