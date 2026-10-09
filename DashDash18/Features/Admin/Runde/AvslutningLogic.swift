import Foundation
import GolfgutuCore

// Avslutning og retting for arrangøren (fase 7): avkort runden, avslutt kvelden, rett en score
// og hele runden som tabell. Ren logikk over `RoundGame`, uten nettverk og SwiftUI.
// Som PWA-ens avkortValg, renderAvkortInnhold, avkortingenKoster, handleAvsluttKvelden,
// rundeSpillere, renderHeleRunden og renderRundeRetting (app-nytt.js 5138–5440, 6411–6660).

// MARK: - Avkorting

nonisolated extension Truncation.Rule {
    /// Verdien i `rounds.cut_rule`. Motsatt vei: `RoundGame.cutRule(_:)`.
    var databaseValue: String {
        switch self {
        case .common: "common"
        case .netPar: "net_par"
        case .zero: "zero"
        }
    }
}

/// Arrangørens valg i avkortingsarket.
nonisolated struct CutChoice: Equatable, Sendable {
    var rule: Truncation.Rule
    /// Antall hull runden stoppet etter (1…antall hull).
    var after: Int
}

/// Hva avkortingen gjør med summene (`avkortingenKoster` uten veddemålene).
nonisolated struct CutPreview: Equatable, Sendable {
    struct Line: Equatable, Identifiable, Sendable {
        let memberID: UUID
        let name: String
        let before: Int
        let after: Int
        var diff: Int { after - before }
        var id: UUID { memberID }

        /// «Anders 36 → 28 (−8)».
        var text: String { "\(name) \(before) → \(after) (\(CutPreview.signed(diff)))" }
    }

    /// Tellende hull med avkortingen.
    let countingHoles: Int
    let holes: Int
    /// Spillerne som får en annen sum, størst tap først.
    let lines: [Line]

    var losers: Int { lines.filter { $0.diff < 0 }.count }

    /// «+8», «−8» (ekte minus), «0».
    static func signed(_ n: Int) -> String {
        n > 0 ? "+\(n)" : n < 0 ? "−\(-n)" : "0"
    }
}

