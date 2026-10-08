import Foundation
import GolfgutuCore

/// Ett kort før seksjonene: kilden, filtrene og det oppsummeringen trenger. Kompakte linjer slås
/// sammen til kort først når seksjonene lages.
nonisolated struct HomeFeedDraft: Sendable {
    struct LineDraft: Equatable, Sendable {
        var symbol: String
        var text: String
        var context: String
        var reactions: HomeReactions?
        /// Påmeldinger som kan slås sammen: navnene og kvelden.
        var signupNames: [String] = []
        var signupDate: String?
    }

    enum Kind: Sendable {
        case myRound(HomeMyRoundCard)
        case feat(HomeFeatCard)
        case table(HomeTableCard)
        case line(LineDraft)
    }

    let id: String
    let date: Date
    let source: HomeFeedSource
    let filters: Set<HomeFeedFilter>
    var kind: Kind
    var isUnread: Bool
    /// Noe du gjorde selv (telles ikke i oppsummeringen).
    var isOwn = false
    /// Påmeldinger med samme nøkkel etter hverandre blir én linje.
    var signupKey: String?
    /// Det oppsummeringen sier om kortet («du klatret til 3. plass i Jakkeracet»), og hvor viktig det er.
    var phrase: String?
    var weight = 0

    var lineDraft: LineDraft? {
        if case .line(let line) = kind { return line }
        return nil
    }

    func line(now: Date) -> HomeLine {
        let l = lineDraft ?? LineDraft(symbol: "clock", text: "", context: "")
        return HomeLine(id: id, symbol: l.symbol, text: l.text, context: l.context,
                        time: ActivityFeed.relativeTime(date, now: now), reactions: l.reactions)
    }

    func card(now: Date) -> HomeFeedCard {
        let content: HomeFeedCard.Content = switch kind {
        case .myRound(let c): .myRound(c)
        case .feat(let c): .feat(c)
        case .table(let c): .table(c)
        case .line: .lines([line(now: now)])
        }
        return HomeFeedCard(id: id, date: date, time: ActivityFeed.relativeTime(date, now: now), source: source,
                            filters: filters, content: content, isUnread: isUnread)
    }
}

