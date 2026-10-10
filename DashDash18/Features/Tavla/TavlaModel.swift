import Foundation
import Observation
import Supabase

/// Tavla-fanen: henter sesongen og regner tabellen.
@Observable
final class TavlaModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private(set) var state: LoadState = .loading
    /// Nil når klubben ikke har en aktiv eller ferdig sesong.
    private(set) var standings: TavlaStandings?

    private let context: ClubContext
    private var pendingReload: Task<Void, Never>?
    private var isReloading = false
    private var reloadAgain = false

    var clubContext: ClubContext { context }

    init(context: ClubContext) {
        self.context = context
    }

    func load() async {
        do {
            let input = try await TavlaQueries.load(client: context.client, clubID: context.clubID)
            standings = input.map { TavlaStandings($0, me: context.memberID) }
            state = .loaded
            WidgetSnapshotPublisher.publish(standings: standings)
        } catch is CancellationError {
            // Dra-ned avbrutt: behold det som vises.
        } catch {
            // Har vi en tabell fra før, beholdes den; feilen vises bare når det ikke er noe å vise.
            if standings == nil { state = .failed(DataError.from(error).message) }
        }
    }

    // MARK: Realtime

    /// Følger med mens Tavla vises (som PWA-ens `subscribeRealtimeNytt`): en runde som startes,
    /// låses eller rettes, en score, en match eller en sidepremie henter tabellen på nytt. Kalles
    /// fra `.task` og varer til den avbrytes (Tavla forsvinner). Hver gang en egen kanal, så en
    /// ny visning ikke kolliderer med at den forrige rydder.
    func follow() async {
        let client = context.client
        // sql/040: én privat kanal for klubben (bare klubbens runder). Før: alle hullscorer i basen,
        // med RLS-sjekk per abonnent og endring.
        let channel = BroadcastFeature.isEnabled
            ? client.channel(BroadcastTopic.club(context.clubID)) { $0.isPrivate = true }
            : client.channel("tavla-\(context.clubID.uuidString)-\(UUID().uuidString)")
        // `rounds` har klubb-id; de andre tabellene har bare runde-id, og RLS holder dem til klubbene dine.
        let statuses = channel.statusChange
        var tasks: [Task<Void, Never>]
        if BroadcastFeature.isEnabled {
            let changes = channel.broadcastStream(event: BroadcastTopic.event)
            tasks = [Task { [weak self] in for await _ in changes { self?.scheduleReload() } }]
        } else {
            let changes = [
                channel.postgresChange(AnyAction.self, schema: "public", table: "rounds",
                                       filter: .eq("club_id", value: context.clubID)),
                channel.postgresChange(AnyAction.self, schema: "public", table: "hole_scores"),
                channel.postgresChange(AnyAction.self, schema: "public", table: "round_matches"),
                channel.postgresChange(AnyAction.self, schema: "public", table: "side_claims"),
            ]
            tasks = changes.map { stream in
                Task { [weak self] in
                    for await _ in stream { self?.scheduleReload() }
                }
            }
        }
        tasks.append(Task { [weak self] in
            // Kobler realtime til på nytt (nettet var borte), er endringene i mellomtiden tapt: hent alt.
            var connectedBefore = false
            for await status in statuses where status == .subscribed {
                if connectedBefore { self?.scheduleReload() }
                connectedBefore = true
            }
        })
        tasks.append(Task { try? await channel.subscribeWithError() })

        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3600))
        }
        tasks.forEach { $0.cancel() }
        pendingReload?.cancel()
        pendingReload = nil
        // Ryddes i en egen oppgave: denne er avbrutt, og da kan avmeldingen gi opp halvveis.
        Task { await client.removeChannel(channel) }
    }

    /// Mange hendelser på rad (en hel bås som lagrer) gir én henting, litt etter den siste.
    private func scheduleReload() {
        pendingReload?.cancel()
        pendingReload = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(1.5)) } catch { return }
            self?.pendingReload = nil
            await self?.reloadCoalesced()
        }
    }

    /// Én henting om gangen; kommer det flere mens den går, kjøres én til etterpå.
    private func reloadCoalesced() async {
        if isReloading { reloadAgain = true; return }
        isReloading = true
        defer { isReloading = false }
        repeat {
            reloadAgain = false
            await load()
        } while reloadAgain
    }
}
