import Foundation
import GolfgutuCore
import Observation
import Supabase

/// «Følger» på Hjem (sql/054, `following_feed_page`): ferdige runder fra dem du følger og dine egne,
/// i sider, med reaksjoner og kommentarer (050, `target_kind = 'activity'`).
@Observable
final class FollowingFeedModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private(set) var state: LoadState = .loading
    private(set) var pages = FollowingFeedPages()
    private(set) var isLoadingMore = false
    var errorMessage: String?

    let client: SupabaseClient?
    let userID: UUID
    /// Navnene du kjenner (kommentarene og omtale).
    private var names: [UUID: String] = [:]

    init(client: SupabaseClient, userID: UUID) {
        self.client = client
        self.userID = userID
    }

    /// Skjermprøve og tester: faste kort, ingen nettverk.
    init(preview cards: [FollowingCard], userID: UUID) {
        client = nil
        self.userID = userID
        pages.reset(cards)
        state = .loaded
    }

    var cards: [FollowingCard] { pages.cards }
    var canLoadMore: Bool { pages.hasMore }

    private var service: FollowService? { client.map(FollowService.init) }

    func load() async {
        guard let service else { return }
        do {
            let page = try await service.feedPage(before: nil)
            pages.reset(page)
            state = .loaded
            if names.isEmpty { names = await service.knownNames(userID: userID) }
        } catch {
            guard !DataError.isCancellation(error) else { return }
            if state == .loaded { return }
            state = .failed(FollowService.message(error))
        }
    }

    func loadMore() async {
        guard let service, pages.hasMore, !isLoadingMore, let cursor = pages.cursor else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            pages.append(try await service.feedPage(before: cursor))
        } catch {
            errorMessage = FollowService.message(error)
        }
    }

    // MARK: Reaksjoner og kommentarer

    /// Vises med en gang og rulles tilbake hvis serveren sier nei.
    func toggle(_ emoji: String, on card: FollowingCard) async {
        let on = !card.myReactions.contains(emoji)
        pages.replace(card.toggling(emoji))
        guard let client else { return }
        do {
            try await SocialService(client: client).react(emoji, on: target(card), on)
        } catch {
            pages.replace(card)
            errorMessage = "Klarte ikke å lagre reaksjonen. " + DataError.from(error).message
        }
    }

    func target(_ card: FollowingCard) -> SocialTarget {
        SocialTarget(kind: .activity, id: card.id, clubID: nil)
    }

    /// Kommentarene på kortet. Eieren av kortet kan slette kommentarer.
    func comments(for card: FollowingCard) -> CommentsModel {
        var known = names
        known[card.profileID] = card.name
        let people = known.map { TradPerson(id: $0.key, name: $0.value) }
            .sorted { NorwegianSort.areInIncreasingOrder($0.name, $1.name) }
        let model = CommentsModel(target: target(card), me: userID, isModerator: card.isMine,
                                  isTargetAuthor: card.isMine, people: people, names: known, client: client)
        model.onCountChange = { [weak self] count in self?.pages.setCommentCount(count, on: card.id) }
        return model
    }
}