nonisolated extension RoundGame {
    /// `lavesteFellesHull`.
    var lowestCommonHole: Int { Truncation.lowestCommonHole(round) }

    /// Regelen runden er avkortet med, eller nil.
    var cutRule: Truncation.Rule? { Truncation.rule(round) }

    /// `avkortValg`: lagret valg, ellers «felles» etter laveste felles hull (eller hele runden).
    var defaultCutChoice: CutChoice {
        let common = lowestCommonHole
        if let rule = cutRule {
            return CutChoice(rule: rule, after: clampAfter(snapshot.round.cutAfter ?? common))
        }
        return CutChoice(rule: .common, after: clampAfter(common > 0 ? common : holeCount))
    }

    private func clampAfter(_ n: Int) -> Int { min(holeCount, max(1, n)) }

    /// Runden med et tenkt kutt (som `avkortingenKoster` bygger `utkast`).
    func rounding(with choice: CutChoice?) -> Round {
        var draft = round
        draft.avkortRegel = choice?.rule.rawValue
        draft.avkortetEtter = choice.map { Double($0.after) }
        return draft
    }

    /// `avkortingenKoster`: summen per spiller før og etter kuttet, for dem som har ført noe.
    /// Med rundens frosne handicap (`handicap(_:)`), som resten av appen; uten lagret
    /// spillehandicap er det PWA-ens `effectiveHandicap`. Likt tap: norsk navnesortering.
    func cutPreview(_ choice: CutChoice) -> CutPreview {
        let draft = rounding(with: choice)
        let lines = snapshot.players.compactMap { p -> CutPreview.Line? in
            let s = scores(p.memberID)
            guard !s.isEmpty else { return nil }
            let hcp = handicap(p.memberID)
            let before = Scoring.points(from: s, in: round, handicap: hcp, rules: rules)
            let after = Scoring.points(from: s, in: draft, handicap: hcp, rules: rules)
            guard before != after else { return nil }
            return CutPreview.Line(memberID: p.memberID, name: name(p.memberID), before: before, after: after)
        }
        .sorted { a, b in
            a.diff != b.diff ? a.diff < b.diff : NorwegianSort.areInIncreasingOrder(a.name, b.name)
        }
        return CutPreview(countingHoles: Truncation.countingHoles(draft), holes: holeCount, lines: lines)
    }

    /// Hjelpeteksten under «Runden stoppet etter hull».
    func cutHint(for rule: Truncation.Rule) -> String {
        let common = lowestCommonHole
        guard common > 0 else { return "Ingen har ført noe ennå." }
        return "Alle som har begynt har ført til og med hull \(holeNumber(common - 1)). "
            + (rule == .common
               ? "Med denne regelen er det tallet du vil ha."
               : "Tallet er opplysning her. Regelen over fyller hullene i stedet for å kutte dem.")
    }

    /// Navnet på hullet runden stopper etter: «Hull 14» (siste ni: «Hull 14» for det femte).
    func cutOptionTitle(_ after: Int) -> String {
        "Hull \(holeNumber(after - 1))" + (after == lowestCommonHole ? " · laveste felles" : "")
    }

    /// «Avkortet etter hull 14 · tell til laveste felles hull», eller nil.
    var cutSummary: String? {
        guard let rule = cutRule, let after = snapshot.round.cutAfter else { return nil }
        return "Avkortet etter hull \(holeNumber(after - 1)) · \(rule.name.lowercased())"
    }

    /// Antall spillere som har begynt, men ikke ført alle tellende hull (`handleAvsluttKvelden`).
    /// Som PWA-ens `roundThru`: antall førte hull, ikke sammenhengende.
    var playersMissingHoles: Int {
        let counting = Truncation.countingHoles(round)
        return snapshot.players.filter { p in
            let thru = scores(p.memberID).count
            return thru > 0 && thru < counting
        }.count
    }
}

/// Endringen i `rounds` for avkortingen. Fjerning skriver eksplisitt null i alle fire.
nonisolated struct CutPatch: Encodable, Equatable, Sendable {
    let rule: String?
    let after: Int?
    let by: UUID?
    let at: Date?

    static func set(_ choice: CutChoice, by member: UUID, at date: Date) -> CutPatch {
        CutPatch(rule: choice.rule.databaseValue, after: choice.after, by: member, at: date)
    }

    static let remove = CutPatch(rule: nil, after: nil, by: nil, at: nil)

    enum CodingKeys: String, CodingKey {
        case rule = "cut_rule"
        case after = "cut_after"
        case by = "cut_by"
        case at = "cut_at"
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(rule, forKey: .rule)
        try c.encode(after, forKey: .after)
        try c.encode(by, forKey: .by)
        try c.encode(at, forKey: .at)
    }

    /// Står raden slik vi skrev den? (RLS kan si nei uten feilkode.)
    func matches(_ row: RoundRow) -> Bool {
        row.cutRule == rule && row.cutAfter == after
    }
}

// MARK: - Avslutt kvelden

/// Spørsmålet før kvelden avsluttes (`handleAvsluttKvelden`).
nonisolated struct EveningClosePrompt: Equatable, Sendable {
    let title: String
    let lines: [String]
    /// Runden arrangøren bør avkorte først, når noen mangler hull og den ikke er avkortet.
    let suggestCut: UUID?
}

