import Foundation
import GolfgutuCore

// Løse runder med venner (fase 13): runden uten klubb og kveld. Skjemaet er 017 (runder, deltakere
// og gjester, felles bibliotek) og 018 (invitasjonskode, start i ett kall, avslutt). Ren logikk her,
// uten nettverk og SwiftUI.

/// Løse runder (fase 13). Av til 017 og 018 er godkjent og kjørt på test. Da vises «Spill»-fanen,
/// lenker og koder tas imot, og banebiblioteket får det felles biblioteket. Med flagget av oppfører
/// appen seg nøyaktig som før.
nonisolated enum LooseRoundsFeature {
    /// `sql/018_lose_runder.sql` er kjørt på test.
    static let schemaReady = true
    /// Krever fundamentet (017) og 018.
    static let isEnabled = FoundationFeature.isEnabled && schemaReady
}

/// Regelsettet for en løs runde. Den hører ikke til en sesong, så malen gjelder (Golfgutu-oppsettet),
/// til runden teller i en konkurranse med egne regler (fase 15).
nonisolated enum LooseRoundRules {
    static let template: Ruleset = .golfgutu

    /// Formene en løs runde kan spilles i: de individuelle formene regelsettet tillater og appen kan
    /// regne. Lagformer krever lagoppsett og kommer senere.
    static func forms(_ rules: Ruleset = template) -> [CompetitionForm] {
        rules.allowedForms.filter { !$0.isTeamForm && $0.support != .missing }
    }

    /// Formen en ny runde starter med: regelsettets standard når den passer, ellers den første.
    static func defaultForm(_ rules: Ruleset = template) -> CompetitionForm? {
        let forms = forms(rules)
        return forms.first { $0.id == rules.formats.defaultFormID } ?? forms.first
    }

    /// Avgjøres runden hull for hull (matchspill)? Da trekkes matcher når runden startes.
    static func isHoleByHole(_ form: CompetitionForm) -> Bool {
        form.scoring == "match"
    }
}

/// Skjemaets grenser for en løs runde. Inndatagrenser, ikke spilleregler.
nonisolated enum LooseRoundLimits {
    /// `start_loose_round` tar 47 i tillegg til deg.
    static let maxPlayers = 48
    /// `round_players.bay_no` er 1–12.
    static let maxGroups = 12
}

/// Eieren og deltakerne i en løs runde, slik `round_roster` gir dem.
nonisolated struct LooseRoundInfo: Equatable, Sendable {
    var ownerID: UUID?
    var roster: [RoundRosterRow]

    /// Spillerens id i runden → navnet (profilens, ellers det som ble skrevet inn).
    var names: [UUID: String] {
        Dictionary(roster.map { ($0.playerID, Self.name($0.displayName)) }, uniquingKeysWith: { first, _ in first })
    }

    /// Deltakeren som er profilen, om hen er med.
    func participant(profile: UUID) -> RoundRosterRow? {
        roster.first { $0.profileID == profile }
    }

    /// Gjestene (uten profil), i lista sin rekkefølge.
    var guests: [RoundRosterRow] { roster.filter(\.isGuest) }

    static func name(_ text: String?) -> String {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Spiller" : trimmed
    }

    /// Dagen runden startet (`YYYY-MM-DD`, norsk tid), brukt som rundens dato.
    static func day(_ date: Date) -> String {
        EveningDates.dateString(from: date)
    }
}

/// Hvem som får gjøre hva i en løs runde. Samme regler som databasen (017 `can_score`, 018):
/// eieren har arrangørens rett; ellers fører markøren for flighten sin, og uten markør fører
/// hver profil selv. En gjest uten profil føres av markøren eller eieren.
nonisolated enum LooseRoundRights {
    /// Den som ser på runden: deltakeren med profilen din, og arrangørens rett når du eier runden.
    /// Er du ikke med (bare eier, eller ikke koblet ennå), er du ikke på kortet.
    static func viewer(info: LooseRoundInfo?, userID: UUID) -> Viewer {
        let me = info?.participant(profile: userID)?.playerID
        return Viewer(memberID: me ?? userID, isOrganizer: info?.ownerID == userID)
    }

    /// Eieren og deltakerne med profil kan dele koden, så lenge runden ikke er avsluttet.
    static func canInvite(info: LooseRoundInfo?, userID: UUID, status: RoundStatus) -> Bool {
        guard let info, status != .locked else { return false }
        return info.ownerID == userID || info.participant(profile: userID) != nil
    }

    /// Bare eieren avslutter, og bare en runde som går.
    static func canFinish(info: LooseRoundInfo?, userID: UUID, status: RoundStatus) -> Bool {
        status == .active && info?.ownerID == userID
    }
}
