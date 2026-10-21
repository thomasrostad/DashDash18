import Foundation
import GolfgutuCore
import Supabase
import Synchronization

/// Formene fra steg 7 (sql/048): flere konkurranser på samme runde (`round_competitions`),
/// øyeblikksbildet ved start (`rounds.rules_snapshot`, `holes_snapshot`) og lag mot lag
/// (`round_players.side`).
///
/// Før 048 er kjørt finnes ikke tabellen og kolonnene. Appen spør én gang per innlogging (`detect`) og
/// husker svaret. Uten 048 er alt som før: én konkurranse (formen), ingen sider og ingen øyeblikksbilde.
nonisolated enum RoundFormatsFeature {
    private static let key = "roundFormats048"
    private static let state = Mutex<Bool>(UserDefaults.standard.bool(forKey: key))

    /// Tabellen og kolonnene fra 048 finnes (sist appen sjekket).
    static var isAvailable: Bool { state.withLock { $0 } }

    /// For tester og for `detect`.
    static func set(_ available: Bool) {
        state.withLock { $0 = available }
        UserDefaults.standard.set(available, forKey: key)
    }

    /// Spør databasen om tabellen finnes. En annen feil (nettet borte) endrer ingenting.
    static func detect(client: SupabaseClient) async {
        do {
            _ = try await client.from("round_competitions").select("id").limit(1).execute()
            set(true)
        } catch let error as PostgrestError where EveningSignupService.isMissing(error) {
            set(false)
        } catch {
            // Behold det vi visste.
        }
    }

    /// Feilen betyr at 048 mangler (funksjon, tabell eller kolonne). Da slås delene av.
    static func isMissing(_ error: any Error) -> Bool {
        guard let postgrest = error as? PostgrestError else { return false }
        return EveningSignupService.isMissing(postgrest)
    }
}

// MARK: - Oppsettet for én konkurranse

/// `round_competitions.config` med `format_version` 1: motorens `RoundCompetition` uten id.
/// Nøklene er nøyaktig de 048 godtar (`private.round_competition_problem`); felt som er nil, sendes ikke.
nonisolated struct CompetitionConfig: Codable, Hashable, Sendable {
    /// Katalogens form-id (`CompetitionForm`), som `rounds.format`.
    var form: String?
    /// Aksene, når konkurransen ikke er en form i katalogen (f.eks. bestball med stableford).
    var teamForm: TeamForm?
    var scoring: ScoringMethod?
    /// Lag eller grupper med spiller-id-er (`round_players.member_id`). nil: alle, hver for seg eller
    /// i én gruppe (se `RoundCompetition.entrants`).
    var entrants: [[String]]?
    /// Hullene, 0-basert og inkludert. nil: alle.
    var holes: HoleRange?
    /// Andelen av spillehandicapet i runden, 0–1. nil: fullt. Ikke på hovedkonkurransen.
    var allowance: Double?

    /// Nøklene 048 godtar i versjon 1.
    static let allowedKeys: Set<String> = ["form", "teamForm", "scoring", "entrants", "holes", "allowance"]
    static let formatVersion = 1

    init(form: String? = nil, teamForm: TeamForm? = nil, scoring: ScoringMethod? = nil,
         entrants: [[String]]? = nil, holes: HoleRange? = nil, allowance: Double? = nil) {
        self.form = form
        self.teamForm = teamForm
        self.scoring = scoring
        self.entrants = entrants
        self.holes = holes
        self.allowance = allowance
    }

    /// Lagform og poengtelling: aksene når begge står, ellers formens.
    var axes: FormAxes {
        if let teamForm, let scoring { return FormAxes(teamForm: teamForm, scoring: scoring) }
        return CompetitionForm.form(id: form ?? CompetitionForm.all[0].id).axes
    }
}

