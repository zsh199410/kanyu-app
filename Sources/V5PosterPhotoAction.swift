import SwiftUI
import Photos

/// The saved image uses the same owner-checked formal renderer as file sharing.
/// This control never substitutes the low-resolution on-screen preview.
struct V5PosterPhotoAction: View {
    let snapshot: PosterDynamicSnapshot
    @State private var saving = false
    @State private var message: String?
    var body: some View {
        if snapshot.canArchive {
            VStack(spacing: 8) {
                Button {
                    save()
                } label: {
                    Label(saving ? "正在存入相册…" : "保存高清海报到相册", systemImage: "photo.badge.plus")
                        .frame(maxWidth: .infinity, minHeight: V5Metric.target)
                }.buttonStyle(.bordered).disabled(saving)
                    .accessibilityIdentifier("v5.poster.savePhoto")
                if let message {
                    Text(message).font(.footnote).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("v5.poster.photoReceipt")
                }
            }
        }
    }
    @MainActor private func save() {
        guard !saving, snapshot.canArchive else { return }
        saving = true; message = nil
        Task { @MainActor in
            // Request add-only access before rasterizing a long image. Denial must not
            // allocate the formal bitmap, and no read access to family photos is needed.
            let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard authorization == .authorized || authorization == .limited else {
                message = "保存失败：请在系统设置中允许添加照片后重试。"; saving = false
                return
            }
            do {
                let file = try autoreleasepool { try PosterFamilyExport.image(snapshot: snapshot) }
                // Import the original PNG bytes. Avoid a second full-size UIImage decode
                // and Photos' UIImage re-encoding; keep the file until Photos has copied it.
                PHPhotoLibrary.shared().performChanges({
                    PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: file, options: nil)
                }) { success, error in
                    DispatchQueue.main.async {
                        try? FileManager.default.removeItem(at: file)
                        message = success ? "已存入相册" : "保存失败：\(error?.localizedDescription ?? "未知原因，请检查相册权限后重试")"
                        saving = false
                    }
                }
            } catch {
                message = "保存失败：\(error.localizedDescription)"; saving = false
            }
        }
    }
}
