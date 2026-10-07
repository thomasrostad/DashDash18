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
            return try await LooseRoundQueries.start(client: client, setup)
        } catch {
            self.error = DataError.from(error).message
            return nil
        }
    }
}
