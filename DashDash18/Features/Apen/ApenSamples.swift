#if DEBUG
import Supabase
import SwiftUI

/// Skjermprøver for fase 17 (åpent for alle), uten nett: `apenvalg`, `apenlogin`, `apendeg`,
/// `apenslett`, `apenrapport`, `apenrapporter`, `apenblokkerte`, `apenbetaling` og `apenregning`.
struct ApenSampleScreen: View {
    let screen: DesignScreenSamples.Screen
    @State private var auth = AuthModel(client: ApenSamples.client)
    @State private var club = ClubModel(client: ApenSamples.client)
    @State private var outbox = OutboxStatus()

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
        case .apenvalg:
            OnboardingChoiceView { _ in }
        case .apenlogin:
            LoginView(showsGoogle: true, showsLegal: true)
        case .apendeg:
            NavigationStack {
                FriendsDegView(config: .preview, client: nil, user: .preview, name: "Frida Fjellstad")
                    .navigationTitle("Deg")
                    .ddNavigationChrome()
            }
            .ddScreenBackground()
        case .apenslett:
            AccountDeletionSheet(client: nil, user: .preview, organizerClubs: ["Golfgutu Invitational"])
        case .apenrapport:
            ReportSheet(target: ReportTarget(kind: .message, targetID: UUID(), memberID: UUID(), authorName: "Kåre")) { _, _, _ in }
        case .apenrapporter:
            NavigationStack {
                ReportsAdminView(service: nil, clubID: UUID(), preview: ApenSamples.reports)
            }
        case .apenblokkerte:
            NavigationStack {
                BlockedUsersView(service: nil, preview: [
                    BlockedUser(blockedID: UUID(), displayName: "Kåre", createdAt: .now),
                    BlockedUser(blockedID: UUID(), displayName: "Spam Spamsen", createdAt: .now),
                ])
            }
        case .apenbetaling:
            PaywallView(service: nil, competitionID: UUID(), competitionName: "Høstcupen 2026",
                        previewPrices: [.tournament: "99,00 kr", .yearly: "399,00 kr"])
        case .apenregning:
            BillSplitView(people: ["Thomas", "Anders", "Bjørn", "Carl"], amount: "1 250", phone: "98765432")
        default:
            EmptyView()
        }
    }
}

enum ApenSamples {
    static let client = SupabaseClient(
        supabaseURL: URL(string: "https://forhandsvisning.supabase.co")!,
        supabaseKey: "sb_publishable_forhandsvisning"
    )

    static var reports: [ContentReportRow] {
        let message = UUID()
        let now = Date.now
        return [
            ContentReportRow(id: UUID(), kind: .message, targetID: message, clubID: nil, reason: .offensive,
                             note: "Ikke greit å skrive sånn", snapshot: "Du er den dårligste golferen i klubben, slutt nå",
                             status: .open, createdAt: now.addingTimeInterval(-21 * 3600)),
            ContentReportRow(id: UUID(), kind: .message, targetID: message, clubID: nil, reason: .harassment,
                             note: nil, snapshot: "Du er den dårligste golferen i klubben, slutt nå",
                             status: .open, createdAt: now.addingTimeInterval(-20 * 3600)),
            ContentReportRow(id: UUID(), kind: .image, targetID: UUID(), clubID: nil, reason: .inappropriateImage,
                             note: nil, snapshot: nil, status: .open, createdAt: now.addingTimeInterval(-2 * 3600)),
            ContentReportRow(id: UUID(), kind: .member, targetID: UUID(), clubID: nil, reason: .impersonation,
                             note: "Later som han er Viktor Hovland", snapshot: "Viktor H.",
                             status: .open, createdAt: now.addingTimeInterval(-600)),
        ]
    }
}
#endif
