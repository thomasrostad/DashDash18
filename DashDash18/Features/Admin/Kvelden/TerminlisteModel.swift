import Foundation
import Observation
import Supabase

/// Det arrangøren fyller inn for en kveld.
struct EventDraft: Equatable {
    var id: UUID?
    var seasonID: UUID?
    /// Liga, cup eller morro: spilledagen hører til turneringen, ikke en sesong (sql/033).
    var competitionID: UUID? = nil
    var date: Date
    var hasTime: Bool
    var time: Date
    var venue: String
    var note: String
    var committee: Set<UUID>
    /// Tak, frister og gjester (sql/045). Står av for nye kvelder.
    var rules = EveningRulesDraft()
}

/// Kveldene for arrangøren: terminlista med sosialkomiteene, påmeldingen per kveld og troppen
/// å velge fra. Brukes av «Kveldene» og «Kvelden».
@Observable
final class TerminlisteModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    /// Bare det terminlista trenger av sesongen (regelsettet hentes ikke).
    struct SeasonSummary: Decodable, Equatable {
        let id: UUID
        let name: String
    }

    private(set) var state: LoadState = .loading
    private(set) var activeSeason: SeasonSummary?
    private(set) var events: [EventRow] = []
    /// Kveld → medlemmer i sosialkomiteen.
    private(set) var committees: [UUID: [UUID]] = [:]
    /// Aktive medlemmer, sortert på navn.
    private(set) var members: [ClubMemberRow] = []
    /// Kveld → svarene. Feiler hentingen, står kveldene uten påmelding.
    private(set) var signups: [UUID: [SignupRow]] = [:]
    /// Kveld → tak, frister og gjester (sql/045). nil når 045 ikke er kjørt: innstillingene skjules.
    private(set) var settings: [UUID: EveningSettingsRow]?
    /// Kveld → gjestene (sql/045).
    private(set) var guests: [UUID: [EventGuestRow]] = [:]
    /// Kveld → medlemmene som har sett den (sql/045). nil: ikke kjent.
    private(set) var views: [UUID: Set<UUID>]?

    /// Tak, frister, gjester og logg finnes (sql/045 er kjørt).
    var supportsSignupRules: Bool { settings != nil }

    /// Seriene i klubben (sql/049), serie-id → serien. nil når 049 ikke er kjørt: da skjules «Lag serie»
    /// og valget «Bare denne» / «Denne og fremtidige».
    private(set) var series: [UUID: EventSeriesRow]?
    /// Kveld → serien den ble laget i.
    private(set) var eventSeries: [UUID: UUID] = [:]
    /// Turneringsraden nye serier hører til: turneringen, eller sesongens rad i `competitions`.
    private(set) var seriesCompetitionID: UUID?

    /// «Lag serie» kan vises: 049 finnes, og lista hører til en turnering.
    var supportsSeries: Bool { series != nil && seriesCompetitionID != nil }

    /// Serien kvelden hører til, når 049 finnes.
    func series(for eventID: UUID?) -> EventSeriesRow? {
        guard let eventID, let id = eventSeries[eventID] else { return nil }
        return series?[id]
    }

    /// Datoene turneringen alt har (de hoppes over i en ny serie).
    var takenDates: Set<String> { Set(events.map(\.eventDate)) }

    private let context: ClubContext
    /// Turneringen kveldene hører til (fase 21). nil: hovedturneringen (den aktive).
    let tournamentID: UUID?
    /// En turnering uten sesong (liga, cup, morro) med egne spilledager (sql/033). Da er lista
    /// turneringens dager, og nye dager får turneringen i stedet for en sesong.
    let competition: CompetitionRow?

    init(context: ClubContext, tournamentID: UUID? = nil, competition: CompetitionRow? = nil) {
        self.context = context
        self.tournamentID = tournamentID
        self.competition = competition
    }

    private var client: SupabaseClient { context.client }
    private var clubID: UUID { context.clubID }

    func load() async {
        do {
            let seasonQuery = SeasonQuery.select(client)
                .eq("club_id", value: clubID)
            // Den valgte turneringen, ellers hovedturneringen (flere serier kan være aktive, sql/034).
            async let seasons: [SeasonRow] = (tournamentID.map { seasonQuery.eq("season_id", value: $0) }
                ?? seasonQuery.eq("status", value: SeasonStatus.active.rawValue))
                .execute().value
            async let mains: Set<UUID> = tournamentID == nil
                ? MainTournament.seasonIDs(client: client, clubID: clubID) : []
            async let eventRows: [EventRow] = client.from("events")
                .select(EventRow.columns)
                .eq("club_id", value: clubID)
                .order("event_date")
                .execute().value
            async let committeeRows: [EventCommitteeRow] = client.from("event_committee")
                .select(EventCommitteeRow.columns)
                .eq("club_id", value: clubID)
                .execute().value
            async let memberRows: [ClubMemberRow] = client.from("club_members")
                .select(ClubMemberRow.columns)
                .eq("club_id", value: clubID)
                .eq("status", value: MemberStatus.active.rawValue)
                .execute().value

            let season = Terminliste.tournament(try await seasons, id: tournamentID, mainSeasonIDs: await mains)
                .map { SeasonSummary(id: $0.id, name: $0.name) }
            let allEvents = try await eventRows
            let committee = try await committeeRows
            let roster = try await memberRows

            activeSeason = competition == nil ? season : nil
            events = competition.map { Terminliste.days(allEvents, competitionID: $0.id) }
                ?? Terminliste.eveningsForSeason(allEvents, activeSeasonID: season?.id)
            committees = Dictionary(grouping: committee, by: \.eventID).mapValues { $0.map(\.memberID) }
            members = KveldQueries.sortedByName(roster)
            state = .loaded
            async let signupsDone: Void = loadSignups()
            async let seriesDone: Void = loadSeries()
            _ = await (signupsDone, seriesDone)
        } catch {
            if case .loaded = state { return }  // behold det vi har ved en feilet oppfrisking
            state = .failed(DataError.from(error).message)
        }
    }

    /// Svarene på sesongens kvelder, med tak, gjester og «sett» (sql/045). Bare et tillegg i lista,
    /// så en feil gir ingen feilet skjerm.
    private func loadSignups() async {
        guard !events.isEmpty else { signups = [:]; return }
        let ids = events.map(\.id)
        async let rows = try? EveningSignupService.signups(client: client, eventIDs: ids)
        async let settingRows = EveningSignupService.settings(client: client, eventIDs: ids)
        async let guestRows = EveningSignupService.guests(client: client, eventIDs: ids)
        async let viewRows = EveningSignupService.views(client: client, eventIDs: ids)
        if let rows = await rows { signups = Dictionary(grouping: rows, by: \.eventID) }
        settings = await settingRows
        guests = Dictionary(grouping: await guestRows, by: \.eventID)
        views = settings == nil ? nil : await viewRows
    }

    /// Seriene og turneringsraden de hører til (sql/049). Bare et tillegg: feiler det, skjules seriene.
    private func loadSeries() async {
        let loaded = await ReuseService.series(client: client, clubID: clubID)
        series = loaded?.series
        eventSeries = loaded?.eventSeries ?? [:]
        guard loaded != nil else { seriesCompetitionID = nil; return }
        if let competition {
            seriesCompetitionID = competition.id
        } else if let season = activeSeason {
            seriesCompetitionID = await ReuseService.competitionID(client: client, seasonID: season.id)
        } else {
            seriesCompetitionID = nil
        }
    }

    // MARK: Serier (sql/049)

    /// «Lag serie»: spilledagene fra og med `firstDate`. Datoer turneringen alt har, hoppes over.
    func createSeries(firstDate: String, plan: SeriesPlan) async throws(DataError) -> CreateSeriesResult {
        guard let competitionID = seriesCompetitionID else { throw .notAllowed }
        let result = try await ReuseService.createSeries(client: client, competitionID: competitionID,
                                                         firstDate: firstDate, plan: plan)
        await load()
        return result
    }

    /// Lagrer en kveld i en serie. «Bare denne» er en vanlig lagring. «Denne og fremtidige» flytter
    /// tid, sted og dato for denne og senere kvelder i serien (`update_event_series`), og lagrer så
    /// notatet, komiteen og påmeldingen for denne. Gir en melding når noen kvelder ble hoppet over.
    func save(_ draft: EventDraft, scope: SeriesScope) async throws(DataError) -> String? {
        guard scope == .future, let id = draft.id, let event = events.first(where: { $0.id == id }),
              series(for: id) != nil else {
            try await save(draft)
            return nil
        }
        let venue = try EventInput.text(draft.venue, max: EventInput.venueMax, field: "Sted").get()
        let date = EveningDates.dateString(from: draft.date)
        let dates = Dictionary(events.map { ($0.id, $0.eventDate) }, uniquingKeysWith: { a, _ in a })
        let result = try await ReuseService.updateSeries(
            client: client, eventID: id, scope: .future,
            startTime: draft.hasTime ? EveningDates.timeString(from: draft.time) : nil,
            venue: venue, newDate: date == event.eventDate ? nil : date)
        try await save(draft)
        return SeriesText.updated(result, dates: dates)
    }

    /// Hele troppen fordelt på svarene for kvelden, med gjestene og hvem som har sett den.
    func signupSummary(for eventID: UUID) -> SignupSummary {
        SignupSummary(members: members, signups: signups[eventID] ?? [], guests: guests[eventID] ?? [],
                      seen: views.map { $0[eventID] ?? [] })
    }

    /// «9 av 12 kommer + 2 gjester · 1 på venteliste».
    func signupText(for eventID: UUID) -> String {
        Tonight.signupText(signups[eventID] ?? [], guests: guests[eventID] ?? [], rosterCount: members.count)
    }

    // MARK: Påmeldingen (arrangøren, sql/045)

    /// Endrer svaret for et medlem. `status` nil fjerner svaret. Arrangøren går forbi fristene.
    func setAnswer(_ event: EventRow, member: UUID, status: SignupStatus?) async throws(DataError) {
        try await EveningSignupService.answer(client: client, event: event, member: member,
                                              ownMemberID: context.memberID, status: status, comment: nil)
        await loadSignups()
    }

    /// Melder på en gjest for et medlem.
    func addGuest(_ event: EventRow, name raw: String, invitedBy: UUID) async throws(DataError) {
        let name = try GuestInput.clean(raw).get()
        try await EveningSignupService.addGuest(client: client, eventID: event.id, name: name, invitedBy: invitedBy)
        await loadSignups()
    }

    func removeGuest(_ guest: EventGuestRow) async throws(DataError) {
        try await EveningSignupService.removeGuest(client: client, guestID: guest.id)
        await loadSignups()
    }

    func log(for event: EventRow) async throws(DataError) -> [SignupLogRow] {
        try await EveningSignupService.log(client: client, eventID: event.id)
    }

    /// Purrer på dem som ikke har svart på kvelden (samme purring som i Kveld). Gir teksten
    /// som skal vises etterpå.
    func nudge(_ event: EventRow) async throws(DataError) -> String {
        guard context.isOrganizer else { throw .notAllowed }
        let missing = Nudge.targets(signupSummary(for: event.id)).map(\.memberID)
        try await ActivityLog(client: client, clubID: clubID)
            .nudge(eventID: event.id, eventDate: event.eventDate, missing: missing)
        return Nudge.doneText(count: missing.count)
    }

    func memberName(_ id: UUID) -> String {
        members.first { $0.id == id }?.displayName ?? "Ukjent"
    }

    /// Komiteen for en kveld som navn, i troppens rekkefølge.
    func committeeNames(for eventID: UUID) -> [String] {
        let ids = Set(committees[eventID] ?? [])
        return members.filter { ids.contains($0.id) }.map(\.displayName)
    }

    func draft(for event: EventRow?) -> EventDraft {
        guard let event else {
            // Ny kveld: neste uke, samme sted og tid som sist.
            let last = events.last
            return EventDraft(
                id: nil, seasonID: activeSeason?.id, competitionID: competition?.id,
                date: Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now,
                hasTime: last?.startTime != nil,
                time: last?.startTime.flatMap { EveningDates.time(from: $0) }
                    ?? EveningDates.time(from: "17:00")!,
                venue: last?.venue ?? "", note: "", committee: []
            )
        }
        let date = EveningDates.date(from: event.eventDate) ?? .now
        return EventDraft(
            id: event.id, seasonID: event.seasonID, competitionID: event.seasonID == nil ? event.competitionID : nil,
            date: EveningDates.date(from: event.eventDate) ?? .now,
            hasTime: event.startTime != nil,
            time: event.startTime.flatMap { EveningDates.time(from: $0) } ?? EveningDates.time(from: "17:00")!,
            venue: event.venue ?? "", note: event.note ?? "",
            committee: Set(committees[event.id] ?? []),
            rules: EveningRulesDraft(settings?[event.id], eventDate: date)
        )
    }

    /// Lagrer kvelden og komiteen. Feilmeldingen er ferdig norsk tekst.
    func save(_ draft: EventDraft) async throws(DataError) {
        let venue = try EventInput.text(draft.venue, max: EventInput.venueMax, field: "Sted").get()
        let note = try EventInput.text(draft.note, max: EventInput.noteMax, field: "Notatet").get()
        let date = EveningDates.dateString(from: draft.date)
        let write = EventWrite(
            clubID: clubID, seasonID: draft.seasonID, competitionID: draft.competitionID, eventDate: date,
            startTime: draft.hasTime ? EveningDates.timeString(from: draft.time) : nil,
            venue: venue, note: note
        )

        let saved: [EventRow]
        do {
            if let id = draft.id {
                saved = try await client.from("events")
                    .update(write)
                    .eq("id", value: id)
                    .select(EventRow.columns)
                    .execute().value
            } else {
                saved = try await client.from("events")
                    .insert(write)
                    .select(EventRow.columns)
                    .execute().value
            }
        } catch {
            throw .invalid(Terminliste.saveErrorMessage(
                sqlState: (error as? PostgrestError)?.code, fallback: DataError.from(error), date: date))
        }
        guard let event = saved.first else { throw .notAllowed }  // RLS sa nei uten feilkode

        try await setCommittee(eventID: event.id, to: draft.committee)
        try await saveRules(draft.rules, eventID: event.id)
        await load()
    }

    func delete(_ event: EventRow) async throws(DataError) {
        let deleted: [EventRow]
        do {
            deleted = try await client.from("events")
                .delete()
                .eq("id", value: event.id)
                .select(EventRow.columns)
                .execute().value
        } catch {
            throw .invalid(Terminliste.deleteErrorMessage(
                sqlState: (error as? PostgrestError)?.code, fallback: DataError.from(error)))
        }
        guard !deleted.isEmpty else { throw .notAllowed }
        await load()
    }

    /// Forslag til komité for kommende kveldene som mangler (lagres ikke).
    func proposeCommittees(perEvening: Int) -> [CommitteeDraw.Assignment] {
        CommitteeDraw.draw(
            evenings: events.map { CommitteeDraw.Evening(id: $0.id, date: $0.eventDate, committee: committees[$0.id] ?? []) },
            members: members.map(\.id),
            perEvening: perEvening,
            fillFrom: EveningDates.today()
        )
    }

    /// Lagrer en trekning. Én innsetting for alle kveldene, så den lykkes eller feiler samlet.
    func apply(_ plan: [CommitteeDraw.Assignment]) async throws(DataError) {
        let rows = plan.flatMap { assignment in
            assignment.added.map { EventCommitteeRow(eventID: assignment.eventID, memberID: $0, clubID: clubID) }
        }
        guard !rows.isEmpty else { return }
        do {
            let inserted: [EventCommitteeRow] = try await client.from("event_committee")
                .insert(rows)
                .select(EventCommitteeRow.columns)
                .execute().value
            guard inserted.count == rows.count else { throw DataError.notAllowed }
        } catch {
            throw DataError.from(error)
        }
        await load()
    }

    /// Tak, frister og gjester (sql/045). Bare når 045 finnes og noe er endret.
    private func saveRules(_ rules: EveningRulesDraft, eventID: UUID) async throws(DataError) {
        guard let settings else { return }
        let wanted = rules.settings(id: eventID)
        guard wanted != (settings[eventID] ?? .off(eventID)) else { return }
        do throws(DataError) {
            try await EveningSignupService.saveSettings(client: client, wanted)
        } catch {
            throw .invalid("Datoen er lagret, men ikke påmeldingen. \(error.message)")
        }
    }

    /// Bytter komiteen for en kveld i én transaksjon (RPC `set_event_committee`, sql/005,
    /// kjørt på test 06.10).
    private func setCommittee(eventID: UUID, to wanted: Set<UUID>) async throws(DataError) {
        struct Params: Encodable {
            let p_event_id: UUID
            let p_member_ids: [UUID]
        }
        guard Set(committees[eventID] ?? []) != wanted else { return }
        do {
            let saved: [UUID] = try await client
                .rpc("set_event_committee", params: Params(p_event_id: eventID, p_member_ids: wanted.sorted { $0.uuidString < $1.uuidString }))
                .execute()
                .value
            guard Set(saved) == wanted else { throw DataError.notAllowed }
        } catch {
            throw DataError.invalid("Datoen er lagret, men ikke sosialkomiteen. \(DataError.from(error).message)")
        }
    }
}

