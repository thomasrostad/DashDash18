import Foundation
import Testing
@testable import DashDash18

// Følge andre spillere (gjennomføringsplanen steg 13, sql/054): knappen, listene, søketeksten,
// QR-lenken, sidene i «Følger», varslene og rekkefølgen i «Ny runde».

private func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }
private let me = id(9), anders = id(1), bjorn = id(2), cato = id(3), dag = id(4)
private let t0 = Date(timeIntervalSince1970: 1_791_482_400)
private func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }

private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(type, from: Data(json.utf8))
}

struct FolgeKnappTests {
    @Test func titlerOgHandling() {
        #expect(FollowButton.title(.none) == "Følg")
        #expect(FollowButton.title(.pending) == "Venter")
        #expect(FollowButton.title(.accepted) == "Følger")
        #expect(FollowButton.action(.none) == .request)
        #expect(FollowButton.action(.pending) == .cancel)
        #expect(FollowButton.action(.accepted) == .unfollow)
        // Følger personen deg, heter Følg «Følg tilbake»; Venter og Følger er like.
        #expect(FollowButton.title(.none, followsMe: true) == "Følg tilbake")
        #expect(FollowButton.title(.pending, followsMe: true) == "Venter")
        #expect(FollowButton.title(.accepted, followsMe: true) == "Følger")
    }

    @Test func statusEtterSvaret() {
        // Godkjenning på: venter. Godkjenning av: følger med en gang.
        #expect(FollowButton.after(.request, answer: "pending") == .pending)
        #expect(FollowButton.after(.request, answer: "accepted") == .accepted)
        // Ukjent svar: venter (serveren har tatt imot forespørselen).
        #expect(FollowButton.after(.request, answer: "noe annet") == .pending)
        #expect(FollowButton.after(.cancel, answer: nil) == .none)
        #expect(FollowButton.after(.unfollow, answer: "true") == .none)
    }

    @Test func helRundeIMaskinen() {
        var status = FollowStatus.none
        status = FollowButton.after(FollowButton.action(status), answer: "pending")
        #expect(status == .pending)
        status = FollowButton.after(FollowButton.action(status), answer: nil)
        #expect(status == .none)
        status = FollowButton.after(FollowButton.action(status), answer: "accepted")
        #expect(status == .accepted)
        #expect(FollowButton.action(status) == .unfollow)
    }

    @Test func ukjentStatusErIngen() {
        #expect(FollowStatus(server: nil) == .none)
        #expect(FollowStatus(server: "blocked") == .none)
        #expect(FollowStatus(server: "accepted") == .accepted)
    }

    @Test func feilkodene() {
        #expect(FollowError.message(.invalid("Grensen er nådd"), code: "54000") == FollowError.rateLimited)
        #expect(FollowError.message(.invalid("x"), code: "P0002") == "Fant ikke personen.")
        #expect(FollowError.message(.offline, code: nil) == DataError.offline.message)
    }
}

struct FolgeListerTests {
    private let json = """
    [
      {"profile_id": "\(id(1).uuidString)", "display_name": "Anders", "avatar_path": null, "direction": "following",
       "status": "accepted", "source": "search", "created_at": "2026-10-12T10:00:00Z", "accepted_at": "2026-10-12T10:01:00Z"},
      {"profile_id": "\(id(2).uuidString)", "display_name": "Bjørn", "avatar_path": null, "direction": "following",
       "status": "pending", "source": "round", "created_at": "2026-10-12T11:00:00Z", "accepted_at": null},
      {"profile_id": "\(id(3).uuidString)", "display_name": "Cato", "avatar_path": "a/b.jpg", "direction": "follower",
       "status": "pending", "source": "search", "created_at": "2026-10-12T12:00:00Z", "accepted_at": null},
      {"profile_id": "\(id(1).uuidString)", "display_name": "Anders", "avatar_path": null, "direction": "follower",
       "status": "accepted", "source": "qr", "created_at": "2026-10-11T10:00:00Z", "accepted_at": "2026-10-11T10:00:00Z"},
      {"profile_id": "\(id(4).uuidString)", "display_name": "Ådne", "avatar_path": null, "direction": "follower",
       "status": "accepted", "source": "qr", "created_at": "2026-10-11T10:00:00Z", "accepted_at": "2026-10-11T10:00:00Z"}
    ]
    """

