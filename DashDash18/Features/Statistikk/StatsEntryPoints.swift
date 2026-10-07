import SwiftUI

/// «Statistikk» under Deg: lenken til din statistikk og bryteren for føring per hull.
struct StatsDegSection: View {
    let context: ClubContext
    @Environment(ClubModel.self) private var club
    @State private var trackHoles = false

    var body: some View {
        Section {
            NavigationLink {
                StatsView(model: StatsModel(client: context.client, scope: scope))
            } label: {
                Label("Statistikk", systemImage: "chart.xyaxis.line")
                    .labelStyle(DDIconLabelStyle())
            }
            Toggle("Før fairway, green og putter", isOn: $trackHoles)
                .onChange(of: trackHoles) { _, on in HoleStatsSetting().set(on, for: context.user.id) }
        } header: {
            DDHeader("Statistikk")
        } footer: {
            DDFooter("Valgfritt. En liten rad under slagtelleren mens du spiller. Gjelder bare deg, på denne telefonen.")
        }
        .onAppear { trackHoles = HoleStatsSetting().isOn(for: context.user.id) }
    }

    private var scope: StatsScope {
        let active = club.memberships.filter { $0.status == .active }
        return .me(userID: context.user.id, memberIDs: active.map(\.id),
                   clubNames: Dictionary(active.map { ($0.clubID, $0.club.name) }, uniquingKeysWith: { a, _ in a }))
    }
}

/// Lenken fra spillerprofilen på Tavla: spillerens runder i klubben.
struct StatsProfileLink: View {
    let memberID: UUID
    let name: String
    @Environment(\.clubContext) private var context

    var body: some View {
        if let context {
            NavigationLink {
                StatsView(model: StatsModel(client: context.client,
                                            scope: .member(memberID: memberID, clubID: context.clubID,
                                                           clubName: context.membership.club.name)),
                          title: context.memberID == memberID ? "Statistikk" : "Statistikk · \(name)")
            } label: {
                HStack {
                    Label("Statistikk", systemImage: "chart.xyaxis.line")
                        .labelStyle(DDIconLabelStyle())
                        .font(.ddBody)
                        .foregroundStyle(Color.ddInk)
                    Spacer()
                    Image(systemName: "chevron.right").imageScale(.small).foregroundStyle(Color.ddInkSecondary)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .ddCard(padding: DDSpacing.l)
        }
    }
}
