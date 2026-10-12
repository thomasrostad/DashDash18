import GolfgutuCore
import Supabase
import SwiftUI

/// En medspiller du kan følge etter runden.
nonisolated struct FollowCandidate: Equatable, Identifiable, Sendable {
    let profileID: UUID
    let name: String
    var status: FollowStatus
    var id: UUID { profileID }
}

nonisolated enum FollowCoPlayers {
    /// Medspillerne med innlogging som du ikke følger ennå (de du venter på, står med «Venter»),
    /// én gang hver, i norsk navnerekkefølge. Gjester uten profil og du selv er ikke med.
    static func candidates(_ players: [(profileID: UUID?, name: String)], me: UUID,
                           lists: FollowLists) -> [FollowCandidate] {
        var seen: Set<UUID> = [me]
        var out: [FollowCandidate] = []
        for player in players {
            guard let id = player.profileID, !seen.contains(id) else { continue }
            seen.insert(id)
            let status = lists.status(of: id)
            guard status != .accepted else { continue }
            out.append(FollowCandidate(profileID: id, name: player.name, status: status))
        }
        return out.sorted { NorwegianSort.areInIncreasingOrder($0.name, $1.name) }
    }

    /// Spillerne i runden med profilen bak: deltakerne i en løs runde, eller troppen via `users`.
    static func players(_ snapshot: RoundSnapshot, users: [UUID: UUID]) -> [(profileID: UUID?, name: String)] {
        if let loose = snapshot.loose {
            return loose.roster.map { ($0.profileID, LooseRoundInfo.name($0.displayName)) }
        }
        return snapshot.players.map { (users[$0.memberID], snapshot.names[$0.memberID] ?? "Spiller") }
    }
}

/// «Følg medspillerne» etter en ferdig runde (sql/054, kilde `round`). Skjult uten 054, og når
/// du alt følger alle.
struct FollowCoPlayersSection: View {
    let client: SupabaseClient
    let userID: UUID
    let snapshot: RoundSnapshot
    @State private var candidates: [FollowCandidate] = []

    var body: some View {
        if !candidates.isEmpty {
            VStack(alignment: .leading, spacing: DDSpacing.s) {
                DDSectionLabel("Følg medspillerne")
                VStack(spacing: 0) {
                    ForEach($candidates) { $candidate in
                        HStack {
                            Text(candidate.name).font(.ddBody).foregroundStyle(Color.ddInk)
                            Spacer()
                            FollowStatusButton(client: client, profileID: candidate.profileID, name: candidate.name,
                                               status: $candidate.status, source: .round)
                                .fixedSize()
                        }
                        .padding(.vertical, 8)
                        if candidate.id != candidates.last?.id { DDDivider() }
                    }
                }
                .ddCard(padding: DDSpacing.l)
                DDFooter("Følger du, ser du de ferdige rundene deres under «Følger» på Hjem.")
            }
        } else {
            Color.clear.frame(height: 0)
                .task(id: snapshot.round.id) { await load() }
        }
    }

    private func load() async {
        guard await FollowFeature.detect(client: client) else { return }
        let service = FollowService(client: client)
        let users = snapshot.isLoose ? [:] : await service.users(forMembers: snapshot.players.map(\.memberID))
        guard let rows = try? await service.myFollows() else { return }
        candidates = FollowCoPlayers.candidates(FollowCoPlayers.players(snapshot, users: users), me: userID,
                                                lists: FollowLists(rows))
    }
}