/// En rad i `round_competitions`. Et oppsett appen ikke kan lese (ny versjon eller ukjent felt) gir
/// `config == nil`, og konkurransen vises med `RoundCompetitionBoard.unsupportedText`.
nonisolated struct RoundCompetitionRow: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID
    let roundID: UUID
    var name: String
    var isMain: Bool
    var formatVersion: Int
    var config: CompetitionConfig?
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id
        case roundID = "round_id"
        case name
        case isMain = "is_main"
        case formatVersion = "format_version"
        case config
        case sortOrder = "sort_order"
    }

    static let columns = "id, round_id, name, is_main, format_version, config, sort_order"

    init(id: UUID = UUID(), roundID: UUID, name: String, isMain: Bool = false, formatVersion: Int = 1,
         config: CompetitionConfig?, sortOrder: Int = 0) {
        self.id = id
        self.roundID = roundID
        self.name = name
        self.isMain = isMain
        self.formatVersion = formatVersion
        self.config = config
        self.sortOrder = sortOrder
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        roundID = try c.decode(UUID.self, forKey: .roundID)
        name = try c.decode(String.self, forKey: .name)
        isMain = (try? c.decode(Bool.self, forKey: .isMain)) ?? false
        formatVersion = (try? c.decode(Int.self, forKey: .formatVersion)) ?? 1
        sortOrder = (try? c.decode(Int.self, forKey: .sortOrder)) ?? 0
        config = formatVersion == CompetitionConfig.formatVersion
            ? (try? c.decode(CompetitionConfig.self, forKey: .config)) : nil
    }
}

/// Ett element i `round_competitions_set(p_round_id, p_competitions)`.
nonisolated struct CompetitionWrite: Encodable, Equatable, Sendable {
    let id: UUID?
    let name: String
    let isMain: Bool
    let formatVersion: Int
    let config: CompetitionConfig
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, name, config
        case isMain = "is_main"
        case formatVersion = "format_version"
        case sortOrder = "sort_order"
    }

    init(id: UUID?, name: String, isMain: Bool, config: CompetitionConfig, sortOrder: Int) {
        self.id = id
        self.name = name
        self.isMain = isMain
        formatVersion = CompetitionConfig.formatVersion
        self.config = config
        self.sortOrder = sortOrder
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(isMain, forKey: .isMain)
        try c.encode(formatVersion, forKey: .formatVersion)
        try c.encode(config, forKey: .config)
        try c.encode(sortOrder, forKey: .sortOrder)
    }
}

/// En konkurranse slik «Samme som sist» (`previous_round_setup.competitions`) og rundemalene har den:
/// uten id, så den lagres som ny rad.
nonisolated struct CompetitionCopy: Codable, Equatable, Sendable {
    var name: String
    var isMain: Bool
    var formatVersion: Int
    var config: CompetitionConfig?
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case name, config
        case isMain = "is_main"
        case formatVersion = "format_version"
        case sortOrder = "sort_order"
    }

    init(name: String, isMain: Bool, config: CompetitionConfig?, sortOrder: Int) {
        self.name = name
        self.isMain = isMain
        formatVersion = CompetitionConfig.formatVersion
        self.config = config
        self.sortOrder = sortOrder
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        isMain = (try? c.decode(Bool.self, forKey: .isMain)) ?? false
        formatVersion = (try? c.decode(Int.self, forKey: .formatVersion)) ?? 1
        sortOrder = (try? c.decode(Int.self, forKey: .sortOrder)) ?? 0
        config = formatVersion == CompetitionConfig.formatVersion
            ? (try? c.decode(CompetitionConfig.self, forKey: .config)) : nil
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(isMain, forKey: .isMain)
        try c.encode(formatVersion, forKey: .formatVersion)
        try c.encodeIfPresent(config, forKey: .config)
        try c.encode(sortOrder, forKey: .sortOrder)
    }
}

// MARK: - Øyeblikksbildet

