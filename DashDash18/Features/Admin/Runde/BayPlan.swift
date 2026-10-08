import Foundation

/// Én spiller i båsoppsettet.
nonisolated struct BaySeat: Equatable, Sendable {
    let memberID: UUID
    var bay: Int
    var isMarker: Bool
}

/// Båsene i en runde: hvem sitter hvor, og hvem er markør.
///
/// Rekkefølgen på setene er den spillerne ble lagt inn i, som nøkkelrekkefølgen i PWA-ens
/// båskart. Den avgjør hvem som blir ny markør når markøren flyttes ut (`kartFlytt`).
nonisolated struct BayPlan: Equatable, Sendable {
    private(set) var seats: [BaySeat]

    init(seats: [BaySeat] = []) {
        self.seats = seats
    }

    func seat(for memberID: UUID) -> BaySeat? {
        seats.first { $0.memberID == memberID }
    }

    /// Båsnumrene som er i bruk, stigende.
    var bayNumbers: [Int] {
        Array(Set(seats.map(\.bay))).sorted()
    }

    /// Høyeste båsnummer (antall båser slik PWA-en teller dem). 0 uten båser.
    /// Flest båser databasen tar imot (`round_players.bay_no between 1 and 12`, sql/001).
    static let maxBays = 12

    var bayCount: Int {
        seats.map(\.bay).max() ?? 0
    }

    func members(in bay: Int) -> [UUID] {
        seats.filter { $0.bay == bay }.map(\.memberID)
    }

    func marker(in bay: Int) -> UUID? {
        seats.first { $0.bay == bay && $0.isMarker }?.memberID
    }

    /// Båser som har spillere, men ingen markør.
    var baysWithoutMarker: [Int] {
        bayNumbers.filter { marker(in: $0) == nil }
    }

    /// Antall spillere per bås.
    var counts: [Int: Int] {
        Dictionary(grouping: seats, by: \.bay).mapValues(\.count)
    }

    // MARK: Forslaget

    /// Så få båser som rommer alle, med regelsettets største antall per bås. Minst én.
    static func defaultBayCount(players: Int, maxPerBay: Int) -> Int {
        let perBay = max(1, maxPerBay)
        return max(1, (players + perBay - 1) / perBay)
    }

    /// `foreslaatteBaaser`: de som er med, fordelt på `bays` båser. Hver match er en gruppe som
    /// holdes samlet (duellpartnere i samme bås), resten står alene. Gruppene legges i båsen med
    /// færrest (ved likt den laveste), og den første i en tom bås blir markør.
    /// - Parameters:
    ///   - participants: de som er med, i den rekkefølgen de skal stå.
    ///   - matchGroups: spillerne i hver match. Spillere som ikke er med, eller som alt står i en gruppe, hoppes over.
    static func suggested(participants: [UUID], matchGroups: [[UUID]] = [], bays: Int) -> BayPlan {
        let count = max(1, bays)
        let included = Set(participants)
        var placed = Set<UUID>()
        var groups: [[UUID]] = []
        for match in matchGroups {
            let group = match.filter { included.contains($0) && placed.insert($0).inserted }
            if !group.isEmpty { groups.append(group) }
        }
        for id in participants where placed.insert(id).inserted {
            groups.append([id])
        }

        var filled = Array(repeating: 0, count: count)
        var seats: [BaySeat] = []
        for group in groups {
            var fewest = 0
            for bay in 1..<count where filled[bay] < filled[fewest] { fewest = bay }
            for (i, id) in group.enumerated() {
                seats.append(BaySeat(memberID: id, bay: fewest + 1, isMarker: filled[fewest] == 0 && i == 0))
            }
            filled[fewest] += group.count
        }
        return BayPlan(seats: seats)
    }

    // MARK: Endringer

    /// `kartFlytt`: flytt spilleren til en bås (`nil` = ut av båsene). En markør som flyttes,
    /// tar markørrollen med seg hvis den nye båsen ikke har en, og båsen han forlot får den
    /// første som er igjen som ny markør.
    mutating func move(_ memberID: UUID, to bay: Int?) {
        let index = seats.firstIndex { $0.memberID == memberID }
        let from = index.map { seats[$0].bay }
        let wasMarker = index.map { seats[$0].isMarker } ?? false

        if let bay {
            let seat = BaySeat(memberID: memberID, bay: bay, isMarker: false)
            if let index { seats[index] = seat } else { seats.append(seat) }
            let hasMarker = seats.contains { $0.bay == bay && $0.isMarker }
            if wasMarker && !hasMarker, let i = seats.firstIndex(where: { $0.memberID == memberID }) {
                seats[i].isMarker = true
            }
        } else if let index {
            seats.remove(at: index)
        }

        if wasMarker, let from, from != bay {
            let left = seats.indices.filter { seats[$0].bay == from }
            if let first = left.first, !left.contains(where: { seats[$0].isMarker }) {
                seats[first].isMarker = true
            }
        }
    }

    /// `kartMarkor`: gjør spilleren til markør i sin bås. De andre i båsen er ikke markør lenger.
    mutating func makeMarker(_ memberID: UUID) {
        guard let bay = seat(for: memberID)?.bay else { return }
        for i in seats.indices where seats[i].bay == bay {
            seats[i].isMarker = seats[i].memberID == memberID
        }
    }

    /// `baasInn`: legg spilleren i båsen med færrest (ved likt den laveste). Uten båser: bås 1, som markør.
    mutating func add(_ memberID: UUID) {
        guard seat(for: memberID) == nil else { return }
        let counts = self.counts
        guard let bay = counts.keys.sorted(by: { (counts[$0]!, $0) < (counts[$1]!, $1) }).first else {
            seats.append(BaySeat(memberID: memberID, bay: 1, isMarker: true))
            return
        }
        seats.append(BaySeat(memberID: memberID, bay: bay, isMarker: false))
    }

    /// Tar ut alle som ikke er med lenger, med samme markørregel som `move(_:to: nil)`.
    mutating func keepOnly(_ participants: Set<UUID>) {
        for id in seats.map(\.memberID) where !participants.contains(id) {
            move(id, to: nil)
        }
    }
}
