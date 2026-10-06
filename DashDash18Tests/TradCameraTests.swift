import Foundation
import Testing
import UIKit
@testable import DashDash18

/// Kamera i tråden: hvilke kilder som vises, og at kamerabildet går gjennom samme krymping.
struct TradCameraTests {
    @Test func utenKameraVisesBareBiblioteket() {
        #expect(TradImageSource.available(cameraAvailable: false) == [.library])
    }

    @Test func medKameraVisesKameraFoerBiblioteket() {
        #expect(TradImageSource.available(cameraAvailable: true) == [.camera, .library])
    }

    @Test func knappeneHarNorskTekstOgIkon() {
        #expect(TradImageSource.camera.accessibilityLabel == "Ta bilde")
        #expect(TradImageSource.library.accessibilityLabel == "Legg ved bilde")
        #expect(TradImageSource.camera.systemImage == "camera")
        #expect(TradImageSource.library.systemImage == "photo")
    }

    @Test func kamerabildetKrympesSomBiblioteksbilder() throws {
        let image = try #require(UIImage(data: TradImageCompressorTests.jpeg(width: 4032, height: 3024)))
        let data = try #require(TradCameraCapture.imageData(from: [.originalImage: image]))
        let output = try TradImageCompressor.compress(data)
        #expect(output.width == 1600 && output.height == 1200)
        #expect(output.data.count <= TradImageSpec.maxBytes)
    }

    @Test func redigertBildeVinnerOverOriginalen() throws {
        let original = try #require(UIImage(data: TradImageCompressorTests.jpeg(width: 400, height: 300)))
        let edited = try #require(UIImage(data: TradImageCompressorTests.jpeg(width: 300, height: 300)))
        let data = try #require(TradCameraCapture.imageData(from: [.originalImage: original, .editedImage: edited]))
        let output = try TradImageCompressor.compress(data)
        #expect(output.width == 300 && output.height == 300)
    }

    @Test func utenBildeGirIngenData() {
        #expect(TradCameraCapture.imageData(from: [:]) == nil)
    }
}
