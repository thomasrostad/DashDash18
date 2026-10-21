import Foundation
import Observation
import Supabase

// Noen vil bli med i klubben (1.0.1, sql/067): varsel i bjella og push til dem med Medlemmer og
// invitasjon, trykk åpner Arrangør → Troppen, og et merke med antall ventende på Arrangør-fanen
// og i arrangørsiden.

/// Varselet og merket for ventende medlemmer. Krever `sql/067_varsel_ventende_medlem.sql`
/// (hendelsen `member_pending`) og push-send deployet med teksten. Av til 067 er kjørt på test og
/// prod; uten 067 kommer det verken varsel eller push, og merket ville vært det eneste som viste
/// noe nytt.
nonisolated enum PendingMembersFeature {
    static let flag = false
    static let isEnabled = flag
}

/// Tekstene og regelen for merket. Ren.
nonisolated enum PendingMembers {
    /// Tallet på merket, eller 0 når det ikke skal vises: flagget av, eller ingen rettighet til troppen.
    static func badge(count: Int, canManage: Bool, enabled: Bool = PendingMembersFeature.isEnabled) -> Int {
        enabled && canManage ? max(count, 0) : 0
    }

    /// Raden øverst på arrangørsiden: «Ola Nordmann vil bli med» eller «3 vil bli med i klubben».
    static func rowTitle(count: Int, firstName: String?) -> String {
        if count == 1, let name = firstName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return "\(name) vil bli med"
        }
        return "\(count) vil bli med i klubben"
    }

    static let rowSubtitle = "Godkjenn eller avvis i Troppen."

    /// «Troppen (2 venter)» i ⋯-menyen.
    static func menuTitle(_ title: String, count: Int) -> String {
        count > 0 ? "\(title) (\(count) venter)" : title
    }
}

/// De som venter i den valgte klubben (`club_members` med status pending). Hentes bare for dem med
/// rettigheten Medlemmer og invitasjon, og bare når flagget er på. RLS gir de ventende radene til
/// arrangøren; for andre blir lista tom.
@MainActor @Observable
final class PendingMembersModel {
    let client: SupabaseClient
    let clubID: UUID
    let canManage: Bool
    private(set) var names: [String] = []

    var count: Int { names.count }
    /// Tallet på merket (`PendingMembers.badge`).
    var badge: Int { PendingMembers.badge(count: count, canManage: canManage) }

    init(client: SupabaseClient, clubID: UUID, canManage: Bool) {
        self.client = client
        self.clubID = clubID
        self.canManage = canManage
    }

    /// Henter på nytt. Feiler det (ingen dekning), står forrige tall.
    func load() async {
        guard PendingMembersFeature.isEnabled, canManage else {
            names = []
            return
        }
        do {
            let rows: [PendingMemberName] = try await client
                .from("club_members")
                .select("display_name")
                .eq("club_id", value: clubID.uuidString)
                .eq("status", value: "pending")
                .order("created_at")
                .limit(100)
                .execute().value
            names = rows.map(\.displayName)
        } catch {
            // Behold det vi hadde.
        }
    }
}

private nonisolated struct PendingMemberName: Decodable, Sendable {
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }
}
