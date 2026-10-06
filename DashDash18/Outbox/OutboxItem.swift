import Foundation
import SwiftData

/// Ett hull som venter i utboksen. Lagres FØR det sendes, så det overlever at appen
/// blir drept. Slettes når serveren har bekreftet det.
@Model
final class OutboxItem {
    enum State: String, Codable {
        /// Venter på å bli sendt (eller er på vei).
        case pending
        /// Serveren sa nei (tilgang eller ugyldig). Beholdes for visning, sendes ikke på nytt.
        case rejected
    }

    @Attribute(.unique) var id: UUID
    var roundID: UUID
    var holeIndex: Int
    /// `[HoleSubmission.Entry]` som JSON. Spillere kan fjernes av en nyere innsending.
    var entriesData: Data
    var recordedAt: Date
    var attempts: Int
    var lastAttemptAt: Date?
    var lastError: String?
    var stateRaw: String
    var createdAt: Date
    /// Hvem som tastet hullet. Køen sendes bare når den samme er innlogget, så hull
    /// ikke sendes (og avvises) i en annens navn. Nil = fra før feltet fantes.
    var userID: UUID?

    init(submission: HoleSubmission, createdAt: Date, userID: UUID? = nil) throws {
        id = UUID()
        self.userID = userID
        roundID = submission.roundID
        holeIndex = submission.holeIndex
        entriesData = try JSONEncoder().encode(submission.entries)
        recordedAt = submission.recordedAt
        attempts = 0
        stateRaw = State.pending.rawValue
        self.createdAt = createdAt
    }

    var state: State {
        get { State(rawValue: stateRaw) ?? .pending }
        set { stateRaw = newValue.rawValue }
    }

    var entries: [HoleSubmission.Entry] {
        get { (try? JSONDecoder().decode([HoleSubmission.Entry].self, from: entriesData)) ?? [] }
        set { entriesData = (try? JSONEncoder().encode(newValue)) ?? Data("[]".utf8) }
    }

    var submission: HoleSubmission {
        HoleSubmission(roundID: roundID, holeIndex: holeIndex, entries: entries, recordedAt: recordedAt)
    }
}
