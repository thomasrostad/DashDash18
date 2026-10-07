import Foundation
import GolfgutuCore

/// Alt som er hentet for veddemålene i én sesong.
nonisolated struct BetsInput: Equatable, Sendable {
    /// Sesongen, troppen og rundene (samme henting som Tavla).
    var tavla: TavlaInput
    var bets: [BetRow] = []
    var stakes: [BetStakeRow] = []
}

/// Veddemålene i sesongen sett fra én spiller: kortene i rekkefølge, poengtabellen, banken og
/// det arrangørens telefon skal avgjøre. Alt regnes av GolfgutuCore (`Bets`). Ren, uten nettverk.
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
        /// Vilkåret gir ikke svar (fri tekst, delt eller manuell): arrangøren må avgjøre.
        let needsOrganizer: Bool

        var id: UUID { row.id }
        var isOpen: Bool { row.status == .open }
        var yesShare: Double { yesPool + noPool > 0 ? yesPool / (yesPool + noPool) : 0.5 }
    }

    /// En rad i poengtabellen, med navn og om det er deg.
    struct TableRow: Identifiable, Hashable, Sendable {
        let place: Int
        let memberID: UUID
        let row: BetTableRow
        let isMe: Bool
        var id: UUID { memberID }
    }

    let me: UUID
    let isOrganizer: Bool
    let rules: Ruleset
    let seasonID: UUID
    let seasonName: String
    /// Rundene i sesongen, etter id.
    let games: [UUID: RoundGame]
    let names: [UUID: String]

    /// Åpne og rettet mot deg, uten innsats fra deg: øverst.
    let challenged: [Item]
    /// Åpne der du har satset.
    let mine: [Item]
    /// Resten av de åpne.
    let others: [Item]
    /// Avgjorte og annullerte, sist avgjort først.
    let settled: [Item]
    let table: [TableRow]

    init(_ input: BetsInput, me: UUID, isOrganizer: Bool) {
        self.me = me
        self.isOrganizer = isOrganizer
        rules = input.tavla.season.rules
        seasonID = input.tavla.season.id
        seasonName = input.tavla.season.name
        let names = Dictionary(input.tavla.members.map { ($0.id, $0.displayName) }, uniquingKeysWith: { a, _ in a })
        self.names = names
        let games = Dictionary(input.tavla.rounds.map { ($0.round.id, RoundGame($0)) }, uniquingKeysWith: { a, _ in a })
        self.games = games
        let rules = input.tavla.season.rules
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
                result = Bets.net(for: meKey, in: [bet])
            }
            let outcome = bet.condition.flatMap { c in
                game.flatMap { Bets.outcome($0.round, condition: c, roster: $0.roster, claims: $0.coreSideClaims, rules: rules) }
            }
            let stakers = input.stakes.filter { $0.betID == row.id }
                .map { Item.Staker(name: name($0.memberID), side: $0.side, points: Double($0.points)) }
                .sorted { $0.points != $1.points ? $0.points > $1.points : NorwegianSort.areInIncreasingOrder($0.name, $1.name) }
            return Item(
                row: row, bet: bet, phase: phase, acceptsStakes: accepts,
                closedReason: (row.status == .open && !accepts) ? BetTexts.closedReason(bet, round: round, rules: rules) : nil,
                yesPool: bet.pool(.yes), noPool: bet.pool(.no),
                mySide: position?.side, myPoints: position?.points ?? 0, myResult: result,
                challengesMe: row.againstID == me && position == nil && accepts,
                creatorName: name(row.creatorID), againstName: row.againstID.map { name($0) },
                resolvedByName: row.resolvedBy.map { name($0) },
                stakers: stakers,
                needsOrganizer: row.status == .open && outcome == nil
                    && (bet.condition == nil || round?.locked == true || !accepts)
            )
        }
        let newestFirst: (Item, Item) -> Bool = { $0.row.createdAt > $1.row.createdAt }
        let open = items.filter(\.isOpen)
        challenged = open.filter(\.challengesMe).sorted(by: newestFirst)
        mine = open.filter { !$0.challengesMe && $0.mySide != nil }.sorted(by: newestFirst)
        others = open.filter { !$0.challengesMe && $0.mySide == nil }.sorted(by: newestFirst)
        settled = items.filter { !$0.isOpen }
            .sorted { ($0.row.resolvedAt ?? $0.row.createdAt) > ($1.row.resolvedAt ?? $1.row.createdAt) }

        // Poengtabellen: aktive spillere, og alle som har satset (også arkiverte).
        let bets = items.map(\.bet)
        let staked = Set(input.stakes.map(\.memberID))
        let players = input.tavla.members
            .filter { $0.status == .active || staked.contains($0.id) }
            .map { Player(id: BetMapping.key($0.id), name: $0.displayName) }
        let ids = Dictionary(input.tavla.members.map { (BetMapping.key($0.id), $0.id) }, uniquingKeysWith: { a, _ in a })
        table = Bets.table(players: players, bets: bets, rules: rules).enumerated().compactMap { i, r in
            guard let id = ids[r.playerID] else { return nil }
            return TableRow(place: i + 1, memberID: id, row: r, isMe: id == me)
        }
    }

    var isEmpty: Bool { challenged.isEmpty && mine.isEmpty && others.isEmpty && settled.isEmpty }
    var openCount: Int { challenged.count + mine.count + others.count }
    var hasBank: Bool { rules.bets.startingPoints != nil }

    /// Din rad i poengtabellen.
    var myRow: BetTableRow? { table.first { $0.isMe }?.row }

    func item(_ id: UUID) -> Item? {
        (challenged + mine + others + settled).first { $0.id == id }
    }

    /// Runden som går (ikke låst), om det finnes en.
    var activeGame: RoundGame? {
        games.values.filter { $0.status == .active }.max { ($0.snapshot.eventDate ?? "") < ($1.snapshot.eventDate ?? "") }
    }

    /// Feiingen (`oppdaterMarkeder` på arrangørens telefon): det vilkårene nå gir svar på.
    /// Tom for andre enn arrangøren.
    var sweepPlan: [(betID: UUID, outcome: BetSide)] {
        guard isOrganizer else { return [] }
        let open = (challenged + mine + others).map(\.bet)
        return games.values.flatMap { game in
            Bets.sweep(open, round: game.round, hole: nil, roster: game.roster, claims: game.coreSideClaims, rules: rules)
        }
        .compactMap { u in
            guard let outcome = u.outcome, let id = u.betID.flatMap(UUID.init(uuidString:)) else { return nil }
            return (id, outcome)
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

    /// Spilleren veddemålet gjelder. Nil = om deg selv.
    let against: UUID?
    let againstName: String?
    let roundID: UUID?
    let eventID: UUID?
    let options: [Option]
    /// Valgt mal. `nil` = egen påstand (fri tekst).
    var selected: Int?
    var customText = ""
    var side: BetSide
    var points: Int

    /// Arket for en spiller eller for deg selv, med malene fra regelmotoren.
    init(board: BetsBoard, against: UUID?, game: RoundGame?) {
        self.against = against
        againstName = against.flatMap { board.names[$0] }
        roundID = game?.roundID
        eventID = game?.snapshot.round.eventID
        let me = board.names[board.me] ?? "Meg"
        let roundName = game.map { "Runde \($0.snapshot.round.roundNo)" }
        let templates = Bets.templates(round: game?.round, me: BetMapping.key(board.me),
                                       against: against.map(BetMapping.key), rules: board.rules)
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
        let bet = Bet(condition: condition, against: against.map(BetMapping.key))
        let round = roundID.flatMap { board.games[$0]?.round }
        let all = (board.challenged + board.mine + board.others + board.settled).map(\.bet)
        guard let p = Bets.stakeProblem(bet, playerID: BetMapping.key(board.me), side: side, points: points,
                                        round: round, bets: all, rules: board.rules) else { return nil }
        return BetTexts.problem(p, closedReason: BetTexts.closedReason(bet, round: round, rules: board.rules))
    }

    /// Kallet til `create_bet`. Uten mal og uten runde gjelder veddemålet sesongen.
    func params(clubID: UUID) -> CreateBetParams {
        let c = condition
        return CreateBetParams(clubID: clubID, roundID: roundID, eventID: roundID == nil ? eventID : nil,
                               question: question, condition: c.map(BetMapping.record), against: against,
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
        let all = (board.challenged + board.mine + board.others + board.settled).map(\.bet)
        guard let p = Bets.stakeProblem(item.bet, playerID: BetMapping.key(board.me), side: side, points: points,
                                        round: round, bets: all, rules: board.rules) else { return nil }
        return BetTexts.problem(p, closedReason: BetTexts.closedReason(item.bet, round: round, rules: board.rules))
    }
}
