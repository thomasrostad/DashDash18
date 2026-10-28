import Foundation

/// Meldingene mellom Atten og Garmin-appen (`garmin/source/PhoneLink.mc` og `AttenModel.mc`).
/// Garmin får ett hull om gangen fra den samme `WatchRound` som Apple Watch, så klokkene kan ikke
/// regne annerledes enn telefonen. Connect IQ tar ordbøker, lister, tekst og tall.
nonisolated enum GarminMessage {
    /// Ingen runde: Garmin viser «Ingen runde nå».
    static var none: [String: Any] { ["t": "none"] }

    /// Hullet slik Garmin-appen leser det: radene med teksten for hvert slagantall, og «Bayen nå».
    static func hole(_ round: WatchRound, index: Int) -> [String: Any]? {
        guard let hole = round.holes.first(where: { $0.index == index }) else { return nil }
        var message: [String: Any] = [
            "t": "hole", "r": round.roundID.uuidString, "h": hole.index, "n": hole.number,
            "p": hole.par, "c": round.holes.count,
            "rows": hole.rows.map(row),
            "st": round.standings.map { s in
                [s.place.map { "\($0)." } ?? "–", s.name, s.value, s.isMe ? "1" : "0"]
            },
        ]
        if let strokeIndex = hole.strokeIndex { message["i"] = strokeIndex }
        return message
    }

    private static func row(_ row: WatchRound.Row) -> [String: Any] {
        var out: [String: Any] = [
            "m": row.memberID.uuidString, "nm": row.name, "me": row.isMe, "e": row.editable,
            "v": row.value, "rc": row.strokesReceived,
            "lo": row.options.first?.strokes ?? row.value,
            "tx": row.options.map { $0.text ?? "" },
            "tn": row.options.map { $0.tone ?? "" },
        ]
        if let saved = row.saved { out["s"] = saved }
        return out
    }

    /// Det Garmin-appen ber om.
    enum Incoming: Equatable, Sendable {
        /// Appen er startet: send hullet som gjelder.
        case hello
        /// «Forrige hull» og «Neste hull».
        case get(roundID: UUID, hole: Int)
        /// Hullet er ført: i utboksen med det.
        case save(WatchHoleEntry)
    }

    /// Tolker en melding fra Garmin-appen. `now` blir tastetiden, siden klokka ikke sender den.
    static func incoming(_ message: Any, now: Date) -> Incoming? {
        guard let d = message as? [String: Any], let type = d["t"] as? String else { return nil }
        switch type {
        case "hello":
            return .hello
        case "get":
            guard let round = (d["r"] as? String).flatMap(UUID.init(uuidString:)), let hole = int(d["h"]) else { return nil }
            return .get(roundID: round, hole: hole)
        case "save":
            guard let round = (d["r"] as? String).flatMap(UUID.init(uuidString:)), let hole = int(d["h"]),
                  let list = d["sc"] as? [Any] else { return nil }
            let scores = list.compactMap { item -> WatchHoleEntry.Score? in
                guard let pair = item as? [Any], pair.count == 2,
                      let member = (pair[0] as? String).flatMap(UUID.init(uuidString:)),
                      let strokes = int(pair[1]) else { return nil }
                return WatchHoleEntry.Score(memberID: member, strokes: strokes)
            }
            guard !scores.isEmpty else { return nil }
            return .save(WatchHoleEntry(roundID: round, holeIndex: hole, scores: scores, recordedAt: now))
        default:
            return nil
        }
    }

    /// Connect IQ sender tall som `NSNumber` (Int eller Int64).
    private static func int(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue ?? (value as? Int)
    }
}
