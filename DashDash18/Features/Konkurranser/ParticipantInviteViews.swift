import Observation
import Supabase
import SwiftUI

/// «Legg til deltakere» (sql/060): lista arrangøren limer inn, og kallet som legger dem inn i én omgang.
@Observable
final class ParticipantImportModel {
    /// Navnene som er påmeldt fra før.
    private(set) var entered: [String] = []
    private(set) var isBusy = false
    /// Antallet som ble lagt til, når det er lagret.
    private(set) var added: Int?
    var error: String?

    let competition: CompetitionRow
    private let client: SupabaseClient?

    init(client: SupabaseClient, competition: CompetitionRow) {
        self.client = client
        self.competition = competition
    }

    #if DEBUG
    init(preview competition: CompetitionRow, entered: [String]) {
        client = nil
        self.competition = competition
        self.entered = entered
    }
    #endif

    /// En feil her gir ingen melding: da sjekkes lista bare mot seg selv, og serveren hopper over dem
    /// som er påmeldt med samme NGF-nummer.
    func load() async {
        guard let client else { return }
        if let names = try? await CompetitionQueries.enteredNames(client: client, competitionID: competition.id) {
            entered = names
        }
    }

    func lines(_ text: String) -> [TroppImportLine] {
        ParticipantImport.parse(text, entered: entered)
    }

    /// Legger inn linjene som kan legges inn. Gir `true` når det gikk.
    func add(_ lines: [TroppImportLine]) async -> Bool {
        let entries = ParticipantImport.entries(lines)
        guard let client, !entries.isEmpty, !isBusy else { return false }
        isBusy = true
        defer { isBusy = false }
        do {
            added = try await CompetitionQueries.addParticipants(client: client, competitionID: competition.id,
                                                                 entries: entries)
            return true
        } catch {
            self.error = DataError.from(error).message
            return false
        }
    }
}

