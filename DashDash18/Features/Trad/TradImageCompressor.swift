import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Krymper et bilde fra bildebiblioteket før opplasting: lengste side 1600 px, JPEG 0,82,
/// under 3 MB (PWA: `komprimerBilde`). Retningen fra kameraet bakes inn, og ingen metadata
/// (som GPS-posisjon) følger med.
nonisolated enum TradImageCompressor {
    struct Output: Equatable, Sendable {
        let data: Data
        let width: Int
        let height: Int
    }

    enum Failure: Error, Equatable {
        case unreadable
        case tooLarge

        var message: String {
            switch self {
            case .unreadable: "Klarte ikke å lese bildet. Prøv et annet."
            case .tooLarge: "Bildet er for stort, selv etter krymping. Prøv et annet."
            }
        }
    }

    static func compress(_ data: Data) throws(Failure) -> Output {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let size = orientedSize(source) else { throw .unreadable }
        let target = TradImageSpec.targetSize(width: size.width, height: size.height)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(target.width, target.height),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw .unreadable
        }
        for quality in [TradImageSpec.quality] + TradImageSpec.fallbackQualities {
            guard let jpeg = encode(image, quality: quality) else { throw .unreadable }
            if jpeg.count <= TradImageSpec.maxBytes {
                return Output(data: jpeg, width: image.width, height: image.height)
            }
        }
        throw .tooLarge
    }

    /// Bredde og høyde slik bildet vises (EXIF-retning 5–8 bytter dem).
    private static func orientedSize(_ source: CGImageSource) -> (width: Int, height: Int)? {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let orientation = props[kCGImagePropertyOrientation] as? UInt32 ?? 1
        return (5...8).contains(orientation) ? (height, width) : (width, height)
    }

    static func encode(_ image: CGImage, quality: Double) -> Data? {
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return out as Data
    }
}
