import SwiftUI

/// Deg › Klubb: alle klubbene dine, «Bli med i en annen klubb» og «Lag ny klubb».
/// Å bytte aktiv klubb og det som skjer etter «Bli med» er den samme logikken som for klubblenker (`ClubModel.finishJoin`).
struct DegClubsSection: View {
    let user: AuthUser
    let current: Membership
    @Environment(ClubModel.self) private var club
    /// Hva som skjedde da du ble med sist (aktiv: byttet; venter: sitter i kø).
    @State private var joinNote: String?

    var body: some View {
        let clubs = DegClubsLogic.rows(club.memberships, currentClubID: current.clubID)
        Section {
            if clubs.count > 1 || clubs.contains(where: { $0.status == .pending }) {
                ForEach(clubs) { row in
                    clubRow(row)
                }
            }
            NavigationLink {
                JoinAnotherClubView(user: user) { joinNote = $0 }
            } label: {
                Label("Bli med i en annen klubb", systemImage: "person.badge.plus")
                    .labelStyle(DDIconLabelStyle())
            }
            NavigationLink { CreateClubView(user: user) } label: {
                Label("Lag ny klubb", systemImage: "flag")
                    .labelStyle(DDIconLabelStyle())
            }
        } header: {
            DDHeader("Dine klubber")
        } footer: {
            if let joinNote {
                DDFooter(joinNote)
            }
        }
    }

    @ViewBuilder
    private func clubRow(_ row: DegClubsLogic.Row) -> some View {
        let label = HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                if let subtitle = row.subtitle {
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if row.isSelected {
                Image(systemName: "checkmark").foregroundStyle(Color.ddForestInk)
                    .accessibilityLabel("Valgt")
            }
        }
        if row.status == .active {
            Button { club.select(clubID: row.clubID) } label: { label }
                .foregroundStyle(.primary)
        } else {
            label
        }
    }
}

/// «Bli med» fra Deg: kode eller lenke, så samme etter-join-logikk som invitasjonslenker.
private struct JoinAnotherClubView: View {
    let user: AuthUser
    let onDone: (String) -> Void
    @Environment(ClubModel.self) private var club
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        JoinClubView(user: user) { preview, status in
            onDone(club.finishJoin(clubID: preview.clubID, clubName: preview.name, status: status))
            dismiss()
        }
    }
}

nonisolated enum DegClubsLogic {
    struct Row: Identifiable, Equatable {
        let clubID: UUID
        let name: String
        let status: MemberStatus
        let isSelected: Bool
        var id: UUID { clubID }
        var subtitle: String? { status == .pending ? "Venter på godkjenning" : nil }
    }

    /// Klubbene du er med i eller venter på (ikke arkiverte): aktive først, så ventende, hver gruppe på navn.
    static func rows(_ memberships: [Membership], currentClubID: UUID?) -> [Row] {
        memberships
            .filter { $0.status != .archived }
            .map { Row(clubID: $0.clubID, name: $0.club.name, status: $0.status, isSelected: $0.clubID == currentClubID) }
            .sorted {
                if ($0.status == .active) != ($1.status == .active) { return $0.status == .active }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }
}