/// Lager kortene fra kildene: aktiviteten, rundene og de private turneringene.
nonisolated struct HomeFeedDrafts: Sendable {
    let context: HomeFeedContext

    init(_ context: HomeFeedContext) {
        self.context = context
    }

    private var input: HomeFeedInput { context.input }

    var all: [HomeFeedDraft] {
        activity + myRounds + roundFeats + privateTables
    }

    // MARK: Aktiviteten i klubbene

    var activity: [HomeFeedDraft] {
        input.activity.compactMap(draft)
    }

    private func draft(_ row: ActivityRow) -> HomeFeedDraft? {
        let own = row.actorMemberID.map { context.viewer.memberIDs.contains($0) } ?? false
        let unread = context.isUnread(row.createdAt, own: own)
        let id = "a-" + row.id.uuidString
        let placement = context.placement(round: row.roundID, club: row.clubID)
        switch row.event {
        case let .bigScore(member, hole, _, name, strokes, par):
            let label = row.roundID.flatMap { input.roundLabels[$0] }
            let card = feat(member: member, name: context.name(member), isMe: context.viewer.memberIDs.contains(member),
                            kind: name, hole: hole, strokes: strokes, par: par, label: label, roundID: row.roundID,
                            reactions: context.reactions(row))
            return HomeFeedDraft(id: id, date: row.createdAt, source: placement.source, filters: placement.filters,
                                 kind: .feat(card), isUnread: unread, isOwn: own,
                                 phrase: featPhrase(card), weight: 5)

        case let .tableChanged(competition, competitionName, roundNo, table):
            let source = context.competitionsByID[competition].map(context.source)
                ?? HomeFeedSource(filter: .competition(competition), title: competitionName, tone: .lime)
            let card = tableCard(table: table, competitionID: competition, competitionName: competitionName,
                                 roundNo: roundNo, name: context.name, reactions: context.reactions(row))
            return HomeFeedDraft(id: id, date: row.createdAt, source: source, filters: [source.filter],
                                 kind: .table(card), isUnread: unread, isOwn: false,
                                 phrase: TableChangeText.summaryPhrase(table: table, competitionName: competitionName,
                                                                       me: context.me, name: context.name),
                                 weight: tableWeight(card.myMove))

        case let .signup(member, status, eventDate):
            var line = lineDraft(row, placement: placement)
            var key: String?
            if status == .yes {
                line.signupNames = [context.name(member)]
                line.signupDate = eventDate
                key = "s:\(row.clubID.uuidString):\(eventDate ?? "")"
            }
            return HomeFeedDraft(id: id, date: row.createdAt, source: placement.source, filters: placement.filters,
                                 kind: .line(line), isUnread: unread, isOwn: own, signupKey: key)

        case .sidePrize, .tipsKing, .announcement, .committeeDrawn:
            return HomeFeedDraft(id: id, date: row.createdAt, source: placement.source, filters: placement.filters,
                                 kind: .line(lineDraft(row, placement: placement)), isUnread: unread, isOwn: own)

        // Ikke i feeden: rundene som startes og låses (dine egne står som «Din runde»), ledelsen
        // underveis (står i «Pågår nå»), rettinger, purring og påminnelser (bjella og «Neste kveld»),
        // veddemål, nye medlemmer og ukjente typer.
        default:
            return nil
        }
    }

    private func lineDraft(_ row: ActivityRow, placement: (source: HomeFeedSource, filters: Set<HomeFeedFilter>))
        -> HomeFeedDraft.LineDraft {
        let display = ActivityText.display(row, name: { input.names[$0] })
        let club = context.clubsByID[row.clubID]?.name ?? placement.source.title
        var context = club
        if let round = row.roundID, let label = input.roundLabels[round] {
            let parts = [placement.source.title, label.roundNo.flatMap { $0 > 0 ? "runde \($0)" : nil }].compactMap { $0 }
            context = parts.joined(separator: " · ")
        }
        return HomeFeedDraft.LineDraft(symbol: display.symbol, text: display.text, context: context,
                                       reactions: self.context.reactions(row))
    }

    // MARK: Dine runder

    /// Ferdige runder du spilte (klubb og løse), som «Din runde».
    var myRounds: [HomeFeedDraft] {
        let lockedRows = Dictionary(input.activity.filter { $0.kind == "round_locked" }
            .compactMap { r in r.roundID.map { ($0, r) } }, uniquingKeysWith: { a, _ in a })
        return uniqueRounds.compactMap { s -> HomeFeedDraft? in
            guard s.round.status == .locked, let me = context.viewer.playerID(in: s) else { return nil }
            let card = myRound(s, me: me, reactions: context.reactions(lockedRows[s.round.id]))
            let placement = context.placement(round: s.round.id, club: s.round.clubID)
            let date = s.round.lockedAt ?? s.round.startedAt ?? .distantPast
            let phrase = card.points.map { "du fikk \($0) poeng på \(card.title)" } ?? "du spilte \(card.title)"
            return HomeFeedDraft(id: "r-" + s.round.id.uuidString, date: date, source: placement.source,
                                 filters: placement.filters, kind: .myRound(card),
                                 isUnread: context.isUnread(date, own: false), phrase: phrase, weight: 1)
        }
    }

    private var uniqueRounds: [RoundSnapshot] {
        var seen = Set<UUID>()
        return input.rounds.filter { seen.insert($0.round.id).inserted }
    }

    func myRound(_ s: RoundSnapshot, me: UUID, reactions: HomeReactions?) -> HomeMyRoundCard {
        let game = RoundGame(s)
        let rows = game.bayenNaa(viewer: Viewer(memberID: me, isOrganizer: false))
        let mine = rows.first(where: \.isMe)
        var counts: [ScoreName: Int] = [:]
        let handicap = game.handicap(me)
        for (index, gross) in game.scores(me) where game.holes.indices.contains(index) {
            let hole = game.holes[index]
            let name = Scoring.scoreName(par: hole.par, gross: gross, handicap: handicap, strokeIndex: hole.strokeIndex,
                                         holes: game.holeCount)
            counts[name, default: 0] += 1
        }
        let marks = ScoreName.allCases.compactMap { n in counts[n].map { HomeScoreMark(name: n, count: $0) } }
        let others = HomeFeedText.others(s.players.map(\.memberID).filter { $0 != me }.map { s.names[$0] ?? "" })
        let roundText = s.isLoose || s.round.roundNo <= 0 ? nil : "Runde \(s.round.roundNo)"
        let subtitle = [roundText, others].compactMap { $0 }.joined(separator: " · ")
        let teams = rows.count != s.players.count
        let of = "av \(rows.count) " + (teams ? "lag" : rows.count == 1 ? "spiller" : "spillere")
        return HomeMyRoundCard(
            roundID: s.round.id, isLoose: s.isLoose, title: s.course?.name ?? "Runde",
            subtitle: subtitle.isEmpty ? nil : subtitle,
            points: mine.flatMap { $0.match == nil ? $0.total : nil },
            value: mine.map(MyRounds.value) ?? "–",
            place: mine?.place, placeText: mine?.place.map { "\($0). plass" }, ofText: of, marks: marks,
            insight: nil,
            winner: MyRounds.leaderLine(rows, finished: true, holeCount: game.holeCount),
            reactions: reactions)
    }

    // MARK: Bragder utenfor klubbene

    /// Eagle og bedre (brutto) i løse runder og i runder fra klubber du ikke er med i (private
    /// turneringer). Klubbrundene dine har dem allerede som `big_score` i aktiviteten.
    var roundFeats: [HomeFeedDraft] {
        uniqueRounds.flatMap { s -> [HomeFeedDraft] in
            guard s.round.status != .draft else { return [] }
            if let club = s.round.clubID, context.viewer.memberships[club] != nil { return [] }
            let game = RoundGame(s)
            let me = context.viewer.playerID(in: s)
            let placement = context.placement(round: s.round.id, club: s.round.clubID)
            let label = HomeRoundLabel(courseName: s.course?.name, roundNo: s.isLoose ? nil : s.round.roundNo)
            return s.scores.compactMap { score -> HomeFeedDraft? in
                guard game.holes.indices.contains(score.holeIndex) else { return nil }
                let par = game.holes[score.holeIndex].par
                guard let kind = BigScore.detect(gross: score.strokes, par: par) else { return nil }
                let name = s.names[score.memberID] ?? input.names[score.memberID] ?? "Noen"
                let card = feat(member: score.memberID, name: name, isMe: score.memberID == me, kind: kind,
                                hole: game.holeNumber(score.holeIndex), strokes: score.strokes, par: par, label: label,
                                roundID: s.round.id, reactions: nil)
                let date = score.recordedAt ?? s.round.startedAt ?? .distantPast
                return HomeFeedDraft(id: "f-\(s.round.id.uuidString)-\(score.memberID.uuidString)-\(score.holeIndex)",
                                     date: date, source: placement.source, filters: placement.filters,
                                     kind: .feat(card), isUnread: context.isUnread(date, own: false),
                                     phrase: featPhrase(card), weight: 5)
            }
        }
    }

    func feat(member: UUID, name: String, isMe: Bool, kind: BigScoreName, hole: Int, strokes: Int, par: Int,
              label: HomeRoundLabel?, roundID: UUID?, reactions: HomeReactions?) -> HomeFeatCard {
        let place = [HomeFeedText.roundPlace(label), "hull \(hole)"].compactMap { $0 }.joined(separator: " · ")
        let detail = ["\(strokes) slag på par \(par)", label?.courseName].compactMap { $0 }.joined(separator: " · ")
        return HomeFeatCard(memberID: member, name: name, initials: HomeFeedText.initials(name), isMe: isMe, kind: kind,
                            strokes: strokes, par: par, hole: hole, headline: HomeFeedText.featHeadline(kind, hole: hole),
                            detail: detail, place: place, roundID: roundID, reactions: reactions)
    }

    private func featPhrase(_ card: HomeFeatCard) -> String {
        (card.isMe ? "du" : card.name) + " " + HomeFeedText.featVerb(card.kind)
    }

    // MARK: Tabellen

    func tableCard(table: [ActivityTableSpot], competitionID: UUID, competitionName: String, roundNo: Int?,
                   name: (UUID) -> String, reactions: HomeReactions?) -> HomeTableCard {
        let me = context.me
        let sorted = table.sorted { $0.place < $1.place }
        let mine = sorted.first { me.contains($0.member) }
        var rows = sorted.filter { $0.place <= TableChange.topCount }
        if let mine, mine.place > TableChange.topCount { rows.append(mine) }
        return HomeTableCard(
            competitionID: competitionID, competitionName: competitionName,
            text: TableChangeText.personal(table: table, competitionName: competitionName, roundNo: roundNo, me: me,
                                           name: name),
            rows: rows.map { s in
                HomeTableRow(id: s.member, place: s.place, name: name(s.member), points: s.points.map(LeagueStandings.points),
                             move: s.move, isMe: me.contains(s.member))
            },
            myPlace: mine?.place, myMove: mine?.move, reactions: reactions)
    }

    private func tableWeight(_ move: Int?) -> Int {
        guard let move, move != 0 else { return 0 }
        return 10 + abs(move) * 2 + (move > 0 ? 1 : 0)
    }

    /// Plassbyttet etter siste låste runde i private turneringer (liga og morro), regnet her fordi
    /// de ikke har en klubb å logge i. Klubbenes turneringer logges (`TableChangeLogger`).
    var privateTables: [HomeFeedDraft] {
        input.competitionInputs.compactMap { ci -> HomeFeedDraft? in
            let c = ci.competition
            guard c.kind == .league || c.kind == .fun else { return nil }
            if let club = c.clubID, context.viewer.memberships[club] != nil { return nil }
            let locked = ci.rounds.filter { $0.round.status == .locked && $0.round.lockedAt != nil }
            guard let latest = locked.max(by: { $0.round.lockedAt! < $1.round.lockedAt! }),
                  let date = latest.round.lockedAt else { return nil }
            let before = CompetitionInput(competition: c, entrants: ci.entrants, roster: ci.roster,
                                          rounds: ci.rounds.filter { $0.round.id != latest.round.id })
            guard let table = TableChange.spots(before: TableBoard(LeagueStandings(before, me: [])),
                                                after: TableBoard(LeagueStandings(ci, me: []))) else { return nil }
            let names = Dictionary(zip(ci.entrants.map(\.id), ci.roster.map(\.name)), uniquingKeysWith: { a, _ in a })
            let lookup: (UUID) -> String = { names[$0] ?? input.names[$0] ?? "Noen" }
            let roundNo = (ci.rounds.firstIndex { $0.round.id == latest.round.id } ?? ci.rounds.count - 1) + 1
            let card = tableCard(table: table, competitionID: c.id, competitionName: c.name, roundNo: roundNo,
                                 name: lookup, reactions: nil)
            let source = context.source(c)
            return HomeFeedDraft(id: "t-\(c.id.uuidString)-\(latest.round.id.uuidString)", date: date, source: source,
                                 filters: [source.filter], kind: .table(card),
                                 isUnread: context.isUnread(date, own: false),
                                 phrase: TableChangeText.summaryPhrase(table: table, competitionName: c.name,
                                                                       me: context.me, name: lookup),
                                 weight: tableWeight(card.myMove))
        }
    }
}
