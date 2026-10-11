import Foundation

/// Trekningsvalgene for matcher og lag (steg 6, `formats.drawMethod`).
///
/// - Etter tabellen: `Triangle.drawMatches` (Golfgutu, som PWA-en).
/// - Uten gjentakelser: `avoidingRepeats`. Gjentakbar med et frø, så en annen plattform kan gjenskape den.
/// - Manuelt: arrangøren setter opp matchene; `validate` sjekker oppsettet.
///
/// Gruppene er som i `Triangle.drawMatches`: par, og én trekant (tre) når antallet er oddetall.
public enum Draw {
    /// Nøkkelen for et møte mellom to spillere: id-ene sortert, med «|» mellom.
    public static func pairKey(_ a: String, _ b: String) -> String {
        a < b ? "\(a)|\(b)" : "\(b)|\(a)"
    }

    /// Hvor mange ganger hvert par har møtt hverandre i rundenes matcher (motstandere; i en trekant møter
    /// alle tre hverandre). Alle rundene teller med, også de som ikke teller i tabellen.
    public static func meetings(in rounds: [Round]) -> [String: Int] {
        var out: [String: Int] = [:]
        for round in rounds {
            for m in round.matches {
                let s = MatchPlay.sides(of: m, in: round)
                if m.isTriangle {
                    addMeetings([s.all], to: &out)
                    continue
                }
                for a in s.a { for b in s.b where a != b { out[pairKey(a, b), default: 0] += 1 } }
            }
        }
        return out
    }

    /// Legger gruppenes møter til (alle i en gruppe møter hverandre).
    public static func addMeetings(_ groups: [[String]], to meetings: inout [String: Int]) {
        for g in groups {
            for i in g.indices { for j in g.indices where j > i { meetings[pairKey(g[i], g[j]), default: 0] += 1 } }
        }
    }

    /// Antall møter i gruppene som har vært før (summen over alle par i gruppene).
    public static func repeats(_ groups: [[String]], previous: [String: Int]) -> Int {
        groups.reduce(0) { $0 + cost($1, previous) }
    }

    static func cost(_ group: [String], _ previous: [String: Int]) -> Int {
        var c = 0
        for i in group.indices { for j in group.indices where j > i { c += previous[pairKey(group[i], group[j])] ?? 0 } }
        return c
    }

    /// Id-ene sortert, så stokket med Fisher–Yates bakfra og SplitMix64 (som cupens trekning).
    static func shuffled(_ ids: [String], seed: UInt64) -> [String] {
        var ids = ids.sorted()
        var rng = SplitMix64(seed: seed)
        if ids.count > 1 {
            for i in stride(from: ids.count - 1, through: 1, by: -1) {
                ids.swapAt(i, Int(rng.next() % UInt64(i + 1)))
            }
        }
        return ids
    }

    /// Tilfeldig trekning med færrest mulig møter som har vært før (`previous`, fra `meetings(in:)`).
    ///
    /// 1. Deltakerne stokkes med frøet (`shuffled`).
    /// 2. Grådig: den første uten motstander får den av de ledige (i stokket rekkefølge) den har møtt
    ///    færrest ganger. Med oddetall blir de tre siste en trekant.
    /// 3. Forbedring: to spillere i ulike grupper bytter plass når det gir færre gjentakelser, til ingen
    ///    bytte hjelper (gruppene og spillerne i rekkefølge, første bytte som hjelper tas).
    /// Under to deltakere: ingen matcher.
    public static func avoidingRepeats(_ participants: [Player], previous: [String: Int], seed: UInt64) -> [[String]] {
        let order = shuffled(participants.map(\.id), seed: seed)
        guard order.count >= 2 else { return [] }
        var free = order
        var groups: [[String]] = []
        while !free.isEmpty {
            if free.count == 3 && order.count % 2 == 1 {
                groups.append(free)
                break
            }
            let x = free.removeFirst()
            var best = 0
            for k in free.indices where (previous[pairKey(x, free[k])] ?? 0) < (previous[pairKey(x, free[best])] ?? 0) {
                best = k
            }
            groups.append([x, free.remove(at: best)])
        }
        var improved = true
        while improved {
            improved = false
            for g1 in groups.indices {
                for g2 in groups.indices where g2 > g1 {
                    for i in groups[g1].indices {
                        for j in groups[g2].indices {
                            var a = groups[g1], b = groups[g2]
                            swap(&a[i], &b[j])
                            if cost(a, previous) + cost(b, previous) < cost(groups[g1], previous) + cost(groups[g2], previous) {
                                groups[g1] = a
                                groups[g2] = b
                                improved = true
                            }
                        }
                    }
                }
            }
        }
        return groups
    }

