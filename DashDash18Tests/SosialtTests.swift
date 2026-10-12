import Foundation
import Testing
@testable import DashDash18

// Sosialt (gjennomføringsplanen steg 9, sql/050): emojisjekken, reaksjonene, kommentarene,
// sidene i Hjem og de nye hendelsestypene.

private func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }
private let club = id(900), me = id(9), anders = id(1), bjorn = id(2), profile = id(100)
private let t0 = Date(timeIntervalSince1970: 1_791_482_400)
private func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }

struct EmojiCheckTests {
    @Test(arguments: ["👍", "😂", "⛳", "🔥", "❤️", "👍🏽", "🏳️‍🌈", "👨‍👩‍👧", "🇳🇴", "1️⃣", "#️⃣", "🏌️‍♂️", "☕"])
    func godtarÉnEmoji(_ text: String) {
        #expect(EmojiCheck.isSingleEmoji(text))
    }

    @Test(arguments: ["", "a", "1", "#", "👍👍", "👍 ", "ok", "❤", "hei 👍", "©"])
    func avviserAltAnnet(_ text: String) {
        #expect(!EmojiCheck.isSingleEmoji(text))
    }

    @Test func deFemFasteErGyldige() {
        #expect(ReactionPalette.quick == ["👍", "😂", "⛳", "🔥", "❤️"])
        #expect((ReactionPalette.quick + ReactionPalette.more).allSatisfy(EmojiCheck.isSingleEmoji))
        #expect(Set(ReactionPalette.more).count == ReactionPalette.more.count)
    }

    @Test func sisteEmojiIFeltet() {
        #expect(EmojiCheck.lastEmoji(in: "😂🔥") == "🔥")
        #expect(EmojiCheck.lastEmoji(in: "abc") == nil)
        #expect(EmojiCheck.lastEmoji(in: "hei 👍🏽") == "👍🏽")
    }
}

struct ReaksjonsTests {
    private let target = SocialTarget(kind: .message, id: id(500), clubID: club)

    private func row(_ who: UUID, _ emoji: String, _ s: Double, kind: SocialTargetKind = .message,
                     on target: UUID = id(500)) -> ReactionRow {
        ReactionRow(targetKind: kind, targetID: target, clubID: club, memberID: who, emoji: emoji, createdAt: at(s))
    }

