import UIKit
import LinkPresentation
import UniformTypeIdentifiers
import ImageIO

/// One immutable file per presentation. SwiftUI receives the item itself instead
/// of a Boolean paired with a separately captured optional URL.
struct V5PosterSharePayload: Identifiable {
    let id = UUID()
    let url: URL
}

/// Share extensions receive the original PNG URL. Only the system header uses
/// a bounded preview; it must not decode a 10,000px poster on its presentation path.
final class V5PosterShareItem: NSObject, UIActivityItemSource {
    let url: URL
    let title: String
    let thumbnail: UIImage?
    var contentTypeIdentifier: String { UTType.png.identifier }
    private static let previewDecoder = V5ArtworkStore(byteLimit: 0)
    init(url: URL, title: String) {
        self.url = url; self.title = title
        // Formal files are immutable and short-lived. Keep their preview separate
        // from the bundled-art cache and its resource identity keys.
        thumbnail = Self.previewDecoder.image(at: url, maximumPixelSize: 320)
        super.init()
    }
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any { url }
    func activityViewController(_ activityViewController: UIActivityViewController,
                                itemForActivityType activityType: UIActivity.ActivityType?) -> Any? { url }
    func activityViewController(_ activityViewController: UIActivityViewController,
                                dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String { contentTypeIdentifier }
    func activityViewController(_ activityViewController: UIActivityViewController,
                                subjectForActivityType activityType: UIActivity.ActivityType?) -> String { title }
    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? { makeMetadata() }
    func makeMetadata() -> LPLinkMetadata {
        let metadata = LPLinkMetadata()
        metadata.title = title
        metadata.url = url; metadata.originalURL = url
        if let thumbnail {
            metadata.iconProvider = NSItemProvider(object: thumbnail)
            metadata.imageProvider = NSItemProvider(object: thumbnail)
        }
        return metadata
    }
}
