import Foundation
import Supabase
import Synchronization

/// Forlat en klubb, eller trekk en forespørsel som venter (`sql/069_forlat_klubb.sql`, Thomas 22.10.2026).
/// Før 069 er kjørt finnes ikke `leave_club`: appen spør én gang per innlogging (`detect`) og husker
/// svaret. Uten 069 vises ingen av knappene.
nonisolated enum LeaveClubFeature {
    private static let key = "leaveClub069"
    private static let state = Mutex<Bool>(UserDefaults.standard.bool(forKey: key))

    /// Funksjonen fra 069 finnes (sist appen sjekket).
    static var isAvailable: Bool { state.withLock { $0 } }

    /// For tester og for `detect`.
    static func set(_ available: Bool) {
        state.withLock { $0 = available }
        UserDefaults.standard.set(available, forKey: key)
    }

    /// Kaller `leave_club` uten klubb. Funksjonen svarer 22023 («Mangler klubb») før den gjør noe,
    /// så kallet endrer ingenting. Ukjent funksjon = 069 er ikke kjørt. En annen feil (nettet borte)
    /// endrer ingenting.
    static func detect(client: SupabaseClient) async {
        do {
            _ = try await client.rpc("leave_club").execute()
            set(true)
        } catch let error as PostgrestError where EveningSignupService.isMissing(error) {
            set(false)
        } catch let error as PostgrestError where error.code == "22023" {
            set(true)
        } catch {
            // Behold det vi visste.
        }
    }
}

/// Tekstene og reglene rundt «Forlat klubben». Ren.
nonisolated enum LeaveClub {
    /// Medlemskapene slik de blir når du har gått ut av klubben: raden er borte (forespørselen er
    /// trukket) eller arkivert. Appen viser dette med en gang, før svaret fra serveren kommer, så
    /// klubben du gikk ut av ikke står igjen hvis hentingen feiler.
    static func remaining(_ memberships: [Membership], afterLeaving clubID: UUID) -> [Membership] {
        memberships.filter { $0.clubID != clubID }
    }

    /// Den huskede klubben glemmes når det er den du gikk ut av. Da velges neste aktive klubb,
    /// ellers en som venter, ellers klubbvalget (`Membership.choose`).
    static func remembered(_ remembered: UUID?, afterLeaving clubID: UUID) -> UUID? {
        remembered == clubID ? nil : remembered
    }

    static func buttonTitle(_ membership: Membership) -> String {
        membership.status == .pending ? "Trekk forespørselen" : "Forlat \(membership.club.name)"
    }

    static func confirmTitle(_ membership: Membership) -> String {
        membership.status == .pending
            ? "Trekke forespørselen om å bli med i \(membership.club.name)?"
            : "Forlate \(membership.club.name)?"
    }

    static func confirmMessage(_ membership: Membership) -> String {
        membership.status == .pending
            ? "Arrangøren får ikke lenger spørsmålet. Du kan be om å bli med igjen senere."
            : "Du ser ikke lenger klubben og får ingen varsler fra den. Rundene og statistikken din blir stående. Vil du tilbake, må arrangøren hente deg inn igjen i Troppen."
    }

    /// Feilen fra `leave_club`. 55000 («siste eier», med hva du må gjøre) og P0002 («Du er ikke med i
    /// klubben») vises som serveren skrev dem; P0002 betyr ellers «fant ingen klubb med koden».
    static func error(sqlState: String?, message: String) -> ClubError {
        ["55000", "P0002"].contains(sqlState ?? "") && !message.isEmpty
            ? .invalidInput(message)
            : ClubError.from(sqlState: sqlState, message: message)
    }
}
