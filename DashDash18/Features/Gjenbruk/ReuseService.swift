import Foundation
import GolfgutuCore
import Observation
import Supabase

/// Kallene for gjenbruk (sql/049): serier av spilledager, «Samme som sist» og malene. Mangler 049
/// (tabellen, kolonnen eller funksjonen), skjules funksjonene i stedet for å vise en feil.
nonisolated enum ReuseService {
    /// Finnes ikke tabellen, kolonnen eller funksjonen (049 er ikke kjørt)?
    static func isMissing(_ error: any Error) -> Bool {
        guard let postgrest = error as? PostgrestError else { return false }
        return EveningSignupService.isMissing(postgrest) || postgrest.code == "PGRST205"
    }

    // MARK: Serier

    /// Seriene i klubben, og hvilken serie hver kveld hører til. nil når 049 mangler (eller hentingen
    /// feiler): da vises ingen serier.
    static func series(client: SupabaseClient, clubID: UUID) async -> (series: [UUID: EventSeriesRow], eventSeries: [UUID: UUID])? {
        struct Link: Decodable {
            let id: UUID
            let seriesID: UUID?
            enum CodingKeys: String, CodingKey {
                case id
                case seriesID = "series_id"
            }
        }
        do {
            async let seriesRows: [EventSeriesRow] = client.from("event_series")
                .select(EventSeriesRow.columns)
                .eq("club_id", value: clubID)
                .execute().value
            async let links: [Link] = client.from("events")
                .select("id, series_id")
                .eq("club_id", value: clubID)
                .not("series_id", operator: .is, value: "null")
                .execute().value
            let rows = try await seriesRows
            let pairs = try await links
            return (Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }),
                    Dictionary(pairs.compactMap { link in link.seriesID.map { (link.id, $0) } },
                               uniquingKeysWith: { a, _ in a }))
        } catch {
            return nil
        }
    }

    /// Turneringsraden bak en sesong (`competitions.season_id`, sql/031). Serien hører til den.
    static func competitionID(client: SupabaseClient, seasonID: UUID) async -> UUID? {
        struct Row: Decodable { let id: UUID }
        let rows: [Row]? = try? await client.from("competitions")
            .select("id")
            .eq("season_id", value: seasonID)
            .limit(1)
            .execute().value
        return rows?.first?.id
    }

    /// «Lag serie» (`create_event_series`).
    static func createSeries(client: SupabaseClient, competitionID: UUID, firstDate: String,
                             plan: SeriesPlan) async throws(DataError) -> CreateSeriesResult {
        struct Params: Encodable {
            let competitionID: UUID
            let firstDate: String
            let plan: SeriesPlan

            enum CodingKeys: String, CodingKey {
                case p_competition_id, p_first_date, p_weekday, p_count, p_every_weeks, p_start_time, p_venue
            }

            func encode(to encoder: any Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(competitionID, forKey: .p_competition_id)
                try c.encode(firstDate, forKey: .p_first_date)
                try c.encode(plan.weekday, forKey: .p_weekday)
                try c.encode(plan.count, forKey: .p_count)
                try c.encode(plan.everyWeeks, forKey: .p_every_weeks)
                try c.encode(plan.startTime.flatMap(EventSeriesDates.shortTime), forKey: .p_start_time)
                try c.encode(plan.venue.flatMap(EventSeriesDates.cleanVenue), forKey: .p_venue)
            }
        }
        do {
            return try await client.rpc("create_event_series",
                                        params: Params(competitionID: competitionID, firstDate: firstDate, plan: plan))
                .execute().value
        } catch {
            throw DataError.from(error)
        }
    }

    /// «Bare denne» eller «Denne og fremtidige» (`update_event_series`). Tid og sted settes som gitt
    /// (nil tømmer); `newDate` nil lar datoen stå.
    static func updateSeries(client: SupabaseClient, eventID: UUID, scope: SeriesScope, startTime: String?,
                             venue: String?, newDate: String?) async throws(DataError) -> UpdateSeriesResult {
        struct Params: Encodable {
            let eventID: UUID
            let scope: String
            let startTime: String?
            let venue: String?
            let newDate: String?

            enum CodingKeys: String, CodingKey {
                case p_event_id, p_scope, p_start_time, p_venue, p_new_date
            }

            func encode(to encoder: any Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(eventID, forKey: .p_event_id)
                try c.encode(scope, forKey: .p_scope)
                try c.encode(startTime, forKey: .p_start_time)
                try c.encode(venue, forKey: .p_venue)
                try c.encode(newDate, forKey: .p_new_date)
            }
        }
        do {
            return try await client.rpc("update_event_series", params: Params(
                eventID: eventID, scope: scope.rawValue, startTime: startTime.flatMap(EventSeriesDates.shortTime),
                venue: venue.flatMap(EventSeriesDates.cleanVenue), newDate: newDate))
                .execute().value
        } catch {
            let mapped = DataError.from(error)
            if mapped == .duplicate, let postgrest = error as? PostgrestError { throw .invalid(postgrest.message) }
            throw mapped
        }
    }

    // MARK: Samme som sist

    enum Previous: Equatable, Sendable {
        /// Oppsettet fra forrige runde.
        case found(PreviousRoundSetup)
        /// Ingen startet runde før denne i turneringen.
        case none
        /// 049 mangler eller kallet feilet: bruk det appen finner selv (`QuickStart.previousRound`).
        case unavailable
    }

    /// `previous_round_setup(kveld)`.
    static func previousRoundSetup(client: SupabaseClient, eventID: UUID) async -> Previous {
        struct Params: Encodable { let p_event_id: UUID }
        do {
            let setup: PreviousRoundSetup? = try await client
                .rpc("previous_round_setup", params: Params(p_event_id: eventID))
                .execute().value
            return setup.map(Previous.found) ?? .none
        } catch {
            return .unavailable
        }
    }
}

