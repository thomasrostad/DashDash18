import Foundation
import GolfgutuCore
import Supabase

/// Nettverket for konkurransene (sql/017 og 022). Brukes bare når `CompetitionsFeature` er på.
/// Alt som skriver flere rader, går gjennom én RPC.
enum CompetitionQueries {
    static let participantColumns = "id, competition_id, member_id, profile_id, status"
    static let linkColumns = "competition_id, round_id, source"
    static let roundParticipantColumns = "id, round_id, profile_id, display_name, handicap_index"

    /// Konkurransene du kan se, påmeldingene i dem og hvilke cuper som er trukket.
    struct Overview: Equatable, Sendable {
        var competitions: [CompetitionRow] = []
        var participants: [CompetitionParticipantRow] = []
        /// Cuper med trekning.
        var drawn: Set<UUID> = []
    }

    static func overview(client: SupabaseClient) async throws -> Overview {
        let competitions: [CompetitionRow] = try await client.from("competitions")
            .select(CompetitionRow.columnsWithSignup)
            .neq("kind", value: CompetitionKind.game.rawValue)
            .order("created_at", ascending: false)
            .execute().value
        guard !competitions.isEmpty else { return Overview() }
        let ids = competitions.map(\.id.uuidString)
        async let participantRows: [CompetitionParticipantRow] = client.from("competition_participants")
            .select(participantColumns)
            .in("competition_id", values: ids)
            .execute().value
        let cups = competitions.filter { $0.kind == .cup }.map(\.id.uuidString)
        struct Drawn: Decodable {
            let competitionID: UUID
            enum CodingKeys: String, CodingKey { case competitionID = "competition_id" }
        }
        async let drawnRows: [Drawn] = cups.isEmpty ? [] : client.from("competition_matches")
            .select("competition_id")
            .in("competition_id", values: cups)
            .eq("round_no", value: 1)
            .execute().value
        return Overview(competitions: competitions, participants: try await participantRows,
                        drawn: Set(try await drawnRows.map(\.competitionID)))
    }

    // MARK: Én konkurranse

    /// Påmeldingene i én konkurranse (samme RLS som i oversikten: `can_read_competition`).
    static func participants(client: SupabaseClient, competitionID: UUID) async throws -> [CompetitionParticipantRow] {
        try await client.from("competition_participants")
            .select(participantColumns)
            .eq("competition_id", value: competitionID)
            .execute().value
    }

    /// Alt tabellen trenger for en liga, cup eller morroturnering: de tellende rundene med alt
    /// under, personene bak spillerne, de påmeldte og cupkampene.
    struct Detail: Sendable {
        let competition: CompetitionRow
        let participants: [CompetitionParticipantRow]
        let scope: CompetitionScope
        let input: CompetitionInput
        let directory: PersonDirectory
        let matches: [CompetitionMatchRow]
    }

    static func detail(client: SupabaseClient, competition: CompetitionRow,
                       participants: [CompetitionParticipantRow]) async throws -> Detail {
        let links: [CompetitionRoundRow] = try await client.from("competition_rounds")
            .select(linkColumns)
            .eq("competition_id", value: competition.id)
            .execute().value
        let roundIDs = links.map(\.roundID.uuidString)
        // Kladder teller ikke (og bare arrangøren ser dem).
        let rounds: [RoundRow] = roundIDs.isEmpty ? [] : try await client.from("rounds")
            .select(RundeQueries.roundColumns)
            .in("id", values: roundIDs)
            .in("status", values: [RoundStatus.active.rawValue, RoundStatus.locked.rawValue])
            .execute().value
        let ids = rounds.map(\.id.uuidString)

        async let snapshotRows = snapshots(client: client, rounds: rounds)
        async let rosterRows: [RoundRosterRow] = ids.isEmpty ? [] : client.from("round_roster")
            .select(LooseRoundQueries.rosterColumns).in("round_id", values: ids).execute().value
        async let roundParticipantRows: [RoundParticipantRow] = ids.isEmpty ? [] : client.from("round_participants")
            .select(roundParticipantColumns).in("round_id", values: ids).execute().value
        async let memberRows = members(client: client, clubID: competition.clubID)
        async let matchRows: [CompetitionMatchRow] = competition.kind == .cup
            ? client.from("competition_matches").select(CompetitionMatchRow.columns)
                .eq("competition_id", value: competition.id).execute().value
            : []

        let snapshots = try await snapshotRows
        let roster = try await rosterRows
        let roundParticipants = try await roundParticipantRows
        let members = try await memberRows
        let matches = try await matchRows

        let profileIDs = Set(participants.compactMap(\.profileID) + roster.compactMap(\.profileID)
                             + roundParticipants.compactMap(\.profileID))
        let profiles: [ProfileRow] = profileIDs.isEmpty ? [] : try await client.from("profiles")
            .select(LooseRoundQueries.profileColumns)
            .in("id", values: profileIDs.map(\.uuidString))
            .execute().value

        let directory = PersonDirectory(members: members + rosterMembers(roster), participants: roundParticipants,
                                        profiles: profiles)
        let scope = CompetitionScope(competition: competition, links: links, participants: participants)
        return Detail(competition: competition, participants: participants.filter { $0.competitionID == competition.id },
                      scope: scope, input: scope.input(candidates: snapshots, directory: directory),
                      directory: directory, matches: matches)
    }