    @Test func delerOppRadene() throws {
        let lists = FollowLists(try decode([FollowRow].self, json))
        #expect(lists.requests.map(\.profileID) == [cato])
        // Godtatte først, så de som venter.
        #expect(lists.following.map(\.profileID) == [anders, bjorn])
        // Norsk rekkefølge: Å til slutt.
        #expect(lists.followers.map(\.displayName) == ["Anders", "Ådne"])
        #expect(lists.followingCount == 1)
        #expect(lists.followerCount == 2)
        #expect(lists.countsText == "Du følger 1 · 2 følgere")
        #expect(lists.followingIDs == [anders])
    }

    @Test func statusMotEnPerson() throws {
        let lists = FollowLists(try decode([FollowRow].self, json))
        #expect(lists.status(of: anders) == .accepted)
        #expect(lists.status(of: bjorn) == .pending)
        #expect(lists.status(of: cato) == .none)
        #expect(lists.followsMe(anders))
        // En forespørsel er ikke en følger ennå.
        #expect(!lists.followsMe(cato))
    }

    @Test func énFølger() {
        let row = FollowRow(profileID: anders, displayName: "Anders", direction: .follower, status: .accepted)
        #expect(FollowLists([row]).countsText == "Du følger 0 · 1 følger")
    }
}

struct FolgeSokTests {
    @Test func minstTreTegn() {
        #expect(PeopleSearchQuery("") == .empty)
        #expect(PeopleSearchQuery("   ") == .empty)
        #expect(PeopleSearchQuery("an") == .tooShort)
        #expect(PeopleSearchQuery(" an ") == .tooShort)
        #expect(PeopleSearchQuery("and") == .ready("and"))
        #expect(PeopleSearchQuery("  Anders B  ") == .ready("Anders B"))
        #expect(PeopleSearchQuery(String(repeating: "a", count: 40)) == .ready(String(repeating: "a", count: 40)))
        #expect(PeopleSearchQuery(String(repeating: "a", count: 41)) == .tooLong)
    }

    @Test func hintet() {
        #expect(PeopleSearchQuery("an").hint == "Skriv minst tre bokstaver.")
        #expect(PeopleSearchQuery(String(repeating: "a", count: 41)).hint == "Høyst 40 tegn.")
        #expect(PeopleSearchQuery("and").hint == nil)
    }

    @Test func treffet() throws {
        let rows = try decode([PersonSearchRow].self, """
        [{"id": "\(id(1).uuidString)", "display_name": "Anders", "avatar_path": null, "club_name": "Golfgutu",
          "my_status": "pending", "follows_me": true},
         {"id": "\(id(2).uuidString)", "display_name": "Bjørn", "avatar_path": null, "club_name": null,
          "my_status": "none", "follows_me": false}]
        """)
        #expect(rows[0].myStatus == .pending)
        #expect(rows[0].subtitle == "Golfgutu · Følger deg")
        #expect(rows[1].myStatus == .none)
        #expect(rows[1].subtitle == nil)
    }
}

struct FolgeLenkeTests {
    @Test func kodenRenses() {
        #expect(FollowLink(code: "abcd-efgh")?.code == "ABCDEFGH")
        #expect(FollowLink(code: " ABCD EFGH ")?.code == "ABCDEFGH")
        #expect(FollowLink(code: "ABCDEFG")?.code == nil)
        #expect(FollowLink(code: "ABCDEFGHJ")?.code == nil)
        // I, O, 0 og 1 finnes ikke i koden.
        #expect(FollowLink(code: "ABCDEFGO") == nil)
        #expect(FollowLink(code: "ABCDEFG1") == nil)
        #expect(FollowLink(code: "ABCD2345")?.display == "ABCD-2345")
    }