    @Test func oppsummeringFlestFørstSåFørstKommet() {
        let rows = [row(anders, "🔥", 1), row(me, "🦅", 2), row(bjorn, "🦅", 3), row(bjorn, "👍", 0)]
        let s = ReactionSummary.from(rows, me: [me])
        #expect(s.counts == [ReactionCount(emoji: "🦅", count: 2), ReactionCount(emoji: "👍", count: 1),
                             ReactionCount(emoji: "🔥", count: 1)])
        #expect(s.mine == ["🦅"])
        #expect(s.total == 4)
    }

    @Test func likeMangeOgLikTidGårPåEmojien() {
        let s = ReactionSummary.from([row(anders, "🔥", 1), row(bjorn, "👍", 1)], me: [])
        #expect(s.counts.map(\.emoji) == ["👍", "🔥"])
    }

    @Test func trykkLeggerTilSistOgFjernerIgjen() {
        let start = ReactionSummary(counts: [ReactionCount(emoji: "🔥", count: 2)], mine: [])
        let on = start.toggled("😂")
        #expect(on.counts == [ReactionCount(emoji: "🔥", count: 2), ReactionCount(emoji: "😂", count: 1)])
        #expect(on.has("😂"))
        let more = on.toggled("🔥")
        #expect(more.counts.first == ReactionCount(emoji: "🔥", count: 3))
        let off = more.toggled("😂").toggled("🔥")
        #expect(off == start)
    }

    @Test func brikkeneHarNavnOgMine() {
        let rows = [row(anders, "🔥", 1), row(me, "🔥", 2), row(bjorn, "❤️", 3), row(anders, "❤️", 9, on: id(501))]
        let names = [anders: "Anders", me: "Thomas", bjorn: "Bjørn"]
        let chips = ReactionRows.chips(for: .message, id: id(500), in: rows, me: [me], name: { names[$0] })
        #expect(chips.map(\.emoji) == ["🔥", "❤️"])
        #expect(chips.map(\.count) == [2, 1])
        #expect(chips.map(\.isMine) == [true, false])
        #expect(chips[0].names == ["Anders", "Thomas"])
        #expect(chips[1].reaction == .heart)
        #expect(chips[0].accessibilityName == "Ild")
    }

    @Test func raderEtterTrykk() {
        let one = ReactionRows.toggled("🐐", on: target, person: me, isMember: true, in: [], now: at(5))
        #expect(one == [ReactionRow(targetKind: .message, targetID: id(500), clubID: club, memberID: me, emoji: "🐐",
                                    createdAt: at(5))])
        #expect(ReactionRows.toggled("🐐", on: target, person: me, isMember: true, in: one).isEmpty)
        // Uten klubb reagerer du som profil.
        let loose = SocialTarget(kind: .activity, id: id(600), clubID: nil)
        let p = ReactionRows.toggled("👍", on: loose, person: profile, isMember: false, in: [])
        #expect(p.first?.profileID == profile)
        #expect(p.first?.memberID == nil)
        #expect(p.first?.personID == profile)
    }

    @Test func hvemHarReagertNorskSortert() {
        let rows = [row(anders, "🔥", 1), row(bjorn, "🔥", 2), row(me, "🔥", 3), row(id(77), "😂", 4)]
        let names = [anders: "Åse", me: "Thomas", bjorn: "Bjørn"]
        let groups = ReactionWho.groups(rows, name: { names[$0] })
        #expect(groups == [ReactionWhoGroup(emoji: "🔥", names: ["Bjørn", "Thomas", "Åse"]),
                           ReactionWhoGroup(emoji: "😂", names: ["Noen"])])
    }

    @Test func gamleRaderBlirNye() {
        let legacy = ActivityReactionRow(activityID: id(700), memberID: anders, clubID: club, emoji: .fire, createdAt: at(1))
        let r = ReactionRow(legacy: legacy)
        #expect(r.targetKind == .activity)
        #expect(r.targetID == id(700))
        #expect(r.emoji == "🔥")
    }

    @Test func leserRaderFraReactions() throws {
        let json = #"""
        [{"target_kind":"comment","target_id":"00000000-0000-0000-0000-000000000500","club_id":null,
          "member_id":null,"profile_id":"00000000-0000-0000-0000-000000000100","emoji":"🐐",
          "created_at":"2026-10-08T18:00:00Z"}]
        """#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let rows = try decoder.decode([ReactionRow].self, from: Data(json.utf8))
        #expect(rows.first?.targetKind == .comment)
        #expect(rows.first?.personID == profile)
    }
}

@MainActor
struct KommentarTests {
    private func comment(_ n: Int, by who: UUID?, _ body: String, _ s: Double, edited: Bool = false,
                         deleted: Bool = false) -> CommentRow {
        CommentRow(id: id(n), clubID: club, targetKind: .activity, targetID: id(500), memberID: who, body: deleted ? "" : body,
                   createdAt: at(s), editedAt: edited ? at(s + 10) : nil, deletedAt: deleted ? at(s + 20) : nil)
    }

    private let names = [anders: "Anders", me: "Thomas", bjorn: "Bjørn"]

    @Test func eldsteFørstMedSlettetOgEndret() {
        let rows = [comment(3, by: bjorn, "Sist", 30), comment(1, by: anders, "Først", 10, edited: true),
                    comment(2, by: me, "Borte", 20, deleted: true)]
        let items = CommentList.items(rows, me: [me], isModerator: false, name: { names[$0] })
        #expect(items.map(\.text) == ["Først", "Kommentaren er slettet", "Sist"])
        #expect(items.map(\.isEdited) == [true, false, false])
        #expect(items[1].isDeleted)
        #expect(!items[1].canDelete && !items[1].canEdit && !items[1].canReport)
        #expect(CommentList.count(rows) == 2)
    }

    @Test func rettigheterForEgneAndreOgModerator() {
        let rows = [comment(1, by: me, "Min", 1), comment(2, by: anders, "Hans", 2)]
        let mine = CommentList.items(rows, me: [me], isModerator: false, name: { names[$0] })
        #expect(mine.map(\.canEdit) == [true, false])
        #expect(mine.map(\.canDelete) == [true, false])
        #expect(mine.map(\.canReport) == [false, true])
        let mod = CommentList.items(rows, me: [me], isModerator: true, name: { names[$0] })
        #expect(mod.map(\.canDelete) == [true, true])
        #expect(mod.map(\.canEdit) == [true, false])
    }

    @Test func rapportertSkjulesOgUkjentErNoen() {
        let rows = [comment(1, by: id(77), "Hvem?", 1), comment(2, by: anders, "Stygt", 2)]
        let items = CommentList.items(rows, me: [me], isModerator: false, hidden: [id(2)], name: { names[$0] })
        #expect(items.map(\.author) == ["Noen"])
    }

    @Test func antallPerMålOgOppdatering() {
        var rows = [comment(1, by: me, "A", 1), comment(2, by: anders, "B", 2, deleted: true)]
        #expect(CommentList.counts(rows) == [id(500): 1])
        rows = CommentList.upserting(comment(2, by: anders, "B igjen", 2), into: rows)
        #expect(rows.count == 2)
        #expect(CommentList.counts(rows) == [id(500): 2])
    }

    @Test func utkastet() {
        #expect(CommentDraft.check("   ") == .empty)
        #expect(CommentDraft.check("  hei \n") == .ready("hei"))
        #expect(CommentDraft.check(String(repeating: "a", count: 1000)) == .ready(String(repeating: "a", count: 1000)))
        #expect(CommentDraft.check(String(repeating: "a", count: 1001)) == .tooLong)
    }

    @Test func følgTråden() {
        #expect(ThreadFollow.isFollowing(row: nil, isTargetAuthor: true))
        #expect(!ThreadFollow.isFollowing(row: nil, isTargetAuthor: false))
        #expect(!ThreadFollow.isFollowing(row: false, isTargetAuthor: true))
        #expect(ThreadFollow.isFollowing(row: true, isTargetAuthor: false))
    }

    @Test func leserSlettetRad() throws {
        let json = #"""
        {"id":"00000000-0000-0000-0000-000000000001","club_id":"00000000-0000-0000-0000-000000000900",
         "competition_id":null,"target_kind":"message","target_id":"00000000-0000-0000-0000-000000000500",
         "member_id":"00000000-0000-0000-0000-000000000009","profile_id":null,"body":"","mentions":[],
         "created_at":"2026-10-08T18:00:00Z","edited_at":null,"deleted_at":"2026-10-08T18:05:00Z"}
        """#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let row = try decoder.decode(CommentRow.self, from: Data(json.utf8))
        #expect(row.isDeleted)
        #expect(row.authorID == me)
        #expect(row.targetKind == .message)
    }

    @Test func modellenMedOmtaleOgRettigheter() {
        let people = [TradPerson(id: me, name: "Thomas"), TradPerson(id: anders, name: "Anders Berg")]
        let model = CommentsModel(preview: [comment(1, by: anders, "Hei @Thomas", 1)],
                                  target: SocialTarget(kind: .activity, id: id(500), clubID: club), me: me, people: people)
        #expect(model.items.first?.author == "Anders Berg")
        #expect(model.items.first?.canReport == true)
        model.draft = "Takk @An"
        #expect(model.suggestions.map(\.handle) == ["Anders"])
        model.insertMention("Anders")
        #expect(model.draft == "Takk @Anders ")
        #expect(model.directory.mentions(in: model.draft, sender: me) == [anders])
        #expect(model.canSend)
        model.startEditing(comment(9, by: me, "Gammel", 5))
        #expect(model.draft == "Gammel")
        model.cancelEditing()
        #expect(model.draft.isEmpty && model.editing == nil)
    }
}

@MainActor
struct FeedSiderTests {
    private func row(_ n: Int, _ s: Double, club c: UUID? = club) -> ActivityRow {
        ActivityRow(id: id(n), clubID: c, kind: "announcement", category: .announcement,
                    data: ActivityData(text: "x"), createdAt: at(s))
    }

    @Test func nøkkelenErDenEldsteLinja() throws {
        let cursor = try #require(FeedCursor(last: [row(1, 30), row(3, 10), row(2, 10), row(4, 20)]))
        // Lik tid: lavest id er eldst (som `order by created_at desc, id desc`).
        #expect(cursor.id == id(2))
        #expect(cursor.createdAt == at(10))
        #expect(FeedCursor(last: []) == nil)
    }

    @Test func tidenRundesOppTilNesteMikrosekund() {
        let c = FeedCursor(createdAt: Date(timeIntervalSince1970: 1_791_482_400.123456), id: id(1))
        #expect(c.timestamp.hasPrefix("2026-10-08T18:00:00.12345"))
        #expect(c.timestamp.hasSuffix("Z"))
        let whole = FeedCursor(createdAt: Date(timeIntervalSince1970: 1_791_482_400), id: id(1))
        #expect(whole.timestamp == "2026-10-08T18:00:00.000001Z")
    }

    @Test func nesteSideUtenDuplikater() {
        let first = [row(5, 50), row(4, 40), row(3, 30)]
        let next = [row(3, 30), row(2, 20), row(1, 10)]
        #expect(FeedPaging.appending(next, to: first).map(\.id) == [id(5), id(4), id(3), id(2), id(1)])
        #expect(FeedPaging.hasMore(pageCount: 40, limit: 40))
        #expect(!FeedPaging.hasMore(pageCount: 12, limit: 40))
    }

    @Test func førsteSidePåNyttBeholderEldreSider() {
        let existing = [row(5, 50), row(4, 40), row(3, 30), row(2, 20), row(1, 10)]
        // Ny linje øverst, og 4 er slettet. Siden er full (3 av 3): de eldre sidene står.
        let fresh = [row(6, 60), row(5, 50), row(3, 30)]
        #expect(FeedPaging.refreshed(first: fresh, limit: 3, existing: existing).map(\.id)
                == [id(6), id(5), id(3), id(2), id(1)])
        // Ikke full: første side er hele feeden.
        #expect(FeedPaging.refreshed(first: [row(6, 60)], limit: 3, existing: existing).map(\.id) == [id(6)])
    }

    @Test func sideFraFeedPage() throws {
        let json = #"""
        [{"id":"00000000-0000-0000-0000-000000000001","club_id":"00000000-0000-0000-0000-000000000900",
          "competition_id":null,"kind":"photo_prompt","category":"social",
          "data":{"event_date":"2026-10-08","round_no":3,"course_name":"Losby"},"actor_member_id":null,
          "event_id":"00000000-0000-0000-0000-000000000300","round_id":"00000000-0000-0000-0000-000000000301",
          "recipients":["00000000-0000-0000-0000-000000000009"],"created_at":"2026-10-08T18:00:00Z",
          "reactions":[{"emoji":"🔥","count":2},{"emoji":"🐐","count":1}],"my_reactions":["🐐"],"comment_count":4},
         {"id":"00000000-0000-0000-0000-000000000002","club_id":null,
          "competition_id":"00000000-0000-0000-0000-000000000700","kind":"comment_added","category":"social",
          "data":{},"actor_member_id":null,"event_id":null,"round_id":null,"recipients":null,
          "created_at":"2026-10-08T17:00:00Z","reactions":[],"my_reactions":[],"comment_count":0}]
        """#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let page = try decoder.decode([FeedPageRow].self, from: Data(json.utf8))
        #expect(page.count == 2)
        #expect(page[0].activity.event == .photoPrompt(eventDate: "2026-10-08", roundNo: 3, courseName: "Losby"))
        #expect(page[0].social.summary.chips().map(\.isMine) == [false, true])
        #expect(page[0].social.commentCount == 4)

        var raw = HomeFeedQueries.Raw()
        raw.apply(page: page, limit: 2)
        // Linja uten klubb står ikke i klubbfeeden, men teller for nøkkelen og «mer».
        #expect(raw.activity.map(\.id) == [id(1)])
        #expect(raw.paging?.cursor?.id == id(2))
        #expect(raw.paging?.hasMore == true)
        #expect(raw.social[id(1)]?.summary.mine == ["🐐"])
    }

    @Test func eldreSiderStårEtterNyHenting() {
        var previous = HomeFeedQueries.Raw()
        previous.activity = [row(5, 50), row(4, 40), row(3, 30), row(2, 20)]
        previous.social = [id(2): ActivitySocial(summary: ReactionSummary(counts: [ReactionCount(emoji: "🔥", count: 1)]),
                                                 commentCount: 1)]
        previous.paging = .init(cursor: FeedCursor(createdAt: at(20), id: id(2)), hasMore: false)
        var fresh = HomeFeedQueries.Raw()
        fresh.activity = [row(6, 60), row(5, 50)]
        fresh.paging = .init(cursor: FeedCursor(createdAt: at(50), id: id(5)), hasMore: true)
        fresh.keepOlderPages(from: previous, limit: 2)
        #expect(fresh.activity.map(\.id) == [id(6), id(5), id(4), id(3), id(2)])
        #expect(fresh.social[id(2)]?.commentCount == 1)
        #expect(fresh.paging?.hasMore == false)
        #expect(fresh.paging?.cursor?.id == id(2))
    }
}

@MainActor
struct SosialeHendelserTests {
    private let names = [anders: "Anders", me: "Thomas"]

    @Test func teksteneForKommentarOmtaleOgBilde() {
        let c = SocialComment(targetKind: "activity", targetID: id(500), commentID: id(501),
                              preview: "Hei   der\nfolkens", authorName: "Anders Berg")
        #expect(ActivityText.display(.commentAdded(c), actor: anders, name: { names[$0] }).text
                == "Anders Berg kommenterte: «Hei der folkens»")
        #expect(ActivityText.display(.mentioned(c), actor: anders, name: { names[$0] }).text
                == "Anders Berg nevnte deg: «Hei der folkens»")
        let bare = SocialComment()
        #expect(ActivityText.display(.commentAdded(bare), actor: anders, name: { names[$0] }).text == "Anders kommenterte")
        #expect(ActivityText.display(.photoPrompt(eventDate: nil, roundNo: 2, courseName: nil), actor: nil,
                                     name: { names[$0] }).text == "Ta et bilde av gjengen")
        #expect(ActivityEvent.photoPrompt(eventDate: nil, roundNo: nil, courseName: nil).category == .social)
    }

    @Test func langtSitatKuttes() {
        let long = String(repeating: "a", count: 120)
        let quoted = SocialComment.quoted(long)
        #expect(quoted?.count == SocialComment.previewLength + 2)
        #expect(quoted?.hasSuffix("…»") == true)
        #expect(SocialComment.quoted("   ") == nil)
    }

    @Test func målet() {
        let c = SocialComment(targetKind: "message", targetID: id(500))
        #expect(c.target(clubID: club) == SocialTarget(kind: .message, id: id(500), clubID: club))
        #expect(SocialComment(targetKind: "noe", targetID: id(500)).target(clubID: club) == nil)
    }

    @Test func bjellaBareForMottakerne() {
        let viewer = HomeViewer(profileID: profile, memberships: [club: me])
        func row(_ event: ActivityEvent, recipients: [UUID]?) -> ActivityRow {
            ActivityRow(id: UUID(), clubID: club, kind: event.kind, category: event.category, data: event.data,
                        actorMemberID: anders, recipients: recipients, createdAt: t0)
        }
        let c = SocialComment(targetKind: "activity", targetID: id(500))
        #expect(HomeBell.reason(row(.commentAdded(c), recipients: [me]), viewer: viewer) == .commented)
        #expect(HomeBell.reason(row(.commentAdded(c), recipients: [bjorn]), viewer: viewer) == nil)
        #expect(HomeBell.reason(row(.mentioned(c), recipients: [me]), viewer: viewer) == .mentioned)
        #expect(HomeBell.reason(row(.photoPrompt(eventDate: nil, roundNo: 1, courseName: nil), recipients: [me]),
                                viewer: viewer) == .photoPrompt)
    }

    @Test func bildeoppfordringIFeeden() throws {
        let viewer = HomeViewer(profileID: profile, memberships: [club: me])
        let event = ActivityEvent.photoPrompt(eventDate: "2026-10-08", roundNo: 3, courseName: "Losby")
        let mine = ActivityRow(id: id(1), clubID: club, kind: event.kind, category: .social, data: event.data,
                               eventID: id(300), roundID: id(301), recipients: [me], createdAt: t0)
        let others = ActivityRow(id: id(2), clubID: club, kind: event.kind, category: .social, data: event.data,
                                 eventID: id(300), roundID: id(302), recipients: [bjorn], createdAt: t0)
        var input = HomeFeedInput(now: t0.addingTimeInterval(60), viewer: viewer)
        input.clubs = [HomeClub(id: club, name: "Golfgutu")]
        input.activity = [mine, others]
        input.social = [id(1): ActivitySocial(summary: ReactionSummary(), commentCount: 0)]
        let feed = HomeFeed.build(input)
        let cards = feed.sections.flatMap(\.cards)
        #expect(cards.count == 1)
        guard case .photoPrompt(let card) = try #require(cards.first).content else {
            Issue.record("ikke bildeoppfordring"); return
        }
        #expect(card.eventID == id(300))
        #expect(card.title == "Ta et bilde av gjengen")
        #expect(card.reactions?.isSocial == true)
    }

    @Test func kommentarlinjeÅpnerKommentarene() throws {
        let viewer = HomeViewer(profileID: profile, memberships: [club: me])
        let c = SocialComment(targetKind: "activity", targetID: id(500), preview: "Hei", authorName: "Anders")
        let line = ActivityRow(id: id(1), clubID: club, kind: "comment_added", category: .social, data: c.data,
                               actorMemberID: anders, recipients: [me], createdAt: t0)
        var input = HomeFeedInput(now: t0.addingTimeInterval(60), viewer: viewer)
        input.clubs = [HomeClub(id: club, name: "Golfgutu")]
        input.activity = [line]
        let feed = HomeFeed.build(input)
        guard case .lines(let lines) = try #require(feed.sections.first?.cards.first).content else {
            Issue.record("ikke linjer"); return
        }
        #expect(lines.first?.opens == SocialTarget(kind: .activity, id: id(500), clubID: club))
        #expect(lines.first?.reactions == nil)
        #expect(lines.first?.text == "Anders kommenterte: «Hei»")
    }

    @Test func feedenMedSiderHarIkkeVindu() {
        let viewer = HomeViewer(profileID: profile, memberships: [club: me])
        let old = ActivityRow(id: id(1), clubID: club, kind: "announcement", category: .announcement,
                              data: ActivityData(text: "Gammel"), createdAt: t0.addingTimeInterval(-90 * 24 * 3600))
        var input = HomeFeedInput(now: t0, viewer: viewer)
        input.clubs = [HomeClub(id: club, name: "Golfgutu")]
        input.activity = [old]
        #expect(HomeFeed.build(input).isEmpty)
        input.paged = true
        #expect(!HomeFeed.build(input).isEmpty)
    }

    @Test func reaksjonMedHvilkenSomHelstEmojiIModellen() async throws {
        let viewer = HomeViewer(profileID: profile, memberships: [club: me])
        var raw = HomeFeedQueries.Raw()
        raw.activity = [ActivityRow(id: id(1), clubID: club, kind: "announcement", category: .announcement,
                                    data: ActivityData(text: "Hei"), actorMemberID: anders, createdAt: t0)]
        raw.social = [id(1): ActivitySocial(summary: ReactionSummary(), commentCount: 2)]
        raw.paging = .init(cursor: nil, hasMore: false)
        let model = HomeFeedModel(preview: raw, viewer: viewer, clubs: [HomeClub(id: club, name: "Golfgutu")],
                                  lastSeen: nil, now: { t0.addingTimeInterval(60) })
        let target = HomeReactions(activityID: id(1), clubID: club, chips: [], commentCount: 2)
        await model.toggle("🐐", on: target)
        #expect(model.hasReacted("🐐", on: target))
        guard case .lines(let lines) = try #require(model.feed.sections.first?.cards.first).content else {
            Issue.record("ikke linjer"); return
        }
        #expect(lines.first?.reactions?.chips.map(\.emoji) == ["🐐"])
        #expect(lines.first?.reactions?.commentCount == 2)
        #expect(model.canLoadMore == false)
    }
}
