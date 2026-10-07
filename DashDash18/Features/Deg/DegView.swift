import SwiftUI

struct DegView: View {
    let config: AppConfig
    let user: AuthUser
    let membership: Membership
    @Environment(ClubModel.self) private var club
    @Environment(\.clubContext) private var context

    var body: some View {
        DDList {
            if let context {
                DegProfileSection(context: context)
                    .id(context.memberID)
            } else {
                Section {
                    DegHeader(membership: membership)
                        .padding(.vertical, 6)
                }
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
            if PushFeature.isEnabled, let context {
                Section {
                    NavigationLink { PushSettingsView(context: context) } label: {
                        Label("Varsler", systemImage: "bell.badge")
                            .labelStyle(DDIconLabelStyle())
                    }
                }
            }
            if StatsFeature.isEnabled, let context {
                StatsDegSection(context: context)
            }
            if membership.isOrganizer {
                Section {
                    NavigationLink { AdminHubView() } label: {
                        Label("Arrangørsiden", systemImage: "slider.horizontal.3")
                            .labelStyle(DDIconLabelStyle())
                    }
                }
            }
            DegAccountSection(user: user)
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
