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

    /// «Følg alle»: dem du ikke har spurt ennå, i rekkefølgen på lista. Knappen vises fra to.
    static func followAll(_ candidates: [FollowCandidate]) -> [UUID] {
        candidates.filter { $0.status == .none }.map(\.profileID)
    }

    /// Så mange må være igjen før «Følg alle» vises (én følger du med knappen på raden).
    static let followAllMinimum = 2

    /// Spillerne i runden med profilen bak: deltakerne i en løs runde, eller troppen via `users`.
    static func players(_ snapshot: RoundSnapshot, users: [UUID: UUID]) -> [(profileID: UUID?, name: String)] {
        if let loose = snapshot.loose {
            return loose.roster.map { ($0.profileID, LooseRoundInfo.name($0.displayName)) }
        }
        return snapshot.players.map { (users[$0.memberID], snapshot.names[$0.memberID] ?? "Spiller") }
    }
}

/// «Følg medspillerne» øverst når runden er ferdig (sql/054, kilde `round`). Navnet åpner profilen,
/// og «Følg alle» sender én forespørsel per person. Skjult uten 054, og når du alt følger alle.
struct FollowCoPlayersSection: View {
    let client: SupabaseClient
    let userID: UUID
    let snapshot: RoundSnapshot
    @State private var candidates: [FollowCandidate] = []
    @State private var isFollowingAll = false
    @State private var error: String?

    var body: some View {
        if !candidates.isEmpty {
            VStack(alignment: .leading, spacing: DDSpacing.s) {
                DDSectionLabel("Følg medspillerne") {
                    if FollowCoPlayers.followAll(candidates).count >= FollowCoPlayers.followAllMinimum {
                        Button {
                            followAll()
                        } label: {
                            HStack(spacing: 6) {
                                Text("Følg alle")
                                if isFollowingAll { ProgressView().controlSize(.mini) }
                            }
                        }
                        .buttonStyle(.dd(.text, compact: true))
                        .disabled(isFollowingAll)
                    }
                }
                VStack(spacing: 0) {
                    ForEach($candidates) { $candidate in
                        HStack {
                            NavigationLink {
                                PersonProfileView(client: client, userID: userID, profileID: candidate.profileID,
                                                  name: candidate.name, source: .round)
                            } label: {
                                Text(candidate.name)
                                    .font(.ddBody)
                                    .foregroundStyle(Color.ddInk)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Åpner profilen.")
                            FollowStatusButton(client: client, profileID: candidate.profileID, name: candidate.name,
                                               status: $candidate.status, source: .round)
                                .fixedSize()
                        }
                        .padding(.vertical, 4)
                        if candidate.id != candidates.last?.id { DDDivider() }
                    }
                }
                .disabled(isFollowingAll)
                .ddCard(padding: DDSpacing.l)
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle").ddErrorStyle()
                }
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

    /// Én `follow_request` per person. Stopper ved første feil (54000: grensen for døgnet).
    private func followAll() {
        isFollowingAll = true
        error = nil
        Task {
            defer { isFollowingAll = false }
            let service = FollowService(client: client)
            for id in FollowCoPlayers.followAll(candidates) {
                do {
                    let status = try await service.request(id, source: .round)
                    if let i = candidates.firstIndex(where: { $0.id == id }) { candidates[i].status = status }
                } catch {
                    self.error = FollowService.message(error)
                    return
                }
            }
        }
    }
}
