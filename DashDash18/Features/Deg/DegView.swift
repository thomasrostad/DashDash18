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
                // sql/069: gå ut av klubben. Den siste eieren stoppes av serveren med en forklaring.
                LeaveClubButton(membership: membership, user: user)
            }
            DegClubsSection(user: user, current: membership)
            if let context {
                OwnProfileNGFSection(context: context)
                    .id(context.user.id)
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
            DegAppearanceSection()
            DegAccountSection(user: user)
            DegOpenAppSections(client: context?.client, user: user)
            DDSection("Om appen") {
                if let version = AppVersion.text() {
                    Text(version)
                }
                // Miljø og database vises bare i test-bygg.
                if config.environment != .prod {
                    LabeledContent("Miljø", value: config.environment.displayName)
                    LabeledContent("Database") {
                        Text(config.projectRef).font(.ddMonoSmall)
                    }
                }
                if SlopeNoFeature.isEnabled {
                    SlopeNoAboutRow()
                }
            }
        }
    }
}

/// «Versjon 1.0.2 (bygg 190)» fra bunten, i «Om appen» (også i App Store-bygget).
nonisolated enum AppVersion {
    static func text(_ info: [String: Any]? = Bundle.main.infoDictionary) -> String? {
        guard let version = info?["CFBundleShortVersionString"] as? String, !version.isEmpty else { return nil }
        guard let build = info?["CFBundleVersion"] as? String, !build.isEmpty else { return "Versjon \(version)" }
        return "Versjon \(version) (bygg \(build))"
    }
}