nonisolated enum EveningClose {
    struct Check: Equatable, Sendable {
        let roundID: UUID
        let title: String
        let missing: Int
        let countingHoles: Int
        /// Poeng et uspilt hull gir slik runden står (`poengForTomtHull`).
        let emptyHolePoints: Int
        /// «Avkortet etter hull 14 · …», eller nil.
        let cutSummary: String?
    }

    static func check(_ game: RoundGame, title: String) -> Check {
        Check(roundID: game.roundID, title: title, missing: game.playersMissingHoles,
              countingHoles: Truncation.countingHoles(game.round),
              emptyHolePoints: Truncation.pointsForEmptyHole(game.round, rules: game.rules),
              cutSummary: game.cutSummary)
    }

    /// Nil når det ikke er noen pågående runde å låse.
    static func prompt(_ checks: [Check], term: DayTerm = .evening) -> EveningClosePrompt? {
        guard !checks.isEmpty else { return nil }
        var lines: [String] = []
        var suggest: UUID?
        for c in checks {
            let prefix = checks.count > 1 ? "\(c.title): " : ""
            if c.missing > 0 && c.cutSummary == nil {
                lines.append(prefix + (c.missing == 1 ? "1 spiller har" : "\(c.missing) spillere har")
                             + " ikke ført alle \(c.countingHoles) hullene. Uspilte hull gir \(c.emptyHolePoints) poeng slik runden står nå, så den som rakk færrest hull taper på det.")
                if suggest == nil { suggest = c.roundID }
            } else if let cut = c.cutSummary {
                lines.append(prefix + cut + ".")
            }
        }
        lines.append(checks.count == 1 ? "Runden låses og teller i turneringen." : "Rundene låses og teller i turneringen.")
        let title = checks.count == 1 ? "Avslutte \(checks[0].title)?" : "Avslutte \(term.the)?"
        return EveningClosePrompt(title: title, lines: lines, suggestCut: suggest)
    }

    /// Meldingen etterpå: hva som ble låst, og hva som står igjen.
    static func summary(locked: [String], drafts: [String], failed: [String], term: DayTerm = .evening) -> String {
        let day = DayTerm.capitalized(term.the)
        var parts: [String] = []
        if !locked.isEmpty {
            parts.append(locked.count == 1 ? "\(locked[0]) er låst." : "Låst: \(locked.joined(separator: ", ")).")
        }
        if !failed.isEmpty {
            parts.append("Ble ikke låst: \(failed.joined(separator: ", ")). Prøv igjen.")
        }
        if drafts.isEmpty {
            if failed.isEmpty { parts.append("\(day) er ferdig, og neste \(term.one) står øverst.") }
        } else {
            parts.append("Kladden \(drafts.joined(separator: ", ")) er ikke spilt. \(day) er ikke ferdig før den er startet og låst, eller slettet.")
        }
        return parts.joined(separator: " ")
    }
}

// MARK: - Hele runden som tabell

nonisolated struct RoundTable: Equatable, Sendable {
    struct Column: Equatable, Identifiable, Sendable {
        let index: Int
        let number: Int
        let par: Int
        /// Utenfor avkortingen: teller ikke.
        let outside: Bool
        var id: Int { index }
    }

    struct Cell: Equatable, Identifiable, Sendable {
        let index: Int
        let strokes: Int?
        let scoreName: ScoreName?
        let outside: Bool
        var id: Int { index }
    }

    struct Row: Equatable, Identifiable, Sendable {
        let memberID: UUID
        let name: String
        let cells: [Cell]
        /// Sum brutto, nil når ingenting er ført.
        let strokes: Int?
        let points: Int
        var id: UUID { memberID }
    }

    let columns: [Column]
    let parTotal: Int
    let rows: [Row]
    let countingHoles: Int

    var hasOutside: Bool { columns.contains(where: \.outside) }
}

