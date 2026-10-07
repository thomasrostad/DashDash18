import Foundation
import GolfgutuCore

/// «Ny konkurranse»: navn, type, periode, regler (mal eller kopi av hovedturneringen), hvem som er
/// med, åpen påmelding, og klubb eller privat. Ren logikk; skjemaet er `NewCompetitionView`, og
/// lagringen er `create_competition_with_entrants` (sql/022) i ett kall.
nonisolated struct CompetitionDraft: Equatable, Sendable {
    /// Typene arrangøren kan lage (sesongen lages av sesongen, spill av runden).
    static let kinds: [CompetitionKind] = [.fun, .league, .cup]

    /// Hvor reglene for rundene (stableford, handicap, sidepremier) kommer fra.
    enum RulesSource: String, CaseIterable, Sendable {
        /// Malen: Golfgutu-oppsettet (som også er malen for løse runder).
        case template
        /// Kopi av klubbens hovedturnering (jakkeracet).
        case copyMain
    }

    var name = ""
    var kind: CompetitionKind = .fun
    /// Klubben som eier konkurransen, eller nil: privat (du er eier).
    var clubID: UUID?
    var hasPeriod = false
    var startsOn: String
    var endsOn: String
    var rulesSource: RulesSource = .template
    var league: LeagueRules = .league
    var fun: LeagueRules = .fun
    var cup: CupRules = .standard
    var entry: CompetitionEntry = .listed
    var signupOpen = true
    /// Påmeldte klubbmedlemmer (klubbkonkurranse).
    var memberIDs: Set<UUID> = []
    /// Påmeldte profiler (folk du kjenner).
    var profileIDs: Set<UUID> = []

    init(clubID: UUID?, today: String) {
        self.clubID = clubID
        startsOn = today
        endsOn = today
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Reglene for typen, som arrangøren endrer i skjemaet.
    var leagueRules: LeagueRules {
        get { kind == .fun ? fun : league }
        set { if kind == .fun { fun = newValue } else { league = newValue } }
    }

    /// Hvem som kan stå i tabellen for typen og eieren. En cup trenger påmeldte, og «hele troppen»
    /// krever en klubb.
    var entryOptions: [CompetitionEntry] {
        if kind == .cup { return [.listed] }
        return clubID == nil ? [.listed, .open] : [.listed, .club, .open]
    }

    /// Rett opp valg som ikke passer etter at type eller eier er endret.
    mutating func normalize() {
        if !entryOptions.contains(entry) { entry = .listed }
        if entry != .listed { signupOpen = false }
        if clubID == nil { memberIDs = [] }
        if rulesSource == .copyMain, clubID == nil { rulesSource = .template }
    }

    /// Hva som mangler før konkurransen kan lagres.
    func issues() -> [String] {
        var out: [String] = []
        if trimmedName.isEmpty { out.append("Gi konkurransen et navn.") }
        if trimmedName.count > 60 { out.append("Navnet kan ha høyst 60 tegn.") }
        if hasPeriod, endsOn < startsOn { out.append("Perioden slutter før den starter.") }
        if !entryOptions.contains(entry) { out.append("\(CompetitionText.entry(entry)) passer ikke for denne typen.") }
        if kind == .cup, memberIDs.count + profileIDs.count + (clubID == nil ? 1 : 0) < 2, !signupOpen {
            out.append("En cup trenger minst to påmeldte, eller åpen påmelding.")
        }
        for issue in CompetitionRules(league: league, fun: fun, cup: cup).validate() {
            out.append(issue.message)
        }
        return out
    }

    /// Regelsettet som lagres: grunnlaget (mal eller hovedturneringen) med reglene for typen.
    func rules(main: Ruleset?) -> Ruleset {
        var base = rulesSource == .copyMain ? (main ?? Ruleset.golfgutu) : Ruleset.golfgutu
        var competition = base.competition ?? CompetitionRules.standard
        switch kind {
        case .league: competition.league = league
        case .fun: competition.fun = fun
        case .cup: competition.cup = cup
        case .season, .game: break
        }
        base.competition = competition
        return base
    }

    func params(main: Ruleset?) -> CreateCompetitionParams {
        CreateCompetitionParams(
            p_kind: kind.rawValue, p_name: trimmedName, p_club_id: clubID, p_entry: entry.rawValue,
            p_rules: rules(main: main),
            p_starts_on: hasPeriod ? startsOn : nil, p_ends_on: hasPeriod ? endsOn : nil,
            p_signup_open: entry == .listed && signupOpen,
            p_member_ids: clubID == nil ? [] : memberIDs.sorted { $0.uuidString < $1.uuidString },
            p_profile_ids: profileIDs.sorted { $0.uuidString < $1.uuidString })
    }
}