    /// Sjekker en manuell trekning: hver deltaker nøyaktig én gang, bare deltakere, grupper på to eller
    /// tre, og én trekant bare når antallet er oddetall. Tom liste: i orden. Rekkefølgen: per gruppe
    /// (størrelse, ukjent, dobbel), så de som mangler (i deltakerrekkefølge), så antall trekanter.
    public static func validate(groups: [[String]], participants: [String]) -> [DrawIssue] {
        var issues: [DrawIssue] = []
        let known = Set(participants)
        var seen = Set<String>(), reported = Set<String>()
        for (i, g) in groups.enumerated() {
            if g.count != 2 && g.count != 3 { issues.append(.groupSize(index: i, size: g.count)) }
            for id in g {
                if !known.contains(id) {
                    if reported.insert(id).inserted { issues.append(.unknownPlayer(id)) }
                } else if !seen.insert(id).inserted, reported.insert(id).inserted {
                    issues.append(.duplicate(id))
                }
            }
        }
        for id in participants where !seen.contains(id) { issues.append(.missing(id)) }
        let triangles = groups.filter { $0.count == 3 }.count
        if triangles != participants.count % 2 { issues.append(.triangles(count: triangles)) }
        return issues
    }
}

/// Et problem i en manuell trekning, med norsk melding til arrangøren.
public enum DrawIssue: Hashable, Sendable {
    case unknownPlayer(String)
    case duplicate(String)
    case missing(String)
    /// Gruppe nummer `index` (0-basert) har `size` spillere, ikke to eller tre.
    case groupSize(index: Int, size: Int)
    /// Feil antall trekanter: én bare med oddetall spillere.
    case triangles(count: Int)

    /// Språknøytral kode (fixturene): `ukjent:X`, `dobbel:X`, `mangler:X`, `gruppe:i:n`, `trekanter:n`.
    public var code: String {
        switch self {
        case .unknownPlayer(let id): "ukjent:\(id)"
        case .duplicate(let id): "dobbel:\(id)"
        case .missing(let id): "mangler:\(id)"
        case .groupSize(let i, let n): "gruppe:\(i):\(n)"
        case .triangles(let n): "trekanter:\(n)"
        }
    }

    public var message: String {
        switch self {
        case .unknownPlayer(let id): "\(id) er ikke med denne kvelden."
        case .duplicate(let id): "\(id) står i mer enn én match."
        case .missing(let id): "\(id) har ingen match."
        case .groupSize(let i, let n): "Match \(i + 1) har \(n) spillere. En match har to, en trekant tre."
        case .triangles(let n):
            n == 0 ? "Med oddetall spillere må én match være en trekant."
                : "Det kan bare være én trekant, og bare med oddetall spillere (nå \(n))."
        }
    }
}

/// Tilfeldige lag og bytte av to spillere (steg 6).
public enum Teams {
    /// Lag med `teamSize` spillere: id-ene stokkes med frøet (som `Draw.shuffled`) og fylles i lag 1, 2, …
    /// Går det ikke opp, blir det siste laget mindre. Svaret er spiller-id → lagnummer (`round_teams`).
    public static func random(_ playerIDs: [String], teamSize: Int, seed: UInt64) -> [String: Int] {
        let size = max(1, teamSize)
        var out: [String: Int] = [:]
        for (i, id) in Draw.shuffled(playerIDs, seed: seed).enumerated() { out[id] = i / size + 1 }
        return out
    }

    /// Bytter lagene til to spillere. Uendret når en av dem ikke har lag, eller de er på samme lag.
    public static func swap(_ teams: [String: Int], _ a: String, _ b: String) -> [String: Int] {
        guard let ta = teams[a], let tb = teams[b], ta != tb else { return teams }
        var out = teams
        out[a] = tb
        out[b] = ta
        return out
    }
}
