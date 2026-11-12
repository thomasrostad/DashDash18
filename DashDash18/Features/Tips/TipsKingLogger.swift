import Foundation
import Supabase

/// Kårer tippekongen når arrangøren har låst den siste runden på kvelden: kupongen regnes som på
/// skjermen (`TipsBoard`), og kongen skrives som én linje (`tips_king`) til Hjem, varsler og push.
/// Er kvelden ikke ferdig, eller ingen har levert, skjer ingenting. `sql/078_tippekonge_en_gang.sql`
/// sørger for én linje per kveld, også når to telefoner låser samtidig. Feiler noe, står låsingen
/// likevel (som de andre linjene, `logQuietly`).
@MainActor
enum TipsKingLogger {
    static func logAfterLocking(client: SupabaseClient, clubID: UUID, me: UUID, eventID: UUID?) async {
        guard let eventID,
              let input = try? await TipsQueries.load(client: client, eventID: eventID),
              let event = TipsBoard(input, me: me, isOrganizer: true).kingEvent else { return }
        await ActivityLog(client: client, clubID: clubID).logQuietly(event, eventID: eventID)
    }
}
