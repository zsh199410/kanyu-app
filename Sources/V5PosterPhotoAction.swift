import SwiftUI
import UIKit

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
            var temporary: URL?
            do {
                let image: UIImage = try autoreleasepool {
                    let url = try PosterFamilyExport.image(snapshot: snapshot)
                    temporary = url
                    guard let image = UIImage(contentsOfFile: url.path) else { throw PosterFamilyExport.Failure.renderingFailed }
                    return image
                }
                let file = temporary
                PosterPhotoSaver.save(image) { result in
                    if let file { try? FileManager.default.removeItem(at: file) }
                    message = result; saving = false
                }
            } catch {
                if let temporary { try? FileManager.default.removeItem(at: temporary) }
                message = "保存失败：\(error.localizedDescription)"; saving = false
            }
        }
    }
}
