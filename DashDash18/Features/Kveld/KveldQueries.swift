import Foundation
import GolfgutuCore

/// Felles for spørringene mot troppen fra Kveld og terminlista.
nonisolated enum KveldQueries {
    /// Brukes fortsatt i Konkurranser/. Ny kode bruker `ClubMemberRow.columns`.
    static let memberColumns = ClubMemberRow.columns

    /// Troppen sortert på navn, norsk (æ, ø, å etter z).
    static func sortedByName(_ members: [ClubMemberRow]) -> [ClubMemberRow] {
        members.sorted { NorwegianSort.areInIncreasingOrder($0.displayName, $1.displayName) }
    }
}
