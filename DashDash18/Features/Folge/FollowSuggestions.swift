import Foundation
import GolfgutuCore
import Observation
import Supabase

/// En du kjenner (klubb, runde eller turnering, `known_profiles`) og kan følge.
nonisolated struct FollowSuggestion: Equatable, Identifiable, Sendable {
    let profileID: UUID
    let name: String
    var avatarPath: String?
    var status: FollowStatus
    /// Personen følger deg (godtatt): følger du tilbake, er dere venner.
    var followsMe: Bool

    var id: UUID { profileID }

    /// Linja under navnet.
    var subtitle: String? {
        if status == .pending { return "Venter på svar" }
        return followsMe ? "Følger deg" : nil
    }
}

/// «Legg til venner»: folk du kjenner som du ikke følger ennå. Venn = dere følger hverandre;
/// det finnes ingen egen vennemodell, bare følging (sql/054).
nonisolated enum FollowSuggestions {
    /// Så mange vises på kortet i «Følger» på Hjem.
    static let previewCount = 3

    /// Dem du kjenner som du ikke følger (de du venter på, står med «Venter»): ikke deg selv,
    /// ikke uten navn, én gang hver. De som følger deg, står først (følg tilbake), så norsk
    /// navnerekkefølge.
    static func people(_ known: [ProfileRow], me: UUID, lists: FollowLists) -> [FollowSuggestion] {
        var seen: Set<UUID> = [me]
        var out: [FollowSuggestion] = []
        for row in known {
            guard !seen.contains(row.id), let name = followTrimmed(row.displayName) else { continue }
            seen.insert(row.id)
            let status = lists.status(of: row.id)
            guard status != .accepted else { continue }
            out.append(FollowSuggestion(profileID: row.id, name: name, avatarPath: row.avatarPath,
                                        status: status, followsMe: lists.followsMe(row.id)))
        }
        return out.sorted { a, b in
            if a.followsMe != b.followsMe { return a.followsMe }
            return NorwegianSort.areInIncreasingOrder(a.name, b.name)
        }
    }

    /// De første på kortet: bare dem du ikke har spurt ennå.
    static func preview(_ people: [FollowSuggestion]) -> [FollowSuggestion] {
        Array(people.filter { $0.status == .none }.prefix(previewCount))
    }
}

nonisolated extension FollowLists {
    /// Venner: dere følger hverandre (begge godtatt).
    var friendIDs: Set<UUID> { followingIDs.intersection(followers.map(\.profileID)) }
}

/// Forslagene til kortet øverst i «Følger» på Hjem.
@Observable
final class FollowAddFriendsModel {
    var suggestions: [FollowSuggestion] = []
    private(set) var friends = 0
    private(set) var isLoaded = false

    let client: SupabaseClient
    let userID: UUID

    init(client: SupabaseClient, userID: UUID) {
        self.client = client
        self.userID = userID
    }

    func load() async {
        let service = FollowService(client: client)
        async let known = try? LooseRoundQueries.friends(client: client, userID: userID)
        async let rows = try? service.myFollows()
        let lists = FollowLists(await rows ?? [])
        suggestions = FollowSuggestions.people(await known ?? [], me: userID, lists: lists)
        friends = lists.friendIDs.count
        isLoaded = true
    }
}

extension FollowAddFriendsModel: Identifiable {
    nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }
}
