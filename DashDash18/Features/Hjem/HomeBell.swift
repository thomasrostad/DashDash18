import Foundation

// Bjella blir «det som angår deg» (fase 19, besluttet 08.10.2026): resten står i feeden på Hjem.
// Regelen og tellingen her; UI-endringen kommer i del 2. Ren logikk.

/// Hvorfor en linje angår deg.
nonisolated enum HomeBellReason: Equatable, Sendable {
    /// «Melding til alle» fra arrangøren.
    case announcement
    /// Purret på: du står på mottakerlista (eller purringen gikk til alle).
    case nudged
    /// Utfordret i et veddemål.
    case challenged
    /// Nevnt i tråden.
    case mentioned
    /// Din bragd (eagle eller bedre).
    case myFeat
    /// Din runde er låst (eller slettet).
    case myRound
    /// Noen gikk forbi deg: i tabellen, eller på en sidepremie du ledet.
    case passed
    /// Du klatret i tabellen.
    case climbed
    /// En score din er rettet.
    case corrected
    /// Du er tippekonge.
    case tipsKing
    /// Du er trukket til sosialkomiteen.
    case committee
}

nonisolated enum HomeBell {
    /// Hvorfor linja angår deg, eller nil når den ikke gjør det. `myRounds` er rundene du spiller
    /// eller har spilt (for «din runde»).
    static func reason(_ row: ActivityRow, viewer: HomeViewer, myRounds: Set<UUID> = []) -> HomeBellReason? {
        guard let me = viewer.memberships[row.clubID] else { return nil }
        switch row.event {
        case .announcement:
            return .announcement
        case .nudge:
            guard let recipients = row.recipients else { return .nudged }
            return recipients.contains(me) ? .nudged : nil
        case let .betChallenge(_, against, _, _):
            return against == me ? .challenged : nil
        case let .bigScore(member, _, _, _, _, _):
            return member == me ? .myFeat : nil
        case .roundLocked, .roundDeleted:
            return row.roundID.map(myRounds.contains) == true ? .myRound : nil
        case let .tableChanged(_, _, _, table):
            guard let mine = table.first(where: { $0.member == me }), let move = mine.move, move != 0 else { return nil }
            return move < 0 ? .passed : .climbed
        case let .sidePrize(_, _, _, _, passed, _):
            return passed == me ? .passed : nil
        case let .scoreCorrected(member, _, _, _, _, _):
            return member == me ? .corrected : nil
        case let .tipsKing(members, _, _, _):
            return members.contains(me) ? .tipsKing : nil
        case let .committeeDrawn(_, members):
            return members.contains(me) ? .committee : nil
        default:
            return nil
        }
    }

    static func concernsMe(_ row: ActivityRow, viewer: HomeViewer, myRounds: Set<UUID> = []) -> Bool {
        reason(row, viewer: viewer, myRounds: myRounds) != nil
    }

    /// Linjene bjella viser, nyeste først.
    static func rows(_ rows: [ActivityRow], viewer: HomeViewer, myRounds: Set<UUID> = []) -> [ActivityRow] {
        rows.filter { concernsMe($0, viewer: viewer, myRounds: myRounds) }.sorted { $0.createdAt > $1.createdAt }
    }

    /// Nevnt i tråden av en annen.
    static func mentionsMe(_ message: ThreadMessageRow, viewer: HomeViewer) -> Bool {
        guard let me = viewer.memberships[message.clubID] else { return false }
        return message.memberID != me && message.mentions.contains(me)
    }

    /// Tallet på bjella: det som angår deg, er nyere enn sist sett og ikke ditt eget. Aldri sett =
    /// alt teller (som Varsler i dag).
    static func unreadCount(_ rows: [ActivityRow], mentions: [ThreadMessageRow] = [], lastSeen: Date?,
                            viewer: HomeViewer, myRounds: Set<UUID> = []) -> Int {
        let activity = rows.filter { row in
            guard concernsMe(row, viewer: viewer, myRounds: myRounds) else { return false }
            if let actor = row.actorMemberID, viewer.memberIDs.contains(actor) { return false }
            return lastSeen.map { row.createdAt > $0 } ?? true
        }.count
        let messages = mentions.filter { m in
            mentionsMe(m, viewer: viewer) && (lastSeen.map { m.createdAt > $0 } ?? true)
        }.count
        return activity + messages
    }

    /// «9+» når det er mange (som `UnreadBadge.label`).
    static func label(_ count: Int) -> String? {
        switch count {
        case 0: nil
        case 1...9: "\(count)"
        default: "9+"
        }
    }
}

/// «Sist sett» på tvers av klubbene, på denne telefonen, per innlogging. To klokker: feeden på Hjem
/// (oppsummeringen og «ulest» på kortene) og bjella. Tiden er serverens tid på det nyeste som ble
/// vist, som `ActivitySeenStore`. Første gang brukes det nyeste av de gamle klokkene per klubb, så
/// byttet ikke gjør alt ulest.
nonisolated struct HomeSeenStore: Sendable {
    enum Clock: String, Sendable {
        case feed = "hjem"
        case bell = "bjelle"
    }

    let userID: UUID
    let clock: Clock
    /// Egen suite i tester.
    var suite: String?

    init(userID: UUID, clock: Clock, suite: String? = nil) {
        self.userID = userID
        self.clock = clock
        self.suite = suite
    }

    var defaults: UserDefaults { suite.map { UserDefaults(suiteName: $0) ?? .standard } ?? .standard }
    var key: String { "\(clock.rawValue).sistSett.\(userID.uuidString.lowercased())" }

    /// Sist sett. Uten egen verdi: det nyeste fra Varsler i klubbene (`ActivitySeenStore`).
    func lastSeen(fallbackClubs clubs: [UUID] = []) -> Date? {
        let t = defaults.double(forKey: key)
        if t > 0 { return Date(timeIntervalSince1970: t) }
        return clubs.compactMap { ActivitySeenStore(clubID: $0, suite: suite).lastSeen }.max()
    }

    /// Flytter bare fram, aldri tilbake.
    func markSeen(upTo date: Date) {
        let t = defaults.double(forKey: key)
        if t > 0, t >= date.timeIntervalSince1970 { return }
        defaults.set(date.timeIntervalSince1970, forKey: key)
    }

    func clear() { defaults.removeObject(forKey: key) }
}