    @Test func lenkene() {
        let code = FollowLink(code: "ABCD2345")!
        #expect(code.url.absoluteString == "https://dashdash18.com/folg/ABCD2345")
        #expect(FollowLink(url: URL(string: "https://dashdash18.com/folg/abcd2345")!) == code)
        #expect(FollowLink(url: URL(string: "https://www.dashdash18.com/folg/ABCD2345/")!) == code)
        #expect(FollowLink(url: URL(string: "dashdash://folg/ABCD2345")!) == code)
        #expect(FollowLink(url: URL(string: "https://example.com/folg/ABCD2345")!) == nil)
        #expect(FollowLink(url: URL(string: "https://dashdash18.com/klubb/ABCD2345")!) == nil)
        #expect(FollowLink(url: URL(string: "dashdash://runde/ABCD2345")!) == nil)
        #expect(FollowLink(url: URL(string: "https://dashdash18.com/folg/ABCD2345/mer")!) == nil)
    }

    @Test func skannet() {
        #expect(FollowLink(scanned: "https://dashdash18.com/folg/ABCD2345")?.code == "ABCD2345")
        #expect(FollowLink(scanned: "  abcd-2345 ")?.code == "ABCD2345")
        #expect(FollowLink(scanned: "https://example.com") == nil)
        #expect(FollowLink(scanned: "hei") == nil)
    }

    @Test func universelleLenkerTarFolg() {
        let url = URL(string: "https://dashdash18.com/folg/ABCD2345")!
        #expect(UniversalLink.appURL(url)?.absoluteString == "dashdash://folg/ABCD2345")
        // Klubb, runde og konkurranse tolker ikke følgelenken.
        #expect(ClubInvite(url: url) == nil)
        #expect(AppLink.parse(url, rounds: true) == nil)
    }

    @Test func svaretFraKoden() throws {
        let notFound = try decode(FollowByCodeResult.self, #"{"status": "not_found"}"#)
        #expect(notFound.isNotFound)
        #expect(notFound.message == "Fant ikke koden.")
        let ok = try decode(FollowByCodeResult.self, """
        {"profile_id": "\(id(1).uuidString)", "display_name": "Anders", "avatar_path": null,
         "status": "accepted", "already": false}
        """)
        #expect(!ok.isNotFound)
        #expect(ok.message == "Du følger nå Anders.")
        var already = ok
        already.already = true
        #expect(already.message == "Du følger allerede Anders.")
    }
}

struct FolgeFeedTests {
    private func card(_ n: Int, _ s: Double, mine: Bool = false) -> FollowingCard {
        FollowingCard(id: id(100 + n), createdAt: at(s), profileID: mine ? me : anders, displayName: "Anders",
                      isMine: mine)
    }

    @Test func førsteSideOgNeste() {
        var pages = FollowingFeedPages()
        pages.reset([card(1, 30), card(2, 20)], limit: 2)
        #expect(pages.hasMore)
        #expect(pages.cursor == FeedCursor(createdAt: at(20), id: id(102)))
        // Neste side kan gjenta den siste (tiden rundes opp): ingen dubletter.
        pages.append([card(2, 20), card(3, 10)], limit: 2)
        #expect(pages.cards.map(\.id) == [id(101), id(102), id(103)])
        #expect(pages.hasMore)
        pages.append([card(4, 5)], limit: 2)
        #expect(!pages.hasMore)
        #expect(pages.cards.count == 4)
        // Dra ned: første side erstatter alt.
        pages.reset([card(5, 40)], limit: 2)
        #expect(pages.cards.map(\.id) == [id(105)])
        #expect(!pages.hasMore)
    }

    @Test func sammeTidSorteresPåId() {
        let pages = FollowingFeedPages.ordered([card(1, 10), card(2, 10)])
        #expect(pages.map(\.id) == [id(102), id(101)])
    }

