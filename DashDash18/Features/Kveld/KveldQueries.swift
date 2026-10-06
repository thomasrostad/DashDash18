import Foundation
import GolfgutuCore

/// Felles for spørringene mot troppen fra Kveld og terminlista.
nonisolated enum KveldQueries {
    /// Kolonnene `ClubMemberRow` leser.
    static let memberColumns =
        "id, club_id, user_id, display_name, handicap_index, seed_group, is_organizer, is_treasurer, status, avatar_path"

    /// Troppen sortert på navn, norsk (æ, ø, å etter z).
    static func sortedByName(_ members: [ClubMemberRow]) -> [ClubMemberRow] {
        members.sorted { NorwegianSort.areInIncreasingOrder($0.displayName, $1.displayName) }
    }
}
