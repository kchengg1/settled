import Foundation
import UIKit

/// Receipt photos attached to expenses. Stored as JPEG files in Application
/// Support, keyed by UUID, outside the group document (they're big, and
/// they never leave the phone unless a group is shared).
enum ReceiptImageStore {

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("receipts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func url(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).jpg")
    }

    /// Saves a downscaled JPEG and returns its ID, or nil if encoding failed.
    static func save(_ image: UIImage) -> UUID? {
        let id = UUID()
        guard let data = downscaled(image, maxDimension: 1600).jpegData(compressionQuality: 0.8) else { return nil }
        do {
            try data.write(to: url(for: id), options: .atomic)
            return id
        } catch {
            return nil
        }
    }

    static func load(_ id: UUID) -> UIImage? {
        guard let data = try? Data(contentsOf: url(for: id)) else { return nil }
        return UIImage(data: data)
    }

    static func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: url(for: id))
    }

    private static func downscaled(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
