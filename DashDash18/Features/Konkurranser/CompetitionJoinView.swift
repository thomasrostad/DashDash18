import Observation
import Supabase
import SwiftUI

/// Meldingen som går når du har blitt med i en turnering med en kode eller lenke: lister over
/// turneringer henter på nytt, og en ny bruker uten klubb får vennemodus (`OpenAppGate.automaticChoice`).
nonisolated enum CompetitionJoinEvents {
    static let joined = Notification.Name("DashDash18.competitionJoined")
}

/// «Har du en kode?» i en privat konkurranse (sql/022): koden fra lenken, QR eller skrevet inn,
/// hva konkurransen er (navn, type, eier og antall påmeldte), og «Bli med», som melder deg på.
/// En klubbturnering (sql/060) viser klubben og de ledige deltakernavnene: velg ditt, eller meld deg
/// på som ny deltaker.
@Observable
final class JoinCompetitionModel {
    enum Step: Equatable {
        case enterCode
        case loading
        case preview(CompetitionInvitePreview)
        case joined(CompetitionInvitePreview)
        case failed(String)
    }

    /// Valget i en klubbturnering med ledige navn.
    enum NameChoice: Equatable {
        case name(CompetitionInvitePreview.OpenName)
        /// «Jeg står ikke på lista»: meld meg på som ny deltaker.
        case notListed
    }

    var codeText: String
    private(set) var step: Step
    private(set) var isJoining = false
    var joinError: String?
    var choice: NameChoice?
    var nameQuery = ""
    private(set) var code: InviteCode?
    private let client: SupabaseClient?

    init(client: SupabaseClient, code: InviteCode?) {
        self.client = client
        self.code = code
        codeText = code?.display ?? ""
        step = code == nil ? .enterCode : .loading
    }

    #if DEBUG
    init(preview: CompetitionInvitePreview, code: InviteCode) {
        client = nil
        self.code = code
        codeText = code.display
        step = .preview(preview)
    }
    #endif

    /// Koden som er skrevet inn (eller limt inn som lenke), eller nil.
    var typedCode: InviteCode? { InviteCode.parse(codeText, host: InviteTarget.competitionHost) }

    func lookUp() async {
        guard let client else { return }
        guard let code = code ?? typedCode else {
            step = .failed("Koden har 10 tegn, f.eks. ABCDE-FGH23.")
            return
        }
        self.code = code
        step = .loading
        do {
            let preview = try await CompetitionQueries.invitePreview(client: client, code: code)
            step = preview.entered ? .joined(preview) : .preview(preview)
        } catch {
            step = .failed(CompetitionInviteErrors.message(for: error))
        }
    }

    /// Ny kode skrevet inn: tilbake til feltet.
    func editCode() {
        code = nil
        choice = nil
        nameQuery = ""
        step = .enterCode
    }

    /// Må du velge (navnet ditt eller «ikke på lista») før du kan bli med?
    var needsChoice: Bool {
        guard case .preview(let preview) = step else { return false }
        return !preview.openNames.isEmpty && choice == nil
    }

    /// Melder deg på (`claim_competition_invite`), med navnet du valgte. Gir konkurransens id.
    func join() async -> UUID? {
        guard let client, let code, case .preview(let preview) = step, !isJoining, !needsChoice else { return nil }
        isJoining = true
        joinError = nil
        defer { isJoining = false }
        var memberID: UUID?
        if case .name(let name) = choice { memberID = name.memberID }
        do {
            let result = try await CompetitionQueries.claimInvite(client: client, code: code, memberID: memberID)
            step = .joined(preview)
            NotificationCenter.default.post(name: CompetitionJoinEvents.joined, object: result.competitionID)
            return result.competitionID
        } catch {
            joinError = CompetitionInviteErrors.message(for: error)
            if CompetitionInviteErrors.isNameTaken(error) {
                // Noen kom før deg: hent de ledige navnene på nytt.
                choice = nil
                let message = joinError
                await lookUp()
                joinError = message
            }
            return nil
        }
    }
}

