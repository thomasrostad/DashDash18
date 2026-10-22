import Foundation
import Observation
import Supabase

/// «Følger» (sql/054): navnesøket, forespørsler, folk du kjenner, dem du følger, dine følgere og
/// innstillingene. Én modell for skjermen og lista bak den.
@Observable
final class FollowHubModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private(set) var state: LoadState = .loading
    private(set) var lists = FollowLists.empty
    private(set) var settings: FollowService.Settings?
    /// Folk du kjenner (klubb, runder, turneringer) som du ikke følger ennå.
    var suggestions: [FollowSuggestion] = []
    /// Forespørslene du har godtatt mens skjermen er åpen: de står igjen øverst med «Følg tilbake».
    private(set) var accepted: [FollowRow] = []
    /// «Følg tilbake» trykket her (statusen vises med en gang, før listene er hentet på nytt).
    var followBack: [UUID: FollowStatus] = [:]
    /// Personen som noe skjer med akkurat nå (knappene er av).
    private(set) var working: Set<UUID> = []
    var errorMessage: String?

    let client: SupabaseClient?
    let userID: UUID
    let search: FollowSearchModel
    private var channel: RealtimeChannelV2?
    private var listenTask: Task<Void, Never>?

    init(client: SupabaseClient, userID: UUID) {
        self.client = client
        self.userID = userID
        search = FollowSearchModel(client: client)
    }

    /// Skjermprøve og tester: faste rader, ingen nettverk.
    init(preview rows: [FollowRow], settings: FollowService.Settings, userID: UUID) {
        client = nil
        self.userID = userID
        search = FollowSearchModel(client: nil)
        lists = FollowLists(rows)
        self.settings = settings
        state = .loaded
    }

    private var service: FollowService? { client.map(FollowService.init) }

    func load() async {
        guard let service, let client else { return }
        do {
            async let rows = service.myFollows()
            async let mine = service.settings(userID: userID)
            async let known = try? LooseRoundQueries.friends(client: client, userID: userID)
            lists = FollowLists(try await rows)
            suggestions = FollowSuggestions.people(await known ?? [], me: userID, lists: lists)
            // Personvern vises først når innstillingene faktisk er hentet, ikke med gjettede standardverdier.
            settings = (try? await mine) ?? settings
            state = .loaded
        } catch {
            guard !DataError.isCancellation(error) else { return }
            if state == .loaded { return }
            state = .failed(FollowService.message(error))
        }
    }

    // MARK: Handlinger

    func respond(to row: FollowRow, accept: Bool) async {
        let done = await run(row.profileID) { try await $0.respond(to: row.profileID, accept: accept) }
        if done, accept, !accepted.contains(where: { $0.profileID == row.profileID }) { accepted.append(row) }
    }

    /// Statusen bak «Følg tilbake» for en som følger deg.
    func followBackStatus(_ profileID: UUID) -> FollowStatus {
        followBack[profileID] ?? lists.status(of: profileID)
    }

    func unfollow(_ profileID: UUID) async {
        await run(profileID) { try await $0.remove(profileID) }
    }

    func removeFollower(_ profileID: UUID) async {
        await run(profileID) { try await $0.removeFollower(profileID) }
    }

    func setApproval(_ on: Bool) async {
        await saveSettings(approval: on, searchable: nil)
    }

    func setSearchable(_ on: Bool) async {
        await saveSettings(approval: nil, searchable: on)
    }

    private func saveSettings(approval: Bool?, searchable: Bool?) async {
        guard let service else { return }
        let before = settings
        if let approval { settings?.followApproval = approval }
        if let searchable { settings?.searchable = searchable }
        do {
            settings = try await service.setSettings(approval: approval, searchable: searchable)
            // Godkjenning av: ventende forespørsler er godtatt på serveren.
            if approval == false { await load() }
        } catch {
            settings = before
            errorMessage = FollowService.message(error)
        }
    }

    @discardableResult
    private func run(_ id: UUID, _ action: (FollowService) async throws -> Void) async -> Bool {
        guard let service, !working.contains(id) else { return false }
        working.insert(id)
        defer { working.remove(id) }
        do {
            try await action(service)
            await load()
            return true
        } catch {
            errorMessage = FollowService.message(error)
            return false
        }
    }

    // MARK: Realtime

    /// Nye forespørsler og endringer kommer med en gang (`follows`, RLS: radene der du er en av to).
    func startRealtime() async {
        guard channel == nil, let client else { return }
        let channel = client.channel("folge-\(userID.uuidString)")
        let changes = channel.postgresChange(AnyAction.self, schema: "public", table: "follows",
                                             filter: .eq("followee_id", value: userID))
        self.channel = channel
        listenTask = Task { [weak self] in
            for await _ in changes { await self?.load() }
        }
        try? await channel.subscribeWithError()
    }

    func stopRealtime() async {
        listenTask?.cancel()
        listenTask = nil
        if let channel, let client { await client.removeChannel(channel) }
        channel = nil
    }
}

extension FollowHubModel: Identifiable {
    nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }
}
