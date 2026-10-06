import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import DashDash18

/// Krympingen før opplasting: 1600 px lengste side, JPEG, under 3 MB (traad-bilder-test.js, del 5).
struct TradImageCompressorTests {
    /// Et JPEG med striper (så det ikke komprimeres til nesten ingenting), og valgfri EXIF-retning.
    static func jpeg(width: Int, height: Int, orientation: Int? = nil) throws -> Data {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        for x in stride(from: 0, to: width, by: 16) {
            context.setFillColor(red: CGFloat(x % 256) / 255, green: 0.5, blue: CGFloat((x / 16) % 2), alpha: 1)
            context.fill(CGRect(x: x, y: 0, width: 16, height: height))
        }
        let image = try #require(context.makeImage())
        let out = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil))
        var props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.95]
        if let orientation { props[kCGImagePropertyOrientation] = orientation }
        CGImageDestinationAddImage(destination, image, props as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return out as Data
    }

    @Test func liggendeKameraBildeBlir1600x1200() throws {
        let output = try TradImageCompressor.compress(Self.jpeg(width: 4032, height: 3024))
        #expect(output.width == 1600 && output.height == 1200)
        #expect(output.data.count <= TradImageSpec.maxBytes)
        // JPEG starter med FF D8.
        #expect(output.data.prefix(2) == Data([0xFF, 0xD8]))
    }

    @Test func staaendeBlir1200x1600() throws {
        let output = try TradImageCompressor.compress(Self.jpeg(width: 3024, height: 4032))
        #expect(output.width == 1200 && output.height == 1600)
    }

    @Test func retningenFraKameraetBakesInn() throws {
        // Lagret liggende, men EXIF 6 sier «roter 90°»: vises stående.
        let output = try TradImageCompressor.compress(Self.jpeg(width: 4032, height: 3024, orientation: 6))
        #expect(output.width == 1200 && output.height == 1600)
        let source = try #require(CGImageSourceCreateWithData(output.data as CFData, nil))
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        #expect((props?[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
    }

    @Test func smaaBilderBlaasesIkkeOpp() throws {
        let output = try TradImageCompressor.compress(Self.jpeg(width: 800, height: 600))
        #expect(output.width == 800 && output.height == 600)
    }

    @Test func oedelagtFilGirMelding() {
        #expect(throws: TradImageCompressor.Failure.unreadable) {
            try TradImageCompressor.compress(Data("ikke et bilde".utf8))
        }
        #expect(TradImageCompressor.Failure.unreadable.message.contains("Prøv et annet"))
    }
}
