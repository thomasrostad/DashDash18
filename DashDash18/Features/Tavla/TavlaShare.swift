import Foundation
import Observation
import Supabase
import SwiftUI

/// «Del tavla» (`sql/056_tavla_deling.sql`): en lenke til Tavla i nettleseren, dashdash18.com/tavla/KODE,
/// som tilskuere åpner fra WhatsApp uten app og uten konto. Arrangøren slår delingen på og av; da
/// trekkes koden tilbake og lenken slutter å virke. Spillerne kan dele lenken videre når den er på.
nonisolated enum TavlaShareFeature {
    /// På fra 16.10.2026: 056 er kjørt på test og `/tavla` er ute i Workeren `atten-lenker`.
    /// Kan slås av fra serveren: `ios_flags.tavla_share` (sql/068).
    static var isEnabled: Bool { !KillSwitch.isOff("tavla_share") }
}

nonisolated enum TavlaShare {
    /// «https://dashdash18.com/tavla/ABCDEFGHJK».
    static func url(_ code: String) -> URL {
        URL(string: "https://\(UniversalLink.domain)/tavla/\(code)")!
    }

    /// Teksten som følger lenken i delingsarket (WhatsApp, Meldinger).
    static func message(_ competitionName: String) -> String {
        "Følg \(competitionName) live – tabellen og scorekortene, uten app:"
    }

    /// Hva arket viser.
    enum Presentation: Equatable {
        /// Arrangøren, delingen er av: bryteren.
        case organizerOff
        /// Arrangøren, delingen er på: bryteren, lenken og «Ny lenke».
        case organizerOn(URL)
        /// Spilleren, delingen er på: lenken.
        case playerOn(URL)
        /// Spilleren, delingen er av: be arrangøren slå den på.
        case playerOff
    }

    static func presentation(code: String?, isOrganizer: Bool) -> Presentation {
        switch (code.map(url), isOrganizer) {
        case (let link?, true): .organizerOn(link)
        case (nil, true): .organizerOff
        case (let link?, false): .playerOn(link)
        case (nil, false): .playerOff
        }
    }
}

@Observable
final class TavlaShareModel {
    private(set) var code: String?
    private(set) var hasLoaded = false
    private(set) var isWorking = false
    var error: String?
    let competitionName: String
    let isOrganizer: Bool
    private let client: SupabaseClient
    private let seasonID: UUID?
    private let knownCompetitionID: UUID?

    /// Turnering med kvelder: turneringsraden finnes via sesongen.
    init(client: SupabaseClient, seasonID: UUID, competitionName: String, isOrganizer: Bool) {
        self.client = client
        self.seasonID = seasonID
        self.knownCompetitionID = nil
        self.competitionName = competitionName
        self.isOrganizer = isOrganizer
    }

    /// Liga, cup og morro: turneringen er kjent.
    init(client: SupabaseClient, competitionID: UUID, competitionName: String, isOrganizer: Bool) {
        self.client = client
        self.seasonID = nil
        self.knownCompetitionID = competitionID
        self.competitionName = competitionName
        self.isOrganizer = isOrganizer
    }

    var presentation: TavlaShare.Presentation {
        TavlaShare.presentation(code: code, isOrganizer: isOrganizer)
    }

    private func competitionID() async throws -> UUID? {
        if let knownCompetitionID { return knownCompetitionID }
        guard let seasonID else { return nil }
        return try await TournamentDeletion.competitionID(client: client, seasonID: seasonID)
    }

    private struct Competition: Encodable { let p_competition_id: UUID }
    private struct Renew: Encodable { let p_competition_id: UUID; let p_renew: Bool }

    /// Er delingen på? Lager aldri en kode.
    func load() async {
        await run { id in
            code = try await client.rpc("tavla_share_current", params: Competition(p_competition_id: id)).execute().value
        }
        hasLoaded = true
    }

