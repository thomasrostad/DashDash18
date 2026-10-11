import Foundation

/// Playoff om førsteplassen i sesongtabellen (steg 6, `table.tieRule = playoff`).
///
/// Playoffen er en egen kort runde (`rounds.kind = playoff` i databasen) der arrangøren velger hullene
/// og rekkefølgen når den starter (forslag: siste hull, første hull, siste hull igjen). Sudden death:
/// hullene spilles i rekkefølge, laveste score vinner hullet, de som ikke har beste score er ute, og
/// første hull med én beste avgjør.
///
/// Netto eller brutto følger konkurransens handicapmodell, slik den står på playoff-runden: scoren er
/// netto med spillerens handicap i runden (`Handicap.effective`, med rundens andel, frosne
/// spillehandicap og seeding) og slagene på hullet etter stroke index, som i en vanlig runde. En
/// bruttokonkurranse (andel 0) og simulatoren som deler ut slagene (`hcpExtern`) gir 0 slag, altså
/// brutto. Runden bør ha samme antall hull som turneringens runder (18), så slagene på hullet blir de
/// samme som spilleren får der.
public enum Playoff {
    /// Stillingen i playoffen.
    public enum Decision: Hashable, Sendable {
        /// Avgjort: `winner` vant på playoff-hull nummer `position` (0-basert, i rekkefølgen de spilles).
        case won(winner: String, position: Int)
        /// Ikke avgjort. `remaining` er de som fortsatt er med (i rekkefølgen inn). `next` er
        /// posisjonen som venter på score; `nil` når alle de valgte hullene er spilt og det fortsatt står
        /// likt (arrangøren legger til hull).
        case pending(remaining: [String], next: Int?)
    }

    /// Forslaget til hull: siste, første, siste igjen (rundens 0-baserte hullindekser).
    public static func suggestedHoles(_ round: Round) -> [Int] {
        let last = round.numberOfHoles - 1
        return [last, 0, last]
    }

    /// Avgjør playoffen.
    /// - Parameters:
    ///   - players: de som står likt øverst, i tabellens rekkefølge.
    ///   - holes: rundens 0-baserte hullindekser i rekkefølgen de spilles. Samme hull kan stå flere ganger.
    ///   - scores: bruttoslag per spiller, i samme rekkefølge som `holes` (posisjon → slag).
    ///   - round: playoff-runden (bane, antall hull, andel, frosne handicap).
    public static func decide(players: [String], holes: [Int], scores: [String: [Int]], round: Round,
                              roster: [Player], rules: Ruleset = .golfgutu) -> Decision {
        var remaining = players
        guard remaining.count > 1 else {
            return remaining.first.map { .won(winner: $0, position: 0) } ?? .pending(remaining: [], next: nil)
        }
        let course = round.courseHoles()
        let count = round.numberOfHoles
        let handicap = Dictionary(uniqueKeysWithValues: Set(players).map { id in
            (id, Handicap.effective(for: roster.first { $0.id == id } ?? Player(id: id), in: round, roster: roster, rules: rules))
        })
        for (position, hole) in holes.enumerated() {
            guard course.indices.contains(hole) else { return .pending(remaining: remaining, next: position) }
            var net: [String: Int] = [:]
            for id in remaining {
                guard let strokes = scores[id], position < strokes.count else {
                    return .pending(remaining: remaining, next: position)
                }
                net[id] = Scoring.netStrokes(gross: strokes[position], handicap: handicap[id] ?? 0,
                                             strokeIndex: course[hole].strokeIndex, holes: count)
            }
            let best = net.values.min()!
            remaining = remaining.filter { net[$0] == best }
            if remaining.count == 1 { return .won(winner: remaining[0], position: position) }
        }
        return .pending(remaining: remaining, next: nil)
    }
}

// MARK: - Skjul de siste hullene

extension Round {
    /// Hullene som skjules nå (rundens 0-baserte indekser): de siste `hideLastHoles` av hullene som
    /// spilles, så lenge runden ikke er låst. Tom når runden er låst eller valget er av.
    public var hiddenHoleIndices: Range<Int> {
        let n = numberOfHoles
        let hidden = min(max(0, hideLastHoles), n)
        guard !locked, hidden > 0 else { return n..<n }
        return (n - hidden)..<n
    }

    /// Runden slik den vises for andre mens den pågår («skjul de tre siste hullene»): scorene på de
    /// skjulte hullene er fjernet, så tavla og tabellen regnes uten dem (et hull uten score gir det
    /// avkortingsregelen sier, til vanlig 0). Når runden er låst, er alt synlig.
    ///
    /// Hvem ser hva (appen bestemmer, motoren gir funksjonen): `revealedTo` er spillerne som vises med
    /// alle hullene. Markøren i en bås skal se hullene hun fører, så appen sender med spillerne i båsen
    /// (eller laget) til den som ser på. Arrangøren kan få alle. Alle andre ser rundens tavle uten de
    /// skjulte hullene.
    public func hidingLastHoles(revealedTo: Set<String> = []) -> Round {
        let hidden = hiddenHoleIndices
        guard !hidden.isEmpty else { return self }
        var r = self
        for (id, scores) in holeScores where !revealedTo.contains(id) {
            r.holeScores[id] = scores.filter { !hidden.contains($0.key) }
        }
        return r
    }
}
