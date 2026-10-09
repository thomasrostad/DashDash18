#if DEBUG
import SwiftUI

/// Skjermprøver for invitasjonen til en klubb, uten nett: `velkommen` (uten kode, med «Lim inn»),
/// `blimedlenke` (koden fra lenken fylt inn og klubben hentet), `blimedbekreft` («Bli med i X?»
/// når du er med i en annen klubb) og `logininvitasjon` (innloggingen etter at lenken er åpnet).
struct ClubInviteSampleScreen: View {
    let screen: DesignScreenSamples.Screen
    @State private var auth = AuthModel(client: ApenSamples.client)
    @State private var club = ClubModel(client: ApenSamples.client)
    @State private var outbox = OutboxStatus()

    static let invite = ClubInvite(code: "02E5172C87")!

    static let preview = ClubPreview(
        clubID: UUID(), name: "Golfgutu Invitational", myStatus: nil,
        openMembers: ["Kåre", "Ola Nordmann", "Per"].map { .init(id: UUID(), displayName: $0) })

    var body: some View {
        content
            .environment(auth)
            .environment(club)
            .environment(outbox)
            .tint(Color.ddForestInk)
    }

    @ViewBuilder
    private var content: some View {
        switch screen {
        case .velkommen:
            ClubOnboardingView(user: .preview)
        case .blimedlenke:
            NavigationStack {
                JoinClubView(user: .preview, initialCode: Self.invite.code, preloaded: Self.preview)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Lukk") {} }
                    }
            }
        case .blimedbekreft:
            NavigationStack {
                ClubInviteConfirmView(invite: Self.invite, user: .preview, currentClub: "Fredagsgolfen",
                                      preloaded: Self.preview, onJoined: { _, _ in }, onClose: {})
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Lukk") {} }
                    }
            }
        case .logininvitasjon:
            LoginView(showsGoogle: false, showsLegal: true, hasClubInvite: true)
        default:
            EmptyView()
        }
    }
}

#Preview("Velkommen") { ClubInviteSampleScreen(screen: .velkommen) }
#Preview("Bli med fra lenke") { ClubInviteSampleScreen(screen: .blimedlenke) }
#endif