    /// Bryteren: på gir lenken (den som gjelder, ellers en ny), av trekker den tilbake.
    func setEnabled(_ on: Bool) async {
        await run { id in
            if on {
                code = try await client.rpc("tavla_share_code", params: Renew(p_competition_id: id, p_renew: false))
                    .execute().value
            } else {
                try await client.rpc("tavla_share_revoke", params: Competition(p_competition_id: id)).execute()
                code = nil
            }
        }
    }

    /// «Ny lenke»: den gamle slutter å virke.
    func renew() async {
        await run { id in
            code = try await client.rpc("tavla_share_code", params: Renew(p_competition_id: id, p_renew: true))
                .execute().value
        }
    }

    private func run(_ body: (UUID) async throws -> Void) async {
        isWorking = true
        defer { isWorking = false }
        do {
            guard let id = try await competitionID() else {
                error = "Fant ikke turneringen."
                return
            }
            try await body(id)
        } catch {
            self.error = DataError.from(error).message
        }
    }
}

/// Arket bak «Del tavla»: bryteren for arrangøren, lenken og delingsarket.
struct TavlaShareSheet: View {
    @State var model: TavlaShareModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsRenew = false

    var body: some View {
        DDList {
            if model.isOrganizer {
                Section {
                    Toggle("Del tavla med en lenke", isOn: Binding(
                        get: { model.code != nil },
                        set: { on in Task { await model.setEnabled(on) } }))
                        .tint(Color.ddForestInk)
                        .disabled(model.isWorking || !model.hasLoaded)
                } footer: {
                    DDFooter("Slår du av, slutter lenken å virke med en gang. TV-koden påvirkes ikke.")
                }
            }
            linkSection
        }
        .navigationTitle("Del tavla")
        .navigationBarTitleDisplayMode(.inline)
        .ddNavigationChrome()
        .toolbar {
            DDConfirmToolbarItem { Button("Ferdig") { dismiss() } }
        }
        .task { await model.load() }
        .confirmationDialog("Lage ny lenke?", isPresented: $confirmsRenew, titleVisibility: .visible) {
            Button("Ny lenke") { Task { await model.renew() } }
        } message: {
            Text("Den gamle lenken slutter å virke. Del den nye i gruppa.")
        }
        .messageAlert("Det gikk ikke", text: $model.error)
    }

    @ViewBuilder
    private var linkSection: some View {
        switch model.presentation {
        case .organizerOn(let link), .playerOn(let link):
            Section {
                VStack(alignment: .leading, spacing: DDSpacing.s) {
                    Text(link.absoluteString.replacingOccurrences(of: "https://", with: ""))
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                    Text("Alle med lenken ser tabellen, alle runder og scorekortene, oppdatert mens det føres. Uten app og uten innlogging.")
                        .font(.ddCallout)
                        .foregroundStyle(Color.ddInkSecondary)
                }
                .padding(.vertical, DDSpacing.xs)
                ShareLink(item: link, subject: Text(model.competitionName),
                          message: Text(TavlaShare.message(model.competitionName))) {
                    Label("Del lenken", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.dd(.primary, fullWidth: true))
                if model.isOrganizer {
                    Button("Ny lenke", systemImage: "arrow.clockwise") { confirmsRenew = true }
                        .buttonStyle(.dd(.secondary, fullWidth: true))
                        .disabled(model.isWorking)
                }
            } footer: {
                DDFooter("Ingen e-post eller bilder vises. Er de siste hullene skjult mens runden går, vises de først når runden er låst.")
            }
            .listRowSeparator(.hidden)
        case .organizerOff:
            Section {
                Text("Slå på for å få en lenke du kan legge i gruppa. Den som åpner den, ser Tavla live i nettleseren, uten app.")
                    .font(.ddCallout)
                    .foregroundStyle(Color.ddInkSecondary)
            }
        case .playerOff:
            Section {
                if model.hasLoaded {
                    Text("Arrangøren har ikke slått på deling av Tavla ennå.")
                        .font(.ddCallout)
                        .foregroundStyle(Color.ddInkSecondary)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}
