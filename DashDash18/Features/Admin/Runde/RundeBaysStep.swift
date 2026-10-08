import GolfgutuCore
import SwiftUI

/// «Spillere og båser» bak «Endre» på hurtigstarten: hvem som er med, og båsene (flightene på ekte bane).
/// Trykk et navn for å flytte ham, gjøre ham til markør eller ta ham ut.
struct RundeBaysStep: View {
    let model: RundeAdminModel
    @Binding var draft: RoundDraft
    @Binding var bayCount: Int

    @State private var selected: ClubMemberRow?

    private var maxPerBay: Int { model.rules.formats.maxPerBay }
    private var term: GroupTerm { draft.groupTerm }

    var body: some View {
        let included = Set(draft.participants)
        let others = model.members.filter { !included.contains($0.id) }
        let unseated = draft.participants.filter { draft.bays.seat(for: $0) == nil }

        DDList {
            Section {
                // 12 er databasens grense for båsnummer (`round_players.bay_no`).
                Stepper("\(term.pluralTitle): \(bayCount)", value: $bayCount, in: 1...max(1, min(12, draft.participants.count)))
                Button("Bland på nytt", systemImage: "shuffle") { reshuffle() }
            } header: {
                DDHeader(headline)
            } footer: {
                DDFooter(footer)
            }

            ForEach(draft.bays.bayNumbers, id: \.self) { bay in
                let ids = draft.bays.members(in: bay)
                Section {
                    ForEach(ids, id: \.self) { id in
                        playerRow(id)
                    }
                } header: {
                    HStack {
                        Text(term.numbered(bay))
                        Spacer()
                        Text("\(ids.count)" + (ids.count > maxPerBay ? " · over \(maxPerBay)" : ""))
                            .foregroundStyle(ids.count > maxPerBay ? Color.ddRustText : Color.ddInkSecondary)
                    }
                } footer: {
                    if draft.bays.marker(in: bay) == nil {
                        Text("Ingen markør. Trykk et navn og velg «Gjør til markør».")
                            .foregroundStyle(Color.ddRustText)
                    }
                }
            }

            if !unseated.isEmpty {
                DDSection("Uten bås") {
                    ForEach(unseated, id: \.self) { id in playerRow(id) }
                }
            }

            if !others.isEmpty {
                Section {
                    ForEach(others) { member in
                        Button {
                            withAnimation { draft.include(member.id, roster: model.members) }
                        } label: {
                            Label(member.displayName, systemImage: "plus.circle")
                        }
                    }
                } header: {
                    DDHeader("Ikke med")
                } footer: {
                    DDFooter("Trykk for å ta med. Han havner i \(term.definite) med færrest.")
                }
            }
        }
        .confirmationDialog(
            selected?.displayName ?? "",
            isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } }),
            titleVisibility: .visible,
            presenting: selected
        ) { member in
            actions(for: member)
        }
    }

    private var headline: String {
        let count = draft.participants.count
        let source: String = switch draft.participantSource {
        case .signups: "\(count) påmeldt"
        case .everyone, .saved: "\(count) med"
        }
        let bays = draft.bays.bayNumbers.count
        return source + (bays > 0 ? " · " + term.count(bays) : "")
    }

    private var footer: String {
        switch draft.participantSource {
        case .everyone:
            "Ingen har svart «Kommer» ennå, så alle står som med. Ta ut dem som ikke kommer."
        case .signups:
            "De som har svart «Kommer» er med. «Bland på nytt» fordeler på \(term.count(bayCount)), med duellpartnere i samme \(term.singular) og én markør i hver."
        case .saved:
            "De som er satt opp i kladden. «Bland på nytt» fordeler på \(term.count(bayCount))."
        }
    }

    private func playerRow(_ id: UUID) -> some View {
        let seat = draft.bays.seat(for: id)
        let member = model.members.first { $0.id == id }
        return Button {
            selected = member
        } label: {
            HStack {
                Text(model.memberName(id))
                    .foregroundStyle(.primary)
                Spacer()
                if seat?.isMarker == true {
                    Label("Markør", systemImage: "pencil.and.list.clipboard")
                        .font(.dd(.sans, size: 12, weight: .semibold, relativeTo: .caption))
                        .foregroundStyle(.tint)
                }
            }
        }
    }

    @ViewBuilder
    private func actions(for member: ClubMemberRow) -> some View {
        let seat = draft.bays.seat(for: member.id)
        let highest = max(draft.bays.bayCount, bayCount)
        ForEach(1...(highest + 1), id: \.self) { bay in
            if bay != seat?.bay {
                Button(bay > highest ? "Flytt til ny \(term.numberedLower(bay))" : "Flytt til \(term.numberedLower(bay))") {
                    withAnimation { draft.bays.move(member.id, to: bay) }
                }
            }
        }
        if let seat, !seat.isMarker {
            Button("Gjør til markør") { withAnimation { draft.bays.makeMarker(member.id) } }
        }
        Button("Ikke med", role: .destructive) {
            withAnimation { draft.exclude(member.id) }
        }
    }

    private func reshuffle() {
        withAnimation { draft.reshuffleBays(count: bayCount) }
    }
}
