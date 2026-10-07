import ActivityKit
import Foundation

/// Live Activity er av til widget-targetet (DashDash18Widgets) finnes og appen har
/// `NSSupportsLiveActivities = YES`. Uten dem feiler `Activity.request`. Se docs/widgets-oppsett.md.
nonisolated enum LiveActivityFeature {
    static let isEnabled = true
}

/// Starter, oppdaterer og avslutter Live Activity for runden som går. `RundeModel` kaller
/// `sync` hver gang runden er bygd på nytt (henting, realtime, lagring). Feil tas stille:
/// aktiviteten er pynt, føringen skal aldri stoppe av den.
@MainActor
final class RoundActivityController {
    static let shared = RoundActivityController()

    private typealias State = RoundActivityAttributes.ContentState

    /// Aktiviteten som går, som id: `Activity` er ikke `Sendable`, så den hentes fram der den brukes.
    private var current: (id: String, roundID: UUID)?
    private var lastState: State?
    /// Oppdateringene går i rekkefølge: hver venter på den forrige.
    private var queue: Task<Void, Never>?

    func sync(game: RoundGame?, viewer: Viewer) {
        guard LiveActivityFeature.isEnabled else { return }
        guard let game, game.wantsLiveActivity(for: viewer),
              let state = game.liveActivityContent(for: viewer) else {
            // Runden er låst, borte, eller jeg spiller ikke: avslutt med det siste vi vet. En låst
            // runde hentes ikke lenger (bare aktive), så da er det siste som ble vist, sluttstillingen.
            end(final: game.flatMap { $0.liveActivityContent(for: viewer) } ?? lastState)
            return
        }

        if let current, current.roundID == game.roundID {
            guard lastState.map({ !state.sameContent(as: $0) }) ?? true else { return }
            lastState = state
            enqueue { await Self.update(id: current.id, to: state) }
            return
        }

        // Ny runde, eller appen er startet på nytt mens aktiviteten står på låseskjermen.
        end(final: nil, keeping: game.roundID)
        if let running = Activity<RoundActivityAttributes>.activities.first(where: { $0.attributes.roundID == game.roundID }) {
            let id = running.id
            current = (id, game.roundID)
            lastState = state
            enqueue { await Self.update(id: id, to: state) }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            let activity = try Activity.request(attributes: game.liveActivityAttributes(for: viewer),
                                                content: ActivityContent(state: state, staleDate: nil),
                                                pushType: nil)
            current = (activity.id, game.roundID)
            lastState = state
        } catch {
            // Uten extension eller NSSupportsLiveActivities, eller brukeren har skrudd det av.
            current = nil
            lastState = nil
        }
    }

    /// Avslutter alle rundeaktiviteter (unntatt den for `keeping`). Med sluttstilling blir den
    /// stående på låseskjermen en stund; uten forsvinner den med en gang.
    private func end(final state: State?, keeping roundID: UUID? = nil) {
        current = nil
        lastState = nil
        let ids = Activity<RoundActivityAttributes>.activities
            .filter { $0.attributes.roundID != roundID }
            .map(\.id)
        guard !ids.isEmpty else { return }
        enqueue { await Self.end(ids: ids, final: state) }
    }

    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = queue
        queue = Task {
            await previous?.value
            await work()
        }
    }

    // `Activity` hentes fram på nytt her, så ingen ikke-`Sendable` verdi krysser en grense.

    private nonisolated static func update(id: String, to state: State) async {
        guard let activity = Activity<RoundActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }

    private nonisolated static func end(ids: [String], final state: State?) async {
        let content = state.map { ActivityContent(state: $0, staleDate: nil) }
        for activity in Activity<RoundActivityAttributes>.activities where ids.contains(activity.id) {
            await activity.end(content, dismissalPolicy: content == nil ? .immediate : .default)
        }
    }
}
