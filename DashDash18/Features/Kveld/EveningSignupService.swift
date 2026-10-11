import Foundation
import Supabase

/// Lesing og skriving av påmeldingen (sql/045), med reserve for en database uten 045:
/// svarene hentes da uten ventelista, og svaret skrives med upsert rett i `signups` som før.
nonisolated enum EveningSignupService {
    // MARK: Lesing

    /// Svarene på kveldene. Med `waitlisted_at` og `late` når kolonnene finnes, ellers uten.
    static func signups(client: SupabaseClient, eventIDs: [UUID]) async throws -> [SignupRow] {
        guard !eventIDs.isEmpty else { return [] }
        do {
            return try await client.from("signups")
                .select(SignupRow.columnsWithWaitlist)
                .in("event_id", values: eventIDs.map(\.uuidString))
                .execute().value
        } catch let error as PostgrestError where isMissing(error) {
            return try await client.from("signups")
                .select(SignupRow.columns)
                .in("event_id", values: eventIDs.map(\.uuidString))
                .execute().value
        }
    }

    /// Innstillingene for kveldene. nil når sql/045 ikke er kjørt (eller noe feilet): da er
    /// påmeldingen som før, uten tak, frister og gjester.
    static func settings(client: SupabaseClient, eventIDs: [UUID]) async -> [UUID: EveningSettingsRow]? {
        guard !eventIDs.isEmpty else { return [:] }
        let rows: [EveningSettingsRow]? = try? await client.from("events")
            .select(EveningSettingsRow.columns)
            .in("id", values: eventIDs.map(\.uuidString))
            .execute().value
        return rows.map { Dictionary($0.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }) }
    }

    /// Gjestene på kveldene. Tom uten sql/045.
    static func guests(client: SupabaseClient, eventIDs: [UUID]) async -> [EventGuestRow] {
        guard !eventIDs.isEmpty else { return [] }
        let rows: [EventGuestRow]? = try? await client.from("event_guests")
            .select(EventGuestRow.columns)
            .in("event_id", values: eventIDs.map(\.uuidString))
            .order("created_at")
            .execute().value
        return rows ?? []
    }

    /// Hvem som har sett kveldene (arrangøren ser alle, andre bare seg selv). nil uten sql/045.
    static func views(client: SupabaseClient, eventIDs: [UUID]) async -> [UUID: Set<UUID>]? {
        guard !eventIDs.isEmpty else { return [:] }
        let rows: [EventViewRow]? = try? await client.from("event_views")
            .select(EventViewRow.columns)
            .in("event_id", values: eventIDs.map(\.uuidString))
            .execute().value
        return rows.map { Dictionary(grouping: $0, by: \.eventID).mapValues { Set($0.map(\.memberID)) } }
    }

    /// Loggen for kvelden, nyeste først.
    static func log(client: SupabaseClient, eventID: UUID) async throws(DataError) -> [SignupLogRow] {
        do {
            return try await client.from("signup_log")
                .select(SignupLogRow.columns)
                .eq("event_id", value: eventID)
                .order("changed_at", ascending: false)
                .limit(200)
                .execute().value
        } catch {
            throw DataError.from(error)
        }
    }

    // MARK: Skriving

    /// Svarer for deg selv (`member` nil) eller, som arrangør, for et annet medlem. `status` nil
    /// fjerner svaret. `comment` nil beholder kommentaren, tom tekst tømmer den.
    /// Gir svaret fra `evening_signup`, eller nil når svaret ble skrevet på den gamle måten.
    @discardableResult
    static func answer(client: SupabaseClient, event: EventRow, member: UUID?, ownMemberID: UUID,
                       status: SignupStatus?, comment: String?) async throws(DataError) -> EveningSignupResult? {
        struct Params: Encodable {
            let p_event_id: UUID
            let p_status: String?
            let p_comment: String?
            let p_member_id: UUID?

            func encode(to encoder: any Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(p_event_id, forKey: .p_event_id)
                try c.encode(p_status, forKey: .p_status)
                try c.encode(p_comment, forKey: .p_comment)
                try c.encode(p_member_id, forKey: .p_member_id)
            }

            enum CodingKeys: String, CodingKey { case p_event_id, p_status, p_comment, p_member_id }
        }
        let params = Params(p_event_id: event.id, p_status: status?.rawValue, p_comment: comment,
                            p_member_id: member == ownMemberID ? nil : member)
        do {
            let result: EveningSignupResult = try await client.rpc("evening_signup", params: params).execute().value
            return result
        } catch let error as PostgrestError where isMissing(error) {
            try await answerDirectly(client: client, event: event, member: member ?? ownMemberID,
                                     status: status, comment: comment)
            return nil
        } catch {
            throw DataError.from(error)
        }
    }

    /// Reserven uten sql/045: upsert (eller sletting) rett i `signups`, som før.
    private static func answerDirectly(client: SupabaseClient, event: EventRow, member: UUID,
                                       status: SignupStatus?, comment: String?) async throws(DataError) {
        do {
            guard let status else {
                try await client.from("signups").delete()
                    .eq("event_id", value: event.id).eq("member_id", value: member)
                    .execute()
                return
            }
            let row = SignupUpsert(eventID: event.id, memberID: member, clubID: event.clubID, status: status,
                                   comment: comment.flatMap { SignupInput.cleanComment($0) })
            let saved: [SignupRow] = try await client.from("signups")
                .upsert(row, onConflict: "event_id,member_id")
                .select(SignupRow.columns)
                .execute().value
            guard !saved.isEmpty else { throw DataError.notAllowed }
        } catch {
            throw DataError.from(error)
        }
    }

    /// «Sett»: kalles når kvelden vises. Uten sql/045 skjer ingenting.
    static func markSeen(client: SupabaseClient, eventID: UUID) async {
        struct Params: Encodable { let p_event_id: UUID }
        _ = try? await client.rpc("evening_mark_seen", params: Params(p_event_id: eventID)).execute()
    }

    static func addGuest(client: SupabaseClient, eventID: UUID, name: String, invitedBy: UUID?) async throws(DataError) {
        struct Params: Encodable {
            let p_event_id: UUID
            let p_name: String
            let p_invited_by: UUID?
        }
        do {
            _ = try await client.rpc("evening_guest_add",
                                     params: Params(p_event_id: eventID, p_name: name, p_invited_by: invitedBy))
                .execute()
        } catch {
            throw guestError(error)
        }
    }

    static func removeGuest(client: SupabaseClient, guestID: UUID) async throws(DataError) {
        struct Params: Encodable { let p_guest_id: UUID }
        do {
            _ = try await client.rpc("evening_guest_remove", params: Params(p_guest_id: guestID)).execute()
        } catch {
            throw guestError(error)
        }
    }

    /// Arrangøren endrer tak, frister og gjester (vanlig update på `events`, sql/045).
    static func saveSettings(client: SupabaseClient, _ settings: EveningSettingsRow) async throws(DataError) {
        do {
            let saved: [EveningSettingsRow] = try await client.from("events")
                .update(EveningSettingsWrite(settings))
                .eq("id", value: settings.id)
                .select(EveningSettingsRow.columns)
                .execute().value
            guard !saved.isEmpty else { throw DataError.notAllowed }
        } catch {
            throw DataError.from(error)
        }
    }

    // MARK: Feil

    /// Funksjonen eller kolonnen finnes ikke (sql/045 ikke kjørt).
    static func isMissing(_ error: PostgrestError) -> Bool {
        isMissing(code: error.code)
    }

    /// PGRST202: ukjent funksjon. 42883: funksjonen finnes ikke. 42703: ukjent kolonne.
    /// PGRST204 og 42P01: ukjent kolonne eller tabell.
    static func isMissing(code: String?) -> Bool {
        ["PGRST202", "42883", "42703", "PGRST204", "42P01"].contains(code ?? "")
    }

    private static func guestError(_ error: any Error) -> DataError {
        let mapped = DataError.from(error)
        if mapped == .duplicate { return .invalid("En gjest med det navnet er alt påmeldt.") }
        if let postgrest = error as? PostgrestError, isMissing(postgrest) {
            return .invalid("Gjester er ikke slått på ennå.")
        }
        return mapped
    }
}
