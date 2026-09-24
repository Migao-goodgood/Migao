import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Produces bounded, orientation-correct JPEGs before they enter a draft.
/// Re-encoding strips location/other original metadata; picker originals stay
/// in Photos and are never modified.
enum DietPhotoPreparation {
    enum Failure: LocalizedError {
        case unreadable, encodingFailed, tooLarge

        var errorDescription: String? {
            switch self {
            case .unreadable: return "有照片无法读取，请重新选择。"
            case .encodingFailed: return "照片处理失败，请重新选择。"
            case .tooLarge: return "照片仍然过大，请选择较小的照片。"
            }
        }
    }

    static func prepare(_ data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1_600,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw Failure.unreadable }
        let buffer = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            buffer, UTType.jpeg.identifier as CFString, 1, nil
        ) else { throw Failure.encodingFailed }
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: 0.82
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Failure.encodingFailed }
        guard buffer.length <= MealImageMetadata.maxImageBytes else { throw Failure.tooLarge }
        return buffer as Data
    }
}