    @Test func kortetFraServeren() throws {
        let rows = try decode([FollowingCard].self, """
        [{"id": "\(id(101).uuidString)", "round_id": "\(id(500).uuidString)", "created_at": "2026-10-12T18:00:00Z",
          "profile_id": "\(id(1).uuidString)", "display_name": "Anders", "avatar_path": null, "is_mine": false,
          "played_on": "2026-10-12", "course_name": "Bjaavann", "hole_count": 9, "format": "stableford",
          "playing_handicap": 12, "strokes": 41, "holes_played": 9, "par_played": 36, "to_par": 5,
          "holes": [{"hole": 1, "par": 4, "strokeIndex": 5, "strokes": 5}, {"hole": 2, "par": 3, "strokeIndex": 9, "strokes": null}],
          "reactions": [{"emoji": "🔥", "count": 2}], "my_reactions": ["🔥"], "comment_count": 3}]
        """)
        let c = rows[0]
        #expect(c.toParText == "+5")
        #expect(c.subtitle.hasSuffix("Bjaavann · 9 hull"))
        #expect(c.holes.count == 2)
        #expect(c.holes[1].strokes == nil)
        #expect(c.chips == [ReactionChip(emoji: "🔥", count: 2, isMine: true)])
        #expect(c.commentCount == 3)
    }

    @Test func tilPar() {
        var c = card(1, 0)
        #expect(c.toParText == nil)
        c.toPar = 0
        #expect(c.toParText == "E")
        c.toPar = -2
        #expect(c.toParText == "-2")
        c.holesPlayed = 6
        c.holeCount = 9
        c.courseName = "Bjaavann"
        #expect(c.subtitle == "Bjaavann · 6 av 9 hull")
    }

    @Test func reaksjonenSlåsAvOgPå() {
        var c = card(1, 0)
        c = c.toggling("🔥")
        #expect(c.chips == [ReactionChip(emoji: "🔥", count: 1, isMine: true)])
        c = c.toggling("🔥")
        #expect(c.chips.isEmpty)
        c.reactions = [FollowingCard.Reaction(emoji: "👍", count: 2)]
        c = c.toggling("👍")
        #expect(c.chips == [ReactionChip(emoji: "👍", count: 3, isMine: true)])
    }
}

struct FolgeVarslerTests {
    private func row(_ kind: String, _ s: Double, actor: UUID = anders, to: [UUID]? = [me],
                     data: PersonalActivityData = PersonalActivityData(actorName: "Anders")) -> PersonalActivity {
        PersonalActivity(id: UUID(), kind: kind, actorProfileID: actor, recipients: to, data: data, createdAt: at(s))
    }

    @Test func tekstene() {
        #expect(PersonalActivityText.display(row("follow_requested", 0))?.text == "Anders vil følge deg")
        #expect(PersonalActivityText.display(row("follow_accepted", 0))?.text == "Anders godtok forespørselen din")
        #expect(PersonalActivityText.display(row("followed", 0))?.text == "Anders følger deg nå")
        let comment = PersonalActivityData(targetKind: "activity", targetID: id(101), preview: "Bra   spilt",
                                           authorName: "Bjørn")
        #expect(PersonalActivityText.display(row("comment_added", 0, data: comment))?.text
                == "Bjørn kommenterte runden: «Bra spilt»")
        #expect(PersonalActivityText.display(row("mentioned", 0, data: comment))?.text == "Bjørn nevnte deg: «Bra spilt»")
        #expect(row("comment_added", 0, data: comment).cardID == id(101))
        // Uten navn: «Noen».
        #expect(PersonalActivityText.display(row("followed", 0, data: PersonalActivityData()))?.text
                == "Noen følger deg nå")
        // round_finished er ikke et varsel.
        #expect(PersonalActivityText.display(row("round_finished", 0)) == nil)
    }

    @Test func barePåMegOgIkkeMineEgne() {
        let rows = [
            row("follow_requested", 10),
            row("followed", 20, actor: me, to: [anders]),
            row("round_finished", 30, to: nil),
            row("follow_accepted", 40, to: [bjorn]),
            row("followed", 50),
        ]
        let shown = PersonalActivityText.notifications(rows, me: me)
        #expect(shown.map(\.kind) == ["followed", "follow_requested"])
        #expect(PersonalActivityText.unreadCount(rows, me: me, lastSeen: at(15)) == 1)
        #expect(PersonalActivityText.unreadCount(rows, me: me, lastSeen: nil) == 2)
    }

    @Test func dekodesFraActivity() throws {
        let rows = try decode([PersonalActivity].self, """
        [{"id": "\(id(700).uuidString)", "kind": "follow_requested", "actor_profile_id": "\(id(1).uuidString)",
          "recipients": ["\(id(9).uuidString)"], "data": {"actor_name": "Anders", "source": "search"},
          "created_at": "2026-10-12T18:00:00Z"}]
        """)
        #expect(rows[0].isFollowRequest)
        #expect(rows[0].data.actorName == "Anders")
        #expect(rows[0].recipients == [me])
    }
}

