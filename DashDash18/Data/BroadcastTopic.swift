import Foundation

/// Sanntid via Broadcast (fase 24, `sql/040_sanntid_broadcast.sql`).
nonisolated enum BroadcastFeature {
    /// Av til 040 er kjørt. Med flagget av følger runden og Tavla med som før (postgres_changes).
    static let isEnabled = false
}

/// Kanalnavnene triggerne i 040 sender på, og hendelsen.
nonisolated enum BroadcastTopic {
    static let event = "change"
    static func round(_ id: UUID) -> String { "round:\(id.uuidString.lowercased())" }
    static func club(_ id: UUID) -> String { "club:\(id.uuidString.lowercased())" }
}
