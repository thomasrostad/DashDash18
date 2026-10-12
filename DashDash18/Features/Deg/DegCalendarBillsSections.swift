import Supabase
import SwiftUI

/// Under Deg (steg 10, sql/051): «Mine oppgjør» og «Kalender». Mangler 051, vises ingen av dem.
struct DegCalendarBillsSections: View {
    let client: SupabaseClient
    let user: AuthUser
    /// Kalenderen har bare klubbkvelder: vises når du er med i en klubb.
    var showsCalendar: Bool
    @State private var billsAvailable = false
    @State private var calendarAvailable = false

    var body: some View {
        Group {
            if billsAvailable {
                Section {
                    NavigationLink { BillSettlementsView(client: client, userID: user.id) } label: {
                        Label("Mine oppgjør", systemImage: "creditcard")
                            .labelStyle(DDIconLabelStyle())
                    }
                } footer: {
                    DDFooter("Regningene du har delt eller skal betale.")
                }
            }
            if showsCalendar, calendarAvailable {
                DegCalendarSection(client: client)
            }
        }
        .task {
            async let bills = BillService.isAvailable(client: client)
            async let calendar = showsCalendar ? CalendarService.isAvailable(client: client) : false
            billsAvailable = await bills
            calendarAvailable = await calendar
        }
    }
}

/// «Kalender»: abonnement på kveldene du er bekreftet påmeldt på.
private struct DegCalendarSection: View {
    let client: SupabaseClient
    @Environment(\.openURL) private var openURL
    @State private var isWorking = false
    @State private var message: String?
    @State private var error: String?
    @State private var confirmsRenew = false
    @State private var confirmsRevoke = false

    var body: some View {
        Section {
            Button("Legg til i kalenderen", systemImage: "calendar.badge.plus") {
                run { token in
                    guard let url = CalendarLink.subscribeURL(token: token) else { return }
                    openURL(url)
                }
            }
            Button("Kopier lenke", systemImage: "doc.on.doc") {
                run { token in
                    UIPasteboard.general.string = CalendarLink.webURL(token: token)?.absoluteString
                    message = "Lenken er kopiert."
                }
            }
            Button("Ny lenke", systemImage: "arrow.triangle.2.circlepath") { confirmsRenew = true }
            Button("Skru av", systemImage: "calendar.badge.minus", role: .destructive) { confirmsRevoke = true }
                .foregroundStyle(Color.ddRustText)
            if let message {
                Label(message, systemImage: "checkmark.circle").foregroundStyle(Color.ddForestInk)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle").ddErrorStyle()
            }
        } header: {
            DDHeader("Kalender")
        } footer: {
            DDFooter("Bare kveldene du er bekreftet påmeldt på. Kalenderen oppdaterer seg selv. Lenken er personlig: den som har den, ser kveldene dine.")
        }
        .disabled(isWorking)
        .confirmationDialog("Lage ny lenke?", isPresented: $confirmsRenew, titleVisibility: .visible) {
            Button("Lag ny lenke") {
                run(renew: true) { token in
                    message = "Ny lenke laget. Legg den til i kalenderen igjen."
                    if let url = CalendarLink.subscribeURL(token: token) { openURL(url) }
                }
            }
            Button("Avbryt", role: .cancel) {}
        } message: {
            Text("Den gamle lenken slutter å virke. Kalendere som bruker den, får ikke flere kvelder.")
        }
        .confirmationDialog("Skru av kalenderen?", isPresented: $confirmsRevoke, titleVisibility: .visible) {
            Button("Skru av", role: .destructive) { revoke() }
            Button("Avbryt", role: .cancel) {}
        } message: {
            Text("Lenken slutter å virke. Kveldene blir borte fra kalenderen ved neste oppdatering.")
        }
    }

    /// Henter tokenet (`calendar_token`) og gjør noe med det.
    private func run(renew: Bool = false, _ action: @escaping (String) -> Void) {
        isWorking = true
        message = nil
        error = nil
        Task {
            defer { isWorking = false }
            do {
                action(try await CalendarService.token(client: client, renew: renew))
            } catch {
                self.error = DataError.from(error).message
            }
        }
    }

    private func revoke() {
        isWorking = true
        message = nil
        error = nil
        Task {
            defer { isWorking = false }
            do {
                try await CalendarService.revoke(client: client)
                message = "Kalenderen er skrudd av."
            } catch {
                self.error = DataError.from(error).message
            }
        }
    }
}
