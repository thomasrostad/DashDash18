import Foundation
import GolfgutuCore
import Supabase
import Synchronization
import Testing
@testable import DashDash18

// Kodegjennomgangen 08.10.2026: konkurransesiden henter bare påmeldingene i sin egen konkurranse,
// ikke hele oversikten over alle konkurranser og deltakere. Serveren er byttet ut med svar fra en
// `URLProtocol`, så dataflyten prøves uten nett.

/// Svarer på PostgREST-kall uten nett og husker hva som ble spurt om. Hver test har sin egen vert.
nonisolated private final class StubPostgREST: URLProtocol, @unchecked Sendable {
    struct Host: Sendable {
        var requests: [URL] = []
        /// Radene per tabell. `competition_id=eq.…` filtreres som PostgREST gjør.
        var tables: [String: [[String: String?]]] = [:]
    }

    static let hosts = Mutex<[String: Host]>([:])

    static func register(_ host: String, tables: [String: [[String: String?]]]) {
        hosts.withLock { $0[host] = Host(tables: tables) }
    }

    static func requests(_ host: String) -> [URL] {
        hosts.withLock { $0[host]?.requests ?? [] }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let host = url.host() else { return }
        let table = url.lastPathComponent
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let filter = items.first { $0.name == "competition_id" }?.value?.replacingOccurrences(of: "eq.", with: "")
        let rows: [[String: String?]] = Self.hosts.withLock { hosts in
            hosts[host]?.requests.append(url)
            let all = hosts[host]?.tables[table] ?? []
            guard let filter else { return all }
            return all.filter { ($0["competition_id"] ?? nil)?.lowercased() == filter.lowercased() }
        }
        let json: [[String: Any]] = rows.map { row in
            row.mapValues { value -> Any in
                if let value { return value }
                return NSNull()
            }
        }
        let body = (try? JSONSerialization.data(withJSONObject: json)) ?? Data("[]".utf8)
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor struct KonkurranseSideTests {
    static let me = UUID(uuidString: "0A0A0A0A-0000-4000-8000-0000000000A1")!
    static let friend = UUID(uuidString: "0A0A0A0A-0000-4000-8000-0000000000A2")!
    static let other = UUID(uuidString: "0A0A0A0A-0000-4000-8000-0000000000A3")!

    static func client(host: String) -> SupabaseClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubPostgREST.self]
        return SupabaseClient(supabaseURL: URL(string: "https://\(host)")!, supabaseKey: "sb_publishable_test",
                              options: .init(global: .init(session: URLSession(configuration: configuration))))
    }

    static func competition(_ id: UUID) -> CompetitionRow {
        CompetitionRow(id: id, kind: .league, name: "Vennecupen", clubID: nil, ownerID: me, seasonID: nil,
                       status: .active, entry: .listed, rules: .golfgutu, startsOn: nil, endsOn: nil, isMain: false,
                       requiresPurchase: false, entitlementID: nil, signupOpen: true)
    }

    static func participant(_ competition: UUID, profile: UUID) -> [String: String?] {
        ["id": UUID().uuidString, "competition_id": competition.uuidString, "member_id": nil,
         "profile_id": profile.uuidString, "status": "active"]
    }

    static func profile(_ id: UUID, _ name: String) -> [String: String?] {
        ["id": id.uuidString, "display_name": name, "handicap_index": nil, "avatar_path": nil]
    }

    @Test func sidenHenterBarePameldingeneIKonkurransen() async throws {
        let host = "konkurranseside-\(UUID().uuidString.lowercased()).test"
        let league = UUID(), elsewhere = UUID()
        StubPostgREST.register(host, tables: [
            "competition_participants": [
                Self.participant(league, profile: Self.me), Self.participant(league, profile: Self.friend),
                Self.participant(elsewhere, profile: Self.other),
            ],
            "profiles": [Self.profile(Self.me, "Meg"), Self.profile(Self.friend, "Venn"), Self.profile(Self.other, "Annen")],
        ])
        let model = CompetitionDetailModel(client: Self.client(host: host), competition: Self.competition(league),
                                           participants: [], access: CompetitionAccess(profileID: Self.me, memberships: []),
                                           main: nil)
        await model.load()

        #expect(model.state == .loaded)
        let detail = try #require(model.detail)
        #expect(Set(detail.participants.compactMap(\.profileID)) == [Self.me, Self.friend])
        #expect(detail.directory.profiles[Self.friend]?.displayName == "Venn")
        guard case .league = model.content else {
            Issue.record("Ligaen skal vises som tabell")
            return
        }

        let requests = StubPostgREST.requests(host)
        // Ikke hele oversikten: ingen henting av konkurranser, og påmeldingene bare for denne.
        #expect(!requests.contains { $0.lastPathComponent == "competitions" })
        let participants = requests.filter { $0.lastPathComponent == "competition_participants" }
        #expect(participants.count == 1)
        let query = try #require(participants.first.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        #expect(query.queryItems?.first { $0.name == "competition_id" }?.value?.lowercased()
                == "eq.\(league.uuidString.lowercased())")
        #expect(query.queryItems?.first { $0.name == "select" }?.value?.replacingOccurrences(of: " ", with: "")
                == CompetitionQueries.participantColumns.replacingOccurrences(of: " ", with: ""))
    }
}

/// Turneringer uten klubb (09.10.2026): bare private, og «Ny turnering» uten matchspill-serien.
@MainActor struct TurneringUtenKlubbTests {
    @Test func privateTurneringerUtenKlubb() {
        let model = CompetitionsModel(client: KonkurranseSideTests.client(host: "uten-klubb.test"),
                                      userID: KonkurranseSideTests.me)
        #expect(model.clubID == nil && model.clubName == nil)
        #expect(model.canCreate && !model.canCreateInClub)
        let new = NewTournamentModel(list: model, seasons: nil, offersPrivate: true)
        #expect(!new.templates.contains(.matchSeries) && new.templates.contains(.cup))
        #expect(new.draft(for: .cup).clubID == nil)
    }
}