/// Malene av én type for klubben (eller dine egne når klubben er nil). `templates` er nil når 049
/// mangler eller de ikke er hentet: da skjules «Bruk mal» og «Lagre som mal».
@Observable
final class SetupTemplateStore {
    let kind: TemplateKind
    /// Klubbens maler, eller nil: dine egne (personlige).
    let clubID: UUID?
    private(set) var templates: [SetupTemplateRow]?
    private let client: SupabaseClient

    init(client: SupabaseClient, clubID: UUID?, kind: TemplateKind) {
        self.client = client
        self.clubID = clubID
        self.kind = kind
    }

    #if DEBUG
    /// Skjermprøve uten nett.
    init(preview client: SupabaseClient, clubID: UUID?, kind: TemplateKind, templates: [SetupTemplateRow]) {
        self.client = client
        self.clubID = clubID
        self.kind = kind
        self.templates = templates
    }
    #endif

    var isAvailable: Bool { templates != nil }

    func load() async {
        do {
            var query = client.from("setup_templates")
                .select(SetupTemplateRow.columns)
                .eq("kind", value: kind.rawValue)
            query = if let clubID { query.eq("club_id", value: clubID) } else { query.is("club_id", value: nil) }
            let rows: [SetupTemplateRow] = try await query.execute().value
            templates = rows.sorted { NorwegianSort.areInIncreasingOrder($0.name, $1.name) }
        } catch {
            // Mangler 049, eller nettet er borte: skjul malene (en feil her skal ikke stoppe oppsettet).
            if ReuseService.isMissing(error) || templates == nil { templates = nil }
        }
    }

    /// «Lagre som mal». En mal med samme navn erstattes ikke: databasen sier nei (23505).
    @discardableResult
    func save(name raw: String, payload: some Codable & Sendable, id: UUID? = nil) async throws(DataError) -> SetupTemplateRow {
        let name = try TemplateName.clean(raw).get()
        let json: AnyJSON
        do { json = try AnyJSON(payload) } catch { throw .invalid("Malen kunne ikke lagres.") }
        return try await write(id: id, name: name, payload: json)
    }

    func rename(_ row: SetupTemplateRow, to raw: String) async throws(DataError) {
        let name = try TemplateName.clean(raw).get()
        guard name != row.name else { return }
        try await write(id: row.id, name: name, payload: row.payload)
    }

    func delete(_ row: SetupTemplateRow) async throws(DataError) {
        struct Params: Encodable { let p_id: UUID }
        do {
            let deleted: Bool = try await client.rpc("setup_template_delete", params: Params(p_id: row.id))
                .execute().value
            guard deleted else { throw DataError.notAllowed }
        } catch {
            throw DataError.from(error)
        }
        templates?.removeAll { $0.id == row.id }
    }

    @discardableResult
    private func write(id: UUID?, name: String, payload: AnyJSON) async throws(DataError) -> SetupTemplateRow {
        struct Params: Encodable {
            let id: UUID?
            let clubID: UUID?
            let kind: String
            let name: String
            let payload: AnyJSON

            enum CodingKeys: String, CodingKey { case p_id, p_club_id, p_kind, p_name, p_payload }

            func encode(to encoder: any Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(id, forKey: .p_id)
                try c.encode(clubID, forKey: .p_club_id)
                try c.encode(kind, forKey: .p_kind)
                try c.encode(name, forKey: .p_name)
                try c.encode(payload, forKey: .p_payload)
            }
        }
        let saved: SetupTemplateRow
        do {
            saved = try await client.rpc("setup_template_save", params: Params(
                id: id, clubID: clubID, kind: kind.rawValue, name: name, payload: payload))
                .execute().value
        } catch {
            let mapped = DataError.from(error)
            if mapped == .duplicate { throw .invalid("Det finnes alt en mal med navnet «\(name)».") }
            throw mapped
        }
        var list = (templates ?? []).filter { $0.id != saved.id }
        list.append(saved)
        templates = list.sorted { NorwegianSort.areInIncreasingOrder($0.name, $1.name) }
        return saved
    }
}
