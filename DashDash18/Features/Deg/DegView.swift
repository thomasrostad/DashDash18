import SwiftUI

struct DegView: View {
    let config: AppConfig
    let user: AuthUser
    let membership: Membership
    @Environment(ClubModel.self) private var club
    @Environment(\.clubContext) private var context

    var body: some View {
        DDList {
            Section {
                DegHeader(membership: membership)
                    .padding(.vertical, 6)
            }
            if let context {
                DegProfileSection(context: context)
                    .id(context.memberID)
            }
            DDSection("Klubb") {
                LabeledContent("Klubb", value: membership.club.name)
                LabeledContent("Navn i troppen", value: membership.displayName)
                LabeledContent("Rolle", value: membership.roleText)
                if membership.isOrganizer, let code = membership.club.joinCode {
                    LabeledContent("Invitasjonskode") {
                        Text(code)
                            .font(.dd(.mono, size: 15, weight: .medium, relativeTo: .body))
                            .tracking(1)
                            .foregroundStyle(Color.ddForestInk)
                            .textSelection(.enabled)
                    }
                    ShareLink(
                        "Del invitasjonen",
                        item: "Bli med i \(membership.club.name) i DashDash18. Invitasjonskode: \(code)"
                    )
                    .fontWeight(.medium)
                }
                if otherActiveClubs.count > 0 {
                    Menu("Bytt klubb") {
                        ForEach(otherActiveClubs) { other in
                            Button(other.club.name) { club.select(other) }
                        }
                    }
                    .fontWeight(.medium)
                }
            }
            if membership.isOrganizer {
                Section {
                    NavigationLink { AdminHubView() } label: {
                        Label("Arrangørsiden", systemImage: "slider.horizontal.3")
                            .labelStyle(DDIconLabelStyle())
                    }
                }
            }
            DDSection("Konto") {
                LabeledContent("Logget inn som", value: user.email ?? "ukjent e-post")
                SignOutButton()
                    .foregroundStyle(Color.ddRustText)
            }
            DDSection("Om appen") {
                LabeledContent("Miljø", value: config.environment.displayName)
                LabeledContent("Database") {
                    Text(config.projectRef).font(.ddMonoSmall)
                }
            }
        }
    }

    private var otherActiveClubs: [Membership] {
        club.memberships.filter { $0.status == .active && $0.clubID != membership.clubID }
    }
}

/// Øverst på Deg: avatar, navnet i troppen, klubben og rollen.
private struct DegHeader: View {
    let membership: Membership

    var body: some View {
        HStack(spacing: 14) {
            DDAvatar(name: membership.displayName, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(membership.displayName)
                    .font(.ddTitle)
                    .foregroundStyle(Color.ddForestInk)
                Text(membership.club.name)
                    .font(.ddCallout)
                    .foregroundStyle(Color.ddInkSecondary)
            }
            Spacer(minLength: 8)
            if membership.isOrganizer {
                DDPill("Arrangør", tone: .lime)
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .combine)
    }
}