struct JoinCompetitionView: View {
    @State var model: JoinCompetitionModel
    /// «Åpne turneringen» når du er med (fra en lenke). nil: bare «Ferdig».
    var openCompetition: ((UUID) -> AnyView)?
    let onJoined: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var codeFocused: Bool

    init(model: JoinCompetitionModel, openCompetition: ((UUID) -> AnyView)? = nil,
         onJoined: @escaping (UUID) -> Void) {
        _model = State(initialValue: model)
        self.openCompetition = openCompetition
        self.onJoined = onJoined
    }

    var body: some View {
        DDForm {
            switch model.step {
            case .enterCode, .failed:
                codeSection
            case .loading:
                Section {
                    HStack { Spacer(); ProgressView("Finner turneringen …"); Spacer() }
                }
            case .preview(let preview):
                summary(preview)
                if !preview.openNames.isEmpty {
                    namesSection(preview)
                }
                joinSection(preview)
            case .joined(let preview):
                summary(preview)
                joinedSection(preview)
            }
        }
        .navigationTitle("Bli med")
        .ddNavigationChrome()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            DDCancelToolbarItem {
                Button("Avbryt") { dismiss() }
            }
        }
        .task {
            if model.step == .loading { await model.lookUp() }
        }
    }

    private var codeSection: some View {
        Section {
            TextField("Kode, f.eks. ABCDE-FGH23", text: $model.codeText)
                .font(.dd(.mono, size: 20, relativeTo: .title3))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($codeFocused)
                .submitLabel(.go)
                .onSubmit { Task { await model.lookUp() } }
            Button("Finn turneringen") { Task { await model.lookUp() } }
                .disabled(model.typedCode == nil)
            if case .failed(let message) = model.step {
                Label(message, systemImage: "exclamationmark.triangle").ddErrorStyle()
            }
        } header: {
            DDHeader("Koden fra invitasjonen")
        } footer: {
            DDFooter("Eieren og de påmeldte finner koden under «Inviter» i turneringen (i en klubbturnering: arrangøren). "
                     + "Du kan også lime inn lenken.")
        }
        .onAppear { codeFocused = true }
    }

    private func summary(_ preview: CompetitionInvitePreview) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(preview.name)
                    .font(.ddTitle)
                    .foregroundStyle(Color.ddInk)
                Text(preview.summary)
                    .font(.ddCallout)
                    .foregroundStyle(Color.ddInkSecondary)
                if let club = preview.clubName {
                    Text(club)
                        .font(.ddCaption)
                        .foregroundStyle(Color.ddInkSecondary)
                } else if let owner = preview.ownerName, !owner.isEmpty {
                    Text("Eier: \(owner)")
                        .font(.ddCaption)
                        .foregroundStyle(Color.ddInkSecondary)
                }
            }
            .padding(.vertical, 4)
        } header: {
            DDHeader("Turneringen")
        }
    }

    /// «Er du en av disse?»: de ledige navnene, med søk når lista er lang, og «Jeg står ikke på lista».
    private func namesSection(_ preview: CompetitionInvitePreview) -> some View {
        Section {
            if OpenNameSearch.showsSearch(preview.openNames) {
                TextField("Søk etter navnet ditt", text: $model.nameQuery)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            }
            let names = OpenNameSearch.filter(preview.openNames, query: model.nameQuery)
            ForEach(names) { name in
                choiceRow(name.displayName, selected: model.choice == .name(name)) { model.choice = .name(name) }
            }
            if names.isEmpty {
                Text("Ingen navn passer søket.")
                    .font(.ddCallout)
                    .foregroundStyle(Color.ddInkSecondary)
            }
            choiceRow("Jeg står ikke på lista", selected: model.choice == .notListed) { model.choice = .notListed }
        } header: {
            DDHeader("Er du en av disse?")
        } footer: {
            DDFooter("Arrangøren har lagt inn navnene. Velg ditt, så blir plassen din, med handicapet som står der.")
        }
    }

    private func choiceRow(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(Color.ddInk)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.ddForestInk)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(.rect)
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func joinTitle(_ preview: CompetitionInvitePreview) -> String {
        switch model.choice {
        case .name(let name): "Ta plassen som \(name.displayName)"
        case .notListed: "Meld meg på som ny deltaker"
        case nil: preview.openNames.isEmpty ? "Bli med" : "Velg navnet ditt"
        }
    }

    private func joinSection(_ preview: CompetitionInvitePreview) -> some View {
        Section {
            Button(joinTitle(preview)) {
                Task {
                    if let id = await model.join() { onJoined(id) }
                }
            }
            .buttonStyle(.dd(.primary, fullWidth: true))
            .disabled(model.isJoining || model.needsChoice)
            .listRowBackground(Color.clear)
            if let error = model.joinError {
                Label(error, systemImage: "exclamationmark.triangle").ddErrorStyle()
            }
            Button("Annen kode") { model.editCode() }
                .buttonStyle(.dd(.text))
                .listRowBackground(Color.clear)
        } footer: {
            if let club = preview.clubName {
                VStack(alignment: .leading, spacing: DDSpacing.s) {
                    DDFooter("Du blir deltaker i turneringen, ikke medlem i \(club). Du ser turneringen, tabellen og "
                             + "rundene du spiller, og fører ditt eget kort.")
                    LegalNotice()
                }
            } else {
                DDFooter("Du meldes på og ser tabellen og rundene som teller.")
            }
        }
    }

    private func joinedSection(_ preview: CompetitionInvitePreview) -> some View {
        Section {
            Label(preview.isClub ? "Du er med som deltaker." : "Du er påmeldt.", systemImage: "checkmark.seal")
                .foregroundStyle(Color.ddForestInk)
            if let openCompetition {
                NavigationLink {
                    openCompetition(preview.competitionID)
                } label: {
                    Text("Åpne turneringen")
                }
                .buttonStyle(.dd(.primary, fullWidth: true))
                .listRowBackground(Color.clear)
            }
            Button("Ferdig") { dismiss() }
                .buttonStyle(.dd(openCompetition == nil ? .primary : .secondary, fullWidth: true))
                .listRowBackground(Color.clear)
        } footer: {
            DDFooter("Du finner den under Spill → Turneringer.")
        }
    }
}

