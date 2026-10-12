import Foundation
import GolfgutuCore
import Supabase

/// Spørringene for veddemålene (`sql/012_veddemaal.sql`, `sql/052_veddemaal.sql`). Lesing direkte,
/// skriving bare via RPC-ene. Kalles ikke før `BetsFeature.isEnabled` er på.
///
/// Med 052 hentes veddemålene per bank: turneringen (`bets.competition_id`) eller enkeltrunden
/// (`bets.round_scope`). Mangler 052 (ukjent kolonne eller funksjon), brukes veien fra før:
/// hovedturneringens sesong (`bets.season_id`) og `create_bet`.
enum BetsQueries {
    private nonisolated struct CreateResult: Decodable, Sendable {
        let bet_id: UUID
    }

    private nonisolated struct EnabledRow: Decodable, Sendable {
        let id: UUID
        let name: String?
        let betsEnabled: Bool

        enum CodingKeys: String, CodingKey {
            case id, name
            case betsEnabled = "bets_enabled"
        }
    }

    /// Kolonnen, funksjonen eller tabellen fra 052 finnes ikke.
    nonisolated static func isMissing(_ error: any Error) -> Bool {
        guard let postgrest = error as? PostgrestError else { return false }
        return EveningSignupService.isMissing(postgrest)
    }

    // MARK: Lesing

    /// Hovedturneringen (aktiv, ellers sist ferdige) med runder og tropp, og veddemålene i den.
    /// Med 052: banken er sesongens turneringsrad. Uten: sesongen, som før.
    static func load(client: SupabaseClient, clubID: UUID) async throws -> BetsInput? {
        guard let season = try await TavlaQueries.mainSeason(client: client, clubID: clubID) else { return nil }
        async let tavla = TavlaQueries.load(client: client, season: season)
        if let competition = try await seasonCompetition(client: client, seasonID: season.id) {
            let scope = BetScope.competition(competition.id)
            async let rows = bets(client: client, scope: scope)
            async let bank = bank(client: client, scope: scope)
            var input = BetsInput(tavla: try await tavla, scope: scope, enabled: competition.betsEnabled)
            (input.bets, input.stakes) = try await rows
            input.bank = await bank
            return input
        }
        async let betRows: [BetRow] = client.from("bets")
            .select(BetRow.columns)
            .eq("season_id", value: season.id)
            .order("created_at", ascending: false)
            .execute().value
        let bets = try await betRows
        let stakes: [BetStakeRow] = bets.isEmpty ? [] : try await client.from("bet_stakes")
            .select(BetStakeRow.columns)
            .in("bet_id", values: bets.map(\.id.uuidString))
            .execute().value
        return BetsInput(tavla: try await tavla, bets: bets, stakes: stakes)
    }

    /// En turnering (052): sesongen med tropp og runder som Tavla, ellers tabellens grunnlag (de
    /// tellende rundene og de som står i tabellen). Nil uten 052.
    static func load(client: SupabaseClient, competition: CompetitionRow) async throws -> BetsInput? {
        guard let enabled = try await competitionEnabled(client: client, id: competition.id) else { return nil }
        let scope = BetScope.competition(competition.id)
        async let rows = bets(client: client, scope: scope)
        async let bank = bank(client: client, scope: scope)
        var input: BetsInput
        if competition.kind == .season, let tavla = try await CompetitionQueries.season(client: client, competition: competition) {
            input = BetsInput(tavla: tavla, scope: scope, enabled: enabled)
        } else {
            let participants = try await CompetitionQueries.participants(client: client, competitionID: competition.id)
            let detail = try await CompetitionQueries.detail(client: client, competition: competition, participants: participants)
            input = BetsAssembly.competition(competition, rounds: detail.rawRounds, entrants: detail.input.entrants,
                                             directory: detail.directory, enabled: enabled)
        }
        (input.bets, input.stakes) = try await rows
        input.bank = await bank
        return input
    }

    /// En turnering fra id-en (valgt fra runden). Nil uten 052, eller når du ikke ser den.
    static func load(client: SupabaseClient, competitionID: UUID) async throws -> BetsInput? {
        let rows: [CompetitionRow] = try await client.from("competitions").select(CompetitionRow.columns)
            .eq("id", value: competitionID).execute().value
        guard let competition = rows.first else { return nil }
        return try await load(client: client, competition: competition)
    }

    /// En enkeltrunde med egen bank (052). Nil uten 052, eller når runden ikke finnes for deg.
    static func load(client: SupabaseClient, roundID: UUID) async throws -> BetsInput? {
        guard let enabled = try await roundEnabled(client: client, id: roundID) else { return nil }
        let rounds: [RoundRow] = try await client.from("rounds").select(RoundRow.columns)
            .eq("id", value: roundID).execute().value
        guard let round = rounds.first else { return nil }
        let scope = BetScope.round(roundID)
        async let rows = bets(client: client, scope: scope)
        async let bank = bank(client: client, scope: scope)
        let snapshot = try await RundeQueries.snapshot(client: client, round: round)
        let (bets, stakes) = try await rows
        return BetsAssembly.round(snapshot, bets: bets, stakes: stakes, enabled: enabled, bank: await bank)
    }

    /// Veddemålene og innsatsene i én bank (052).
    static func bets(client: SupabaseClient, scope: BetScope) async throws -> ([BetRow], [BetStakeRow]) {
        let column: String
        let id: UUID
        switch scope {
        case .competition(let c): column = "competition_id"; id = c
        case .round(let r): column = "round_scope"; id = r
        }
        let bets: [BetRow] = try await client.from("bets")
            .select(BetRow.columnsV2)
            .eq(column, value: id)
            .order("created_at", ascending: false)
            .execute().value
        let stakes: [BetStakeRow] = bets.isEmpty ? [] : try await client.from("bet_stakes")
            .select(BetStakeRow.columnsV2)
            .in("bet_id", values: bets.map(\.id.uuidString))
            .execute().value
        return (bets, stakes)
    }

