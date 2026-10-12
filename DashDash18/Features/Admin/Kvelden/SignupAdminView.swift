import GolfgutuCore
import SwiftUI

/// Arrangøren: endre svaret for et medlem, gjester og loggen for kvelden (sql/045).
/// Uten 045 kan svaret endres som før (rett i `signups`); gjester og logg skjules.
struct SignupAdminView: View {
    @Environment(\.dayTerm) private var dayTerm
    let model: TerminlisteModel
    let event: EventRow
    @State private var error: String?
    @State private var isBusy = false
    @State private var guestName = ""
    @State private var guestHost: UUID?

    private var summary: SignupSummary { model.signupSummary(for: event.id) }
    private var settings: EveningSettingsRow? { model.settings?[event.id] }

    var body: some View {
        DDList {
            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Color.ddError)
                }
            }
            Section {
                Text(model.signupText(for: event.id))
                    .font(.ddBodyEmphasis)
                if let settings, let text = EveningSignupText.capacity(coming: summary.coming, max: settings.maxPlayers,
                                                                     waitlist: summary.waitlist.count) {
                    Text(text).foregroundStyle(Color.ddInkSecondary)
                }
            } footer: {
                DDFooter("Trykk på et navn for å endre svaret. Du går forbi fristene, og endringen står i loggen.")
            }
            ForEach(summary.groups, id: \.title) { group in
                if !group.entries.isEmpty {
                    Section {
                        ForEach(group.entries) { entry in row(entry) }
                    } header: {
                        DDHeader("\(group.title) (\(group.entries.count))")
                    }
                }
            }
            if settings?.allowGuests == true {
                guestSection
            }
            if model.supportsSignupRules {
                Section {
                    NavigationLink {
                        SignupLogView(model: model, event: event)
                    } label: {
                        Label("Logg", systemImage: "list.bullet.rectangle")
                            .labelStyle(DDIconLabelStyle())
                            .foregroundStyle(Color.ddInk)
                    }
                }
            }
        }
        .navigationTitle("Påmeldingen")
        .navigationBarTitleDisplayMode(.inline)
        .ddNavigationChrome()
        .disabled(isBusy)
        .overlay { if isBusy { ProgressView() } }
    }

    @ViewBuilder
    private func row(_ entry: SignupSummary.Entry) -> some View {
        if let guestID = entry.guestID {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                    if let detail = entry.detail {
                        Text(detail).font(.ddCaption).foregroundStyle(Color.ddInkSecondary)
                    }
                }
                Spacer()
                Button("Fjern", role: .destructive) {
                    if let guest = model.guests[event.id]?.first(where: { $0.id == guestID }) {
                        run { () async throws(DataError) in try await model.removeGuest(guest) }
                    }
                }
                .buttonStyle(.borderless)
            }
        } else {
            Menu {
                ForEach(SignupStatus.allCases, id: \.self) { status in
                    Button(status.title) { set(entry.memberID, status) }
                }
                Button("Fjern svaret", role: .destructive) { set(entry.memberID, nil) }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name).foregroundStyle(Color.ddInk)
                        if let detail = entry.detail ?? entry.comment.map({ "«\($0)»" }) {
                            Text(detail).font(.ddCaption).foregroundStyle(Color.ddInkSecondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .foregroundStyle(Color.ddInkSecondary)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityHint("Endrer svaret")
        }
    }

    private var guestSection: some View {
        Section {
            Picker("Gjest av", selection: $guestHost) {
                Text("Velg medlem").tag(UUID?.none)
                ForEach(model.members) { member in
                    Text(member.displayName).tag(Optional(member.id))
                }
            }
            HStack {
                TextField("Navn på gjesten", text: $guestName)
                    .textInputAutocapitalization(.words)
                Button("Legg til") {
                    guard let host = guestHost else { error = "Velg hvem gjesten kommer med."; return }
                    let name = guestName
                    run { () async throws(DataError) in
                        try await model.addGuest(event, name: name, invitedBy: host)
                        guestName = ""
                    }
                }
                .disabled(guestName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            DDHeader("Ny gjest")
        } footer: {
            DDFooter("Gjester teller mot taket og står på ventelista når \(dayTerm.the) er full.")
        }
    }

    private func set(_ member: UUID, _ status: SignupStatus?) {
        run { () async throws(DataError) in try await model.setAnswer(event, member: member, status: status) }
    }

    private func run(_ action: @escaping () async throws(DataError) -> Void) {
        isBusy = true
        error = nil
        Task {
            defer { isBusy = false }
            do throws(DataError) {
                try await action()
            } catch {
                self.error = error.message
            }
        }
    }
}

/// Loggen over svarene på kvelden, nyeste først (`signup_log`).
struct SignupLogView: View {
    let model: TerminlisteModel
    let event: EventRow
    @State private var rows: [SignupLogRow]?
    @State private var error: String?

    var body: some View {
        DDList {
            if let error {
                Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Color.ddError) }
            } else if let rows {
                if rows.isEmpty {
                    Text("Ingen endringer ennå.").foregroundStyle(Color.ddInkSecondary)
                }
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(EveningSignupText.logLine(row) { id in model.members.first { $0.id == id }?.displayName })
                        Text(row.changedAt.formatted(.dateTime.day().month().hour().minute()
                                                     .locale(Locale(identifier: "nb_NO"))))
                            .font(.ddCaption)
                            .foregroundStyle(Color.ddInkSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Logg")
        .navigationBarTitleDisplayMode(.inline)
        .ddNavigationChrome()
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do throws(DataError) {
            rows = try await model.log(for: event)
            error = nil
        } catch {
            self.error = "Fikk ikke hentet loggen. \(error.message)"
        }
    }
}