struct FolgeRekkefolgeTests {
    @Test func demJegFølgerFørst() {
        let rows = [
            ProfileRow(id: anders, displayName: "Anders"),
            ProfileRow(id: bjorn, displayName: "Bjørn"),
            ProfileRow(id: cato, displayName: "Cato"),
            ProfileRow(id: dag, displayName: "Ådne"),
        ]
        let sorted = FollowOrdering.followedFirst(rows, following: [cato, dag])
        #expect(sorted.map(\.displayName) == ["Cato", "Ådne", "Anders", "Bjørn"])
        #expect(FollowOrdering.followedFirst(rows, following: []).map(\.id) == [anders, bjorn, cato, dag])
    }

    @Test func medspillereEtterRunden() {
        let lists = FollowLists([
            FollowRow(profileID: anders, displayName: "Anders", direction: .following, status: .accepted),
            FollowRow(profileID: bjorn, displayName: "Bjørn", direction: .following, status: .pending),
        ])
        let players: [(profileID: UUID?, name: String)] = [
            (me, "Meg"), (anders, "Anders"), (bjorn, "Bjørn"), (nil, "Gjest"), (cato, "Cato"), (cato, "Cato"),
        ]
        let candidates = FollowCoPlayers.candidates(players, me: me, lists: lists)
        // Ikke meg, ikke gjesten, ikke den jeg alt følger, Cato én gang.
        #expect(candidates.map(\.profileID) == [bjorn, cato])
        #expect(candidates.map(\.status) == [.pending, .none])
    }

    @Test func følgAlleBareDemDuIkkeHarSpurt() {
        let candidates = [
            FollowCandidate(profileID: anders, name: "Anders", status: .none),
            FollowCandidate(profileID: bjorn, name: "Bjørn", status: .pending),
            FollowCandidate(profileID: cato, name: "Cato", status: .none),
            FollowCandidate(profileID: dag, name: "Ådne", status: .accepted),
        ]
        // Én forespørsel per person, i rekkefølgen på lista; Bjørn venter og Ådne følger du alt.
        #expect(FollowCoPlayers.followAll(candidates) == [anders, cato])
        #expect(FollowCoPlayers.followAll([]).isEmpty)
        #expect(FollowCoPlayers.followAll(candidates).count >= FollowCoPlayers.followAllMinimum)
        #expect(FollowCoPlayers.followAll(Array(candidates.prefix(2))).count < FollowCoPlayers.followAllMinimum)
    }
}

/// «Folk du kjenner» i «Følger» og kortet på Hjem: folk du kjenner som du ikke følger ennå.
struct FolgeForslagTests {
    private let lists = FollowLists([
        FollowRow(profileID: anders, displayName: "Anders", direction: .following, status: .accepted),
        FollowRow(profileID: bjorn, displayName: "Bjørn", direction: .following, status: .pending),
        FollowRow(profileID: dag, displayName: "Ådne", direction: .follower, status: .accepted),
        FollowRow(profileID: anders, displayName: "Anders", direction: .follower, status: .accepted),
    ])

    @Test func ikkeMegIkkeFulgteIkkeUtenNavn() {
        let known = [
            ProfileRow(id: me, displayName: "Meg"),
            ProfileRow(id: anders, displayName: "Anders"),
            ProfileRow(id: bjorn, displayName: "Bjørn"),
            ProfileRow(id: cato, displayName: "Cato"),
            ProfileRow(id: cato, displayName: "Cato"),
            ProfileRow(id: id(5), displayName: "  "),
            ProfileRow(id: id(6), displayName: nil),
            ProfileRow(id: dag, displayName: "Ådne"),
        ]
        let people = FollowSuggestions.people(known, me: me, lists: lists)
        // Ådne følger meg og står først (følg tilbake), så Bjørn og Cato i norsk rekkefølge.
        #expect(people.map(\.profileID) == [dag, bjorn, cato])
        #expect(people.map(\.status) == [.none, .pending, .none])
        #expect(people.map(\.subtitle) == ["Følger deg", "Venter på svar", nil])
    }