nonisolated extension RoundGame {
    /// `rundeSpillere` + `renderHeleRunden`: de som har ført noe, flest poeng først
    /// (likt: norsk navnesortering). Har ingen ført noe, står alle deltakerne.
    func table() -> RoundTable {
        let counting = Truncation.countingHoles(round)
        let columns = holes.enumerated().map { i, hole in
            RoundTable.Column(index: i, number: holeNumber(i), par: hole.par, outside: i >= counting)
        }
        var members = snapshot.players.map(\.memberID).filter { !scores($0).isEmpty }
        if members.isEmpty { members = snapshot.players.map(\.memberID) }

        let rows = members.map { member -> RoundTable.Row in
            let s = scores(member)
            let hcp = handicap(member)
            let cells = holes.enumerated().map { i, hole in
                RoundTable.Cell(index: i, strokes: s[i],
                                scoreName: s[i].map { Scoring.scoreName(par: hole.par, gross: $0, handicap: hcp,
                                                                         strokeIndex: hole.strokeIndex, holes: holeCount) },
                                outside: i >= counting)
            }
            let gross = s.filter { $0.key >= 0 && $0.key < holes.count }.values.reduce(0, +)
            return RoundTable.Row(memberID: member, name: name(member), cells: cells,
                                  strokes: s.isEmpty ? nil : gross, points: total(member))
        }
        .sorted { a, b in
            a.points != b.points ? a.points > b.points : NorwegianSort.areInIncreasingOrder(a.name, b.name)
        }
        return RoundTable(columns: columns, parTotal: columns.reduce(0) { $0 + $1.par },
                          rows: rows, countingHoles: counting)
    }
}

// MARK: - Rett en score

/// Én retting: spiller, hull og nytt tall (`rundeRetting`).
nonisolated struct ScoreCorrection: Equatable, Sendable {
    let memberID: UUID
    let holeIndex: Int
    /// Det som står lagret nå, eller nil.
    let original: Int?
    var strokes: Int

    /// `velgRundeRute`: åpner med tallet som står, ellers par.
    init(game: RoundGame, member: UUID, hole: Int) {
        memberID = member
        holeIndex = hole
        original = game.scores(member)[hole]
        strokes = StrokeInput.clamp(original ?? game.holes[hole].par)
    }

    var isChanged: Bool { strokes != original }

    /// `stegRundeRetting`.
    mutating func step(_ delta: Int) {
        strokes = StrokeInput.clamp(strokes + delta)
    }

    /// «Lagre 5 på hull 2», eller «Lagre rettingen» når ingenting er endret.
    func buttonTitle(_ game: RoundGame) -> String {
        isChanged ? "Lagre \(strokes) på hull \(game.holeNumber(holeIndex))" : "Lagre rettingen"
    }

    /// «Står nå: 6 slag.» / «Ikke lagret.»
    var currentText: String {
        original.map { "Står nå: \($0) slag." } ?? "Ikke lagret."
    }

    /// Poeng og scorenavn for det nye tallet.
    func outcome(_ game: RoundGame) -> (name: ScoreName, points: Int) {
        let hole = game.holes[holeIndex]
        let hcp = game.handicap(memberID)
        return (Scoring.scoreName(par: hole.par, gross: strokes, handicap: hcp, strokeIndex: hole.strokeIndex,
                                  holes: game.holeCount),
                Scoring.points(par: hole.par, gross: strokes, handicap: hcp, strokeIndex: hole.strokeIndex,
                               holes: game.holeCount, rules: game.rules))
    }

    /// Innsendingen for denne ene spilleren. Nil når ingenting er endret.
    func submission(roundID: UUID, recordedAt: Date) -> HoleSubmission? {
        guard isChanged else { return nil }
        return HoleSubmission(roundID: roundID, holeIndex: holeIndex,
                              entries: [.init(memberID: memberID, strokes: strokes)], recordedAt: recordedAt)
    }

    /// «Hull 2 for Bjørn er rettet fra 6 til 5.»
    func doneText(_ game: RoundGame) -> String {
        "Hull \(game.holeNumber(holeIndex)) for \(game.name(memberID)) er rettet "
            + (original.map { "fra \($0) " } ?? "") + "til \(strokes)."
    }
}

/// Teksten i låst runde (`renderRundeRetting`).
nonisolated enum CorrectionNotice {
    static func text(for status: RoundStatus) -> String? {
        status == .locked
            ? "Runden er låst. Rettingen regner poengene om, og tavla og matchene følger med."
            : nil
    }
}
