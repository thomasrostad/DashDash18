import Foundation
import GolfgutuCore

/// Hvor veddemålene hører til (052): en turnering (liga, cup, morro, sesong, private) eller en
/// enkeltrunde med egen bank (`round_scope`).
nonisolated enum BetScope: Hashable, Sendable {
    case competition(UUID)
    case round(UUID)

    var competitionID: UUID? {
        if case .competition(let id) = self { return id }
        return nil
    }

    var roundID: UUID? {
        if case .round(let id) = self { return id }
        return nil
    }
}

/// En person i banken: et klubbmedlem eller en profil. `id` er `person_key` (medlemmets eller
/// profilens id), samme nøkkel som innsatsene bruker.
nonisolated struct BetPerson: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case member
        case profile
    }

    let id: UUID
    let kind: Kind
    let name: String
    /// Med i banken nå (aktiv i troppen, påmeldt, spiller i runden). Andre står bare i tabellen når
    /// de har satset.
    var active = true
}

/// Alt som er hentet for veddemålene i én bank: rundene, personene, veddemålene og innsatsene.
nonisolated struct BetsInput: Equatable, Sendable {
    /// Banken (052). nil: før 052, sesongen som før.
    var scope: BetScope?
    /// Turneringens navn, eller rundens.
    var title: String
    var rules: Ruleset
    /// Rundene veddemålene kan gjelde, med spiller-id-ene slik runden har dem (vilkårene bruker dem).
    var rounds: [RoundSnapshot]
    var people: [BetPerson]
    /// Spiller-id i en runde → personen (medlem eller profil). Mangler den, er det samme id
    /// (klubbrunder i klubbens egen turnering).
    var personOf: [UUID: UUID] = [:]
    var bets: [BetRow] = []
    var stakes: [BetStakeRow] = []
    /// `bets_enabled` (052). Før 052 alltid på.
    var enabled = true
    /// Din bank fra serveren (`bet_bank`), når den er hentet.
    var bank: BetBankRow?
    /// Bankens klubb (tom for private turneringer og løse runder).
    var clubID: UUID?
    /// Eieren av en privat turnering eller en løs runde.
    var ownerID: UUID?

    /// 052 er kjørt: serveren gjør opp når runden låses.
    var serverSettles: Bool { scope != nil }

    init(scope: BetScope?, title: String, rules: Ruleset, rounds: [RoundSnapshot], people: [BetPerson],
         personOf: [UUID: UUID] = [:], bets: [BetRow] = [], stakes: [BetStakeRow] = [], enabled: Bool = true,
         bank: BetBankRow? = nil, clubID: UUID? = nil, ownerID: UUID? = nil) {
        self.clubID = clubID
        self.ownerID = ownerID
        self.scope = scope
        self.title = title
        self.rules = rules
        self.rounds = rounds
        self.people = people
        self.personOf = personOf
        self.bets = bets
        self.stakes = stakes
        self.enabled = enabled
        self.bank = bank
    }

    /// Sesongen (samme henting som Tavla): troppen er personene, og medlems-id er nøkkelen.
    init(tavla: TavlaInput, scope: BetScope? = nil, bets: [BetRow] = [], stakes: [BetStakeRow] = [],
         enabled: Bool = true) {
        self.init(scope: scope, title: tavla.season.name, rules: tavla.season.rules, rounds: tavla.rounds,
                  people: tavla.members.map { BetPerson(id: $0.id, kind: .member, name: $0.displayName,
                                                        active: $0.status == .active) },
                  bets: bets, stakes: stakes, enabled: enabled, clubID: tavla.season.clubID)
    }

    /// Personen bak en spiller i en runde.
    func person(ofPlayer id: UUID) -> UUID { personOf[id] ?? id }
}

