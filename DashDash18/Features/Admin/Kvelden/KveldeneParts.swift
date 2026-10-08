import SwiftUI

// Deler av tidslinja på arrangørsiden (før fase 21: skjermen «Kveldene»).

/// En kveld i tidslinja. Kommende: dato, tid og sted, påmeldte, sosialkomité og status. Passert: dato
/// og resultatet.
struct EveningRowLabel: View {
    let event: EventRow
    let referenceYear: Int?
    var isPast = false
    var committee: [String] = []
    /// «9 av 14 kommer · 1 usikker».
    var signups: String?
    /// Neste steg eller resultatet. nil til rundene er hentet.
    var action: TonightAction?
    var status: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(EveningDates.longText(event.eventDate, referenceYear: referenceYear, capitalized: true))
                .font(.dd(.sans, size: 17, weight: .semibold, relativeTo: .headline))
                .foregroundStyle(isPast ? Color.ddInkSecondary : Color.ddInk)
            if isPast {
                if let status {
                    Text(status)
                        .font(.dd(.sans, size: 14, relativeTo: .subheadline))
                        .foregroundStyle(Color.ddInkSecondary)
                }
            } else {
                let details = [EveningDates.timeText(event.startTime), event.venue].compactMap { $0 }
                if !details.isEmpty {
                    Text(details.joined(separator: " · "))
                        .font(.dd(.sans, size: 14, relativeTo: .subheadline))
                        .foregroundStyle(Color.ddInkSecondary)
                }
                if let signups {
                    Text(signups)
                        .font(.dd(.sans, size: 13, relativeTo: .footnote))
                        .foregroundStyle(Color.ddInkSecondary)
                }
                Text(committee.isEmpty ? "Ingen sosialkomité" : "Sosialkomité: \(NorwegianList.join(committee))")
                    .font(.dd(.sans, size: 13, relativeTo: .footnote))
                    .foregroundStyle(committee.isEmpty ? Color.ddRustText : Color.ddInkSecondary)
                if let action, let status {
                    DDPill(status, tone: EveningStatusTone.tone(action))
                        .fixedSize()
                        .padding(.top, 4)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// Fargen på kveldens status: grønn når en runde går, gul for kladd, mørk når den er ferdig.
enum EveningStatusTone {
    static func tone(_ action: TonightAction) -> DDTone {
        switch action {
        case .goToRound, .closeEvening: .lime
        case .continueDraft: .sun
        case .seeResult: .earthDeep
        case .noEvening, .nudge, .setUp, .notPlayed: .earth
        }
    }
}

/// Forslaget fra trekningen, som arrangøren godtar eller trekker på nytt.
struct CommitteeDrawSheet: View {
    let model: TerminlisteModel
    @State var plan: [CommitteeDraw.Assignment]
    let perEvening: Int
    let done: () -> Void
    @State private var error: String?
    @State private var isBusy = false

    var body: some View {
        DDList {
            Section {
                ForEach(plan, id: \.eventID) { assignment in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(EveningDates.longText(assignment.date, capitalized: true)).font(.dd(.sans, size: 17, weight: .semibold, relativeTo: .headline))
                        Text(NorwegianList.join(assignment.memberIDs.map(model.memberName)))
                            .foregroundStyle(Color.ddInkSecondary)
                    }
                }
            } footer: {
                DDFooter("Ingenting er lagret ennå.")
            }
            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Color.ddError)
                }
            }
        }
        .navigationTitle("Sosialkomité")
        .ddNavigationChrome()
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isBusy)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Avbryt", action: done)
            }
            ToolbarItem(placement: .confirmationAction) {
                if isBusy {
                    ProgressView()
                } else {
                    Button("Lagre", action: save)
                }
            }
            ToolbarItem(placement: .bottomBar) {
                Button("Trekk på nytt", systemImage: "dice") {
                    plan = model.proposeCommittees(perEvening: perEvening)
                }
            }
        }
    }

    private func save() {
        isBusy = true
        error = nil
        Task {
            defer { isBusy = false }
            do throws(DataError) {
                try await model.apply(plan)
                done()
            } catch {
                self.error = error.message
            }
        }
    }
}

struct IdentifiedPlan: Identifiable {
    let id = UUID()
    let plan: [CommitteeDraw.Assignment]
}