/// `rounds.rules_snapshot`, `holes_snapshot` og `snapshot_source` for én runde (sql/048).
/// Et regelsett eller hull som ikke kan leses, regnes som borte (appen faller tilbake til dagens data).
nonisolated struct RoundFreeze: Decodable, Equatable, Sendable {
    /// Ett hull i `holes_snapshot.holes`, som motorens `PlayedHole`. par er null når ingen kilde har par.
    struct Hole: Decodable, Equatable, Sendable {
        var hole: Int?
        var par: Int?
        var cardIndex: Int?
        var meters: Double?
        var strokeIndex: Int?
    }

    var rules: Ruleset?
    var holes: [Hole]?
    /// `start`, `refresh` eller `backfill` (rekonstruert da 048 ble kjørt). nil: kladd.
    var source: String?

    enum CodingKeys: String, CodingKey {
        case rules = "rules_snapshot"
        case holes = "holes_snapshot"
        case source = "snapshot_source"
    }

    private struct HolesWrapper: Decodable { var holes: [Hole] }

    static let columns = "rules_snapshot, holes_snapshot, snapshot_source"

    init(rules: Ruleset? = nil, holes: [Hole]? = nil, source: String? = nil) {
        self.rules = rules
        self.holes = holes
        self.source = source
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rules = (try? c.decodeIfPresent(Ruleset.self, forKey: .rules)) ?? nil
        holes = ((try? c.decodeIfPresent(HolesWrapper.self, forKey: .holes)) ?? nil)?.holes
        source = (try? c.decodeIfPresent(String.self, forKey: .source)) ?? nil
    }

    /// Øyeblikksbildet er rekonstruert fra data da 048 ble kjørt, ikke frosset ved start.
    var isReconstructed: Bool { source == "backfill" }
}

// MARK: - Spørringer

nonisolated enum RoundFormatsQueries {
    /// Konkurransene på runden, i rekkefølge. Tom uten 048.
    static func competitions(client: SupabaseClient, roundID: UUID) async -> [RoundCompetitionRow] {
        guard RoundFormatsFeature.isAvailable else { return [] }
        do {
            return try await client.from("round_competitions")
                .select(RoundCompetitionRow.columns)
                .eq("round_id", value: roundID)
                .order("sort_order")
                .execute().value
        } catch {
            if RoundFormatsFeature.isMissing(error) { RoundFormatsFeature.set(false) }
            return []
        }
    }

    /// Øyeblikksbildet for runden. nil uten 048 eller når hentingen feiler.
    static func freeze(client: SupabaseClient, roundID: UUID) async -> RoundFreeze? {
        guard RoundFormatsFeature.isAvailable else { return nil }
        do {
            let rows: [RoundFreeze] = try await client.from("rounds")
                .select(RoundFreeze.columns)
                .eq("id", value: roundID)
                .execute().value
            return rows.first
        } catch {
            if RoundFormatsFeature.isMissing(error) { RoundFormatsFeature.set(false) }
            return nil
        }
    }

    /// Lagrer hele lista (`round_competitions_set`). Gir radene slik de ble lagret.
    @discardableResult
    static func save(client: SupabaseClient, roundID: UUID, competitions: [CompetitionWrite]) async throws -> [RoundCompetitionRow] {
        struct Params: Encodable {
            let p_round_id: UUID
            let p_competitions: [CompetitionWrite]
        }
        return try await client
            .rpc("round_competitions_set", params: Params(p_round_id: roundID, p_competitions: competitions))
            .execute().value
    }

    /// «Oppdater øyeblikksbildet» (`round_snapshot_refresh`): regelsettet og hullene på nytt fra dagens
    /// data, bare mens runden går.
    static func refreshSnapshot(client: SupabaseClient, roundID: UUID) async throws(DataError) {
        struct Params: Encodable { let p_round_id: UUID }
        do {
            _ = try await client.rpc("round_snapshot_refresh", params: Params(p_round_id: roundID)).execute()
        } catch {
            if RoundFormatsFeature.isMissing(error) {
                RoundFormatsFeature.set(false)
                throw .invalid("Øyeblikksbildet finnes ikke ennå.")
            }
            if (error as? PostgrestError)?.code == "55000" {
                throw .invalid("Øyeblikksbildet kan bare oppdateres mens runden går.")
            }
            throw DataError.from(error)
        }
    }
}
