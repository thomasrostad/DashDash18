import Foundation

// DELT FIL: må være medlem av både DashDash18 og Atten Watch App (se docs/plan-apple-watch.md).
// Bare Foundation her, ingen typer fra appen.

/// Runden slik klokka viser den. Telefonen regner alt (`RoundGame`: hullkortet og «Bayen nå») og
/// sender det ferdig, så klokka ikke kan regne annerledes enn telefonen. Klokka viser og sender slag.
nonisolated struct WatchRound: Codable, Equatable, Sendable {
    /// Det hullet teller med `strokes` slag, slik hullkortet på telefonen viser det.
    struct Option: Codable, Equatable, Sendable {
        let strokes: Int
        /// «2 p · netto par», «brutto bogey», «tak 6 slag». Nil: ingen tekst.
        let text: String?
        /// Scorefargen som `ScoreName.rawValue` («birdie»). Nil: ingen farge.
        let tone: String?
    }

    struct Row: Codable, Equatable, Identifiable, Sendable {
        let memberID: UUID
        let name: String
        let isMe: Bool
        /// Klokka kan føre for spilleren: deg selv, eller båsen når du er markør.
        let editable: Bool
        /// Lagret på serveren, eller i kø på telefonen.
        let saved: Int?
        /// Tallet som står: det lagrede, ellers par (forvalget).
        let value: Int
        let strokesReceived: Int
        /// Tekst og farge for hvert slagantall stepperen kan stå på, fra 1 til taket. Raden klokka
        /// ikke kan føre, har bare tallet som står.
        let options: [Option]

        var id: UUID { memberID }

        func option(_ strokes: Int) -> Option? {
            options.first { $0.strokes == strokes }
        }

        /// Stepperen: aldri under det minste eller over taket (`play.maxStrokes`).
        func clamp(_ strokes: Int) -> Int {
            guard let low = options.first?.strokes, let high = options.last?.strokes else { return value }
            return min(high, max(low, strokes))
        }
    }

    struct Hole: Codable, Equatable, Identifiable, Sendable {
        /// Rundens 0-baserte hull.
        let index: Int
        /// Banens nummer på hullet.
        let number: Int
        let par: Int
        /// Indeksen på scorekortet, eller nil med eksternt handicap.
        let strokeIndex: Int?
        let rows: [Row]

        var id: Int { index }
        /// Alle radene klokka fører for, er lagret.
        var isSaved: Bool { rows.filter(\.editable).allSatisfy { $0.saved != nil } }
    }

    /// Én rad i «Bayen nå», for båsen din.
    struct Standing: Codable, Equatable, Identifiable, Sendable {
        let memberID: UUID
        /// Nil når runden avgjøres hull for hull (match).
        let place: Int?
        let name: String
        let isMe: Bool
        /// Hull spilt.
        let thru: Int
        /// «24 p», «72 slag», «+2», «1 opp».
        let value: String

        var id: UUID { memberID }
    }

    let roundID: UUID
    /// Banen, eller «Kvelden» uten bane.
    let title: String
    /// Hullet båsen står på.
    let currentHole: Int
    let holes: [Hole]
    let standings: [Standing]
    /// Når telefonen laget runden. Klokka glemmer et sendt hull når en nyere runde har kommet.
    let updatedAt: Date
}

/// Ett hull ført på klokka. Telefonen gjør det om til en `HoleSubmission` og legger det i utboksen,
/// som hullkortet gjør.
nonisolated struct WatchHoleEntry: Codable, Equatable, Sendable {
    struct Score: Codable, Equatable, Sendable {
        let memberID: UUID
        let strokes: Int
    }

    let roundID: UUID
    /// Rundens 0-baserte hull.
    let holeIndex: Int
    let scores: [Score]
    /// Når hullet ble tastet på klokka.
    let recordedAt: Date
}

/// Et hull klokka har sendt. Det står på klokka til telefonen har fått det og sendt en nyere runde.
nonisolated struct WatchOutgoing: Codable, Equatable, Sendable {
    var entry: WatchHoleEntry
    /// Når telefonen tok imot hullet. Nil: ligger fortsatt i køen på klokka.
    var deliveredAt: Date?
}

nonisolated extension WatchRound {
    /// Hullene som fortsatt skal stå på klokka med `round`: de som ikke er levert, og de som er levert
    /// etter at runden ble laget. Hull fra en annen runde glemmes.
    static func keeping(_ outgoing: [WatchOutgoing], round: WatchRound?) -> [WatchOutgoing] {
        guard let round else { return outgoing }
        return outgoing.filter { item in
            guard item.entry.roundID == round.roundID else { return false }
            guard let delivered = item.deliveredAt else { return true }
            return delivered >= round.updatedAt
        }
    }

    /// Tallet som står for spilleren på hullet: det klokka har sendt og telefonen ikke har bekreftet
    /// (nyeste først), ellers rundens.
    func value(hole: Int, member: UUID, outgoing: [WatchOutgoing]) -> Int? {
        let sent = outgoing
            .filter { $0.entry.roundID == roundID && $0.entry.holeIndex == hole }
            .max { $0.entry.recordedAt < $1.entry.recordedAt }?
            .entry.scores.first { $0.memberID == member }?.strokes
        return sent ?? holes.first { $0.index == hole }?.rows.first { $0.memberID == member }?.value
    }
}

/// Meldingene mellom telefonen og klokka (WatchConnectivity): JSON, komprimert, under én nøkkel.
nonisolated enum WatchMessage {
    /// Runden, som application context fra telefonen. Mangler den: ingen runde.
    static let round = "round"
    /// Et hull fra klokka, som user info.
    static let hole = "hole"

    static func payload<T: Encodable>(_ value: T, key: String) -> [String: Any]? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        guard let json = try? encoder.encode(value),
              let packed = try? (json as NSData).compressed(using: .lzfse) else { return nil }
        return [key: packed as Data]
    }

    static func value<T: Decodable>(_ type: T.Type, key: String, in payload: [String: Any]) -> T? {
        guard let packed = payload[key] as? Data,
              let json = try? (packed as NSData).decompressed(using: .lzfse) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try? decoder.decode(type, from: json as Data)
    }
}
