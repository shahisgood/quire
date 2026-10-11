import Foundation
import UIKit
import UniformTypeIdentifiers

/// Turns picked photos and files into attachments stored as data URLs, the same shape the PWA uses.
enum AttachmentMaker {
    static let maxEdge: CGFloat = 1600
    static let maxFileBytes = 8 * 1024 * 1024

    enum Failure: LocalizedError {
        case unreadable(String), tooLarge(String)
        var errorDescription: String? {
            switch self {
            case .unreadable(let n): "\(n) could not be read."
            case .tooLarge(let n): "\(n) is larger than 8 MB."
            }
        }
    }

    /// Downscale to ≤1600 px on the long edge and re-encode as JPEG 0.86 (PNG kept when it's small and not resized).
    static func image(_ data: Data, name: String) throws -> Attachment {
        guard let img = UIImage(data: data) else { throw Failure.unreadable(name) }
        let size = img.size
        let scale = min(1, maxEdge / max(size.width, size.height, 1))
        if scale == 1, data.count < 1_500_000, let type = imageMime(data), type == "image/jpeg" || type == "image/png" {
            return Attachment(kind: .image, mime: type, name: name, size: data.count, dataUrl: dataURL(data, mime: type))
        }
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            img.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let jpeg = rendered.jpegData(compressionQuality: 0.86) else { throw Failure.unreadable(name) }
        return Attachment(kind: .image, mime: "image/jpeg", name: name, size: jpeg.count, dataUrl: dataURL(jpeg, mime: "image/jpeg"))
    }

    /// A file picked from Files. Images go through the image path; anything else is sent as-is.
    static func file(at url: URL) throws -> Attachment {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let name = url.lastPathComponent
        guard let data = try? Data(contentsOf: url) else { throw Failure.unreadable(name) }
        let type = UTType(filenameExtension: url.pathExtension)
        if type?.conforms(to: .image) == true { return try image(data, name: name) }
        guard data.count <= maxFileBytes else { throw Failure.tooLarge(name) }
        let mime = type?.preferredMIMEType ?? "application/octet-stream"
        return Attachment(kind: .file, mime: mime, name: name, size: data.count, dataUrl: dataURL(data, mime: mime))
    }

    static func dataURL(_ data: Data, mime: String) -> String { "data:\(mime);base64,\(data.base64EncodedString())" }

    static func decode(_ dataUrl: String) -> Data? {
        guard let comma = dataUrl.firstIndex(of: ",") else { return nil }
        return Data(base64Encoded: String(dataUrl[dataUrl.index(after: comma)...]))
    }

    private static func imageMime(_ d: Data) -> String? {
        let b = [UInt8](d.prefix(4))
        if b.count >= 3, b[0] == 0xFF, b[1] == 0xD8, b[2] == 0xFF { return "image/jpeg" }
        if b.count >= 4, b[0] == 0x89, b[1] == 0x50, b[2] == 0x4E, b[3] == 0x47 { return "image/png" }
        return nil
    }
}

/// Decoded thumbnails, so scrolling past images doesn't re-decode base64 on every frame.
enum ThumbnailCache {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(for a: Attachment) -> UIImage? {
        let key = a.id as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let data = AttachmentMaker.decode(a.dataUrl), let img = UIImage(data: data) else { return nil }
        cache.setObject(img, forKey: key)
        return img
    }
}
