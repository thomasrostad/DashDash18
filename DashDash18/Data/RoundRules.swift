import Foundation
import GolfgutuCore
import Supabase
import Synchronization

/// Tabellreglene på runden og playoff-runden (sql/047, gjennomføringsplanen steg 6).
///
/// Før 047 er kjørt finnes ikke kolonnene, og en `select` med dem feiler. Appen spør derfor én gang
/// per innlogging om kolonnene finnes (`detect`) og husker svaret til neste oppstart. Uten dem gjelder
/// standardverdiene: runden teller, ingen poengtabell, ingen skjulte hull og ingen playoff.
nonisolated enum RoundRulesFeature {
    private static let key = "roundRules047"
    private static let state = Mutex<Bool>(UserDefaults.standard.bool(forKey: key))

    /// Kolonnene fra 047 finnes (sist appen sjekket).
    static var isAvailable: Bool { state.withLock { $0 } }

    /// For tester og for `detect`.
    static func set(_ available: Bool) {
        state.withLock { $0 = available }
        UserDefaults.standard.set(available, forKey: key)
    }

    /// Spør databasen om kolonnene finnes. En annen feil (nettet borte) endrer ingenting.
    static func detect(client: SupabaseClient) async {
        do {
            _ = try await client.from("rounds").select("kind").limit(1).execute()
            set(true)
        } catch let error as PostgrestError where EveningSignupService.isMissing(error) {
            set(false)
        } catch {
            // Behold det vi visste.
        }
    }
}

// MARK: - Runden

nonisolated extension RoundRow {
    /// `rounds.kind = playoff`: en kort runde som avgjør førsteplassen. Teller aldri og står ikke
    /// blant de vanlige rundene (Tavla, statistikk, tips, spill, «Mine runder»).
    var isPlayoff: Bool { kind == "playoff" }

    /// Runden teller i tabellen (`Round.counts`). Standard: ja.
    var countsInTable: Bool { counts ?? true }

    /// Antall hull på slutten som skjules for andre til runden er låst (`Round.hideLastHoles`).
    var hiddenLastHoles: Int { max(0, hideLastHoles ?? 0) }
}

nonisolated extension Array where Element == RoundRow {
    /// Bare de vanlige rundene (uten playoff).
    var ordinary: [RoundRow] { filter { !$0.isPlayoff } }
}

nonisolated extension Array where Element == RoundSnapshot {
    /// Bare de vanlige rundene (uten playoff).
    var ordinary: [RoundSnapshot] { filter { !$0.round.isPlayoff } }
}

// MARK: - Skjul de siste hullene

/// «Skjul de tre siste hullene» (`rounds.hide_last_holes`): mens runden går, ser bare spillerne i din
/// egen bås (eller du selv uten bås) og arrangøren med rettigheten `rounds` scorene på de siste
/// hullene. Alle andre ser runden uten dem, til runden er låst. Motoren gir funksjonen
/// (`Round.hidingLastHoles(revealedTo:)`); her bestemmes hvem som ser hva.
nonisolated enum HiddenHoles {
    static let note = "De siste hullene vises når runden er låst"

    /// Spillerne `viewer` ser alle hullene til. nil: alle (arrangøren).
    static func revealed(in snapshot: RoundSnapshot, viewer: Viewer) -> Set<UUID>? {
        if viewer.isOrganizer { return nil }
        let me = viewer.memberID
        guard let mine = snapshot.players.first(where: { $0.memberID == me }) else { return [] }
        guard let bay = mine.bayNo, bay >= 1 else { return [me] }
        return Set(snapshot.players.filter { $0.bayNo == bay }.map(\.memberID))
    }

    /// Runden slik `viewer` skal se den: scorene på de skjulte hullene er borte for spillere utenfor
    /// båsen din. Uendret når runden er låst, valget er av, eller du er arrangør.
    static func apply(_ snapshot: RoundSnapshot, viewer: Viewer?) -> RoundSnapshot {
        guard let viewer, snapshot.round.hiddenLastHoles > 0, snapshot.round.status != .locked,
              let revealed = revealed(in: snapshot, viewer: viewer) else { return snapshot }
        let round = RoundGame.makeRound(snapshot).hidingLastHoles(revealedTo: Set(revealed.map(\.uuidString)))
        var out = snapshot
        out.scores = snapshot.scores.filter { round.holeScores[$0.memberID.uuidString]?[$0.holeIndex] != nil }
        return out
    }

    /// Skal skjermen si at de siste hullene er skjult for `viewer`?
    static func isHiding(_ snapshot: RoundSnapshot, viewer: Viewer?) -> Bool {
        guard let viewer, snapshot.round.hiddenLastHoles > 0, snapshot.round.status == .active else { return false }
        return revealed(in: snapshot, viewer: viewer) != nil
    }
}

// MARK: - Oppsettet

/// Valgene for poengtabellen i runde-oppsettet (`table.pointsTables`).
nonisolated enum RoundTableRules {
    /// Navnene i regelsettet, sortert (norsk).
    static func tableNames(_ rules: Ruleset) -> [String] {
        rules.table.pointsTables.keys.sorted { NorwegianSort.areInIncreasingOrder($0, $1) }
    }

    /// Valgene: regelsettets tabeller, og den lagrede når den ikke lenger finnes (så den ikke forsvinner).
    static func choices(_ names: [String], current: String?) -> [String] {
        guard let current, !names.contains(current) else { return names }
        return names + [current]
    }

    /// «Finale (× 2)», eller bare navnet når tabellen ikke finnes.
    static func title(_ name: String, rules: Ruleset) -> String {
        let label = name.prefix(1).uppercased() + name.dropFirst()
        guard let m = rules.table.pointsTables[name]?.multiplier else { return label }
        let factor = m == m.rounded() ? String(Int(m)) : String(m).replacingOccurrences(of: ".", with: ",")
        return "\(label) (× \(factor))"
    }
}
