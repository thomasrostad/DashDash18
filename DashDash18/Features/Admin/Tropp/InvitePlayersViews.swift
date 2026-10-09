import SwiftUI

/// «Inviter spillere» som rad i en liste (arrangørsiden og «Kom i gang»): trykk åpner delearket
/// med lenken og koden med en gang, og koden står synlig for den som vil lese den opp.
struct InvitePlayersRow: View {
    let clubName: String
    let invite: ClubInvite
    var subtitle = "Send lenken til gjengen. De som har appen, kommer rett inn."
    @State private var showsSheet = false

    var body: some View {
        Button { showsSheet = true } label: {
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
                Image(systemName: "qrcode")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.ddForestInk)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Viser QR-koden og lenken til \(clubName)")
        .sheet(isPresented: $showsSheet) {
            NavigationStack { InviteShareSheet(clubName: clubName, invite: invite) }
                .presentationDetents([.large])
        }
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
    @State private var showsQR = false

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
            Button("Vis QR-kode", systemImage: "qrcode") { showsQR = true }
                .buttonStyle(.dd(.secondary, fullWidth: true))
        }
        .ddCard()
        .sheet(isPresented: $showsQR) {
            NavigationStack { InviteShareSheet(clubName: invite.clubName, invite: invite.invite) }
        }
    }
}

/// Invitasjonen til å vise fram: QR-koden (lenken), koden og knappene for å dele og kopiere.
/// Den andre skanner med kameraet og kommer rett inn i klubben (universell lenke).
struct InviteShareSheet: View {
    let clubName: String
    let invite: ClubInvite
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        DDList {
            Section {
                VStack(spacing: DDSpacing.m) {
                    if let image = QRCode.image(for: invite.shareURL().absoluteString) {
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 260)
                            .padding(DDSpacing.m)
                            .background(Color.white, in: .rect(cornerRadius: DDRadius.card))
                            .accessibilityLabel("QR-kode til invitasjonen")
                    }
                    Text("Skann med kameraet for å bli med i \(clubName).")
                        .font(.ddCallout)
                        .foregroundStyle(Color.ddInkSecondary)
                        .multilineTextAlignment(.center)
                    InviteCodeText(code: invite.code)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DDSpacing.s)
            }
            Section {
                ShareLink(item: invite.shareText(clubName: clubName)) {
                    Label("Del lenken", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.dd(.primary, fullWidth: true))
                Button(copied ? "Kopiert" : "Kopier lenken", systemImage: copied ? "checkmark" : "doc.on.doc") {
                    UIPasteboard.general.string = invite.shareURL().absoluteString
                    copied = true
                }
                .buttonStyle(.dd(.secondary, fullWidth: true))
            }
            .listRowSeparator(.hidden)
        }
        .navigationTitle("Inviter spillere")
        .navigationBarTitleDisplayMode(.inline)
        .ddNavigationChrome()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Ferdig") { dismiss() }
                    .tint(Color.ddOnDark)
            }
        }
    }
}
