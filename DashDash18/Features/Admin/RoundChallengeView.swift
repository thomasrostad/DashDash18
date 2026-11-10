import Foundation
import SwiftUI

/// Det «Challenge etter runden» trenger fra runden: kvelden, ordet for gruppene og spillerne med gruppe.
struct ChallengeContext: Identifiable {
    let eventID: UUID
    let term: GroupTerm
    let players: [(memberID: UUID, group: Int)]
    var id: UUID { eventID }
}

/// «Challenge etter runden» (I kveld): navn, poeng og én vinner per bås eller for hele runden. Hver vinner
/// blir et tilleggspoeng for kvelden (sql/072), med samme skriving som «Tilleggspoeng» (`TilleggspoengModel`).
struct RoundChallengeView: View {
    let model: TilleggspoengModel
    let context: ChallengeContext
    let done: () -> Void
    @State private var setup = ChallengeSetup.standard
    @State private var winners: [Int: UUID] = [:]
    @State private var error: String?
    @State private var isBusy = false
    @State private var didResume = false

    private var groups: [ChallengeGroup] {
        RoundChallenge.groups(setup, players: context.players, term: context.term)
    }

    /// Tillegget som allerede er registrert for gruppa i kveld, eller nil.
    private func registered(_ group: ChallengeGroup) -> PointAdjustmentRow? {
        model.rows.last { $0.eventID == context.eventID && $0.reason == group.reason }
    }

    private var allRegistered: Bool { groups.allSatisfy { registered($0) != nil } }

    var body: some View {
        DDForm {
            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Color.ddError)
                }
            }
            Section {
                TextField("Navn", text: $setup.name)
                    .textInputAutocapitalization(.sentences)
                Stepper(value: $setup.points, in: RoundChallenge.step...100, step: RoundChallenge.step) {
                    LabeledContent("Poeng til vinneren", value: model.pointsText(setup.points))
                }
                Picker("Vinnere", selection: $setup.scope) {
                    Text("Per \(context.term.singular)").tag(ChallengeScope.group)
                    Text("Hele runden").tag(ChallengeScope.all)
                }
                .pickerStyle(.segmented)
            } header: {
                DDHeader(setup.round > 1 ? "Runde \(setup.round)" : "Challengen")
            } footer: {
                DDFooter(RoundChallenge.problem(setup)
                         ?? "Vinneren får tilleggspoeng for \(dayText). Grunnen vises for spillerne.")
            }

            ForEach(groups) { group in
                Section {
                    if let row = registered(group) {
                        LabeledContent("Vinner", value: "\(model.name(row.memberID)) \(model.pointsText(row.points))")
                        Button("Angre", role: .destructive) { undo(row) }
                    } else {
                        Picker("Vinner", selection: Binding(get: { winners[group.no] },
                                                            set: { winners[group.no] = $0 })) {
                            Text("Velg").tag(UUID?.none)
                            ForEach(group.members, id: \.self) { id in
                                Text(model.name(id)).tag(Optional(id))
                            }
                        }
                        Button("Registrer") { register(group) }
                            .disabled(winners[group.no] == nil || RoundChallenge.problem(setup) != nil)
                    }
                } header: {
                    DDHeader(group.title)
                } footer: {
                    DDFooter(group.reason)
                }
            }

            if allRegistered, setup.round < RoundChallenge.maxRounds {
                Section {
                    Button("Én runde til", systemImage: "plus") {
                        setup.round += 1
                        winners = [:]
                    }
                } footer: {
                    DDFooter("Samme \(context.term.plural), ny vinner. Velg poengene for runden over.")
                }
            }
        }
        .navigationTitle("Challenge etter runden")
        .ddNavigationChrome()
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isBusy)
        .interactiveDismissDisabled(isBusy)
        .toolbar {
            DDConfirmToolbarItem {
                if isBusy { ProgressView() } else { Button("Ferdig", action: done) }
            }
        }
        .task {
            await model.load()
            resume()
        }
    }

    private var dayText: String { model.eventText(context.eventID) ?? "kvelden" }

    /// Fortsetter på runden dere var på, ut fra kveldens grunner.
    private func resume() {
        guard !didResume, model.loadState == .loaded else { return }
        didResume = true
        let reasons = model.rows.filter { $0.eventID == context.eventID }.map(\.reason)
        let last = RoundChallenge.lastRound(setup, players: context.players, term: context.term, reasons: reasons)
        setup.round = max(1, last)
    }

    private func register(_ group: ChallengeGroup) {
        guard let winner = winners[group.no] else { return }
        let draft = TilleggspoengDraft(memberID: winner, points: setup.points, reason: group.reason,
                                       eventID: context.eventID)
        run { () async throws(DataError) in try await model.add(draft) }
    }

    private func undo(_ row: PointAdjustmentRow) {
        run { () async throws(DataError) in try await model.delete(row) }
    }

    private func run(_ action: @escaping () async throws(DataError) -> Void) {
        error = nil
        isBusy = true
        Task {
            do {
                try await action()
            } catch {
                self.error = DataError.from(error).message
            }
            isBusy = false
        }
    }
}