/// Invitasjon fra en lenke (`dashdash://konkurranse/KODE`): se konkurransen, bli med og åpne den.
struct JoinCompetitionFromLinkView: View {
    let client: SupabaseClient
    let code: InviteCode
    let userID: UUID
    /// Medlemskapene dine, så turneringen kjenner deg igjen («deg» i tabellen).
    var memberships: [CompetitionAccess.Membership] = []

    var body: some View {
        NavigationStack {
            JoinCompetitionView(model: JoinCompetitionModel(client: client, code: code),
                                openCompetition: { id in
                                    AnyView(JoinedCompetitionScreen(client: client, userID: userID,
                                                                    memberships: memberships, competitionID: id))
                                },
                                onJoined: { _ in })
        }
        .tint(Color.ddForestInk)
    }
}

/// Turneringen du nettopp ble med i: henter turneringene dine og viser den.
private struct JoinedCompetitionScreen: View {
    @State private var list: CompetitionsModel
    let competitionID: UUID

    init(client: SupabaseClient, userID: UUID, memberships: [CompetitionAccess.Membership], competitionID: UUID) {
        _list = State(initialValue: CompetitionsModel(client: client, userID: userID, memberships: memberships))
        self.competitionID = competitionID
    }

    var body: some View {
        Group {
            if let competition = list.overview.competitions.first(where: { $0.id == competitionID }) {
                CompetitionDetailScreen(list: list, competition: competition)
            } else if case .failed(let message) = list.state {
                ContentUnavailableView {
                    Label("Fikk ikke hentet turneringen", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Prøv igjen") { Task { await list.load() } }
                        .buttonStyle(.dd(.primary))
                }
            } else if list.state == .loaded {
                ContentUnavailableView("Fant ikke turneringen", systemImage: "trophy",
                                       description: Text("Se under Spill → Turneringer."))
            } else {
                ProgressView("Henter turneringen …")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await list.load() }
    }
}
