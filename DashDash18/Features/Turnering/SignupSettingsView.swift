import Observation
import Supabase
import SwiftUI

/// Arrangørens innstillinger for påmeldingen i én turnering (sql/031-feltene, lagres med
/// `set_competition_signup` i 032), og ventelista.
@Observable
final class SignupSettingsModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private(set) var state: LoadState = .loading
    var draft: SignupSettingsDraft
    private(set) var status: CompetitionSignupStatus?
    private(set) var waitlist: [WaitlistEntryRow] = []
    private(set) var isSaving = false
    var error: String?

    let competition: CompetitionRow
    private let client: SupabaseClient?

    init(client: SupabaseClient, competition: CompetitionRow) {
        self.client = client
        self.competition = competition
        draft = SignupSettingsDraft(.closed, entry: competition.entry, hasClub: competition.clubID != nil)
    }

    #if DEBUG
    init(preview competition: CompetitionRow, settings: CompetitionSignupSettings, status: CompetitionSignupStatus?,
         waitlist: [WaitlistEntryRow]) {
        client = nil
        self.competition = competition
        draft = SignupSettingsDraft(settings, entry: competition.entry, hasClub: competition.clubID != nil)
        self.status = status
        self.waitlist = waitlist
        state = .loaded
    }
    #endif

    func load() async {
        guard let client else { return }
        do {
            let settings = try await TournamentCoreQueries.signupSettings(client: client, competitionID: competition.id)
            draft = SignupSettingsDraft(settings, entry: competition.entry, hasClub: competition.clubID != nil)
            status = try? await TournamentCoreQueries.signupStatus(client: client, competitionIDs: [competition.id]).first
            waitlist = (try? await TournamentCoreQueries.waitlist(client: client, competitionID: competition.id)) ?? []
            state = .loaded
        } catch is CancellationError {
        } catch {
            if case .loaded = state { return }
            state = .failed(DataError.from(error).message)
        }
    }

    /// Gir `true` når innstillingene er lagret.
    func save() async -> Bool {
        if let issue = draft.issues().first {
            error = issue
            return false
        }
        guard let client, !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            try await TournamentCoreQueries.saveSignupSettings(client: client, draft.params(competitionID: competition.id))
            await load()
            return true
        } catch {
            self.error = DataError.from(error).message
            return false
        }
    }
}

struct SignupSettingsView: View {
    @State var model: SignupSettingsModel
    var loads = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        content
            .navigationTitle("Påmelding")
            .navigationBarTitleDisplayMode(.inline)
            .ddNavigationChrome()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lagre") {
                        Task { if await model.save() { dismiss() } }
                    }
                    .disabled(model.state != .loaded || model.isSaving || model.draft.isWholeClub)
                }
            }
            .task { if loads { await model.load() } }
            .messageAlert("Det gikk ikke", text: $model.error)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView("Henter påmeldingen …")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let text):
            ContentUnavailableView {
                Label("Fikk ikke hentet påmeldingen", systemImage: "wifi.exclamationmark")
            } description: {
                Text(text)
            } actions: {
                Button("Prøv igjen") { Task { await model.load() } }
                    .buttonStyle(.dd(.primary))
            }
        case .loaded:
            if model.draft.isWholeClub {
                ContentUnavailableView("Hele troppen er med", systemImage: "person.3",
                                       description: Text("Alle i klubben er med i denne turneringen, så den har ingen påmelding."))
            } else {
                form
            }
        }
    }

    private var form: some View {
        DDList {
            Section {
                Toggle("Åpen for påmelding", isOn: $model.draft.isOpen)
                Picker("Hvem kan melde seg på", selection: $model.draft.openToAnyone) {
                    Text(model.draft.hasClub ? "Medlemmer" : "Inviterte").tag(false)
                    Text("Alle").tag(true)
                }
                .pickerStyle(.segmented)
                if model.draft.openToAnyone && model.draft.hasClub {
                    Toggle("Vis i klubbens offentlige liste", isOn: $model.draft.listed)
                }
            } header: {
                DDHeader("Påmelding")
            } footer: {
                DDFooter(model.draft.openToAnyone
                         ? "Alle innloggede som har lenken kan melde seg på, også de som ikke er medlemmer. De ser rundene i turneringen når de er påmeldt."
                         : (model.draft.hasClub ? "Bare klubbens medlemmer kan melde seg på." : "Bare de du inviterer, kan melde seg på."))
            }

            Section {
                Toggle("Begrens antall", isOn: $model.draft.hasCap.animation())
                if model.draft.hasCap {
                    Stepper(value: $model.draft.maxEntrants, in: 2...5000) {
                        LabeledContent("Plasser", value: "\(model.draft.maxEntrants)")
                    }
                    Toggle("Venteliste når det er fullt", isOn: $model.draft.waitlistEnabled)
                }
            } header: {
                DDHeader("Plasser")
            } footer: {
                DDFooter(model.draft.hasCap && model.draft.waitlistEnabled
                         ? "Blir en plass ledig, får den første på ventelista tilbud om den og 48 timer på å svare. Så går tilbudet videre."
                         : "Uten tak kan alle som finner turneringen, melde seg på.")
            }

            Section {
                Toggle("Åpner", isOn: $model.draft.hasOpensAt.animation())
                if model.draft.hasOpensAt {
                    DatePicker("Fra", selection: $model.draft.opensAt)
                }
                Toggle("Stenger", isOn: $model.draft.hasClosesAt.animation())
                if model.draft.hasClosesAt {
                    DatePicker("Til", selection: $model.draft.closesAt)
                }
            } header: {
                DDHeader("Påmeldingsvindu")
            } footer: {
                if let issue = model.draft.issues().first {
                    Text(issue)
                        .font(.ddCaption)
                        .foregroundStyle(Color.ddRustText)
                } else {
                    DDFooter("Uten vindu er påmeldingen åpen til du stenger den.")
                }
            }

            if let status = model.status {
                Section {
                    LabeledContent("Påmeldt", value: SignupCard.capacityText(status))
                    if model.waitlist.isEmpty {
                        Text("Ingen står på ventelista.")
                            .foregroundStyle(Color.ddInkSecondary)
                    }
                    ForEach(model.waitlist) { entry in
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(entry.position).")
                                .font(.ddCallout.monospacedDigit())
                                .foregroundStyle(Color.ddInkSecondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.displayName)
                                if let text = entry.status() {
                                    Text(text)
                                        .font(.ddCaption)
                                        .foregroundStyle(Color.ddForestInk)
                                }
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    DDHeader("Påmeldte og venteliste")
                }
            }
        }
        .disabled(model.isSaving)
    }
}
