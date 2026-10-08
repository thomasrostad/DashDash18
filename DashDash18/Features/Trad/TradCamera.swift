import AVFoundation
import SwiftUI
import UIKit

/// Hvor et bilde til tråden kan komme fra. Kameraet vises bare når enheten har et
/// (ikke i simulatoren).
nonisolated enum TradImageSource: Hashable, Sendable {
    case library
    case camera

    /// Kildene i rekkefølgen knappene vises.
    static func available(cameraAvailable: Bool) -> [TradImageSource] {
        cameraAvailable ? [.camera, .library] : [.library]
    }

    var systemImage: String {
        switch self {
        case .library: "photo"
        case .camera: "camera"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .library: "Legg ved bilde"
        case .camera: "Ta bilde"
        }
    }
}

/// Gjør bildet fra kameraet om til data som går gjennom samme krymping som biblioteksbildene
/// (`TradImageCompressor`). Kvaliteten her er høy, krympingen tar seg av størrelsen.
nonisolated enum TradCameraCapture {
    static let intermediateQuality: CGFloat = 0.95

    static func imageData(from info: [UIImagePickerController.InfoKey: Any]) -> Data? {
        let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
        return image?.jpegData(compressionQuality: intermediateQuality)
    }
}

/// Kameratilgangen før kameraet åpnes. Er den nektet, viser iOS bare et svart kamera; da
/// forklarer appen det og lenker til Innstillinger i stedet.
nonisolated enum CameraAccess {
    enum Step: Equatable, Sendable {
        /// Tilgang gitt: åpne kameraet.
        case open
        /// Ikke spurt ennå: spør iOS først.
        case ask
        /// Nektet eller sperret (f.eks. skjermtid): forklar.
        case explain
    }

    static func step(for status: AVAuthorizationStatus) -> Step {
        switch status {
        case .authorized: .open
        case .notDetermined: .ask
        case .denied, .restricted: .explain
        @unknown default: .explain
        }
    }

    static let deniedTitle = "Ingen tilgang til kameraet"
    static let deniedMessage = "Slå på kameraet for Atten i Innstillinger for å ta bilder i appen."

    /// Spør om nødvendig. Gir true når kameraet kan åpnes.
    static func requestIfNeeded() async -> Bool {
        switch step(for: AVCaptureDevice.authorizationStatus(for: .video)) {
        case .open: true
        case .ask: await AVCaptureDevice.requestAccess(for: .video)
        case .explain: false
        }
    }
}

extension View {
    /// Forklaringen når kameraet er nektet, med lenke til Innstillinger.
    func cameraDeniedAlert(isPresented: Binding<Bool>) -> some View {
        modifier(CameraDeniedAlert(isPresented: isPresented))
    }
}

private struct CameraDeniedAlert: ViewModifier {
    @Binding var isPresented: Bool
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content.alert(CameraAccess.deniedTitle, isPresented: $isPresented) {
            Button("Åpne Innstillinger") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            Button("Avbryt", role: .cancel) {}
        } message: {
            Text(CameraAccess.deniedMessage)
        }
    }
}

/// `UIImagePickerController` med kameraet, presentert som `fullScreenCover`.
/// `onCapture` får JPEG-data, eller `nil` når brukeren avbryter.
struct TradCameraPicker: UIViewControllerRepresentable {
    let onCapture: (Data?) -> Void

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = ["public.image"]
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (Data?) -> Void

        init(onCapture: @escaping (Data?) -> Void) { self.onCapture = onCapture }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onCapture(TradCameraCapture.imageData(from: info))
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCapture(nil)
        }
    }
}
