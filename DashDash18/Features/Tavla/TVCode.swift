import Foundation
import Observation
import Supabase
import SwiftUI

/// TV-visning med kode (fase 26, `sql/041_tv_kode.sql`): en skjerm uten appen åpner
/// dashdash18.com/tv/KODE og viser tabellen, regnet av regelmotoren på serveren.
nonisolated enum TVCodeFeature {
    /// På siden 10.10.2026: 041 er kjørt på test, og TV-siden er ute (Workeren `atten-lenker`, prøvd med en
    /// kode mot «Test golf»).
    static let isEnabled = true
}

nonisolated enum TVCode {
    /// «https://dashdash18.com/tv/ABCDEFGHJK».
    static func url(_ code: String) -> URL {
        URL(string: "https://\(UniversalLink.domain)/tv/\(code)")!
    }

    /// «ABCDE FGHJK», lettere å lese av og skrive inn på en TV.
    static func spaced(_ code: String) -> String {
        guard code.count == 10 else { return code }
        return String(code.prefix(5)) + " " + String(code.suffix(5))
    }
}

@Observable
final class TVCodeModel {
    private(set) var code: String?
    private(set) var isWorking = false
    var error: String?
    let competitionName: String
    private let client: SupabaseClient
    private let seasonID: UUID

    init(client: SupabaseClient, seasonID: UUID, competitionName: String) {
        self.client = client
        self.seasonID = seasonID
        self.competitionName = competitionName
    }

    private struct Params: Encodable { let p_competition_id: UUID; let p_renew: Bool }
    private struct Revoke: Encodable { let p_competition_id: UUID }

    func load(renew: Bool = false) async {
        isWorking = true
        defer { isWorking = false }
        do {
            guard let id = try await TournamentDeletion.competitionID(client: client, seasonID: seasonID) else {
                error = "Fant ikke turneringen."
                return
            }
            code = try await client.rpc("tv_code", params: Params(p_competition_id: id, p_renew: renew)).execute().value
        } catch {
            self.error = DataError.from(error).message
        }
    }

    func revoke() async {
        isWorking = true
        defer { isWorking = false }
        do {
            guard let id = try await TournamentDeletion.competitionID(client: client, seasonID: seasonID) else { return }
            try await client.rpc("tv_code_revoke", params: Revoke(p_competition_id: id)).execute()
            code = nil
        } catch {
            self.error = DataError.from(error).message
        }
    }
}

/// Arket med koden: lenken, QR-koden og koden med store bokstaver, «Ny kode» og «Trekk tilbake».
struct TVCodeSheet: View {
    @State var model: TVCodeModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsRevoke = false

    var body: some View {
        DDList {
            Section {
                VStack(spacing: DDSpacing.m) {
                    if let code = model.code {
                        if let image = QRCode.image(for: TVCode.url(code).absoluteString) {
                            Image(uiImage: image)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 220)
                                .padding(DDSpacing.m)
                                .background(Color.white, in: .rect(cornerRadius: DDRadius.card))
                                .accessibilityLabel("QR-kode til TV-visningen")
                        }
                        Text(TVCode.spaced(code))
                            .font(.system(size: 30, weight: .semibold, design: .monospaced))
                            .textSelection(.enabled)
                        Text("Åpn \(UniversalLink.domain)/tv på skjermen og skriv koden, eller skann QR-koden.")
                            .font(.ddCallout)
                            .foregroundStyle(Color.ddInkSecondary)
                            .multilineTextAlignment(.center)
                    } else if model.isWorking {
                        ProgressView("Lager koden …")
                    } else {
                        Text("Ingen kode. Lag en ny for å vise tabellen på en skjerm.")
                            .font(.ddCallout)
                            .foregroundStyle(Color.ddInkSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DDSpacing.s)
            } footer: {
                DDFooter("Skjermen viser tabellen og siste runde for \(model.competitionName), og oppdateres mens det føres. Ingen innlogging, e-post eller bilder vises.")
            }
            Section {
                if let code = model.code {
                    ShareLink(item: TVCode.url(code)) {
                        Label("Del lenken", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.dd(.primary, fullWidth: true))
                }
                Button(model.code == nil ? "Lag kode" : "Ny kode", systemImage: "arrow.clockwise") {
                    Task { await model.load(renew: model.code != nil) }
                }
                .buttonStyle(.dd(.secondary, fullWidth: true))
                if model.code != nil {
                    Button("Trekk tilbake", systemImage: "xmark.circle", role: .destructive) { confirmsRevoke = true }
                        .buttonStyle(.dd(.text, fullWidth: true))
                }
            }
            .listRowSeparator(.hidden)
            .disabled(model.isWorking)
        }
        .navigationTitle("TV-kode")
        .navigationBarTitleDisplayMode(.inline)
        .ddNavigationChrome()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Ferdig") { dismiss() } }
        }
        .task { if model.code == nil { await model.load() } }
        .confirmationDialog("Trekke tilbake koden?", isPresented: $confirmsRevoke, titleVisibility: .visible) {
            Button("Trekk tilbake", role: .destructive) { Task { await model.revoke() } }
        } message: {
            Text("Skjermer som bruker koden, slutter å vise tabellen.")
        }
        .messageAlert("Det gikk ikke", text: $model.error)
    }
}
