import Foundation
import GolfgutuCore
import Observation
import Supabase

/// «Ny runde»: banebiblioteket, vennene, utkastet og starten (`start_loose_round`).
@Observable
final class NyRundeModel {
    var draft: LooseRoundDraft
    let library: CourseLibraryModel
    private(set) var friends: [ProfileRow] = []
    private(set) var me: ProfileRow?
    private(set) var isStarting = false
    var error: String?

    let rules: Ruleset
    private let client: SupabaseClient?
    private let userID: UUID

    init(client: SupabaseClient, userID: UUID, me: ProfileRow?, rules: Ruleset = LooseRoundRules.template) {
        self.client = client
        self.userID = userID
        self.me = me
        self.rules = rules
        library = CourseLibraryModel(shared: client, userID: userID)
        draft = .new(rules: rules)
    }

    #if DEBUG
    /// Skjermprøve uten nett.
    init(preview library: CourseLibraryModel, friends: [ProfileRow], me: ProfileRow, draft: LooseRoundDraft) {
        client = nil
        userID = me.id
        self.library = library
        self.friends = friends
        self.me = me
        self.draft = draft
        rules = LooseRoundRules.template
    }
    #endif

    func load() async {
        guard let client else { return }
        await library.load()
        do {
            if me == nil { me = try await LooseRoundQueries.ensureProfile(client: client) }
            friends = try await LooseRoundQueries.friends(client: client, userID: userID)
        } catch {
            self.error = DataError.from(error).message
        }
    }

    var forms: [CompetitionForm] { LooseRoundRules.forms(rules) }
    var course: CourseListItem? { library.items.first { $0.id == draft.courseID } }
    var myName: String { LooseRoundInfo.name(me?.displayName) }

    func friendName(_ id: UUID) -> String {
        LooseRoundInfo.name(friends.first { $0.id == id }?.displayName)
    }

    /// Navnene i lista: deg, vennene, gjestene.
    var names: [String] {
        [myName] + draft.friends.map(friendName) + draft.guests.map(\.trimmedName)
    }

    var issues: [LooseRoundIssue] { LooseRoundSetup.issues(draft, course: course, rules: rules) }

    var startOptions: [QuickStartStart] {
        var options = QuickStart.startOptions(courseHoles: course?.holeCount)
        if !options.contains(draft.start) { options.append(draft.start) }
        return options
    }

    // MARK: «Teller også i …» (fase 15)

    /// Konkurransene runden kan telle i. Nil når `CompetitionsFeature` er av.
    private(set) var links: CompetitionLinkModel?

    /// Henter konkurransene du styrer. `access` har klubbmedlemskapet ditt når appen har en klubb.
    func prepareLinks(access: CompetitionAccess?, clubID: UUID?) async {
        guard CompetitionsFeature.isActive, let client, links == nil else { return }
        let model = CompetitionLinkModel(client: client,
                                         access: access ?? CompetitionAccess(profileID: userID, memberships: []))
        links = model
        await model.load(clubID: clubID, roundID: nil)
    }

    /// Spillerne slik konkurransene kjenner dem: deg og vennene (profiler) og gjestene.
    var linkPlayers: [CompetitionLinking.Player] {
        [CompetitionLinking.Player(playerID: userID, clubID: nil, profileID: userID)]
            + draft.friends.map { CompetitionLinking.Player(playerID: $0, clubID: nil, profileID: $0) }
            + draft.guests.map { CompetitionLinking.Player(playerID: $0.id, clubID: nil, profileID: nil) }
    }

    func select(course: CourseListItem) {
        draft.setCourse(course.id, courseHoles: course.holeCount)
    }

    /// Starter runden. Gir rundens id, eller nil (feilen står i `error`).
    func start() async -> UUID? {
        guard let client, !isStarting,
              let setup = LooseRoundStart.make(draft, course: course, names: names, rules: rules) else { return nil }
        isStarting = true
        error = nil
        defer { isStarting = false }
        do {
            let id = try await LooseRoundQueries.start(client: client, setup)
            if let links, let message = await links.save(roundID: id, players: linkPlayers) {
                // Runden er startet; bare koblingen feilet.
                self.error = message
            }
            return id
        } catch {
            self.error = DataError.from(error).message
            return nil
        }
    }
}
