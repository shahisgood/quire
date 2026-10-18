import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Turns picked photos, camera shots, pasted images and files into attachments stored as data URLs,
/// the same shape the PWA uses. Decoding and resizing use ImageIO off the main thread, which also
/// handles HEIC from the photo library and applies EXIF orientation.
nonisolated enum AttachmentMaker {
    static let maxEdge = 1600
    static let maxFileBytes = 8 * 1024 * 1024

    nonisolated enum Failure: LocalizedError {
        case unreadable(String), tooLarge(String)
        var errorDescription: String? {
            switch self {
            case .unreadable(let n): "\(n) could not be read."
            case .tooLarge(let n): "\(n) is larger than 8 MB."
            }
        }
    }

    /// Downscale to ≤1600 px on the long edge and re-encode as JPEG 0.86. A small, upright JPEG or
    /// PNG that needs no resizing is kept as it is.
    @concurrent
    static func image(_ data: Data, name: String) async throws -> Attachment {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { throw Failure.unreadable(name) }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any] ?? [:]
        let w = props[kCGImagePropertyPixelWidth as String] as? Int ?? 0
        let h = props[kCGImagePropertyPixelHeight as String] as? Int ?? 0
        let orientation = props[kCGImagePropertyOrientation as String] as? Int ?? 1
        let longest = max(w, h)
        if longest > 0, longest <= maxEdge, orientation == 1, data.count < 1_500_000, let mime = imageMime(data) {
            return Attachment(kind: .image, mime: mime, name: name, size: data.count, dataUrl: dataURL(data, mime: mime))
        }
        let options: [String: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways as String: true,
            kCGImageSourceCreateThumbnailWithTransform as String: true,
            kCGImageSourceShouldCacheImmediately as String: true,
            kCGImageSourceThumbnailMaxPixelSize as String: longest > 0 ? min(maxEdge, longest) : maxEdge,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else { throw Failure.unreadable(name) }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw Failure.unreadable(name)
        }
        CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality as String: 0.86] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw Failure.unreadable(name) }
        let jpeg = out as Data
        return Attachment(kind: .image, mime: "image/jpeg", name: name, size: jpeg.count, dataUrl: dataURL(jpeg, mime: "image/jpeg"))
    }

    /// A file picked from Files. Images go through the image path; anything else is sent as-is.
    @concurrent
    static func file(at url: URL) async throws -> Attachment {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let name = url.lastPathComponent
        guard let data = try? Data(contentsOf: url) else { throw Failure.unreadable(name) }
        let type = UTType(filenameExtension: url.pathExtension)
        if type?.conforms(to: .image) == true { return try await image(data, name: name) }
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

extension AttachmentMaker {
    /// A UIImage from the camera or the pasteboard: encoded here on the main actor (UIKit), then
    /// resized off it.
    @MainActor
    static func image(_ img: UIImage, name: String) async throws -> Attachment {
        guard let data = img.jpegData(compressionQuality: 0.95) else { throw Failure.unreadable(name) }
        return try await image(data, name: name)
    }
}

/// Decoded images, so scrolling past them doesn't re-decode base64 on every frame. Message
/// thumbnails are downsampled off the main thread to the size they're shown at; a full-size image
/// is decoded only for the viewer and the composer.
enum ThumbnailCache {
    private static let cache = NSCache<NSString, UIImage>()
    private static let thumbs = NSCache<NSString, UIImage>()

    /// The full image, decoded on the spot.
    static func image(for a: Attachment) -> UIImage? {
        let key = a.id as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let data = AttachmentMaker.decode(a.dataUrl), let img = UIImage(data: data) else { return nil }
        cache.setObject(img, forKey: key)
        return img
    }

    /// A thumbnail already decoded, if there is one.
    static func cachedThumbnail(for a: Attachment) -> UIImage? {
        thumbs.object(forKey: a.id as NSString)
    }

    /// A thumbnail no more than `maxPixel` on its long edge, decoded off the main thread.
    static func thumbnail(for a: Attachment, maxPixel: CGFloat = 360) async -> UIImage? {
        let key = a.id as NSString
        if let hit = thumbs.object(forKey: key) { return hit }
        let made = await ThumbnailMaker.make(dataUrl: a.dataUrl, maxPixel: maxPixel)
        if let made { thumbs.setObject(made, forKey: key) }
        return made
    }
}

nonisolated enum ThumbnailMaker {
    @concurrent
    static func make(dataUrl: String, maxPixel: CGFloat) async -> UIImage? {
        guard let data = AttachmentMaker.decode(dataUrl),
              let src = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let opts = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixel] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts) else { return nil }
        return UIImage(cgImage: cg)
    }
}
