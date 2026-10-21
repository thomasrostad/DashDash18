import Foundation
import Observation

// Trykk på en push åpner skjermen varselet handler om. Innholdet er `dd18` fra `push-send`
// (`planActivity`/`planThread` + `apnsBody` i logic.ts):
//   aktivitet: type = activity, activity_id, kind, event_id?, round_id?, target_kind?, target_id?
//   tråden:    type = thread, message_id, event_id
// og category på begge. `club_id` og `competition_id` sendes ikke ennå; leses når de kommer.

/// Skjermen et trykk på en push åpner. nil (i `PushTap`) betyr bare å åpne appen.
nonisolated enum PushDestination: Equatable, Sendable {
    /// En klubbrunde (har kveld): føringen på Hjem.
    case clubRound(UUID)
    /// En runde uten kveld (løs runde eller turnering uten klubb).
    case looseRound(UUID)
    /// Kveld-skjermen: påmelding, purring, påminnelse, komiteen og tipsen.
    case evening(UUID?)
    /// Kveldens tråd. Med kameraet åpent for bildeoppfordringen (sql/050).
    case thread(eventID: UUID, camera: Bool)
    /// Tabellen i en turnering.
    case competition(UUID)
    /// Tavla-fanen (låst runde, tabellendring uten turnerings-id).
    case tavla
    /// Veddemålene i klubben.
    case bets
    /// «Mine oppgjør» (Del regningen, sql/051).
    case bills
    /// Varsler bak bjella (melding til alle, kommentarer, omtaler og følging).
    case notifications
    /// Hjem, uten noe mer (ny spiller, slettet runde).
    case home
    /// Arrangør → Troppen: noen vil bli med i klubben (sql/067, `PendingMembersFeature`).
    case roster

    /// Fanen skjermen ligger i.
    var tab: AppTab {
        switch self {
        case .tavla: .tavla
        case .roster: .arrangor
        default: .hjem
        }
    }
}

/// Et trykk på en push: hvor det skal, og klubben det gjelder når pushen sier det.
nonisolated struct PushTap: Equatable, Sendable {
    let destination: PushDestination
    /// `dd18.club_id`. Sendes ikke av `push-send` i dag; da åpnes skjermen i klubben som er valgt.
    let clubID: UUID?

    init(destination: PushDestination, clubID: UUID? = nil) {
        self.destination = destination
        self.clubID = clubID
    }

    /// Fra `userInfo`. nil når innholdet mangler, er ukjent eller ikke holder til en skjerm.
    init?(userInfo: [AnyHashable: Any], bets: Bool = BetsFeature.isEnabled,
          pendingMembers: Bool = PendingMembersFeature.isEnabled) {
        guard let data = userInfo["dd18"] as? [String: Any],
              let destination = Self.destination(data, bets: bets, pendingMembers: pendingMembers) else { return nil }
        self.destination = destination
        clubID = Self.uuid(data["club_id"])
    }

    private static func uuid(_ value: Any?) -> UUID? {
        (value as? String).flatMap(UUID.init(uuidString:))
    }

    private static func destination(_ data: [String: Any], bets: Bool, pendingMembers: Bool) -> PushDestination? {
        let event = uuid(data["event_id"])
        switch data["type"] as? String {
        case "thread":
            return event.map { .thread(eventID: $0, camera: false) }
        case "activity":
            guard let kind = data["kind"] as? String else { return nil }
            return activity(kind, event: event, round: uuid(data["round_id"]),
                            competition: uuid(data["competition_id"]), bets: bets, pendingMembers: pendingMembers)
        default:
            return nil
        }
    }

    private static func activity(_ kind: String, event: UUID?, round: UUID?, competition: UUID?,
                                 bets: Bool, pendingMembers: Bool) -> PushDestination? {
        switch kind {
        case "round_started", "evening_started", "lead_changed", "big_score", "side_prize", "score_corrected":
            // En runde med kveld er klubbens; uten kveld er den løs (eller en turnering uten klubb).
            if let round { return event == nil ? .looseRound(round) : .clubRound(round) }
            return event == nil ? .home : .evening(event)
        case "round_locked":
            // Klubbrunden er ferdig: resultatet står på Tavla. Den løse viser resultatet selv.
            if let round, event == nil { return .looseRound(round) }
            return .tavla
        case "round_deleted", "member_joined":
            return .home
        case "signup", "signup_dropped", "waitlist_promoted", "nudge", "reminder", "committee_drawn", "tips_king":
            return .evening(event)
        case "photo_prompt":
            return event.map { .thread(eventID: $0, camera: true) } ?? .home
        case "announcement", "comment_added", "mentioned", "follow_requested", "follow_accepted", "followed":
            return .notifications
        case "bet_challenge", "bet_created", "bet_resolved":
            return bets ? .bets : .home
        case "bill_share_sent", "bill_share_disputed":
            return .bills
        case "table_changed":
            return competition.map(PushDestination.competition) ?? .tavla
        case "member_pending":
            return pendingMembers ? .roster : .home
        default:
            return nil
        }
    }
}

/// Trykket som venter på å bli åpnet. iOS gir trykket før innloggingen og klubben er klare (kald
/// oppstart), så det tas vare på til `RootView` (eller `FriendsRootView`) kan åpne det.
@MainActor @Observable
final class PushTapInbox {
    static let shared = PushTapInbox()

    private(set) var pending: PushTap?
    private var receivedAt: Date?

    /// Et trykk som er eldre enn dette (for eksempel en lang innlogging), åpnes ikke.
    nonisolated static let maxAge: TimeInterval = 15 * 60

    func receive(_ tap: PushTap, at date: Date = .now) {
        pending = tap
        receivedAt = date
    }

    /// Trykket som venter, og glemmer det. nil når det ikke finnes eller er for gammelt.
    func take(now: Date = .now) -> PushTap? {
        defer { pending = nil; receivedAt = nil }
        guard let pending, let receivedAt, now.timeIntervalSince(receivedAt) <= Self.maxAge else { return nil }
        return pending
    }
}
