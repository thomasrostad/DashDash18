import SwiftUI
import Testing
import UIKit
@testable import DashDash18

/// Ingen kort på Hjem kan være bredere enn skjermen: da kan hele feeden dras sideveis (16.10.2026).
@MainActor
struct HjemBreddeTests {
    private func width(_ view: some View, available: CGFloat, size: DynamicTypeSize = .large) -> CGFloat {
        let host = UIHostingController(rootView: view.dynamicTypeSize(size))
        return host.sizeThatFits(in: CGSize(width: available, height: .greatestFiniteMagnitude)).width
    }

    /// Lange turneringsnavn: kildepillen krymper ikke, så de er verst for bredden.
    private func longNames() -> HomeFeedModel {
        var raw = HjemSamples.raw(now: .now)
        raw.competitions = raw.competitions.map { var c = $0; c.name = "Golfgutu Invitational høstsesongen 2026 – \(c.name)"; return c }
        return HomeFeedModel(preview: raw, viewer: HjemSamples.viewer, clubs: HjemSamples.clubs,
                             lastSeen: Date.now.addingTimeInterval(-2 * 86_400))
    }

    @Test(arguments: [DynamicTypeSize.large, .xxxLarge, .accessibility2], [false, true])
    func kortenePasserISkjermen(size: DynamicTypeSize, long: Bool) {
        let model = long ? longNames() : HjemSamples.model()
        let available: CGFloat = 375 - 2 * DDSpacing.gutter
        var report: [String] = []
        for section in model.feed.sections {
            for card in section.cards {
                let w = width(HjemCardView(card: card, actions: HjemActions()), available: available, size: size)
                report.append("\(card.content) → \(w)")
                #expect(w <= available + 0.5, "\(section.title): \(card.content) er \(w) bred, plass til \(available)")
            }
        }
        print("HJEMBREDDE \(size):\n" + report.joined(separator: "\n"))
    }

    private func scrollViews(in view: UIView) -> [UIScrollView] {
        (view as? UIScrollView).map { [$0] } ?? [] + view.subviews.flatMap(scrollViews)
    }

    /// Hele feeden som på telefonen (iPhone 17 Pro): rullelista skal ikke ha innhold bredere enn seg selv.
    @Test(arguments: [DynamicTypeSize.large, .xxxLarge], [false, true])
    func feedenRullerIkkeSideveis(size: DynamicTypeSize, long: Bool) throws {
        let model = long ? longNames() : HjemSamples.model()
        var tab = HjemFeedTab.club
        let actions = HjemActions(organizer: HjemOrganizerStep(title: "Se resultatet", hint: "", perform: {}),
                                  invite: HjemInvite(clubName: "Golfgutu Invitational",
                                                     invite: ClubInvite(code: "A1B2C3D4E5")!, activeMembers: 2),
                                  startRound: {})
        let view = NavigationStack {
            HjemFeedView(feed: model.feed, actions: actions,
                         tabPicker: Binding(get: { tab }, set: { tab = $0 }))
                .navigationTitle("Hjem")
        }
        .dynamicTypeSize(size)
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        let host = UIHostingController(rootView: view)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        host.view.layoutIfNeeded()
        let main = scrollViews(in: host.view).max { $0.bounds.height < $1.bounds.height }
        let report = scrollViews(in: host.view).map { "\($0.bounds.width)x\($0.bounds.height) innhold \($0.contentSize.width)" }
        print("HJEMRULL \(size): " + report.joined(separator: " | "))
        #expect(main != nil, "Fant ingen rulleliste")
        if let main {
            #expect(main.contentSize.width <= main.bounds.width + 0.5,
                    "Innholdet er \(main.contentSize.width) bredt i en rulleliste på \(main.bounds.width)")
        }
    }
}
