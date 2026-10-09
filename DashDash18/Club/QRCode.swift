import CoreImage.CIFilterBuiltins
import UIKit

/// QR-kode for en tekst (lenken i en invitasjon), med Core Image. Skarp i alle størrelser: vis med
/// `.interpolation(.none)`.
nonisolated enum QRCode {
    static func image(for text: String, scale: CGFloat = 10) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
