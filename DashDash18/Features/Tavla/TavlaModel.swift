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
}
