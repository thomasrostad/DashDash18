import Foundation
import GolfgutuCore
import Testing
@testable import DashDash18

// 1.0.1: blokker bare navn med innlogging, App Store-lenken i prod, ingen «ikke støttet ennå»
// og ingen veddemålslinjer når veddemål er av.

private func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n))! }

struct BlokkerUtenInnloggingTests {
    let withLogin = id(1), noLogin = id(2), user = id(11), profile = id(21)

    @Test func medlemITradenTrengerInnlogging() {
        let users = [withLogin: user]
        #expect(BlockRules.canBlock(memberID: withLogin, userForMember: users))
        #expect(!BlockRules.canBlock(memberID: noLogin, userForMember: users))
    }

    @Test func kommentarMedlemProfilOgUkjentTropp() {
        let known: Set<UUID> = [withLogin]
        #expect(BlockRules.canBlock(memberID: withLogin, profileID: nil, membersWithLogin: known))
        #expect(!BlockRules.canBlock(memberID: noLogin, profileID: nil, membersWithLogin: known))
        // Troppen er ikke kjent: den som kommenterte, var logget inn.
        #expect(BlockRules.canBlock(memberID: noLogin, profileID: nil, membersWithLogin: nil))
        // En profil er alltid en innlogging.
        #expect(BlockRules.canBlock(memberID: nil, profileID: profile, membersWithLogin: known))
        #expect(!BlockRules.canBlock(memberID: nil, profileID: nil, membersWithLogin: known))
    }

    @Test @MainActor func kommentarmodellenSkjulerBlokkering() {
        let me = id(9), club = id(900)
        let target = SocialTarget(kind: .activity, id: id(500), clubID: club)
        func comment(_ n: Int, by member: UUID) -> CommentRow {
            CommentRow(id: id(100 + n), clubID: club, targetKind: .activity, targetID: target.id, memberID: member,
                       body: "Hei", createdAt: Date(timeIntervalSince1970: 1_000))
        }
        let rows = [comment(1, by: withLogin), comment(2, by: noLogin)]
        let model = CommentsModel(preview: rows, target: target, me: me,
                                  people: [TradPerson(id: withLogin, name: "Anders"), TradPerson(id: noLogin, name: "Bjørn")],
                                  membersWithLogin: [withLogin, me])
        #expect(model.canBlock(rows[0]))
        #expect(!model.canBlock(rows[1]))
        // Rapportering virker fortsatt for begge.
        #expect(model.items.allSatisfy { $0.canReport })
    }

    @Test @MainActor func tradenViserBlokkerBareMedInnlogging() async {
        let club = id(900), event = id(901), me = id(3)
        let backend = FakeTradBackend()
        func member(_ m: UUID, _ name: String, user: UUID?) -> ClubMemberRow {
            ClubMemberRow(id: m, clubID: club, userID: user, displayName: name, handicapIndex: nil, seedGroup: nil,
                          isOrganizer: false, isTreasurer: false, status: .active, avatarPath: nil)
        }
        func row(_ n: Int, from: UUID) -> ThreadMessageRow {
            ThreadMessageRow(id: id(100 + n), clubID: club, eventID: event, memberID: from, body: "Hei", mentions: [],
                             imagePath: nil, createdAt: Date(timeIntervalSince1970: 2_000_000 + Double(n) * 60))
        }
        await backend.set(members: [member(withLogin, "Anders", user: user), member(noLogin, "Bjørn", user: nil),
                                    member(me, "Kåre", user: id(13))])
        await backend.set(rows: [row(1, from: withLogin), row(2, from: noLogin), row(3, from: me)])
        let model = TradModel(eventID: event, clubID: club, viewer: me, isOrganizer: false, backend: backend,
                              readStore: MemoryTradReadStore(), images: TradImageStore(),
                              now: { Date(timeIntervalSince1970: 2_500_000) })
        await model.load()
        let canBlock = Dictionary(model.items.map { ($0.message.memberID, $0.canBlock) }, uniquingKeysWith: { a, _ in a })
        #expect(canBlock[withLogin] == true)
        #expect(canBlock[noLogin] == false)
        #expect(canBlock[me] == false)
    }

    @Test @MainActor func rapportarketHarBryterenBareNarDetKanBlokkeres() {
        let target = ReportTarget(kind: .message, targetID: id(1), memberID: noLogin, authorName: "Bjørn")
        #expect(!target.canBlock)
    }
}

struct OppdaterAttenLenkeTests {
    @Test func prodGarTilAppStore() {
        let link = MinimumBuild.updateLink(for: .prod)
        #expect(link.title == "Åpne App Store")
        #expect(link.url == URL(string: "https://apps.apple.com/app/id6820031728"))
        #expect(!link.message.contains("TestFlight"))
        #expect(link.suggestion.contains("App Store"))
    }