/// Veddemålene i én bank sett fra én spiller: kortene i rekkefølge, poengtabellen, banken og det
/// arrangørens telefon skal avgjøre. Alt regnes av GolfgutuCore (`Bets`). Ren, uten nettverk.
nonisolated struct BetsBoard: Sendable {
    /// Ett veddemål slik kortet viser det.
    struct Item: Identifiable, Sendable {
        struct Staker: Hashable, Sendable {
            let name: String
            let side: BetSide
            let points: Double
        }

        let row: BetRow
        let bet: Bet
        let phase: BetPhase
        let acceptsStakes: Bool
        /// Hvorfor det ikke tar innsatser, når det er åpent men stengt.
        let closedReason: String?
        let yesPool: Double
        let noPool: Double
        /// Din side og sum, eller nil.
        let mySide: BetSide?
        let myPoints: Double
        /// Netto for deg når det er avgjort og du var med.
        let myResult: Double?
        /// Rettet mot deg, du har ikke satset, og det tar innsatser.
        let challengesMe: Bool
        let creatorName: String
        let againstName: String?
        let resolvedByName: String?
        /// Hvem som har satset, største innsats først.
        let stakers: [Staker]
        /// Vilkåret gir ikke svar (fri tekst eller manuell): arrangøren må avgjøre. Delt hull og
        /// likt resultat annulleres av feiingen når regelsettet sier det (`voidTies`).
        let needsOrganizer: Bool
        /// Du er arrangør, det er åpent, og du har ikke satset: du kan avgjøre det for hånd.
        let canResolve: Bool
        /// Du er arrangør med innsats: en annen arrangør må avgjøre det.
        let resolverHasStake: Bool

        var id: UUID { row.id }
        var isOpen: Bool { row.status == .open }
        var yesShare: Double { yesPool + noPool > 0 ? yesPool / (yesPool + noPool) : 0.5 }
    }

    /// En rad i poengtabellen, med navn og om det er deg.
    struct TableRow: Identifiable, Hashable, Sendable {
        let place: Int
        /// `person_key`: medlemmet eller profilen.
        let personID: UUID
        let row: BetTableRow
        let isMe: Bool
        var id: UUID { personID }
    }

    /// Deg i banken (`person_key`).
    let me: UUID
    let isOrganizer: Bool
    let rules: Ruleset
    let scope: BetScope?
    let title: String
    let enabled: Bool
    let serverSettles: Bool
    /// Rundene i banken, etter id.
    let games: [UUID: RoundGame]
    /// Personene og spillerne i rundene → navn.
    let names: [UUID: String]
    /// Personene i banken, etter id.
    let people: [UUID: BetPerson]
    /// Spiller-id i en runde → personen.
    let personOf: [UUID: UUID]
    let bank: BetBankRow?

    /// Åpne og rettet mot deg, uten innsats fra deg: øverst.
    let challenged: [Item]
    /// Åpne der du har satset.
    let mine: [Item]
    /// Resten av de åpne.
    let others: [Item]
    /// Avgjorte og annullerte, sist avgjort først.
    let settled: [Item]
    let table: [TableRow]

    /// Navnet sesongen hadde før 052 (samme som `title`).
    var seasonName: String { title }

    init(_ input: BetsInput, me: UUID, isOrganizer: Bool) {
        self.me = me
        self.isOrganizer = isOrganizer
        rules = input.rules
        scope = input.scope
        title = input.title
        enabled = input.enabled
        serverSettles = input.serverSettles
        bank = input.bank
        personOf = input.personOf
        var names: [UUID: String] = [:]
        for s in input.rounds {
            for (id, name) in s.names where !name.isEmpty { names[id] = name }
        }
        for p in input.people { names[p.id] = p.name }
        self.names = names
        people = Dictionary(input.people.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let games = Dictionary(input.rounds.map { ($0.round.id, RoundGame($0)) }, uniquingKeysWith: { a, _ in a })
        self.games = games
        let rules = input.rules
        let meKey = BetMapping.key(me)

        func name(_ id: UUID?) -> String { id.flatMap { names[$0] } ?? "Ukjent" }

        let items: [Item] = input.bets.map { row in
            let bet = BetMapping.bet(row, stakes: input.stakes)
            let game = row.roundID.flatMap { games[$0] }
            let round = game?.round
            let accepts = Bets.acceptsStakes(bet, round: round, rules: rules)
            let phase = Bets.phase(bet, acceptsStakes: accepts)
            let position = bet.position(of: meKey)
            var result: Double?
            if position != nil, row.status != .open {
                result = Bets.net(for: meKey, in: [bet], rules: rules)
            }
            let verdict = bet.condition.flatMap { c in
                game.flatMap { Bets.verdict($0.round, condition: c, roster: $0.roster, claims: $0.coreSideClaims, rules: rules) }
            }
            let stakers = input.stakes.filter { $0.betID == row.id }
                .map { Item.Staker(name: name($0.person), side: $0.side, points: Double($0.points)) }
                .sorted { $0.points != $1.points ? $0.points > $1.points : NorwegianSort.areInIncreasingOrder($0.name, $1.name) }
            return Item(
                row: row, bet: bet, phase: phase, acceptsStakes: accepts,
                closedReason: (row.status == .open && !accepts) ? BetTexts.closedReason(bet, round: round, rules: rules) : nil,
                yesPool: bet.pool(.yes), noPool: bet.pool(.no),
                mySide: position?.side, myPoints: position?.points ?? 0, myResult: result,
                challengesMe: row.against == me && position == nil && accepts,
                creatorName: name(row.creator), againstName: row.against.map { name($0) },
                resolvedByName: row.resolver.map { name($0) },
                stakers: stakers,
                needsOrganizer: row.status == .open && verdict == nil
                    && (bet.condition == nil || round?.locked == true || !accepts),
                canResolve: isOrganizer && Bets.canResolve(bet, by: meKey),
                resolverHasStake: isOrganizer && row.status == .open && position != nil
            )
        }
        let newestFirst: (Item, Item) -> Bool = { $0.row.createdAt > $1.row.createdAt }
        let open = items.filter(\.isOpen)
        challenged = open.filter(\.challengesMe).sorted(by: newestFirst)
        mine = open.filter { !$0.challengesMe && $0.mySide != nil }.sorted(by: newestFirst)
        others = open.filter { !$0.challengesMe && $0.mySide == nil }.sorted(by: newestFirst)
        settled = items.filter { !$0.isOpen }
            .sorted { ($0.row.resolvedAt ?? $0.row.createdAt) > ($1.row.resolvedAt ?? $1.row.createdAt) }

        // Poengtabellen: personene i banken, og alle som har satset (også de som har gått ut).
        // Innsatsene er gruppert på `person_key`, så medlemmer og profiler står side om side.
        let bets = items.map(\.bet)
        let staked = input.stakes.compactMap(\.person)
        var seen = Set<UUID>()
        var ids: [UUID] = []
        for p in input.people where (p.active || staked.contains(p.id)) && seen.insert(p.id).inserted {
            ids.append(p.id)
        }
        for id in staked where seen.insert(id).inserted { ids.append(id) }
        let players = ids.map { Player(id: BetMapping.key($0), name: name($0)) }
        let byKey = Dictionary(ids.map { (BetMapping.key($0), $0) }, uniquingKeysWith: { a, _ in a })
        table = Bets.table(players: players, bets: bets, rules: rules).enumerated().compactMap { i, r in
            guard let id = byKey[r.playerID] else { return nil }
            return TableRow(place: i + 1, personID: id, row: r, isMe: id == me)
        }
    }

    var isEmpty: Bool { challenged.isEmpty && mine.isEmpty && others.isEmpty && settled.isEmpty }
    var openCount: Int { challenged.count + mine.count + others.count }
    var hasBank: Bool { rules.bets.startingPoints != nil }
    var allBets: [Bet] { (challenged + mine + others + settled).map(\.bet) }

    /// Din rad i poengtabellen.
    var myRow: BetTableRow? { table.first { $0.isMe }?.row }

    /// Det du kan sette nå (saldo minus det som står ute). Nil uten poengbank. Serverens bank
    /// (`bet_bank`) går foran når den er hentet.
    var available: Double? {
        guard hasBank else { return nil }
        return bank?.available ?? Bets.available(for: BetMapping.key(me), in: allBets, rules: rules)
    }

    /// Ledige poeng og taket, vist før du satser. `already` er det du har på veddemålet fra før.
    func stakeHint(already: Double = 0) -> String {
        BetTexts.stakeHint(available: available, maxStake: rules.bets.maxStakePerBet, already: already)
    }

    func item(_ id: UUID) -> Item? {
        (challenged + mine + others + settled).first { $0.id == id }
    }

    /// Runden som går (ikke låst), om det finnes en.
    var activeGame: RoundGame? {
        games.values.filter { $0.status == .active }.max { ($0.snapshot.eventDate ?? "") < ($1.snapshot.eventDate ?? "") }
    }

    // MARK: Personer og spillere

    /// Personen bak en spiller i en runde.
    func person(ofPlayer id: UUID) -> UUID { personOf[id] ?? id }

    /// Spiller-id-en personen har i runden, om hen spiller der.
    func player(_ person: UUID, in game: RoundGame) -> UUID? {
        game.snapshot.players.map(\.memberID).first { self.person(ofPlayer: $0) == person }
    }

    /// Personene du kan vedde på: spillerne i runden (ellers banken), uten deg og uten gjester (de
    /// er ikke med i banken), etter navn.
    func opponents(in game: RoundGame?) -> [UUID] {
        let ids: [UUID]
        if let game {
            ids = game.snapshot.players.map { person(ofPlayer: $0.memberID) }
        } else {
            ids = people.values.filter(\.active).map(\.id)
        }
        return Array(Set(ids)).filter { $0 != me && (people.isEmpty || people[$0] != nil) }
            .sorted { NorwegianSort.areInIncreasingOrder(names[$0] ?? "", names[$1] ?? "") }
    }

    // MARK: Feiingen

    /// Feiingen (`oppdaterMarkeder` på arrangørens telefon): det vilkårene nå gir svar på, og
    /// delt hull eller likt resultat som annulleres (`voidTies`). Tom for andre enn arrangøren.
    /// Gjelder også veddemål arrangøren har satset på: det er vilkåret som avgjør, ikke han.
    /// Med serveroppgjør (052) bare runder der serveren skulle vært ferdig (`BetSweep`).
    var sweepPlan: [(betID: UUID, verdict: BetVerdict)] { sweepPlan(now: .now) }

    func sweepPlan(now: Date) -> [(betID: UUID, verdict: BetVerdict)] {
        guard isOrganizer else { return [] }
        let open = (challenged + mine + others).map(\.bet)
        return games.values
            .filter { g in
                BetSweep.phoneMaySettle(roundLocked: g.snapshot.round.status == .locked,
                                        lockedAt: g.snapshot.round.lockedAt, now: now, serverSettles: serverSettles)
            }
            .flatMap { game in
                Bets.sweep(open, round: game.round, hole: nil, roster: game.roster, claims: game.coreSideClaims, rules: rules)
            }
            .compactMap { u in
                guard let verdict = u.verdict, let id = u.betID.flatMap(UUID.init(uuidString:)) else { return nil }
                return (id, verdict)
            }
            .sorted { $0.betID.uuidString < $1.betID.uuidString }
    }
}

// MARK: - Vedd-arket

/// Vedd-arket (`renderUtfordringArk`): malene, egen påstand, side og beløp.
nonisolated struct BetSheetDraft: Equatable, Sendable {
    struct Option: Equatable, Sendable {
        let template: BetTemplate
        let text: String
    }

    /// Personen veddemålet gjelder (medlem eller profil). Nil = om deg selv.
    let against: UUID?
    let againstKind: BetPerson.Kind?
    let againstName: String?
    let roundID: UUID?
    let eventID: UUID?
    let options: [Option]
    /// Valgt mal. `nil` = egen påstand (fri tekst).
    var selected: Int?
    var customText = ""
    var side: BetSide
    var points: Int

    /// Arket for en person eller for deg selv, med malene fra regelmotoren. Vilkårene bruker
    /// spiller-id-ene i runden; innsatsen og motparten er personer.
    init(board: BetsBoard, against: UUID?, game: RoundGame?) {
        self.against = against
        againstKind = against.flatMap { board.people[$0]?.kind }
        againstName = against.flatMap { board.names[$0] }
        roundID = game?.roundID
        eventID = game?.snapshot.round.eventID
        let me = board.names[board.me] ?? "Meg"
        let roundName = game.map { "Runde \($0.snapshot.round.roundNo)" }
        let mePlayer = game.flatMap { board.player(board.me, in: $0) } ?? board.me
        let himPlayer = against.map { a in game.flatMap { board.player(a, in: $0) } ?? a }
        let templates = Bets.templates(round: game?.round, me: BetMapping.key(mePlayer),
                                       against: himPlayer.map(BetMapping.key), rules: board.rules)
        options = templates.map { t in
            Option(template: t, text: BetTexts.template(t, me: me, him: against.flatMap { board.names[$0] }, roundName: roundName))
        }
        selected = options.isEmpty ? nil : 0
        side = options.first?.template.side ?? .yes
        points = board.rules.bets.defaultStake
    }

    var title: String {
        againstName.map { "Vedd på \($0)" } ?? "Vedd på deg selv"
    }

    var question: String {
        if let selected, options.indices.contains(selected) { return options[selected].text }
        return customText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var condition: BetCondition? {
        guard let selected, options.indices.contains(selected) else { return nil }
        return options[selected].template.condition
    }

    mutating func select(_ index: Int?) {
        selected = index
        if let index, options.indices.contains(index) { side = options[index].template.side }
    }

    /// Hva som er galt, eller nil når innsatsen kan sendes. Samme sjekk som databasen.
    func problem(board: BetsBoard) -> String? {
        let q = question
        if q.count < 4 { return "Skriv en tydelig påstand." }
        if q.count > 140 { return "Påstanden kan ikke være lengre enn 140 tegn." }
        if !board.enabled { return BetTexts.notEnabled }
        let bet = Bet(condition: condition, against: against.map(BetMapping.key))
        let round = roundID.flatMap { board.games[$0]?.round }
        guard let p = Bets.stakeProblem(bet, playerID: BetMapping.key(board.me), side: side, points: points,
                                        round: round, bets: board.allBets, rules: board.rules) else { return nil }
        return BetTexts.problem(p, closedReason: BetTexts.closedReason(bet, round: round, rules: board.rules))
    }

    /// Kallet til `create_bet` (før 052). Uten mal og uten runde gjelder veddemålet sesongen.
    func params(clubID: UUID) -> CreateBetParams {
        let c = condition
        return CreateBetParams(clubID: clubID, roundID: roundID, eventID: roundID == nil ? eventID : nil,
                               question: question, condition: c.map(BetMapping.record), against: against,
                               side: side, points: points)
    }

    /// Kallet til `create_bet_v2` (052): turneringens bank med runden når det er en, eller
    /// enkeltrundens bank. Motparten er medlem eller profil.
    func params(scope: BetScope) -> CreateBetV2Params {
        let round: UUID? = switch scope {
        case .competition: roundID
        case .round(let id): id
        }
        return CreateBetV2Params(competitionID: scope.competitionID, roundID: round, question: question,
                                 condition: condition.map(BetMapping.record),
                                 againstMember: againstKind == .profile ? nil : against,
                                 againstProfile: againstKind == .profile ? against : nil,
                                 side: side, points: points)
    }

    /// «Sats 100 poeng på NEI».
    var buttonTitle: String {
        "Sats \(points) poeng på \(BetTexts.sideShort(side))"
    }
}

/// En innsats på et veddemål som finnes (kortet).
nonisolated enum BetStakeCheck {
    static func problem(_ item: BetsBoard.Item, side: BetSide, points: Int, board: BetsBoard) -> String? {
        let round = item.row.roundID.flatMap { board.games[$0]?.round }
        guard let p = Bets.stakeProblem(item.bet, playerID: BetMapping.key(board.me), side: side, points: points,
                                        round: round, bets: board.allBets, rules: board.rules) else { return nil }
        return BetTexts.problem(p, closedReason: BetTexts.closedReason(item.bet, round: round, rules: board.rules))
    }
}
