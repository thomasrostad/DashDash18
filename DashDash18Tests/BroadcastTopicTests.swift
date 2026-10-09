import Foundation
import Testing
@testable import DashDash18

/// Kanalnavnene må stemme med triggerne og policyen i sql/040 (`round:<uuid>`, `club:<uuid>`, små bokstaver).
struct BroadcastTopicTests {
    @Test func kanalnavnene() throws {
        let id = try #require(UUID(uuidString: "0A0A0A0A-0000-4000-8000-0000000000A1"))
        #expect(BroadcastTopic.round(id) == "round:0a0a0a0a-0000-4000-8000-0000000000a1")
        #expect(BroadcastTopic.club(id) == "club:0a0a0a0a-0000-4000-8000-0000000000a1")
        #expect(BroadcastTopic.event == "change")
        // Samme mønster som can_listen_topic i 040.
        #expect(BroadcastTopic.round(id).wholeMatch(of: /round:[0-9a-f-]{36}/) != nil)
    }

    @Test func flaggetErAvTil040ErKjørt() {
        #expect(BroadcastFeature.isEnabled == false)
    }
}
