import Foundation
import GolfgutuCore

/// Alt kupongen henter for én kveld, slik databasen leverer det. Rene rader, ingen poeng.
nonisolated struct TipsInput: Equatable, Sendable {
    var event: TipsEventRow
    /// Regelsettet til kveldens sesong (standard frist, innsats og linje). Ellers Golfgutu.
    var rules: Ruleset = .golfgutu
    /// Hele troppen, alle statuser (en arkivert spiller kan ha levert eller spilt).
    var members: [ClubMemberRow] = []
    var signups: [SignupRow] = []
    /// Kveldens runder med alt under, i opprettelsesrekkefølge. Kladder ser bare arrangøren.
    var rounds: [RoundSnapshot] = []
    /// Kupongene du får lese: din egen før låsing, alles etter (RLS).
    var coupons: [TipsRow] = []
    /// `tips_submitted`: hvem som har levert.
    var submitted: [TipsSubmittedRow] = []
    /// `tips_deadline` fra databasen. Mangler den, regnes fristen her.
    var serverDeadline: Date?
    /// `tips_open` fra databasen, som er låsen som gjelder. Mangler den, regnes det her.
    var serverOpen: Bool?
}

/// Tippekupongen for én kveld: tilstand, frist, kandidatene, hvem som har levert, fasit og
/// resultat. Tallene regnes av GolfgutuCore (`Tips`). Ren, uten nettverk og SwiftUI.
nonisolated struct TipsBoard: Sendable {
    enum Phase: Equatable, Sendable {
        /// Før fristen og før første slag: du kan levere, endre og trekke.
        case open
        /// Kvelden er i gang: alle ser alles kuponger, fasiten er stillingen så langt.
        case locked
        /// Alle rundene er låst: tippekongen er kåret.
        case finished
    }

    /// En spiller å velge på kupongen.
    struct Candidate: Identifiable, Hashable, Sendable {
        let memberID: UUID
        let name: String
        var id: UUID { memberID }
    }

    /// Ett svar på ett spørsmål og hvem som tippet det («Dette tippet gjengen»).
    struct AnswerGroup: Identifiable, Hashable, Sendable {
        let text: String
        let memberIDs: [UUID]
        /// Riktig etter fasiten. `nil`: strøket, eller kvelden er ikke ferdig.
        let correct: Bool?
        var id: String { text }
    }

    let event: TipsEventRow
    let rules: Ruleset
    /// Spørsmålene på kupongen, fra regelsettet.
    var questions: [TipsQuestion] { rules.tips.questions }
    let me: UUID
    let isOrganizer: Bool
    let phase: Phase
    let deadline: Date?
    /// Innsats per kupong i poeng. 0 = for æra.
    let stake: Int
    /// Om arrangøren kan sette innsats (av i App Store-bygget).
    let allowsStakes: Bool
    let line: Double
    /// Kandidatene: de som kommer først, så resten av troppen. Kommer ingen, er alle i `first`.
    let firstCandidates: [Candidate]
    let otherCandidates: [Candidate]

    /// Står spilleren blant kandidatene? En spiller som er arkivert etter at kupongen ble fylt ut, gjør ikke det.
    func isCandidate(_ id: UUID) -> Bool {
        firstCandidates.contains { $0.memberID == id } || otherCandidates.contains { $0.memberID == id }
    }
    /// Hvem som har levert, sortert på navn.
    let submitted: [UUID]
    /// Påmeldt (kommer), men ikke levert.
    let missing: [UUID]
    let myCoupon: TipsCoupon?
    let answerKey: TipsAnswerKey
    let result: TipsResult
    let pot: TipsPot

    private let names: [UUID: String]
    private let shortNames: [UUID: String]

    /// `allowsStakes` av (App Store-bygget, `BetsFeature`): kupongen er alltid for æra, uten pott.
    init(_ input: TipsInput, me: UUID, isOrganizer: Bool, now: Date = .now,
         allowsStakes: Bool = BetsFeature.isEnabled) {
        self.me = me
        self.isOrganizer = isOrganizer
        self.allowsStakes = allowsStakes
        event = input.event
        rules = input.rules
        stake = allowsStakes ? Tips.stake(input.event.stakePoints, rules: input.rules) : 0
        line = Tips.line(input.event.line, rules: input.rules)

        let names = Dictionary(input.members.map { ($0.id, $0.displayName) }, uniquingKeysWith: { a, _ in a })
        self.names = names
        let short = TipsBoard.shortNames(input.members)
        shortNames = short

        // Rundene slik regelmotoren ser dem, med frosset handicap fra round_players.
        let rounds = input.rounds.map { snapshot -> TipsRound in
            var s = snapshot
            s.rules = input.rules
            for m in input.members where s.names[m.id] == nil { s.names[m.id] = m.displayName }
            let game = RoundGame(s)
            let handicaps = Dictionary(s.players.map { ($0.memberID.uuidString, game.handicap($0.memberID)) },
                                       uniquingKeysWith: { a, _ in a })
            return TipsRound(round: game.round, roster: game.roster, handicaps: handicaps,
                             isDraft: snapshot.round.status == .draft)
        }

        let computedDeadline = Tips.deadline(date: input.event.eventDate, startTime: input.event.startTime,
                                             rules: input.rules)
        deadline = input.serverDeadline ?? computedDeadline
        let open = input.serverOpen
            ?? Tips.isOpen(deadline: deadline, now: now, hasScore: Tips.hasScore(rounds))
        let key = Tips.answerKey(rounds: rounds, line: line, rules: input.rules)
        answerKey = key
        phase = open ? .open : (key.finished ? .finished : .locked)

        let players = input.members.map { Player(id: $0.id.uuidString, name: $0.displayName) }
        let coupons = input.coupons.filter { $0.eventID == input.event.id }
        result = Tips.result(coupons: coupons.map(\.coupon), key: key, players: players, rules: input.rules)
        pot = Tips.pot(result, stake: stake)
        myCoupon = coupons.first { $0.memberID == me }?.coupon

        // Levert: tips_submitted, pluss ditt eget og de kupongene du ser.
        var delivered = Set(input.submitted.map(\.memberID))
        delivered.formUnion(coupons.map(\.memberID))
        submitted = delivered.filter { names[$0] != nil }
            .sorted { NorwegianSort.areInIncreasingOrder(names[$0] ?? "", names[$1] ?? "") }

        let sorted = KveldQueries.sortedByName(input.members)
        let summary = SignupSummary(members: sorted, signups: input.signups.filter { $0.eventID == input.event.id })
        let candidate = { (e: SignupSummary.Entry) in Candidate(memberID: e.memberID, name: short[e.memberID] ?? e.name) }
        let coming = summary.yes.map(candidate)
        // Ventelista kommer ikke (ennå), så den står blant resten. Gjester tipper ikke.
        let rest = (summary.waitlist.filter { !$0.isGuest } + summary.maybe + summary.notAnswered + summary.no)
            .map(candidate)
        firstCandidates = coming.isEmpty ? rest : coming
        otherCandidates = coming.isEmpty ? [] : rest
        missing = summary.yes.map(\.memberID).filter { !delivered.contains($0) }
    }

    // MARK: Navn

    /// `tipsKortNavn`: fornavnet, med første bokstav i etternavnet når to deler fornavn.
    static func shortNames(_ members: [ClubMemberRow]) -> [UUID: String] {
        let parts = members.map { m in (m.id, m.displayName.split(whereSeparator: \.isWhitespace).map(String.init)) }
        var out: [UUID: String] = [:]
        for (id, words) in parts {
            guard let first = words.first else { out[id] = ""; continue }
            let shared = parts.contains { $0.0 != id && $0.1.first == first }
            out[id] = shared && words.count > 1 ? first + " " + String(words[1].prefix(1)) + "." : first
        }
        return out
    }

    func shortName(_ id: UUID) -> String { shortNames[id] ?? "Ukjent" }

    func shortName(_ id: String?) -> String {
        guard let id, let uuid = UUID(uuidString: id) else { return "Ukjent" }
        return shortName(uuid)
    }

    /// `tipsNavnListe`: «Anders, Bjørn og Cato».
    func nameList(_ ids: [UUID]) -> String { NorwegianList.join(ids.map(shortName)) }

    func nameList(_ ids: [String]) -> String { NorwegianList.join(ids.map { shortName($0) }) }

    // MARK: Tilstand

    /// Når skjermen skal hente kupongen på nytt fordi fristen låser den, i sekunder fra `now`.
    /// Bare mens den er åpen. Er fristen passert uten at serveren har låst (telefonens klokke
    /// går foran), prøves det igjen litt senere.
    func secondsUntilLockCheck(now: Date) -> TimeInterval? {
        guard phase == .open, let deadline else { return nil }
        let left = deadline.timeIntervalSince(now)
        return left > 0 ? left + Self.lockCheckMargin : Self.lockRecheckInterval
    }

    /// Litt etter fristen, så serveren rekker å regne den som passert.
    static let lockCheckMargin: TimeInterval = 2
    static let lockRecheckInterval: TimeInterval = 30

    /// Arrangøren kan endre innsats og linje til første kupong er levert (databasen: 55000).
    var canEditSettings: Bool { isOrganizer && phase == .open && submitted.isEmpty }

    /// `tipsFristTekst`: «torsdag 8. oktober kl. 17:00», i Oslo-tid.
    var deadlineText: String {
        guard let deadline else { return "ukjent frist" }
        return TipsBoard.deadlineFormatter.string(from: deadline)
    }

    var statusText: String {
        switch phase {
        case .open: "Låses \(deadlineText), eller når første slag føres"
        case .locked: "Låst · kvelden er i gang"
        case .finished: "Ferdig · alle rundene er låst"
        }
    }

    /// «Innsats 50 poeng» eller «For æra».
    var stakeText: String { stake > 0 ? "Innsats \(stake) poeng" : "For æra · ingen poeng" }

    /// «4 levert · 200 poeng i potten».
    var potText: String {
        let n = submitted.count
        return "\(n) levert" + (stake > 0 && n > 0 ? " · \(stake * n) poeng i potten" : "")
    }

    func title(_ q: TipsQuestion) -> String {
        Tips.title(q, line: Tips.line(for: q, eventLine: line, rules: rules) ?? line)
    }

    /// Spør kupongen om snittet? Ellers har kveldens linje ingenting å si.
    var asksAverage: Bool { questions.contains(.over) }

    // MARK: Svar og fasit

    /// `tipsSvarTekst`.
    func answerText(_ q: TipsQuestion, coupon: TipsCoupon?) -> String {
        switch q.kind {
        case .player:
            guard let id = coupon?.player(q), !id.isEmpty else { return "—" }
            return shortName(id)
        case .yesNo:
            guard let v = coupon?.flag(q) else { return "—" }
            return v ? "Ja" : "Nei"
        case .overUnder:
            guard let v = coupon?.flag(q) else { return "—" }
            return v ? "Over" : "Under"
        }
    }

    /// `tipsFasitTekst`: «Anders og Dag · 36 poeng», «Under · snittet ble +2,25 mot +2,5».
    func answerKeyText(_ q: TipsQuestion) -> String {
        let f = answerKey
        if f.isVoid(q) {
            switch q {
            case .frontNine: return "Strøket – ingen førte alle de ni første hullene"
            case .backNine: return "Strøket – ingen førte alle de ni siste hullene"
            case .over: return f.average == nil ? "Strøket – ingen scorer" : "Strøket – snittet traff linja"
            case .mostBirdies: return f.field.isEmpty ? "Strøket – ingen scorer" : "Strøket – ingen birdier"
            case .birdieCount, .winnerPoints:
                return f.figure(q) == nil ? "Strøket – ingen scorer" : "Strøket – traff linja"
            default: return Self.voidText(q, outcome: f.outcomes[q], hasField: !f.field.isEmpty)
            }
        }
        switch q {
        case .winner: return nameList(f.winner ?? []) + " · \(f.winnerPoints ?? 0) poeng"
        case .frontNine: return nameList(f.frontNine ?? []) + " · \(f.frontNineNet ?? 0) netto"
        case .mostPars: return nameList(f.mostPars ?? []) + " · \(f.mostParsHoles ?? 0) hull"
        case .birdie: return f.birdie == true ? "Ja" : "Nei"
        case .over:
            return (f.over == true ? "Over" : "Under") + " · snittet ble "
                + Tips.formatSigned(f.average ?? 0, decimals: 2) + " mot " + Tips.formatSigned(f.line, decimals: 1)
        case .backNine: return nameList(f.backNine ?? []) + " · \(f.backNineNet ?? 0) netto"
        case .mostBirdies:
            let n = f.mostBirdiesCount ?? 0
            return nameList(f.mostBirdies ?? []) + " · \(n) " + (n == 1 ? "birdie" : "birdier")
        case .birdieCount:
            let n = f.birdies ?? 0
            return (f.birdieCount == true ? "Over" : "Under") + " · \(n) " + (n == 1 ? "birdie" : "birdier") + " mot "
                + Tips.formatPlain(f.birdieCountLine ?? rules.tips.birdieCountLine)
        case .winnerPoints:
            return (f.overWinnerPoints == true ? "Over" : "Under") + " · vinneren fikk \(f.winnerPoints ?? 0) poeng mot "
                + Tips.formatPlain(f.winnerPointsLine ?? rules.tips.winnerPointsLine)
        default:
            let o = f.outcomes[q] ?? TipsOutcome()
            switch q.kind {
            case .player: return nameList(o.players ?? []) + " · " + Self.figureText(q, o.figure ?? 0)
            case .yesNo: return o.flag == true ? "Ja" : "Nei"
            case .overUnder:
                return (o.flag == true ? "Over" : "Under") + " · " + Self.figureText(q, o.figure ?? 0)
                    + " mot " + Tips.formatPlain(o.line ?? 0)
            }
        }
    }

    /// «3 poeng», «+3 poeng» (comeback), «17 hull», «2 spillere».
    static func figureText(_ q: TipsQuestion, _ x: Double) -> String {
        let n = Int(x.rounded())
        let number = q == .comeback && n > 0 ? "+\(n)" : (n < 0 ? "−\(-n)" : "\(n)")
        return number + " " + q.unit(x)
    }

    /// Hvorfor et av de morsomme spørsmålene er strøket.
    static func voidText(_ q: TipsQuestion, outcome: TipsOutcome?, hasField: Bool) -> String {
        guard hasField else { return "Strøket – ingen scorer" }
        if q.kind == .overUnder { return outcome?.figure == nil ? "Strøket – for få spillere" : "Strøket – traff linja" }
        switch q {
        case .lowestGross: return "Strøket – ingen førte alle hullene"
        case .comeback: return "Strøket – ingen førte alle de 18 hullene"
        case .leaderWins: return "Strøket – ingen førte alle de ni første hullene"
        case .mostBlanks: return "Strøket – ingen blanke hull"
        case .parStreak: return "Strøket – ingen par eller bedre"
        case .bestParThrees: return "Strøket – ingen par 3-hull"
        case .bestParFives: return "Strøket – ingen par 5-hull"
        case .highHandicapWins: return "Strøket – for få spillere"
        default: return "Strøket – ingen scorer"
        }
    }

    /// `renderTipsAlle`: svarene per spørsmål, flest stemmer først, så svaret alfabetisk.
    /// Riktige svar merkes først når kvelden er ferdig (som PWA-en).
    func groups(_ q: TipsQuestion) -> [AnswerGroup] {
        var byText: [String: [UUID]] = [:]
        var sample: [String: TipsCoupon] = [:]
        for row in result.rows {
            let text = answerText(q, coupon: row.coupon)
            if let id = UUID(uuidString: row.playerID) { byText[text, default: []].append(id) }
            sample[text] = sample[text] ?? row.coupon
        }
        return byText.map { text, ids in
            let correct = phase == .finished ? Tips.isCorrect(q, coupon: sample[text], key: answerKey) : nil
            return AnswerGroup(text: text, memberIDs: ids, correct: correct)
        }
        .sorted { a, b in
            a.memberIDs.count != b.memberIDs.count
                ? a.memberIDs.count > b.memberIDs.count
                : NorwegianSort.areInIncreasingOrder(a.text, b.text)
        }
    }

    /// Plassen i resultatlista (delt plass ved likt), 1-basert.
    func place(of row: TipsResult.Row) -> Int {
        (result.rows.firstIndex { $0.points == row.points } ?? 0) + 1
    }

    /// Kongelinja: «Anders og Cato · 4 av 5 riktige · deler potten på 200 poeng».
    var kingText: String {
        guard !result.winners.isEmpty else { return "" }
        var text = "\(result.best) av \(result.possible) riktige"
        if pot.total > 0 && result.rows.count > 1 && result.winners.count < result.rows.count {
            text += result.winners.count > 1 ? " · deler potten på \(pot.total) poeng" : " · tar potten på \(pot.total) poeng"
        }
        return text
    }

    /// VoiceOver for én linje i resultatlista: «2. plass, Anders, 3 av 5 riktige».
    static func resultAccessibilityLabel(place: Int, name: String, isWinner: Bool, points: Int, possible: Int) -> String {
        "\(place). plass, \(name)" + (isWinner ? ", tippekonge" : "") + ", \(points) av \(possible) riktige"
    }

    // MARK: Hjelpere

    static let deadlineFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "nb_NO")
        f.timeZone = Tips.timeZone
        f.dateFormat = "EEEE d. MMMM 'kl.' HH:mm"
        return f
    }()
}

