import SwiftUI

// MARK: - Logikk

/// Hvilke rader arrangøren ser for klubbverktøyene: på huben og i «Varsler til troppen».
/// Ren logikk, så flaggene kan testes uten SwiftUI.
nonisolated enum ClubTools {
    /// Radene i «Varsler til troppen».
    enum NoticeRow: Equatable, Sendable {
        /// «Melding til alle»: står i varslene og virker også uten push.
        case announcement
        /// «Hva blir push».
        case pushSettings
        /// «Hvem har push».
        case pushStatus
    }

    /// Radene på huben under «Varsler og rapporter».
    enum HubRow: Equatable, Sendable {
        case notices
        case reports
    }

    static func noticeRows(pushEnabled: Bool) -> [NoticeRow] {
        pushEnabled ? [.announcement, .pushSettings, .pushStatus] : [.announcement]
    }

    static func hubRows(moderationEnabled: Bool) -> [HubRow] {
        moderationEnabled ? [.notices, .reports] : [.notices]
    }

    /// Underteksten til «Varsler til troppen» på huben.
    static func noticesSubtitle(pushEnabled: Bool) -> String {
        pushEnabled
            ? "Melding til alle, hva som blir push og hvem som får varsler."
            : "Send en melding til alle i klubben."
    }
}

// MARK: - Skjerm

/// «Varsler til troppen»: melding til alle, hva som blir push og hvem som har push, samlet ett sted.
struct VarslerTilTroppenView: View {
    @Environment(\.clubContext) private var context

    var body: some View {
        Group {
            if let context {
                VarslerTilTroppenList(model: VarslerModel(context: context))
            } else {
                ContentUnavailableView("Ingen klubb", systemImage: "bell", description: Text("Velg en klubb først."))
            }
        }
        .navigationTitle("Varsler til troppen")
        .ddNavigationChrome()
    }
}

private struct VarslerTilTroppenList: View {
    @State var model: VarslerModel
    @State private var showsAnnouncement = false

    var body: some View {
        let rows = ClubTools.noticeRows(pushEnabled: PushFeature.isEnabled)
        DDList {
            if rows.contains(.announcement) {
                Section {
                    Button { showsAnnouncement = true } label: {
                        ClubToolRow("Melding til alle", "Går til alle i klubben og står i varslene.",
                                    systemImage: "megaphone")
                    }
                } footer: {
                    DDFooter("Meldingen kan også sendes fra Varsler, under bjella.")
                }
            }
            if rows.contains(.pushSettings) || rows.contains(.pushStatus) {
                DDSection("Push") {
                    if rows.contains(.pushSettings) {
                        NavigationLink { ClubPushSettingsView() } label: {
                            ClubToolRow("Hva blir push", "Hvilke hendelser som sendes som varsel til alle.",
                                        systemImage: "bell.badge")
                        }
                    }
                    if rows.contains(.pushStatus) {
                        NavigationLink { PushStatusView() } label: {
                            ClubToolRow("Hvem har push", "Hvem som får varsler på telefonen, og hvem som ikke gjør det.",
                                        systemImage: "iphone.radiowaves.left.and.right")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showsAnnouncement) {
            AnnouncementSheet(model: model)
        }
        .alert("Noe gikk galt", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

/// «Rapporter» fra arrangørsiden: henter klubben fra miljøet.
struct ClubReportsView: View {
    @Environment(\.clubContext) private var context

    var body: some View {
        if let context {
            ReportsAdminView(service: ModerationService(client: context.client), clubID: context.clubID)
        } else {
            ContentUnavailableView("Ingen klubb", systemImage: "flag", description: Text("Velg en klubb først."))
                .navigationTitle("Rapporter")
                .ddNavigationChrome()
        }
    }
}

/// Rad med tittel og en undertekst i klart språk, som på arrangørsiden.
private struct ClubToolRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    init(_ title: String, _ subtitle: String, systemImage: String) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
    }

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(Color.ddInk)
                Text(subtitle)
                    .font(.ddCaption)
                    .foregroundStyle(Color.ddInkSecondary)
            }
        } icon: {
            Image(systemName: systemImage)
        }
        .labelStyle(DDIconLabelStyle())
    }
}