    @Test func testbyggetBeholderTestFlight() {
        let link = MinimumBuild.updateLink(for: .test)
        #expect(link.title == "Åpne TestFlight")
        #expect(link.url.scheme == "itms-beta")
    }
}

struct IkkeStottetTekstTests {
    @Test func konkurransetekstenHorerIkkeUferdigUt() {
        #expect(!RoundCompetitionBoard.unsupportedText.lowercased().contains("ennå"))
        #expect(!RoundCompetitionBoard.unsupportedText.lowercased().contains("støttet"))
    }

    @Test func formerAppenIkkeKanForeSkjulesIVelgeren() {
        let skins = CompetitionForm.form(id: "skins")
        #expect(skins.support == .missing)
        let stableford = CompetitionForm.form(id: "stableford")
        let choices = RundeSetupStep.formChoices(allowed: CompetitionForm.all, current: stableford)
        #expect(!choices.contains { $0.id == "skins" })
        #expect(choices.contains { $0.id == "stableford" })
        // En kladd som alt står på skins, beholder valget sitt (og stoppes ved lagring).
        #expect(RundeSetupStep.formChoices(allowed: CompetitionForm.all, current: skins).first?.id == "skins")
    }

    /// App Review 2.1: ingen mal i «Ny turnering» skal gi en første runde som ikke kan føres.
    @Test func ingenTilbudtMalHarEnFormSomMangler() {
        for inClub in [true, false] {
            for template in TournamentSetup.templates(inClub: inClub) {
                let form = CompetitionForm.form(id: template.rules.formats.defaultFormID)
                #expect(form.support != .missing, "\(template.title): \(form.name)")
                // Standardformen står heller ikke som «ikke ferdig» i formvelgeren.
                #expect(RundeSetupStep.supportNote(form).isEmpty, "\(template.title): \(form.name)")
            }
        }
        // Skins-malen finnes fortsatt, så turneringer som bruker den, kjennes igjen.
        #expect(!TournamentSetup.isOffered(.skinsSeries))
        #expect(RulesetSummary.template(for: RulesetTemplate.skinsSeries.rules) == .skinsSeries)
    }

    /// «Ikke ferdig» står bare på former motoren ikke regner som hovedform.
    @Test func ikkeFerdigBareDerMotorenMangler() {
        for id in ["par-bogey", "amerikaner", "kobenhavner", "stableford", "fourball"] {
            #expect(RundeSetupStep.supportNote(CompetitionForm.form(id: id)).isEmpty, "\(id)")
        }
        for id in ["slag-netto", "slag-brutto", "stableford-brutto", "maks-score"] {
            #expect(RundeSetupStep.supportNote(CompetitionForm.form(id: id)) == " · ikke ferdig", "\(id)")
        }
    }

    @Test func lagmatchUtenValgtLag() {
        #expect(RundeSetupStep.teamMatchText(1, 2) == "Lag 1 – lag 2")
        #expect(RundeSetupStep.teamMatchText(nil, 2) == "Velg lag – lag 2")
        #expect(RundeSetupStep.teamMatchText(1, nil) == "Lag 1 – velg lag")
    }
}

struct IngenVeddemalUtenBetsTests {
    let club = id(900), anders = id(1), bjorn = id(2)

    func row(_ n: Int, _ event: ActivityEvent) -> ActivityRow {
        ActivityRow(id: id(n), clubID: club, kind: event.kind, category: event.category, data: event.data,
                    actorMemberID: anders, createdAt: Date(timeIntervalSince1970: 1_000 + Double(n)))
    }

    var rows: [ActivityRow] {
        [row(1, .memberJoined(member: bjorn)),
         row(2, .betCreated(question: "Thomas vinner", side: "yes", points: 50)),
         row(3, .betChallenge(question: "Birdie på 7", against: bjorn, side: "no", points: 20)),
         row(4, .betResolved(question: "Thomas vinner", resolution: "yes", server: true)),
         // Et veddemål appen ikke klarer å lese (mangler påstanden), blir `.unknown`.
         ActivityRow(id: id(5), clubID: club, kind: "bet_created", category: .bet, data: ActivityData(),
                     createdAt: Date(timeIntervalSince1970: 1_005))]
    }

    @Test func varslerOgUlesteUtenVeddemal() {
        let sections = ActivityFeed.sections(rows, now: Date(timeIntervalSince1970: 2_000), bets: false)
        #expect(sections.flatMap(\.rows).map(\.id) == [id(1)])
        #expect(ActivityFeed.unreadCount(rows, lastSeen: nil, me: nil, bets: false) == 1)
        let texts = ActivityFeed.shown(rows, bets: false).map { ActivityText.display($0, name: { _ in "Anders" }).text }
        for word in ["satset", "Veddemål", "utfordret", "Avgjort av scorene"] {
            #expect(!texts.contains { $0.contains(word) })
        }
    }

    @Test func medVeddemalStarAltSomFor() {
        #expect(ActivityFeed.shown(rows, bets: true).count == rows.count)
    }
}