    /// Spillerne i klubbrundene som «medlemmer» med navn og profil fra `round_roster`, for den som
    /// ser rundene via konkurransen uten å kunne lese troppen. Ekte tropp går foran (`PersonDirectory`).
    nonisolated static func rosterMembers(_ roster: [RoundRosterRow]) -> [ClubMemberRow] {
        roster.compactMap { r in
            guard let club = r.clubID else { return nil }
            return ClubMemberRow(id: r.playerID, clubID: club, userID: r.profileID, displayName: r.displayName ?? "",
                                 handicapIndex: nil, seedGroup: nil, isOrganizer: false, isTreasurer: false,
                                 status: .archived, avatarPath: nil)
        }
    }

    /// De aktive i troppen, i navnerekkefølge (påmeldte i «Ny konkurranse»).
    static func activeMembers(client: SupabaseClient, clubID: UUID) async throws -> [ClubMemberRow] {
        let rows: [ClubMemberRow] = try await client.from("club_members").select(KveldQueries.memberColumns)
            .eq("club_id", value: clubID).eq("status", value: MemberStatus.active.rawValue).execute().value
        return KveldQueries.sortedByName(rows)
    }

    /// Troppen i konkurransens klubb (tom for private, og for den som ikke er medlem).
    private static func members(client: SupabaseClient, clubID: UUID?) async throws -> [ClubMemberRow] {
        guard let clubID else { return [] }
        return try await client.from("club_members").select(KveldQueries.memberColumns)
            .eq("club_id", value: clubID).execute().value
    }

    private static func snapshots(client: SupabaseClient, rounds: [RoundRow]) async throws -> [RoundSnapshot] {
        try await withThrowingTaskGroup(of: RoundSnapshot.self) { group in
            for round in rounds {
                group.addTask { try await RundeQueries.snapshot(client: client, round: round) }
            }
            var out: [RoundSnapshot] = []
            for try await s in group { out.append(s) }
            return out
        }
    }

    /// Jakkeracet (sesongens konkurranse) som Tavla regner det i dag.
    static func season(client: SupabaseClient, competition: CompetitionRow) async throws -> TavlaInput? {
        guard let seasonID = competition.seasonID, let club = competition.clubID else { return nil }
        let season = SeasonRow(id: seasonID, clubID: club, name: competition.name, status: competition.status,
                               rules: competition.rules)
        return try await TavlaQueries.load(client: client, season: season)
    }

    // MARK: Skriving (sql/022)

    static func create(client: SupabaseClient, _ params: CreateCompetitionParams) async throws -> UUID {
        try await client.rpc("create_competition_with_entrants", params: params).execute().value
    }

    static func join(client: SupabaseClient, competitionID: UUID) async throws -> CompetitionParticipantRow {
        struct Params: Encodable { let p_competition_id: UUID }
        return try await client.rpc("join_competition", params: Params(p_competition_id: competitionID)).execute().value
    }

    @discardableResult
    static func leave(client: SupabaseClient, competitionID: UUID) async throws -> Bool {
        struct Params: Encodable { let p_competition_id: UUID }
        return try await client.rpc("leave_competition", params: Params(p_competition_id: competitionID)).execute().value
    }

    /// Koblingene runden har til konkurranser (alle kilder).
    static func links(client: SupabaseClient, roundID: UUID) async throws -> [CompetitionRoundRow] {
        try await client.from("competition_rounds")
            .select(linkColumns)
            .eq("round_id", value: roundID)
            .execute().value
    }

    /// «Teller også i …»: rundens manuelle koblinger blant konkurransene du styrer blir `ids`.
    static func setRoundCompetitions(client: SupabaseClient, roundID: UUID, ids: [UUID]) async throws {
        struct Params: Encodable { let p_round_id: UUID; let p_competition_ids: [UUID] }
        _ = try await client.rpc("set_round_competitions", params: Params(p_round_id: roundID, p_competition_ids: ids))
            .execute()
    }

    static func draw(client: SupabaseClient, competitionID: UUID, pairings: [CupPairingParam]) async throws {
        struct Params: Encodable { let p_competition_id: UUID; let p_pairings: [CupPairingParam] }
        _ = try await client.rpc("draw_cup", params: Params(p_competition_id: competitionID, p_pairings: pairings))
            .execute()
    }

