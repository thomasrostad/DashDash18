import SwiftUI

/// «Inviter spillere» som rad i en liste (arrangørsiden og «Kom i gang»): trykk åpner delearket
/// med lenken og koden med en gang, og koden står synlig for den som vil lese den opp.
struct InvitePlayersRow: View {
    let clubName: String
    let invite: ClubInvite
    var subtitle = "Send lenken til gjengen. De som har appen, kommer rett inn."

    var body: some View {
        ShareLink(item: invite.shareText(clubName: clubName)) {
            HStack(spacing: DDSpacing.s) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Inviter spillere")
                            .font(.ddBodyEmphasis)
                            .foregroundStyle(Color.ddForestInk)
                        Text(subtitle)
                            .font(.ddCaption)
                            .foregroundStyle(Color.ddInkSecondary)
                        InviteCodeText(code: invite.code)
                            .padding(.top, 2)
                    }
                } icon: {
                    Image(systemName: "person.badge.plus")
                }
                .labelStyle(DDIconLabelStyle())
                Spacer(minLength: 8)
                Image(systemName: "square.and.arrow.up")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.ddForestInk)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Deler lenken og koden \(invite.code)")
    }
}

/// «Koden: 02E5172C87» i monospace, som i Troppen.
struct InviteCodeText: View {
    let code: String

    var body: some View {
        HStack(spacing: 6) {
            Text("Koden")
                .font(.ddCaption)
                .foregroundStyle(Color.ddInkSecondary)
            Text(code)
                .font(.dd(.mono, size: 13, weight: .medium, relativeTo: .caption))
                .tracking(1)
                .foregroundStyle(Color.ddForestInk)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Hjem-kortet for arrangøren mens troppen er liten (`ClubInvite.homeCardRosterLimit`).
struct HjemInvite {
    let clubName: String
    let invite: ClubInvite
    let activeMembers: Int
}

struct HjemInviteCard: View {
    let invite: HjemInvite

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Troppen")
                    .ddEyebrow()
                Text("Inviter spillere")
                    .font(.ddTitleSmall)
                    .foregroundStyle(Color.ddForestInk)
                Text(ClubInvite.organizerSubtitle(activeMembers: invite.activeMembers))
                    .font(.ddCallout)
                    .foregroundStyle(Color.ddInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            InviteCodeText(code: invite.invite.code)
            ShareLink(item: invite.invite.shareText(clubName: invite.clubName)) {
                Label("Del invitasjonen", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.dd(.primary, fullWidth: true))
        }
        .ddCard()
    }
}
