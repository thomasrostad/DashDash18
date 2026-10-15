import Foundation
import GolfgutuCore
import Supabase
import Synchronization

/// Låst kort etter levering (sql/058, regelsettets `play.lockSubmittedCards`).
///
/// Før 058 er kjørt finnes ikke `round_players.card_submitted_at`, og en `select` med den feiler. Appen
/// spør derfor én gang per innlogging (`detect`) og husker svaret til neste oppstart. Uten kolonnen
/// vises ikke «Lever kortet», og ingen kort er levert.
nonisolated enum CardLockFeature {
    private static let key = "cardLock058"
    private static let state = Mutex<Bool>(UserDefaults.standard.bool(forKey: key))

    /// Kolonnen og funksjonene fra 058 finnes (sist appen sjekket).
    static var isAvailable: Bool { state.withLock { $0 } }

    /// For tester og for `detect`.
    static func set(_ available: Bool) {
        state.withLock { $0 = available }
        UserDefaults.standard.set(available, forKey: key)
    }

    /// Spør databasen om kolonnen finnes. En annen feil (nettet borte) endrer ingenting.
    static func detect(client: SupabaseClient) async {
        do {
            _ = try await client.from("round_players").select("card_submitted_at").limit(1).execute()
            set(true)
        } catch let error as PostgrestError where EveningSignupService.isMissing(error) {
            set(false)
        } catch {
            // Behold det vi visste.
        }
    }
}

/// `submit_card` og `reopen_card` (sql/058). Serveren sjekker hvem som kan (markøren for båsen,
/// arrangøren for å åpne) og at kortet er ferdig ført.
nonisolated enum CardLockQueries {
    private struct Params: Encodable {
        let p_round_id: UUID
        let p_member_ids: [UUID]
    }

    @discardableResult
    static func submit(client: SupabaseClient, roundID: UUID, members: [UUID]) async throws -> Int {
        try await client.rpc("submit_card", params: Params(p_round_id: roundID, p_member_ids: members)).execute().value
    }

    @discardableResult
    static func reopen(client: SupabaseClient, roundID: UUID, members: [UUID]) async throws -> Int {
        try await client.rpc("reopen_card", params: Params(p_round_id: roundID, p_member_ids: members)).execute().value
    }
}

// MARK: - Runden

nonisolated extension RoundGame {
    /// Kortet til spilleren er levert (sql/058). Da fører bare arrangøren for henne.
    func isCardSubmitted(_ member: UUID) -> Bool {
        snapshot.players.first { $0.memberID == member }?.cardSubmittedAt != nil
    }

    /// «Lever kortet» for `viewer`: hva båsen kan gjøre nå. `nil`: ingenting å vise (av i regelsettet,
    /// 058 mangler, runden går ikke, eller du fører ikke noe kort).
    func cardSubmission(viewer: Viewer, pending: Set<Int>, available: Bool = CardLockFeature.isAvailable) -> CardSubmission? {
        guard available, rules.play.lockSubmittedCards, status == .active else { return nil }
        let card = cardPlayers(for: viewer)
        guard !card.isEmpty else { return nil }
        let submitted = card.filter(isCardSubmitted)
        // Radene du fører (eller ville ført om kortet ikke var levert).
        let writable = card.filter { cardRowEditable($0, for: viewer, ignoringSubmission: true) }
        if !submitted.isEmpty, writable.allSatisfy(isCardSubmitted) {
            return .submitted(members: submitted, canReopen: viewer.isOrganizer)
        }
        let open = writable.filter { !isCardSubmitted($0) }
        guard !open.isEmpty else { return nil }
        let missing = (0..<holeCount).filter { !isComplete(hole: $0, for: open) }
        if !missing.isEmpty || !pending.isEmpty {
            return .notReady(missingHoles: missing.count, hasPending: !pending.isEmpty)
        }
        return .ready(members: open)
    }

    /// Kortene arrangøren kan åpne igjen: levert, gruppert per bås (uten bås: hver for seg).
    func submittedCards() -> [SubmittedCard] {
        let done = snapshot.players.filter { $0.cardSubmittedAt != nil }
        var groups: [Int: [UUID]] = [:]
        var loose: [UUID] = []
        for p in done {
            if let bay = p.bayNo, bay >= 1 { groups[bay, default: []].append(p.memberID) } else { loose.append(p.memberID) }
        }
        let byName = { (a: UUID, b: UUID) in NorwegianSort.areInIncreasingOrder(name(a), name(b)) }
        var out = groups.keys.sorted().map { bay in
            SubmittedCard(title: groupTerm.numbered(bay), members: groups[bay]!.sorted(by: byName))
        }
        out += loose.sorted(by: byName).map { SubmittedCard(title: name($0), members: [$0]) }
        return out
    }
}

/// Det føringen viser under kortet når regelsettet har låst kort etter levering.
nonisolated enum CardSubmission: Equatable, Sendable {
    /// Alt er ført og sendt: «Lever kortet» for disse spillerne.
    case ready(members: [UUID])
    /// Ikke ferdig ennå: hull som mangler, eller hull som ligger i kø på telefonen.
    case notReady(missingHoles: Int, hasPending: Bool)
    /// Levert. Arrangøren kan åpne kortet igjen.
    case submitted(members: [UUID], canReopen: Bool)

    var text: String {
        switch self {
        case .ready: "Alle hullene er ført. Når du leverer, kan bare arrangøren endre kortet."
        case .notReady(let missing, let pending):
            if missing > 0 { missing == 1 ? "1 hull mangler før du kan levere kortet." : "\(missing) hull mangler før du kan levere kortet." }
            else if pending { "Kortet kan leveres når hullene på telefonen er sendt." }
            else { "" }
        case .submitted(_, let canReopen):
            canReopen ? "Kortet er levert. Du kan åpne det igjen." : "Kortet er levert. Bare arrangøren kan åpne det igjen."
        }
    }
}

/// Et levert kort i arrangørens liste.
nonisolated struct SubmittedCard: Equatable, Sendable, Identifiable {
    let title: String
    let members: [UUID]
    var id: String { title + members.map(\.uuidString).joined() }
}