#if DEBUG
extension TerminlisteModel {
    /// Kveldene fra skjermprøvens rundemodell, med sosialkomité og påmelding (`kvelden`, `kveldene`).
    static func sample(from admin: RundeAdminModel) -> TerminlisteModel {
        let model = TerminlisteModel(context: admin.clubContext, tournamentID: admin.tournamentID,
                                     competition: admin.competition)
        model.activeSeason = admin.tournament.map { SeasonSummary(id: $0.id, name: $0.name) }
        model.events = admin.events
        model.members = admin.members
        for (index, event) in admin.events.enumerated() {
            model.committees[event.id] = admin.members.dropFirst(index * 2).prefix(index == admin.events.count - 1 ? 0 : 2)
                .map(\.id)
        }
        if let selected = admin.selectedEventID {
            model.signups[selected] = admin.signups
        }
        if let next = admin.events.first(where: { $0.eventDate > EveningDates.today() }) {
            model.signups[next.id] = admin.members.prefix(5).map {
                SignupRow(eventID: next.id, memberID: $0.id, clubID: $0.clubID, status: .yes, comment: nil)
            }
        }
        model.state = .loaded
        return model
    }
}
#endif

/// Raden som skrives til `events`. Tomme felt sendes som null, så de også tømmes ved endring.
nonisolated struct EventWrite: Encodable, Sendable {
    let clubID: UUID
    let seasonID: UUID?
    /// Bare for spilledager uten sesong. Sesongens kvelder får turneringen fra sesongen (trigger, sql/031).
    var competitionID: UUID? = nil
    let eventDate: String
    let startTime: String?
    let venue: String?
    let note: String?

    enum CodingKeys: String, CodingKey {
        case clubID = "club_id"
        case seasonID = "season_id"
        case competitionID = "competition_id"
        case eventDate = "event_date"
        case startTime = "start_time"
        case venue
        case note
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(clubID, forKey: .clubID)
        try container.encode(seasonID, forKey: .seasonID)
        try container.encodeIfPresent(competitionID, forKey: .competitionID)
        try container.encode(eventDate, forKey: .eventDate)
        try container.encode(startTime, forKey: .startTime)
        try container.encode(venue, forKey: .venue)
        try container.encode(note, forKey: .note)
    }
}
