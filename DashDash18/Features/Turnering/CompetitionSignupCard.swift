import Observation
import Supabase
import SwiftUI

/// Min påmelding i én turnering (sql/032): status, meld på/av, venteliste og tilbud.
@Observable
final class CompetitionSignupModel {
    private(set) var status: CompetitionSignupStatus?
    private(set) var isWorking = false
    var error: String?

    let competitionID: UUID
    private let client: SupabaseClient?

    init(client: SupabaseClient, competitionID: UUID) {
        self.client = client
        self.competitionID = competitionID
    }

    #if DEBUG
    init(preview status: CompetitionSignupStatus) {
        client = nil
        competitionID = status.competitionID
        self.status = status
    }
    #endif

    /// En feil gir ingen feilmelding: kortet står som sist, eller vises ikke.
    func load() async {
        guard let client else { return }
        if let rows = try? await TournamentCoreQueries.signupStatus(client: client, competitionIDs: [competitionID]) {
            status = rows.first
        }
    }

    /// Gir `true` når handlingen gikk gjennom.
    @discardableResult
    func perform(_ action: SignupCard.Action) async -> Bool {
        guard let client, !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            switch action {
            case .join, .joinWaitlist:
                status = try await TournamentCoreQueries.signup(client: client, competitionID: competitionID)
            case .leave, .leaveWaitlist:
                status = try await TournamentCoreQueries.withdraw(client: client, competitionID: competitionID)
            case .accept, .decline:
                status = try await TournamentCoreQueries.respond(client: client, competitionID: competitionID,
                                                                 accept: action == .accept)
            }
            return true
        } catch {
            self.error = DataError.from(error).message
            await load()
            return false
        }
    }
}

/// Påmeldingskortet på turneringssiden. Vises ikke når turneringen ikke har påmelding for deg.
struct CompetitionSignupSection: View {
    @State private var model: CompetitionSignupModel
    let competitionName: String
    /// Etter en endring (lista og tabellen hentes på nytt).
    var onChange: () async -> Void = {}

    init(model: CompetitionSignupModel, competitionName: String, onChange: @escaping () async -> Void = {}) {
        _model = State(initialValue: model)
        self.competitionName = competitionName
        self.onChange = onChange
    }

    var body: some View {
        Group {
            if let status = model.status {
                CompetitionSignupCard(presentation: SignupCard.presentation(status), competitionName: competitionName,
                                      isWorking: model.isWorking) { action in
                    if await model.perform(action) { await onChange() }
                }
            }
        }
        .task { await model.load() }
        .alert("Det gikk ikke", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.error ?? "")
        }
    }
}

/// Selve kortet: overskrift, plassene, forklaring og knappene.
struct CompetitionSignupCard: View {
    let presentation: SignupCard.Presentation
    let competitionName: String
    var isWorking = false
    let perform: (SignupCard.Action) async -> Void

    @State private var confirming: SignupCard.Action?

    var body: some View {
        VStack(alignment: .leading, spacing: DDSpacing.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("Påmelding")
                    .ddEyebrow()
                Spacer()
                DDPill(presentation.capacity, tone: presentation.tone == .closed ? .earth : .lime,
                       systemImage: "person.2")
            }
            Text(presentation.headline)
                .font(.ddTitleSmall)
                .foregroundStyle(presentation.tone == .urgent ? Color.ddForestInk : Color.ddInk)
            if let detail = presentation.detail {
                Text(detail)
                    .font(.ddCallout)
                    .foregroundStyle(Color.ddInkSecondary)
            }
            if presentation.primary != nil || presentation.secondary != nil {
                HStack(spacing: DDSpacing.m) {
                    if let primary = presentation.primary {
                        Button(primary.title) { run(primary) }
                            .buttonStyle(.dd(.primary, fullWidth: true))
                    }
                    if let secondary = presentation.secondary {
                        Button(secondary.title) { confirming = secondary }
                            .buttonStyle(.dd(.secondary, fullWidth: true))
                    }
                }
                .disabled(isWorking)
            }
        }
        .ddCard(presentation.tone == .urgent ? .large : .standard)
        .confirmationDialog(confirmTitle, isPresented: Binding(get: { confirming != nil },
                                                               set: { if !$0 { confirming = nil } }),
                            titleVisibility: .visible, presenting: confirming) { action in
            Button(action.title, role: .destructive) { run(action) }
        } message: { action in
            Text(confirmMessage(action))
        }
    }

    private var confirmTitle: String {
        switch confirming {
        case .decline: "Avslå plassen i \(competitionName)?"
        case .leaveWaitlist: "Gå ut av ventelista?"
        default: "Meld deg av \(competitionName)?"
        }
    }

    private func confirmMessage(_ action: SignupCard.Action) -> String {
        switch action {
        case .decline: "Plassen går videre til den neste på ventelista."
        case .leaveWaitlist: "Du mister plassen i køen."
        default: "Plassen din kan gå til den første på ventelista. Rundene du har spilt, står."
        }
    }

    private func run(_ action: SignupCard.Action) {
        Task { await perform(action) }
    }
}
