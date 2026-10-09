import SwiftUI

/// En klubbinvitasjon fra en lenke som skal vises: koden og hva som skal skje (`ClubInviteFlow`),
/// låst når arkket åpnes, så det ikke skifter innhold når klubbene hentes på nytt etter «Bli med».
struct PresentedClubInvite: Identifiable, Equatable {
    let invite: ClubInvite
    let step: ClubInviteFlow.Step
    var id: String { invite.code }
}

/// Invitasjonen fra `dashdash://klubb/KODE` etter innlogging: rett til «Bli med» uten klubb,
/// «Bli med i X?» når du er med i andre klubber, eller beskjed når du allerede er med.
struct ClubInviteSheet: View {
    let presented: PresentedClubInvite
    let user: AuthUser
    let onClose: () -> Void
    @Environment(ClubModel.self) private var club
    /// Ferdig fra «Bli med i X?»: hva som skjedde.
    @State private var done: String?

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Lukk", action: onClose)
                    }
                }
        }
        .tint(Color.ddForestInk)
    }

    @ViewBuilder
    private var content: some View {
        if let done {
            message(title: "Klart", text: done, systemImage: "checkmark.circle")
        } else {
            switch presented.step {
            case .join:
                // Uten klubb bytter appen skjerm av seg selv når du er med (eller venter).
                JoinClubView(user: user, initialCode: presented.invite.code) { _, _ in onClose() }
            case .confirmJoin:
                ClubInviteConfirmView(invite: presented.invite, user: user, currentClub: club.current?.club.name,
                                      onJoined: joined, onClose: onClose)
            case .alreadyMember(let membership):
                alreadyMember(membership)
            case .waitForSignIn, .waitForClubs:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ddScreenBackground()
            }
        }
    }

    private func alreadyMember(_ membership: Membership) -> some View {
        ContentUnavailableView {
            Label(membership.club.name, systemImage: "person.3")
        } description: {
            Text(ClubInviteFlow.alreadyMemberText(membership))
        } actions: {
            if membership.status == .active, club.current?.clubID != membership.clubID {
                Button("Gå til \(membership.club.name)") {
                    club.select(membership)
                    onClose()
                }
                .buttonStyle(.dd(.primary))
            }
            Button("OK", action: onClose)
                .buttonStyle(.dd(.secondary))
        }
        .ddScreenBackground()
    }

    private func message(title: String, text: String, systemImage: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(text)
        } actions: {
            Button("OK", action: onClose)
                .buttonStyle(.dd(.primary))
        }
        .ddScreenBackground()
    }

    /// Med i en annen klubb fra før: bytt til den nye når du er med med én gang.
    private func joined(_ preview: ClubPreview, _ status: MemberStatus) {
        if status == .active { club.select(clubID: preview.clubID) }
        done = ClubInviteFlow.joinedText(clubName: preview.name, status: status)
    }
}

/// «Bli med i X?» for den som er med i en klubb fra før. Klubbnavnet hentes med `club_preview`.
struct ClubInviteConfirmView: View {
    let invite: ClubInvite
    let user: AuthUser
    let currentClub: String?
    let onJoined: (ClubPreview, MemberStatus) -> Void
    let onClose: () -> Void
    @Environment(ClubModel.self) private var club
    @State private var preview: ClubPreview?
    @State private var error: ClubError?
    @State private var showsJoin = false

    var body: some View {
        Group {
            if let preview {
                if preview.myStatus == .active || preview.myStatus == .pending {
                    ContentUnavailableView {
                        Label(preview.name, systemImage: "person.3")
                    } description: {
                        Text(preview.myStatus == .active ? "Du er allerede med i \(preview.name)."
                             : "Du har bedt om å bli med i \(preview.name). Arrangøren må godkjenne deg.")
                    } actions: {
                        Button("OK", action: onClose).buttonStyle(.dd(.secondary))
                    }
                } else {
                    confirm(preview)
                }
            } else if let error {
                ContentUnavailableView {
                    Label("Fant ikke klubben", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.message)
                } actions: {
                    Button("Prøv igjen") { Task { await load() } }
                        .buttonStyle(.dd(.primary))
                }
            } else {
                ProgressView("Henter klubben …")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .ddScreenBackground()
        .navigationTitle("Invitasjon")
        .navigationBarTitleDisplayMode(.inline)
        .ddNavigationChrome()
        .task { if preview == nil { await load() } }
        .navigationDestination(isPresented: $showsJoin) {
            JoinClubView(user: user, initialCode: invite.code) { preview, status in
                showsJoin = false
                onJoined(preview, status)
            }
        }
    }

    private func confirm(_ preview: ClubPreview) -> some View {
        ContentUnavailableView {
            Label("Bli med i \(preview.name)?", systemImage: "person.badge.plus")
        } description: {
            Text(currentClub.map { "Du er med i \($0) fra før. Når du er med, bytter appen til \(preview.name). Du bytter klubb under Deg." }
                 ?? "Når du er med, bytter appen til \(preview.name).")
        } actions: {
            Button("Bli med") { showsJoin = true }
                .buttonStyle(.dd(.primary))
            Button("Ikke nå", action: onClose)
                .buttonStyle(.dd(.secondary))
        }
    }

    private func load() async {
        error = nil
        do {
            preview = try await club.preview(code: invite.code)
        } catch {
            self.error = error
        }
    }
}
