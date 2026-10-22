import SwiftUI

/// «Forlat {klubb}» eller «Trekk forespørselen», med bekreftelse (sql/069). Vises bare når 069 er
/// kjørt (`LeaveClubFeature`). Når det er gjort, bytter appen klubb eller viser klubbvalget av seg selv.
struct LeaveClubButton: View {
    let membership: Membership
    let user: AuthUser
    @Environment(ClubModel.self) private var club
    @State private var confirming = false
    @State private var isLeaving = false
    @State private var error: String?

    var body: some View {
        if LeaveClubFeature.isAvailable {
            Button(LeaveClub.buttonTitle(membership), role: .destructive) {
                confirming = true
            }
            .disabled(isLeaving)
            .confirmationDialog(LeaveClub.confirmTitle(membership), isPresented: $confirming,
                                titleVisibility: .visible) {
                Button(LeaveClub.buttonTitle(membership), role: .destructive) { leave() }
                Button("Avbryt", role: .cancel) {}
            } message: {
                Text(LeaveClub.confirmMessage(membership))
            }
            .messageAlert("Det gikk ikke", text: $error)
        }
    }

    private func leave() {
        isLeaving = true
        Task {
            do throws(ClubError) {
                try await club.leave(clubID: membership.clubID, userID: user.id)
            } catch {
                self.error = error.message
            }
            isLeaving = false
        }
    }
}
