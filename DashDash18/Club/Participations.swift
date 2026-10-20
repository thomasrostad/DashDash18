import Foundation
import GolfgutuCore
import Supabase

// Deltakermodus (sql/059): du er påmeldt en klubbturnering uten å være medlem i klubben. Da har du
// en aktiv rad i `club_members` med kind = participant. Raden er spiller-id-en din i klubbens runder,
// men gir ingen ClubContext: du ser bare turneringen, rundene i den og ditt eget kort.

/// Deltakerraden din i én klubb.
nonisolated struct Participation: Codable, Equatable, Identifiable, Sendable {
    struct Club: Codable, Equatable, Sendable {
        let name: String
    }

    /// `club_members.id`: spiller-id-en din i klubbens runder og påmeldingen i turneringen.
    let id: UUID
    let clubID: UUID
    var club: Club?

    var clubName: String { club?.name ?? "Klubben" }

    enum CodingKeys: String, CodingKey {
        case id
        case clubID = "club_id"
        case club = "clubs"
    }

    static let columns = "id, club_id, clubs(name)"
}

/// En klubbrunde du spiller som deltaker: nok til å åpne føringen (`RundeSource.participant`).
nonisolated struct ParticipantRound: Hashable, Sendable {
    let roundID: UUID
    let clubID: UUID
    /// Deltakerraden din i klubben.
    let memberID: UUID

    init(roundID: UUID, clubID: UUID, memberID: UUID) {
        self.roundID = roundID
        self.clubID = clubID
        self.memberID = memberID
    }

    init(roundID: UUID, participation: Participation) {
        self.init(roundID: roundID, clubID: participation.clubID, memberID: participation.id)
    }
}

/// Rundene du spiller som deltaker. Ren, uten nettverk.
nonisolated enum ParticipantRounds {
    /// Deltakerraden din i klubben, eller nil (ingen klubb, eller du er ikke deltaker der).
    static func participation(forClub clubID: UUID?, in participations: [Participation]) -> Participation? {
        guard let clubID else { return nil }
        return participations.first { $0.clubID == clubID }
    }

    /// Runden som føring for deltakeren: bare når du spiller i den med deltakerraden.
    static func round(_ snapshot: RoundSnapshot, participations: [Participation]) -> ParticipantRound? {
        guard let p = participation(forClub: snapshot.round.clubID, in: participations),
              snapshot.players.contains(where: { $0.memberID == p.id }) else { return nil }
        return ParticipantRound(roundID: snapshot.round.id, participation: p)
    }

    /// «Turneringsrunder» i Spill: rundene som går og som du spiller i, nyeste først.
    static func items(_ snapshots: [RoundSnapshot], participations: [Participation],
                      referenceYear: Int? = nil) -> [(item: MyRoundItem, round: ParticipantRound)] {
        snapshots
            .filter { $0.round.status == .active && !$0.round.isPlayoff }
            .compactMap { s -> (item: MyRoundItem, round: ParticipantRound)? in
                guard let round = round(s, participations: participations),
                      let p = participation(forClub: s.round.clubID, in: participations) else { return nil }
                let item = MyRounds.item(s, viewer: Viewer(memberID: round.memberID, isOrganizer: false),
                                         prefix: p.clubName, referenceYear: referenceYear)
                return (item, round)
            }
            .sorted { $0.item.sortKey > $1.item.sortKey }
    }

    /// Medlemskapene til `HomeViewer` (Pågår nå uten klubb): deltakerraden per klubb.
    static func memberships(_ participations: [Participation]) -> [UUID: UUID] {
        Dictionary(participations.map { ($0.clubID, $0.id) }, uniquingKeysWith: { first, _ in first })
    }
}

/// Nettverket for deltakermodusen. RLS (sql/059): du leser dine egne rader (`user_id = auth.uid()`),
/// og rundene, spillerne og banene i turneringene du er påmeldt.
enum ParticipationQueries {
    /// Deltakerradene dine som er aktive, med klubbnavnet.
    static func mine(client: SupabaseClient, userID: UUID) async throws -> [Participation] {
        try await client.from("club_members")
            .select(Participation.columns)
            .eq("user_id", value: userID)
            .eq("kind", value: MemberKind.participant.rawValue)
            .eq("status", value: MemberStatus.active.rawValue)
            .execute().value
    }

    /// Klubbrundene som går og der en av deltakerradene dine spiller, med alt under.
    static func activeRounds(client: SupabaseClient, participations: [Participation]) async throws -> [RoundSnapshot] {
        guard !participations.isEmpty else { return [] }
        struct Played: Decodable {
            let roundID: UUID
            enum CodingKeys: String, CodingKey { case roundID = "round_id" }
        }
        let played: [Played] = try await client.from("round_players")
            .select("round_id")
            .in("member_id", values: participations.map(\.id.uuidString))
            .execute().value
        let ids = Set(played.map(\.roundID))
        guard !ids.isEmpty else { return [] }
        let rounds: [RoundRow] = try await client.from("rounds")
            .select(RoundRow.columns)
            .in("id", values: ids.map(\.uuidString))
            .eq("status", value: RoundStatus.active.rawValue)
            .execute().value
        return try await withThrowingTaskGroup(of: RoundSnapshot.self) { group in
            for round in rounds.ordinary {
                group.addTask { try await RundeQueries.snapshot(client: client, round: round) }
            }
            var out: [RoundSnapshot] = []
            for try await s in group { out.append(s) }
            return out
        }
    }

    /// Runden fra en push (`.clubRound`) uten klubb: føringen når runden hører til en klubb der du er
    /// deltaker. nil ellers (ukjent runde, eller en klubb du ikke er deltaker i).
    static func participantRound(client: SupabaseClient, userID: UUID, roundID: UUID) async -> ParticipantRound? {
        struct Club: Decodable {
            let clubID: UUID?
            enum CodingKeys: String, CodingKey { case clubID = "club_id" }
        }
        async let participations = mine(client: client, userID: userID)
        async let rows: [Club] = client.from("rounds").select("club_id").eq("id", value: roundID).limit(1)
            .execute().value
        guard let club = (try? await rows)?.first?.clubID,
              let p = ParticipantRounds.participation(forClub: club, in: (try? await participations) ?? []) else {
            return nil
        }
        return ParticipantRound(roundID: roundID, participation: p)
    }
}
