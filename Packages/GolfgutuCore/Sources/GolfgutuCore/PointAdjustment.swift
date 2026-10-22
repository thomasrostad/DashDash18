import Foundation

/// Tilleggspoeng: poeng arrangøren gir en spiller for hånd, med en grunn (sql/072). For eksempel en
/// konkurranse som ble spilt utenfor appen. Legges på totalen i tabellen ved siden av sidepremiene,
/// uvektet, og strykes aldri av «beste N». Kan være negative (en straff eller en rettelse).
public struct PointAdjustment: Codable, Hashable, Sendable {
    public var id: String?
    public var playerId: String
    public var points: Double
    /// Kort grunn, vist for spillerne.
    public var reason: String
    /// Kvelden (`YYYY-MM-DD`) tillegget hører til, eller nil. Bare til visning.
    public var date: String?

    public init(id: String? = nil, playerId: String, points: Double, reason: String, date: String? = nil) {
        self.id = id
        self.playerId = playerId
        self.points = points
        self.reason = reason
        self.date = date
    }
}