    static func record(client: SupabaseClient, competitionID: UUID, round: Int, slot: Int, winner: UUID?,
                       walkover: Bool, result: String?, roundID: UUID?) async throws {
        struct Params: Encodable {
            let p_competition_id: UUID
            let p_round_no: Int
            let p_slot: Int
            let p_winner: UUID?
            let p_walkover: Bool
            let p_result: String?
            let p_round_id: UUID?

            // p_winner skrives alltid (null fjerner resultatet).
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(p_competition_id, forKey: .p_competition_id)
                try c.encode(p_round_no, forKey: .p_round_no)
                try c.encode(p_slot, forKey: .p_slot)
                try c.encode(p_winner, forKey: .p_winner)
                try c.encode(p_walkover, forKey: .p_walkover)
                try c.encodeIfPresent(p_result, forKey: .p_result)
                try c.encodeIfPresent(p_round_id, forKey: .p_round_id)
            }

            enum CodingKeys: String, CodingKey {
                case p_competition_id, p_round_no, p_slot, p_winner, p_walkover, p_result, p_round_id
            }
        }
        _ = try await client.rpc("record_cup_result", params: Params(
            p_competition_id: competitionID, p_round_no: round, p_slot: slot, p_winner: winner, p_walkover: walkover,
            p_result: result, p_round_id: roundID)).execute()
    }

    // MARK: Invitasjon (private konkurranser)

    /// Koden til konkurransen (`competition_invite`): den som gjelder. Bare eieren lager en ny når
    /// den mangler, og fornyer (`renew`: ny kode, den gamle slutter å virke).
    static func invite(client: SupabaseClient, competitionID: UUID, renew: Bool = false) async throws -> InviteCode {
        struct Params: Encodable { let p_competition_id: UUID; let p_renew: Bool }
        let invite: LooseRoundQueries.Invite = try await client
            .rpc("competition_invite", params: Params(p_competition_id: competitionID, p_renew: renew)).execute().value
        guard let code = InviteCode(invite.code) else { throw DataError.invalid("Serveren ga en ugyldig kode.") }
        return code
    }

    /// Eieren trekker koden tilbake (`revoke_competition_invite`). De påmeldte er fortsatt med.
    static func revokeInvite(client: SupabaseClient, competitionID: UUID) async throws {
        struct Params: Encodable { let p_competition_id: UUID }
        _ = try await client.rpc("revoke_competition_invite", params: Params(p_competition_id: competitionID)).execute()
    }

    static func invitePreview(client: SupabaseClient, code: InviteCode) async throws -> CompetitionInvitePreview {
        struct Params: Encodable { let p_code: String }
        return try await client.rpc("competition_invite_preview", params: Params(p_code: code.value)).execute().value
    }

    /// «Bli med» (`claim_competition_invite`): melder deg på. Én transaksjon.
    static func claimInvite(client: SupabaseClient, code: InviteCode) async throws -> CompetitionClaimResult {
        struct Params: Encodable { let p_code: String }
        return try await client.rpc("claim_competition_invite", params: Params(p_code: code.value)).execute().value
    }

    // MARK: Kveld

    /// Morroturneringene kvelden hører til (perioden eller rundene), for merket på Kveld.
    static func funNames(client: SupabaseClient, event: EventRow) async throws -> [String] {
        let competitions: [CompetitionRow] = try await client.from("competitions")
            .select(CompetitionRow.columns)
            .eq("kind", value: CompetitionKind.fun.rawValue)
            .neq("status", value: SeasonStatus.finished.rawValue)
            .execute().value
        guard !competitions.isEmpty else { return [] }
        struct RoundID: Decodable { let id: UUID }
        let rounds: [RoundID] = try await client.from("rounds").select("id").eq("event_id", value: event.id)
            .execute().value
        let links: [CompetitionRoundRow] = rounds.isEmpty ? [] : try await client.from("competition_rounds")
            .select(linkColumns)
            .in("round_id", values: rounds.map(\.id.uuidString))
            .execute().value
        return CompetitionCalendar.funNames(eventDate: event.eventDate, eventClubID: event.clubID,
                                            roundIDs: Set(rounds.map(\.id)), competitions: competitions, links: links)
    }
}

nonisolated extension CompetitionScope {
    /// Personen bak en påmelding, som tabellen teller hen.
    func entrant(for p: CompetitionParticipantRow, directory: PersonDirectory) -> Entrant? {
        if let member = p.memberID { return .member(member) }
        guard let profile = p.profileID else { return nil }
        if let club = competition.clubID, let member = directory.member(in: club, profile: profile) {
            return .member(member.id)
        }
        return .profile(profile)
    }
}