    @Test func kortetViserBareDemDuIkkeHarSpurt() {
        let known = (10..<16).map { ProfileRow(id: id($0), displayName: "Spiller \($0)") }
            + [ProfileRow(id: bjorn, displayName: "Bjørn")]
        let preview = FollowSuggestions.preview(FollowSuggestions.people(known, me: me, lists: lists))
        #expect(preview.count == FollowSuggestions.previewCount)
        #expect(!preview.contains { $0.profileID == bjorn })
        #expect(preview.allSatisfy { $0.status == .none })
    }

    @Test func venneneFølgerHverandre() {
        // Anders: begge veier. Bjørn venter, Ådne følger bare meg.
        #expect(lists.friendIDs == [anders])
        #expect(FollowLists.empty.friendIDs.isEmpty)
    }
}

/// Hvem som får «Følg tilbake»: de som følger meg, og som jeg ikke følger ennå.
struct FolgeTilbakeTests {
    private let erik = id(5)
    private let lists = FollowLists([
        // Anders: vi følger hverandre.
        FollowRow(profileID: anders, displayName: "Anders", direction: .following, status: .accepted),
        FollowRow(profileID: anders, displayName: "Anders", direction: .follower, status: .accepted),
        // Bjørn: jeg venter på svar, han følger ikke meg.
        FollowRow(profileID: bjorn, displayName: "Bjørn", direction: .following, status: .pending),
        // Cato: forespørsel til meg som ikke er besvart.
        FollowRow(profileID: cato, displayName: "Cato", direction: .follower, status: .pending),
        // Ådne: følger meg, jeg følger ikke.
        FollowRow(profileID: dag, displayName: "Ådne", direction: .follower, status: .accepted),
        // Erik: følger meg, og jeg har bedt om å følge tilbake.
        FollowRow(profileID: id(5), displayName: "Erik", direction: .follower, status: .accepted),
        FollowRow(profileID: id(5), displayName: "Erik", direction: .following, status: .pending),
    ])

    @Test func bareDeSomFølgerMegUtenAtJegFølgerTilbake() {
        #expect(lists.followBackStatus(dag) == FollowStatus.none)
        #expect(lists.followBackStatus(erik) == .pending)
        #expect(lists.followBackStatus(anders) == nil)
        #expect(lists.followBackStatus(bjorn) == nil)
        // En forespørsel som venter, får Godta og Avslå, ikke «Følg tilbake».
        #expect(lists.followBackStatus(cato) == nil)
        #expect(lists.followBackStatus(me) == nil)
    }

    @Test func iVarslene() {
        func row(_ kind: String, _ actor: UUID?) -> PersonalActivity {
            PersonalActivity(id: id(50), kind: kind, actorProfileID: actor, recipients: [me], createdAt: t0)
        }
        // Godtatt forespørsel og «X følger deg nå».
        #expect(PersonalActivityText.followBack(row("follow_requested", dag), lists: lists) == dag)
        #expect(PersonalActivityText.followBack(row("followed", erik), lists: lists) == erik)
        // Forespørselen venter fortsatt, eller jeg følger alt.
        #expect(PersonalActivityText.followBack(row("follow_requested", cato), lists: lists) == nil)
        #expect(PersonalActivityText.followBack(row("followed", anders), lists: lists) == nil)
        // Andre varsler, og uten avsender.
        #expect(PersonalActivityText.followBack(row("follow_accepted", dag), lists: lists) == nil)
        #expect(PersonalActivityText.followBack(row("comment_added", dag), lists: lists) == nil)
        #expect(PersonalActivityText.followBack(row("followed", nil), lists: lists) == nil)
    }
}
