import GolfgutuCore
import SwiftUI

/// Ny eller endre kveld.
struct EventEditor: View {
    @Environment(\.dayTerm) private var dayTerm
    let model: TerminlisteModel
    @State var draft: EventDraft
    let done: () -> Void
    @State private var error: String?
    @State private var isBusy = false
    @State private var confirmDelete = false
    /// «Bare denne» eller «Denne og fremtidige», for en kveld i en serie (sql/049).
    @State private var scope: SeriesScope = .one
    /// Kvelder som ikke ble endret (passert eller startet). Vises før arket lukkes.
    @State private var notice: String?

    var body: some View {
        DDForm {
            // Øverst, ved «Lagre»: lenger ned havner den under troppen og ses ikke.
            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Color.ddError)
                }
            }

            Section {
                DatePicker("Dato", selection: $draft.date, displayedComponents: .date)
                Toggle("Klokkeslett", isOn: $draft.hasTime)
                if draft.hasTime {
                    DatePicker("Starter", selection: $draft.time, displayedComponents: .hourAndMinute)
                }
                TextField("Sted", text: $draft.venue)
                    .textInputAutocapitalization(.words)
                TextField("Notat (valgfritt)", text: $draft.note, axis: .vertical)
                    .lineLimit(2...5)
            } footer: {
                DDFooter("Én \(dayTerm.one) per dato.")
            }

            if let series = model.series(for: draft.id) {
                seriesSection(series)
            }

            if model.supportsSignupRules {
                signupSection
            }

            Section {
                ForEach(model.members) { member in
                    Button {
                        toggle(member.id)
                    } label: {
                        HStack {
                            Text(member.displayName)
                            Spacer()
                            if draft.committee.contains(member.id) {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                    .tint(Color.ddInk)
                    .accessibilityAddTraits(draft.committee.contains(member.id) ? .isSelected : [])
                }
            } header: {
                DDHeader("Sosialkomité (\(draft.committee.count))")
            }

            if draft.id != nil {
                Section {
                    Button("Slett \(dayTerm.the)", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .environment(\.timeZone, EveningDates.osloTimeZone)
        .navigationTitle(draft.id == nil ? "Ny \(dayTerm.one)" : "Endre \(dayTerm.one)")
        .ddNavigationChrome()
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isBusy)
        .interactiveDismissDisabled(isBusy)
        .toolbar {
            DDCancelToolbarItem {
                Button("Avbryt", action: done)
            }
            DDConfirmToolbarItem {
                if isBusy {
                    ProgressView()
                } else {
                    Button("Lagre", action: save)
                }
            }
        }
        .messageAlert("Serien er endret", text: Binding(get: { notice }, set: { if $0 == nil { notice = nil; done() } }))
        .confirmationDialog("Slette \(dayTerm.the)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Slett", role: .destructive, action: delete)
        } message: {
            Text("Påmeldingene og sosialkomiteen for \(dayTerm.the) slettes også.")
        }
    }

    /// Serien kvelden hører til: «Hver torsdag kl. 18:00», og om endringen gjelder bare denne.
    private func seriesSection(_ series: EventSeriesRow) -> some View {
        Section {
            Picker("Endre", selection: $scope) {
                ForEach(SeriesScope.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        } header: {
            DDHeader("Serie · \(series.summary)")
        } footer: {
            DDFooter(scope == .one
                     ? "Bare \(dayTerm.the) endres."
                     : "Tid, sted og dato endres også for senere \(dayTerm.many) i serien. Passerte og startede står.")
        }
    }

    /// Tak, frister og gjester (sql/045). Alt er av som standard.
    private var signupSection: some View {
        Section {
            Toggle("Maks antall", isOn: $draft.rules.hasMax)
            if draft.rules.hasMax {
                Stepper("\(draft.rules.maxPlayers) plasser", value: $draft.rules.maxPlayers,
                        in: EveningRulesDraft.maxRange)
            }
            Toggle("Påmeldingsfrist", isOn: $draft.rules.hasSignupDeadline)
            if draft.rules.hasSignupDeadline {
                DatePicker("Frist", selection: $draft.rules.signupDeadline)
            }
            Toggle("Avmeldingsfrist", isOn: $draft.rules.hasWithdrawDeadline)
            if draft.rules.hasWithdrawDeadline {
                DatePicker("Frist", selection: $draft.rules.withdrawDeadline)
            }
            Toggle("Tillat gjester", isOn: $draft.rules.allowGuests)
        } header: {
            DDHeader("Påmelding")
        } footer: {
            DDFooter("Når \(dayTerm.the) er full, havner nye på ventelista og rykker opp når noen melder av. Etter fristen kan bare arrangøren endre.")
        }
        .onChange(of: draft.rules.hasSignupDeadline) { _, on in
            if on, draft.id == nil { draft.rules.signupDeadline = suggestedDeadline }
        }
        .onChange(of: draft.rules.hasWithdrawDeadline) { _, on in
            if on, draft.id == nil { draft.rules.withdrawDeadline = suggestedDeadline }
        }
    }

    /// Kl. 12 dagen før kvelden.
    private var suggestedDeadline: Date {
        EveningRulesDraft(nil, eventDate: EveningDates.date(from: EveningDates.dateString(from: draft.date)) ?? draft.date)
            .signupDeadline
    }

    private func toggle(_ id: UUID) {
        if draft.committee.contains(id) {
            draft.committee.remove(id)
        } else {
            draft.committee.insert(id)
        }
    }

    private func save() {
        isBusy = true
        error = nil
        Task {
            defer { isBusy = false }
            do throws(DataError) {
                if let message = try await model.save(draft, scope: scope) {
                    notice = message
                } else {
                    done()
                }
            } catch {
                self.error = error.message
            }
        }
    }

    private func delete() {
        guard let id = draft.id, let event = model.events.first(where: { $0.id == id }) else { return }
        run { () async throws(DataError) in try await model.delete(event) }
    }

    private func run(_ action: @escaping () async throws(DataError) -> Void) {
        isBusy = true
        error = nil
        Task {
            defer { isBusy = false }
            do throws(DataError) {
                try await action()
                done()
            } catch {
                self.error = error.message
            }
        }
    }
}

/// Identifiserbar innpakning, så et utkast kan styre et ark.
struct EventEditItem: Identifiable {
    let id = UUID()
    let draft: EventDraft
}