/// Arket for «Legg til deltakere»: som Troppens «Legg til mange», med NGF-nummer i egen kolonne.
struct ParticipantImportView: View {
    @State var model: ParticipantImportModel
    /// «Del lenken» etter at de er lagt inn.
    var onShare: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        let lines = model.lines(text)
        let valid = ParticipantImport.valid(lines)
        NavigationStack {
            DDForm {
                if let added = model.added {
                    doneSection(added)
                } else {
                    Section {
                        TextEditor(text: $text)
                            .frame(minHeight: 160)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .accessibilityLabel("Deltakerne")
                    } header: {
                        DDHeader("Ett navn per linje")
                    } footer: {
                        DDFooter("Handicap kan stå etter navnet, f.eks. «Kari Nordmann 18,4». Fra et regneark (GolfBox, "
                                 + "påmeldingslista) kan du lime inn kolonnene navn, handicap og NGF-nummer. Deltakerne "
                                 + "blir ikke medlemmer i klubben. Høyst \(ParticipantImport.maxLines) om gangen.")
                    }
                    if !lines.isEmpty {
                        Section {
                            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                                row(line)
                            }
                        } header: {
                            DDHeader("\(valid.count) av \(lines.count) legges til")
                        }
                    }
                }
            }
            .navigationTitle("Legg til deltakere")
            .ddNavigationChrome()
            .navigationBarTitleDisplayMode(.inline)
            .disabled(model.isBusy)
            .discardChangesGuard(hasChanges: !text.isEmpty && !model.isBusy && model.added == nil, alwaysShowsCancel: true)
            .toolbar {
                DDConfirmToolbarItem {
                    if model.added != nil {
                        Button("Ferdig") { dismiss() }
                    } else {
                        Button(valid.isEmpty ? "Legg til" : "Legg til \(valid.count)") {
                            Task { _ = await model.add(lines) }
                        }
                        .disabled(model.isBusy || valid.isEmpty)
                    }
                }
            }
            .alert("Det gikk ikke", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.error ?? "")
            }
            .task { await model.load() }
        }
    }

    private func doneSection(_ added: Int) -> some View {
        Section {
            Label(ParticipantImport.addedText(added), systemImage: "checkmark.seal")
                .foregroundStyle(Color.ddForestInk)
            if let onShare {
                Button("Del lenken til turneringen", systemImage: "link") {
                    dismiss()
                    onShare()
                }
                .buttonStyle(.dd(.primary, fullWidth: true))
                .listRowBackground(Color.clear)
            }
        } footer: {
            DDFooter("Del lenken med deltakerne. De velger navnet sitt, lager en bruker i Atten og fører selv.")
        }
    }

    private func row(_ line: TroppImportLine) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DDSpacing.s) {
            Image(systemName: line.problem == nil ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(line.problem == nil ? Color.ddForestInk : Color.ddInkSecondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(line.name.isEmpty ? line.text : line.name)
                    .strikethrough(line.problem != nil)
                if let message = ParticipantImport.message(line) {
                    Text(message)
                        .font(.ddCallout)
                        .foregroundStyle(Color.ddInkSecondary)
                }
            }
            Spacer()
            if line.problem == nil {
                VStack(alignment: .trailing, spacing: 2) {
                    if line.handicapIndex != nil {
                        Text("hcp \(TroppInput.handicapText(line.handicapIndex))")
                    }
                    if let ngf = line.ngfNumber {
                        Text("NGF \(ngf)")
                    }
                }
                .font(.ddCallout)
                .foregroundStyle(Color.ddInkSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Radene på arrangørsiden for en klubbturnering med påmelding (sql/060): legg inn deltakerne og del
/// lenken, så de kan ta plassen sin.
struct ParticipantInviteRows: View {
    let competition: CompetitionRow
    let context: ClubContext
    @State private var showsImport = false
    @State private var showsInvite = false
    /// «Del lenken» fra arket med lista: vises når det arket er lukket.
    @State private var sharesAfterImport = false

    var body: some View {
        if ParticipantImport.canAdd(competition, access: context.competitionAccess) {
            Button {
                showsImport = true
            } label: {
                AdminHubRow("Legg til deltakere (lim inn liste)",
                            "Fra e-post, GolfBox eller et regneark. De blir deltakere, ikke medlemmer.",
                            systemImage: "list.bullet.clipboard")
            }
            .sheet(isPresented: $showsImport, onDismiss: {
                if sharesAfterImport {
                    sharesAfterImport = false
                    showsInvite = true
                }
            }) {
                ParticipantImportView(model: ParticipantImportModel(client: context.client, competition: competition)) {
                    sharesAfterImport = true
                }
            }
            Button {
                showsInvite = true
            } label: {
                AdminHubRow("Del lenken til turneringen",
                            "Deltakerne tar plassen sin og lager en bruker i Atten. QR-kode og lenke.",
                            systemImage: "qrcode")
            }
            .sheet(isPresented: $showsInvite) {
                NavigationStack {
                    InviteView(model: .competition(client: context.client, competition: competition,
                                                   clubName: context.membership.club.name, isAdmin: true))
                }
            }
        }
    }
}

extension InviteModel {
    /// Koden til en turnering (`competition_invite`). Arrangøren eller eieren kan fornye og trekke den
    /// tilbake (sql/022). En klubbturnering (sql/060) gir klubbens tekster.
    static func competition(client: SupabaseClient, competition: CompetitionRow, clubName: String?,
                            isAdmin: Bool) -> InviteModel {
        let id = competition.id
        let manage = isAdmin
            ? Manage(renew: { try await CompetitionQueries.invite(client: client, competitionID: id, renew: true) },
                     revoke: { try await CompetitionQueries.revokeInvite(client: client, competitionID: id) })
            : nil
        let club = competition.clubID == nil ? nil : (clubName ?? "klubben")
        return InviteModel(target: .competition(name: competition.name, clubName: club), manage: manage) {
            try await CompetitionQueries.invite(client: client, competitionID: id)
        }
    }
}
