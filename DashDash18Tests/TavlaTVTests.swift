import Foundation
import Testing
@testable import DashDash18

/// TV-visningen: tabellen side for side og siste runde.
@MainActor struct TavlaTVTests {
    @Test func sider() {
        #expect(TavlaTV.pages(count: 0, perPage: 8).isEmpty)
        #expect(TavlaTV.pages(count: 8, perPage: 8) == [0..<8])
        #expect(TavlaTV.pages(count: 19, perPage: 8) == [0..<8, 8..<16, 16..<19])
    }

    @Test func sisteRundeBesteFørst() throws {
        let latest = try #require(TavlaTV.latestRound(TavlaSamples.standings().roundGrid, limit: 3))
        #expect(latest.lines.count == 3)
        #expect(latest.lines.map(\.points) == latest.lines.map(\.points).sorted(by: >))
    }
}