    /// Din bank (`bet_bank`). Nil når du ikke er med i banken, eller ved feil: da regnes den av
    /// veddemålene som er hentet.
    static func bank(client: SupabaseClient, scope: BetScope) async -> BetBankRow? {
        let rows: [BetBankRow]? = try? await client.rpc("bet_bank", params: BetScopeParams(scope)).execute().value
        return rows?.first
    }

    /// Sesongens turneringsrad med `bets_enabled`. Nil uten 052 (eller uten speilet rad).
    private static func seasonCompetition(client: SupabaseClient, seasonID: UUID) async throws -> EnabledRow? {
        do {
            let rows: [EnabledRow] = try await client.from("competitions").select("id, name, bets_enabled")
                .eq("season_id", value: seasonID).execute().value
            return rows.first
        } catch where isMissing(error) {
            return nil
        }
    }

    /// `competitions.bets_enabled`. Nil uten 052.
    static func competitionEnabled(client: SupabaseClient, id: UUID) async throws -> Bool? {
        do {
            let rows: [EnabledRow] = try await client.from("competitions").select("id, name, bets_enabled")
                .eq("id", value: id).execute().value
            return rows.first?.betsEnabled ?? false
        } catch where isMissing(error) {
            return nil
        }
    }

    /// `rounds.bets_enabled`. Nil uten 052.
    static func roundEnabled(client: SupabaseClient, id: UUID) async throws -> Bool? {
        struct Row: Decodable {
            let betsEnabled: Bool
            enum CodingKeys: String, CodingKey { case betsEnabled = "bets_enabled" }
        }
        do {
            let rows: [Row] = try await client.from("rounds").select("bets_enabled")
                .eq("id", value: id).execute().value
            return rows.first?.betsEnabled ?? false
        } catch where isMissing(error) {
            return nil
        }
    }

    /// Bankene en runde kan vedde i (052): turneringene den hører til (kveldens turnering eller
    /// sesong, og «Teller også i …») med veddemål på, og rundens egen når den er slått på. Nil
    /// uten 052: da gjelder hovedturneringen som før.
    static func scopes(client: SupabaseClient, round: RoundRow, roundName: String) async throws -> [BetScopeOption]? {
        guard let roundEnabled = try await roundEnabled(client: client, id: round.id) else { return nil }
        struct EventLink: Decodable {
            let competitionID: UUID?
            let seasonID: UUID?
            enum CodingKeys: String, CodingKey {
                case competitionID = "competition_id"
                case seasonID = "season_id"
            }
        }
        async let linkRows = CompetitionQueries.links(client: client, roundID: round.id)
        var event: EventLink?
        if let eventID = round.eventID {
            let rows: [EventLink] = try await client.from("events").select("competition_id, season_id")
                .eq("id", value: eventID).execute().value
            event = rows.first
        }
        var ids = Set(try await linkRows.map(\.competitionID))
        if let id = event?.competitionID { ids.insert(id) }
        var candidates: [EnabledRow] = []
        if !ids.isEmpty {
            let rows: [EnabledRow] = try await client.from("competitions").select("id, name, bets_enabled")
                .in("id", values: ids.map(\.uuidString)).execute().value
            candidates += rows
        }
        if let season = event?.seasonID {
            let rows: [EnabledRow] = try await client.from("competitions").select("id, name, bets_enabled")
                .eq("season_id", value: season).execute().value
            candidates += rows
        }
        return BetScopeChoice.options(
            competitions: candidates.map { .init(id: $0.id, name: $0.name ?? "Turneringen", enabled: $0.betsEnabled) },
            roundID: round.id, roundEnabled: roundEnabled, roundName: roundName)
    }

    // MARK: Skriving

    /// Veddemålet og første innsats i én transaksjon (før 052). Returnerer id-en.
    static func create(client: SupabaseClient, _ params: CreateBetParams) async throws -> UUID {
        let result: CreateResult = try await client.rpc("create_bet", params: params).execute().value
        return result.bet_id
    }

    /// Veddemålet og første innsats i turneringens eller rundens bank (052).
    static func create(client: SupabaseClient, _ params: CreateBetV2Params) async throws -> UUID {
        let result: CreateResult = try await client.rpc("create_bet_v2", params: params).execute().value
        return result.bet_id
    }

    static func stake(client: SupabaseClient, betID: UUID, side: BetSide, points: Int) async throws {
        try await client.rpc("place_bet_stake", params: PlaceStakeParams(p_bet_id: betID, p_side: side, p_points: points))
            .execute()
    }

    /// Arrangøren for hånd. Avvises når hun har innsats i veddemålet.
    static func resolve(client: SupabaseClient, betID: UUID, verdict: BetVerdict) async throws {
        try await client.rpc("resolve_bet", params: ResolveBetParams(p_bet_id: betID, p_resolution: verdict.rawValue))
            .execute()
    }

    /// Feiingen på arrangørens telefon: bare veddemål med vilkår, og bare når scorene kan ha gitt svar.
    static func settle(client: SupabaseClient, betID: UUID, verdict: BetVerdict) async throws {
        try await client.rpc("settle_bet", params: ResolveBetParams(p_bet_id: betID, p_resolution: verdict.rawValue))
            .execute()
    }

    /// Slår veddemål på eller av i turneringen eller runden (`bets_set_enabled`, 052).
    static func setEnabled(client: SupabaseClient, scope: BetScope, enabled: Bool) async throws {
        try await client.rpc("bets_set_enabled", params: BetsSetEnabledParams(scope: scope, enabled: enabled)).execute()
    }
}