/// Kupongutkastet på skjermen: det du har valgt, før det er levert.
nonisolated struct TipsDraft: Equatable, Sendable {
    var coupon: TipsCoupon

    init(me: UUID, saved: TipsCoupon?) {
        coupon = saved ?? TipsCoupon(playerID: me.uuidString)
    }

    mutating func choose(_ q: TipsQuestion, player: UUID) {
        coupon.setPlayer(q, player.uuidString)
    }

    mutating func set(_ q: TipsQuestion, _ value: Bool) {
        coupon.setFlag(q, value)
    }

    /// `tipsEndret`: noe er annerledes enn den leverte (eller ingenting er levert).
    func isChanged(from saved: TipsCoupon?) -> Bool {
        guard let saved else { return true }
        return !coupon.hasSameAnswers(as: saved)
    }

    /// Knappen: «Send inn kupongen», «Lagre endringene» eller «Levert».
    func buttonTitle(saved: TipsCoupon?) -> String {
        saved == nil ? "Send inn kupongen" : (isChanged(from: saved) ? "Lagre endringene" : "Levert")
    }

    func canSubmit(saved: TipsCoupon?, questions: [TipsQuestion] = Ruleset.golfgutu.tips.questions) -> Bool {
        coupon.isComplete(for: questions) && isChanged(from: saved)
    }
}
