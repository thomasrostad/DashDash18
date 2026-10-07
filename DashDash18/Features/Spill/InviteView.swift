import CoreImage.CIFilterBuiltins
import Observation
import Supabase
import SwiftUI

/// Koden til runden (`loose_round_invite`) eller konkurransen (`competition_invite`): hentes eller lages.
@Observable
final class InviteModel {
    private(set) var code: InviteCode?
    private(set) var error: String?
    /// Koden er trukket tilbake (eieren). Den virker ikke lenger.
    private(set) var isRevoked = false
    private(set) var isWorking = false
    /// Hva invitasjonen gjelder: lenken og tekstene.
    let target: InviteTarget
    private let fetch: (() async throws -> InviteCode)?
    /// Bare eieren: ny kode og «trekk tilbake» (sql/022). nil for de andre.
    let manage: Manage?

    /// Eierens handlinger på koden.
    struct Manage {
        let renew: () async throws -> InviteCode
        let revoke: () async throws -> Void
    }

    init(target: InviteTarget, manage: Manage? = nil, fetch: @escaping () async throws -> InviteCode) {
        self.target = target
        self.manage = manage
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
        manage = nil
        self.target = target
        self.code = code
    }

    convenience init(preview code: InviteCode, courseName: String?) {
        self.init(preview: code, target: .round(courseName: courseName))
    }
    #endif

    func load() async {
        guard let fetch, code == nil, !isRevoked else { return }
        do {
            code = try await fetch()
            error = nil
        } catch {
            self.error = DataError.from(error).message
        }
    }

    /// Ny kode (eieren). Den gamle slutter å virke.
    func renew() async {
        guard let manage, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            code = try await manage.renew()
            isRevoked = false
            error = nil
        } catch {
            self.error = DataError.from(error).message
        }
    }

    /// Trekker koden tilbake (eieren). Lenker og QR som er delt, slutter å virke.
    func revoke() async {
        guard let manage, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await manage.revoke()
            code = nil
            isRevoked = true
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
                    if model.manage != nil {
                        HStack {
                            Button("Ny kode") { Task { await model.renew() } }
                            Button("Trekk tilbake", role: .destructive) { Task { await model.revoke() } }
                        }
                        .buttonStyle(.dd(.text))
                        .disabled(model.isWorking)
                    }
                } else if model.isRevoked {
                    ContentUnavailableView {
                        Label("Koden er trukket tilbake", systemImage: "xmark.seal")
                    } description: {
                        Text("Lenker og QR-koder som er delt, virker ikke lenger. De som er med, er fortsatt med.")
                    } actions: {
                        Button("Lag en ny kode") { Task { await model.renew() } }
                            .buttonStyle(.dd(.primary))
                            .disabled(model.isWorking)
                    }
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
