import Foundation
import Supabase

/// Kallene for «Del regningen» lagret og kalenderlenken (sql/051). Mangler 051 (tabellen eller
/// funksjonen), skjules det nye: regningen deles som før uten lagring, og kalenderen vises ikke.
nonisolated enum BillService {
    /// Finnes ikke tabellen eller funksjonen (051 er ikke kjørt)?
    static func isMissing(_ error: any Error) -> Bool {
        ReuseService.isMissing(error)
    }

    /// Finnes regningene på serveren? false bare når 051 mangler. En annen feil (nettet) gir true,
    /// så feilen vises når du prøver.
    static func isAvailable(client: SupabaseClient) async -> Bool {
        do {
            _ = try await client.from("bill_splits").select("id", head: true).limit(1).execute()
            return true
        } catch {
            return !isMissing(error)
        }
    }

    // MARK: Lagre

    /// Det som trengs for å lagre: hvor regningen hører til, og hvem du er.
    struct SaveContext: Sendable {
        let client: SupabaseClient
        let userID: UUID
        var clubID: UUID?
        var eventID: UUID?
        var roundID: UUID?
    }

    struct CreateResult: Decodable, Sendable {
        let splitID: UUID

        enum CodingKeys: String, CodingKey {
            case splitID = "split_id"
        }
    }

    /// `bill_split_create`. `payeeVipps` sendes bare når du selv er mottakeren (serveren krever det).
    static func create(context: SaveContext, title: String, total: NOK, payee: BillPerson, payeeShare: NOK,
                       shares: [(person: BillPerson, amount: NOK)], payeeVipps: String?) async throws(DataError) -> UUID {
        struct Share: Encodable {
            let profile_id: UUID?
            let name: String
            let amount_ore: Int
        }
        struct Params: Encodable {
            let p_title: String
            let p_total_ore: Int
            let p_payee_name: String
            let p_shares: [Share]
            let p_payee_profile_id: UUID?
            let p_payee_share_ore: Int
            let p_payee_vipps: String?
            let p_club_id: UUID?
            let p_event_id: UUID?
            let p_round_id: UUID?

            func encode(to encoder: any Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(p_title, forKey: .p_title)
                try c.encode(p_total_ore, forKey: .p_total_ore)
                try c.encode(p_payee_name, forKey: .p_payee_name)
                try c.encode(p_shares, forKey: .p_shares)
                try c.encode(p_payee_profile_id, forKey: .p_payee_profile_id)
                try c.encode(p_payee_share_ore, forKey: .p_payee_share_ore)
                try c.encode(p_payee_vipps, forKey: .p_payee_vipps)
                try c.encode(p_club_id, forKey: .p_club_id)
                try c.encode(p_event_id, forKey: .p_event_id)
                try c.encode(p_round_id, forKey: .p_round_id)
            }

            enum CodingKeys: String, CodingKey {
                case p_title, p_total_ore, p_payee_name, p_shares, p_payee_profile_id, p_payee_share_ore
                case p_payee_vipps, p_club_id, p_event_id, p_round_id
            }
        }
        let vipps = payee.profileID == context.userID ? payeeVipps : nil
        let params = Params(
            p_title: title, p_total_ore: total.ore, p_payee_name: BillSplit.storedName(payee.name),
            p_shares: shares.map { Share(profile_id: $0.person.profileID, name: BillSplit.storedName($0.person.name),
                                         amount_ore: $0.amount.ore) },
            p_payee_profile_id: payee.profileID, p_payee_share_ore: payeeShare.ore, p_payee_vipps: vipps,
            p_club_id: context.clubID, p_event_id: context.eventID, p_round_id: context.roundID)
        do {
            let result: CreateResult = try await context.client.rpc("bill_split_create", params: params).execute().value
            return result.splitID
        } catch {
            throw DataError.from(error)
        }
    }

    // MARK: Lese

    /// Regningene du er med på (RLS: den som laget den, mottakeren og de som skal betale), nyeste først.
    static func settlements(client: SupabaseClient) async throws(DataError) -> [BillSettlement] {
        do {
            let splits: [BillSplitRow] = try await client.from("bill_splits")
                .select(BillSplitRow.columns)
                .order("created_at", ascending: false)
                .limit(100)
                .execute().value
            guard !splits.isEmpty else { return [] }
            let shares: [BillShareRow] = try await client.from("bill_split_shares")
                .select(BillShareRow.columns)
                .in("split_id", values: splits.map(\.id))
                .execute().value
            return BillSettlement.group(splits: splits, shares: shares)
        } catch {
            throw DataError.from(error)
        }
    }

    // MARK: Status

    /// `bill_share_mark_sent`: din del er sendt (etter Vipps). Idempotent på serveren.
    static func markSent(client: SupabaseClient, shareID: UUID) async throws(DataError) {
        struct Params: Encodable { let p_share_id: UUID }
        do {
            try await client.rpc("bill_share_mark_sent", params: Params(p_share_id: shareID)).execute()
        } catch {
            throw DataError.from(error)
        }
    }

    /// `bill_share_confirm`: «Fikk den» (true) eller «Kom ikke» (false). Bare mottakeren.
    static func confirm(client: SupabaseClient, shareID: UUID, received: Bool) async throws(DataError) {
        struct Params: Encodable {
            let p_share_id: UUID
            let p_received: Bool
        }
        do {
            try await client.rpc("bill_share_confirm", params: Params(p_share_id: shareID, p_received: received)).execute()
        } catch {
            throw DataError.from(error)
        }
    }

    /// `bill_split_delete`: bare den som laget den, og bare før noen del er bekreftet.
    static func delete(client: SupabaseClient, splitID: UUID) async throws(DataError) {
        struct Params: Encodable { let p_split_id: UUID }
        do {
            try await client.rpc("bill_split_delete", params: Params(p_split_id: splitID)).execute()
        } catch {
            throw DataError.from(error)
        }
    }
}

/// Kalenderlenken (sql/051): `calendar_token`, `calendar_token_revoke`.
nonisolated enum CalendarService {
    /// Finnes kalenderen på serveren? Spør `calendar_feed` med et token som ikke finnes: svaret er
    /// «fant ingen» (P0002) når 051 er kjørt, og «ukjent funksjon» når den mangler. Lager ingenting.
    static func isAvailable(client: SupabaseClient) async -> Bool {
        struct Params: Encodable { let p_token: String }
        do {
            try await client.rpc("calendar_feed", params: Params(p_token: "-")).execute()
            return true
        } catch {
            return !BillService.isMissing(error)
        }
    }

    /// Ditt token. `renew` gir et nytt, og det gamle slutter å virke.
    static func token(client: SupabaseClient, renew: Bool = false) async throws(DataError) -> String {
        struct Params: Encodable { let p_renew: Bool }
        do {
            return try await client.rpc("calendar_token", params: Params(p_renew: renew)).execute().value
        } catch {
            throw DataError.from(error)
        }
    }

    /// Skrur av lenken. `token()` gir en ny senere.
    static func revoke(client: SupabaseClient) async throws(DataError) {
        do {
            try await client.rpc("calendar_token_revoke").execute()
        } catch {
            throw DataError.from(error)
        }
    }
}
