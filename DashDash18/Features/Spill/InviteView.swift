import CoreImage.CIFilterBuiltins
import Observation
import Supabase
import SwiftUI

/// Koden til runden (`loose_round_invite`) eller konkurransen (`competition_invite`): hentes eller lages.
@Observable
final class InviteModel {
    private(set) var code: InviteCode?
    private(set) var error: String?
    /// Hva invitasjonen gjelder: lenken og tekstene.
    let target: InviteTarget
    private let fetch: (() async throws -> InviteCode)?

    init(target: InviteTarget, fetch: @escaping () async throws -> InviteCode) {
        self.target = target
        self.fetch = fetch
    }

    convenience init(client: SupabaseClient, roundID: UUID, courseName: String?) {
        self.init(target: .round(courseName: courseName)) {
            try await LooseRoundQueries.invite(client: client, roundID: roundID)
        }
    }

    #if DEBUG
    init(preview code: InviteCode, target: InviteTarget) {
        fetch = nil
        self.target = target
        self.code = code
    }

    convenience init(preview code: InviteCode, courseName: String?) {
        self.init(preview: code, target: .round(courseName: courseName))
    }
    #endif

    func load() async {
        guard let fetch, code == nil else { return }
        do {
            code = try await fetch()
            error = nil
        } catch {
            self.error = DataError.from(error).message
        }
    }
}

/// «Inviter»: QR-kode, lenke og kode å skrive inn. Den som åpner lenken og er logget inn, blir med
/// (eller tar en gjesteplass).
struct InviteView: View {
    @State var model: InviteModel
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(spacing: DDSpacing.l) {
                if let code = model.code {
                    if let image = QRCodeImage.make(model.target.url(code).absoluteString) {
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 240)
                            .padding(DDSpacing.l)
                            .background(Color.white, in: .rect(cornerRadius: DDRadius.card))
                            .accessibilityLabel(model.target.qrLabel)
                    }
                    VStack(spacing: 4) {
                        Text("Koden")
                            .ddEyebrow()
                        Text(code.display)
                            .font(.dd(.mono, size: 30, relativeTo: .title))
                            .foregroundStyle(Color.ddInk)
                            .textSelection(.enabled)
                            .accessibilityLabel(code.value.map(String.init).joined(separator: " "))
                    }
                    ShareLink(item: model.target.shareText(code)) {
                        Label("Del invitasjonen", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.dd(.primary, fullWidth: true))
                    Button(copied ? "Kopiert" : "Kopier koden", systemImage: copied ? "checkmark" : "doc.on.doc") {
                        UIPasteboard.general.string = code.display
                        copied = true
                    }
                    .buttonStyle(.dd(.secondary, fullWidth: true))
                    Text(model.target.help)
                        .font(.ddCaption)
                        .foregroundStyle(Color.ddInkSecondary)
                        .multilineTextAlignment(.center)
                } else if let error = model.error {
                    ContentUnavailableView {
                        Label("Fikk ikke laget koden", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Prøv igjen") { Task { await model.load() } }
                            .buttonStyle(.dd(.primary))
                    }
                } else {
                    ProgressView("Lager koden …")
                        .padding(.top, 60)
                }
            }
            .padding(.horizontal, DDSpacing.gutter)
            .padding(.vertical, DDSpacing.l)
            .frame(maxWidth: .infinity)
        }
        .ddScreenBackground()
        .navigationTitle("Inviter")
        .ddNavigationChrome()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Ferdig") { dismiss() }
            }
        }
        .task { await model.load() }
    }
}

/// QR-kode av en tekst med CoreImage (Apple-rammeverk, ingen avhengighet).
nonisolated enum QRCodeImage {
    static func make(_ text: String, scale: CGFloat = 10) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
