import Foundation
import GolfgutuCore

// Veddemål overalt (sql/052, steg 11): banken er en turnering eller en enkeltrunde, og personene er
// medlemmer eller profiler. Ren logikk her: hvem du er i banken, hvem som er med, og hvordan
// spillerne i rundene henger sammen med personene. Ingen nettverk og ingen SwiftUI.

/// Hvem du er i en bank (`private.bet_me`): medlemmet ditt i bankens klubb når du har et, ellers
/// profilen din.
nonisolated enum BetIdentity {
    /// `memberships`: klubb → medlems-id-en din der.
    static func me(clubID: UUID?, memberships: [UUID: UUID], userID: UUID) -> UUID {
        clubID.flatMap { memberships[$0] } ?? userID
    }
}

/// Grunnlaget for Vedd i en turnering eller en runde, satt sammen av radene som er hentet.
nonisolated enum BetsAssembly {
    /// En turnering som ikke er en sesong (liga, cup, morro, private): personene er de som står i
    /// tabellen (`Entrant`: medlem eller profil; gjester kan ikke vedde), og hver spiller i en runde
    /// peker på personen bak (`PersonDirectory.entrant`).
    static func competition(_ competition: CompetitionRow, rounds: [RoundSnapshot], entrants: [Entrant],
                            directory: PersonDirectory, bets: [BetRow] = [], stakes: [BetStakeRow] = [],
                            enabled: Bool = true, bank: BetBankRow? = nil) -> BetsInput {
        let club = competition.clubID
        var personOf: [UUID: UUID] = [:]
        var fallback: [UUID: String] = [:]
        for s in rounds {
            for p in s.players {
                let e = directory.entrant(p.memberID, competitionClub: club)
                personOf[p.memberID] = e.id
                if let name = s.names[p.memberID], !name.isEmpty { fallback[e.id] = name }
            }
        }
        let people: [BetPerson] = entrants.compactMap { e in
            switch e {
            case .member(let id):
                return BetPerson(id: id, kind: .member, name: directory.name(e, fallback: fallback[id]))
            case .profile(let id):
                return BetPerson(id: id, kind: .profile, name: directory.name(e, fallback: fallback[id]))
            case .guest:
                return nil
            }
        }
        return BetsInput(scope: .competition(competition.id), title: competition.name, rules: competition.rules,
                         rounds: rounds, people: people, personOf: personOf, bets: bets, stakes: stakes,
                         enabled: enabled, bank: bank, clubID: club, ownerID: competition.ownerID)
    }

    /// En enkeltrunde med egen bank (`round_scope`). Klubbrunde: spillerne er medlemmer. Løs runde:
    /// deltakerne med profil er personene (gjester kan ikke vedde), og deltakeren peker på profilen.
    static func round(_ snapshot: RoundSnapshot, bets: [BetRow] = [], stakes: [BetStakeRow] = [],
                      enabled: Bool = true, bank: BetBankRow? = nil) -> BetsInput {
        var people: [BetPerson] = []
        var personOf: [UUID: UUID] = [:]
        if let loose = snapshot.loose {
            for r in loose.roster {
                guard let profile = r.profileID else { continue }
                personOf[r.playerID] = profile
                people.append(BetPerson(id: profile, kind: .profile, name: LooseRoundInfo.name(r.displayName)))
            }
        } else {
            for p in snapshot.players {
                people.append(BetPerson(id: p.memberID, kind: .member, name: snapshot.names[p.memberID] ?? ""))
            }
        }
        let title = snapshot.course?.name ?? "Runden"
        return BetsInput(scope: .round(snapshot.round.id), title: title, rules: snapshot.rules, rounds: [snapshot],
                         people: people, personOf: personOf, bets: bets, stakes: stakes, enabled: enabled, bank: bank,
                         clubID: snapshot.round.clubID, ownerID: snapshot.loose?.ownerID)
    }
}

/// Deg, sett fra veddemålene: innloggingen, medlemskapene og rettighetene. Reglene speiler
/// `resolve_bet` og `bets_set_enabled` (052), så appen viser bare det databasen vil godta.
nonisolated struct BetViewer: Equatable, Sendable {
    let userID: UUID
    /// Klubb → medlems-id-en din der.
    var memberships: [UUID: UUID] = [:]
    /// Klubber der du har rettigheten `money` (avgjør veddemål).
    var moneyClubs: Set<UUID> = []
    /// Klubber der du styrer turneringer eller runder.
    var organizerClubs: Set<UUID> = []

    /// Deg i banken (`person_key`).
    func me(in input: BetsInput) -> UUID {
        BetIdentity.me(clubID: input.clubID, memberships: memberships, userID: userID)
    }

    /// Kan du avgjøre for hånd (og feie)? Klubbens bank: `money`. Uten klubb: eieren av turneringen
    /// eller runden.
    func canResolve(_ input: BetsInput) -> Bool {
        if let club = input.clubID { return moneyClubs.contains(club) }
        return input.ownerID == userID
    }

    /// Kan du slå veddemål av og på? Bare med 052. Klubb: arrangør eller `money`. Uten klubb: eieren.
    func canToggle(_ input: BetsInput) -> Bool {
        guard input.scope != nil else { return false }
        if let club = input.clubID { return moneyClubs.contains(club) || organizerClubs.contains(club) }
        return input.ownerID == userID
    }
}

nonisolated extension BetViewer {
    /// Fra konkurransene (også uten klubb).
    init(access: CompetitionAccess, userID: UUID) {
        let active = access.memberships.filter(\.isActive)
        let organizer = Set(active.filter(\.isOrganizer).map(\.clubID))
        self.init(userID: userID,
                  memberships: Dictionary(active.map { ($0.clubID, $0.memberID) }, uniquingKeysWith: { a, _ in a }),
                  moneyClubs: organizer, organizerClubs: organizer)
    }
}

/// En bank du kan velge når runden hører til flere turneringer med veddemål på.
nonisolated struct BetScopeOption: Identifiable, Hashable, Sendable {
    let scope: BetScope
    let name: String
    var id: BetScope { scope }
}

/// Hvilke banker en runde kan vedde i (052): turneringene den hører til med veddemål på, og
/// rundens egen bank når den er slått på. Turneringene kommer først, i navnerekkefølge.
nonisolated enum BetScopeChoice {
    struct Candidate: Equatable, Sendable {
        let id: UUID
        let name: String
        let enabled: Bool
    }

    static func options(competitions: [Candidate], roundID: UUID, roundEnabled: Bool, roundName: String) -> [BetScopeOption] {
        var seen = Set<UUID>()
        var out = competitions
            .filter { $0.enabled && seen.insert($0.id).inserted }
            .sorted { NorwegianSort.areInIncreasingOrder($0.name, $1.name) }
            .map { BetScopeOption(scope: .competition($0.id), name: $0.name) }
        if roundEnabled { out.append(BetScopeOption(scope: .round(roundID), name: roundName)) }
        return out
    }
}
