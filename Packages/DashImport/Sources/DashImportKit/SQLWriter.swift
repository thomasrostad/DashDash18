import Foundation

/// Skriver planen som én SQL-fil: én transaksjon, `insert … on conflict … do update/do nothing`,
/// og opprydding av rader under importerte runder og kvelder som ikke lenger finnes i PWA-en.
/// Ingen tidsstempel fra kjøringen i fila: samme plan gir byte for byte samme SQL.
public enum SQLWriter {
    public static func write(_ plan: ImportPlan, sourceChecksum: String? = nil) -> String {
        var out: [String] = []
        func emit(_ s: String) { out.append(s) }

        emit("""
        -- ===========================================================================
        -- Import fra Golfgutu-PWA-en til DashDash18 (fase 9). GENERERT av dashimport.
        -- ===========================================================================
        -- INNEHOLDER NAVN. Skal ikke i git. Kjøres bare etter godkjenning, først på
        -- appens TEST-prosjekt (tsekialrxuhrugscosgi), aldri på PWA-basen.
        -- Idempotent: kan kjøres flere ganger. Rader under importerte runder og kvelder
        -- som ikke lenger finnes i PWA-en, slettes (PWA-en er fasit fram til byttet).
        -- Innlogging (user_id) og invitasjonskoden røres aldri.
        --
        -- Kilde (SHA-1 av snapshot.json): \(sourceChecksum ?? "ukjent")
        -- Klubb: \(plan.club.id.uuidString.lowercased())\(plan.clubExists ? " (finnes fra før)" : " (ny)")
        -- Rader: \(plan.members.count) spillere, \(plan.courses.count) baner, \(plan.courseHoles.count) banehull, \
        \(plan.events.count) kvelder, \(plan.signups.count) påmeldinger, \(plan.rounds.count) runder, \
        \(plan.roundPlayers.count) deltakere, \(plan.matches.count) matcher, \(plan.scores.count) scorer, \
        \(plan.sideClaims.count) sidepremier, \(plan.tips.count) tips, \(plan.threadMessages.count) meldinger.
        -- ===========================================================================

        begin;

        -- Vern: dette skal aldri kjøres mot PWA-basen, og appens skjema må finnes.
        do $guard$
        begin
          if to_regclass('public.players') is not null or to_regclass('public.round_points') is not null then
            raise exception 'Dette ser ut som PWA-basen. Importen skal kjøres mot appens database.';
          end if;
          if to_regclass('public.club_members') is null or to_regclass('public.thread_messages') is null then
            raise exception 'Appens skjema (sql/001–011) mangler.';
          end if;
        end
        $guard$;

        """)

        let club = q(plan.club.id)
        if plan.clubExists {
            emit("""
            do $club$
            begin
              if not exists (select 1 from public.clubs where id = \(club)) then
                raise exception 'Fant ikke klubben \(plan.club.id.uuidString.lowercased())';
              end if;
            end
            $club$;

            """)
        } else {
            emit("-- Klubben. Finnes den, røres den ikke (navn og invitasjonskode beholdes).")
            emit(upsert("clubs", ["id", "name"], [[club, q(plan.club.name)]], conflict: "id", update: nil))
        }

        emit("-- Troppen. Uten user_id: hver spiller tar navnet sitt ved første innlogging (join_club).")
        emit(upsert("club_members",
                    ["id", "club_id", "display_name", "handicap_index", "seed_group", "is_organizer", "is_treasurer", "status", "created_at"],
                    plan.members.map { m in
                        [q(m.id), club, q(m.displayName), q(m.handicapIndex), q(m.seedGroup), q(m.isOrganizer),
                         q(m.isTreasurer), q("active"), ts(m.createdAt, default: "now()")]
                    },
                    conflict: "id",
                    update: ["display_name", "handicap_index", "seed_group", "is_organizer", "is_treasurer"]))

        emit("-- Sesongen med Golfgutu-regelsettet. Regelsettet overskrives ikke ved ny import.")
        emit(upsert("seasons", ["id", "club_id", "name", "status", "rules"],
                    [[q(plan.season.id), club, q(plan.season.name), q(plan.season.status), q(plan.season.rulesJSON) + "::jsonb"]],
                    conflict: "id", update: ["name", "status"]))

        emit("-- Banebiblioteket.")
        emit(upsert("courses",
                    ["id", "club_id", "name", "external_name", "course_rating", "slope_rating", "in_use", "confirmed_by", "confirmed_at", "created_at"],
                    plan.courses.map { c in
                        [q(c.id), club, q(c.name), q(c.externalName), q(c.courseRating), q(c.slopeRating), q(c.inUse),
                         q(c.confirmedBy), ts(c.confirmedAt), ts(c.createdAt, default: "now()")]
                    },
                    conflict: "id",
                    update: ["name", "external_name", "course_rating", "slope_rating", "in_use", "confirmed_by", "confirmed_at"]))
        emit(deleteMissing("course_holes", scope: "course_id", scopeIDs: plan.courses.map(\.id),
                           keys: ["course_id", "hole_number"],
                           rows: plan.courseHoles.map { [q($0.courseID), q($0.holeNumber) + "::smallint"] }))
        emit(upsert("course_holes", ["course_id", "hole_number", "par", "stroke_index", "length_m"],
                    plan.courseHoles.map { [q($0.courseID), q($0.holeNumber), q($0.par), q($0.strokeIndex), q($0.lengthM)] },
                    conflict: "course_id, hole_number", update: ["par", "stroke_index", "length_m"]))

        emit("-- Terminlista. Innsatsen (kroner i PWA-en) tas ikke med (B10).")
        emit(upsert("events", ["id", "club_id", "season_id", "event_date", "start_time", "tips_line"],
                    plan.events.map { e in
                        [q(e.id), club, q(plan.season.id), q(e.eventDate) + "::date",
                         e.startTime.map { q($0) + "::time" } ?? "null", q(e.tipsLine)]
                    },
                    conflict: "id", update: ["season_id", "event_date", "start_time", "tips_line"]))
        let eventIDs = plan.events.map(\.id)
        emit(deleteMissing("event_committee", scope: "event_id", scopeIDs: eventIDs, keys: ["event_id", "member_id"],
                           rows: plan.committee.map { [q($0.eventID), q($0.memberID)] }))
        emit(upsert("event_committee", ["event_id", "member_id", "club_id"],
                    plan.committee.map { [q($0.eventID), q($0.memberID), club] },
                    conflict: "event_id, member_id", update: nil))
        emit(deleteMissing("signups", scope: "event_id", scopeIDs: eventIDs, keys: ["event_id", "member_id"],
                           rows: plan.signups.map { [q($0.eventID), q($0.memberID)] }))
        emit(upsert("signups", ["event_id", "member_id", "club_id", "status", "comment", "created_at"],
                    plan.signups.map { [q($0.eventID), q($0.memberID), club, q($0.status), q($0.comment), ts($0.createdAt, default: "now()")] },
                    conflict: "event_id, member_id", update: ["status", "comment"]))

        emit("-- Rundene.")
        let roundColumns = ["id", "club_id", "event_id", "course_id", "round_no", "name", "status", "hole_count", "first_hole",
                            "tee_time", "format", "handicap_allowance", "external_handicap", "weight",
                            "ld_enabled", "ld_hole_index", "kp_enabled", "kp_hole_index",
                            "cut_rule", "cut_after", "cut_by", "cut_at", "par_confirmed_by", "par_confirmed_at",
                            "started_at", "locked_at", "created_at"]
        emit(upsert("rounds", roundColumns,
                    plan.rounds.map { r in
                        [q(r.id), club, q(r.eventID), q(r.courseID), q(r.roundNo), q(r.name), q(r.status), q(r.holeCount),
                         q(r.firstHole), r.teeTime.map { q($0) + "::time" } ?? "null", q(r.format), q(r.handicapAllowance),
                         q(r.externalHandicap), q(r.weight), q(r.ldEnabled), q(r.ldHoleIndex), q(r.kpEnabled), q(r.kpHoleIndex),
                         q(r.cutRule), q(r.cutAfter), q(r.cutBy), ts(r.cutAt), q(r.parConfirmedBy), ts(r.parConfirmedAt),
                         ts(r.startedAt), ts(r.lockedAt), ts(r.createdAt, default: "now()")]
                    },
                    conflict: "id", update: Array(roundColumns.dropFirst(2).filter { $0 != "created_at" })))

        let roundIDs = plan.rounds.map(\.id)
        emit("-- Rydd under de importerte rundene: det som ikke lenger finnes i PWA-en.")
        emit(deleteMissing("side_claims", scope: "round_id", scopeIDs: roundIDs, keys: ["id"],
                           rows: plan.sideClaims.map { [q($0.id)] }))
        emit(deleteMissing("hole_scores", scope: "round_id", scopeIDs: roundIDs, keys: ["round_id", "member_id", "hole_index"],
                           rows: plan.scores.map { [q($0.roundID), q($0.memberID), q($0.holeIndex) + "::smallint"] }))
        emit(deleteMissing("round_matches", scope: "round_id", scopeIDs: roundIDs, keys: ["round_id", "match_no"],
                           rows: plan.matches.map { [q($0.roundID), q($0.matchNo) + "::smallint"] }))
        emit(deleteMissing("round_players", scope: "round_id", scopeIDs: roundIDs, keys: ["round_id", "member_id"],
                           rows: plan.roundPlayers.map { [q($0.roundID), q($0.memberID)] }))
        emit(deleteMissing("round_holes", scope: "round_id", scopeIDs: roundIDs, keys: ["round_id", "hole_index"],
                           rows: plan.roundHoles.map { [q($0.roundID), q($0.holeIndex) + "::smallint"] }))
        if !roundIDs.isEmpty {
            emit("-- Markørene settes på nytt under (én per bås), så en flyttet markør ikke kolliderer.")
            emit("update public.round_players set is_marker = false\n where round_id = any(\(uuidArray(roundIDs))) and is_marker;\n")
        }

        emit("-- Deltakere med bås, markør og lag. Handicapet fryses med PWA-ens nåværende tall (B16).")
        emit(upsert("round_players", ["round_id", "member_id", "club_id", "handicap_index", "seed_group", "bay_no", "is_marker", "team_no"],
                    plan.roundPlayers.map { p in
                        [q(p.roundID), q(p.memberID), club, q(p.handicapIndex), q(p.seedGroup), q(p.bayNo), q(p.isMarker), q(p.teamNo)]
                    },
                    conflict: "round_id, member_id", update: ["handicap_index", "seed_group", "bay_no", "is_marker", "team_no"]))
        emit(upsert("round_holes", ["round_id", "hole_index", "par", "stroke_index", "length_m"],
                    plan.roundHoles.map { [q($0.roundID), q($0.holeIndex), q($0.par), q($0.strokeIndex), q($0.lengthM)] },
                    conflict: "round_id, hole_index", update: ["par", "stroke_index", "length_m"]))
        emit(upsert("round_matches", ["round_id", "match_no", "player_a", "player_b", "player_c", "team_a", "team_b", "result"],
                    plan.matches.map { m in
                        [q(m.roundID), q(m.matchNo), q(m.playerA), q(m.playerB), q(m.playerC), q(m.teamA), q(m.teamB), q(m.result)]
                    },
                    conflict: "round_id, match_no", update: ["player_a", "player_b", "player_c", "team_a", "team_b", "result"]))

        emit("-- Scorer (brutto slag). Poeng lagres ikke; appen regner dem.")
        emit(upsert("hole_scores", ["round_id", "member_id", "hole_index", "strokes", "recorded_at"],
                    plan.scores.map { [q($0.roundID), q($0.memberID), q($0.holeIndex), q($0.strokes), ts($0.recordedAt, default: "now()")] },
                    conflict: "round_id, member_id, hole_index", update: ["strokes", "recorded_at"]))
        emit(upsert("side_claims", ["id", "round_id", "member_id", "kind", "meters", "hole_index", "created_at"],
                    plan.sideClaims.map { c in
                        [q(c.id), q(c.roundID), q(c.memberID), q(c.kind), q(c.meters), q(c.holeIndex), ts(c.createdAt, default: "now()")]
                    },
                    conflict: "id", update: ["meters", "hole_index"]))

        emit("-- Tippekupongen.")
        emit(upsert("tips", ["event_id", "member_id", "club_id", "winner", "front_nine", "most_pars", "birdie", "over_line"],
                    plan.tips.map { t in
                        [q(t.eventID), q(t.memberID), club, q(t.winner), q(t.frontNine), q(t.mostPars), q(t.birdie), q(t.overLine)]
                    },
                    conflict: "event_id, member_id", update: ["winner", "front_nine", "most_pars", "birdie", "over_line"]))

        emit("-- Kveldens tråd. pushed_at er satt, så ingen gammel melding sendes som push.")
        emit(upsert("thread_messages", ["id", "club_id", "event_id", "member_id", "body", "mentions", "created_at", "pushed_at"],
                    plan.threadMessages.map { m in
                        let created = ts(m.createdAt, default: "now()")
                        return [q(m.id), club, q(m.eventID), q(m.memberID), q(m.body), uuidArray(m.mentions), created, created]
                    },
                    conflict: "id", update: nil))

        emit("""
        commit;

        -- Kontroll (kjør etterpå): antall rader i den importerte klubben.
        -- select
        --   (select count(*) from public.club_members where club_id = \(club)) as spillere,
        --   (select count(*) from public.club_members where club_id = \(club) and user_id is not null) as innlogget,
        --   (select count(*) from public.events where club_id = \(club)) as kvelder,
        --   (select count(*) from public.rounds where club_id = \(club)) as runder,
        --   (select count(*) from public.hole_scores s join public.rounds r on r.id = s.round_id where r.club_id = \(club)) as scorer,
        --   (select join_code from public.clubs where id = \(club)) as invitasjonskode;
        -- Forventet: \(plan.members.count) spillere, \(plan.events.count) kvelder, \(plan.rounds.count) runder, \(plan.scores.count) scorer.
        """)
        return out.joined(separator: "\n") + "\n"
    }

    // MARK: Byggeklosser

    static func upsert(_ table: String, _ columns: [String], _ rows: [[String]], conflict: String, update: [String]?) -> String {
        guard !rows.isEmpty else { return "-- \(table): ingen rader.\n" }
        let action: String
        if let update, !update.isEmpty {
            action = "do update set\n  " + update.map { "\($0) = excluded.\($0)" }.joined(separator: ",\n  ")
        } else {
            action = "do nothing"
        }
        var parts: [String] = []
        for start in stride(from: 0, to: rows.count, by: 500) {
            let chunk = rows[start..<min(rows.count, start + 500)]
            parts.append("""
            insert into public.\(table) (\(columns.joined(separator: ", "))) values
              \(chunk.map { "(" + $0.joined(separator: ", ") + ")" }.joined(separator: ",\n  "))
            on conflict (\(conflict)) \(action);

            """)
        }
        return parts.joined(separator: "\n")
    }

    /// Sletter rader i `scope` som ikke står i `rows` (nøklene i `keys`).
    static func deleteMissing(_ table: String, scope: String, scopeIDs: [UUID], keys: [String], rows: [[String]]) -> String {
        guard !scopeIDs.isEmpty else { return "" }
        var sql = "delete from public.\(table) t\n where t.\(scope) = any(\(uuidArray(scopeIDs)))"
        if !rows.isEmpty {
            let values = rows.map { "(" + $0.joined(separator: ", ") + ")" }.joined(separator: ",\n         ")
            let match = keys.map { "k.\($0) = t.\($0)" }.joined(separator: " and ")
            sql += "\n   and not exists (\n     select 1 from (values\n         \(values)\n     ) as k(\(keys.joined(separator: ", "))) where \(match))"
        }
        return sql + ";\n"
    }

    static func uuidArray(_ ids: [UUID]) -> String {
        guard !ids.isEmpty else { return "'{}'::uuid[]" }
        return "array[" + ids.map(q).joined(separator: ", ") + "]::uuid[]"
    }

    // MARK: Literaler

    static func q(_ s: String?) -> String {
        guard let s else { return "null" }
        return "'" + s.replacingOccurrences(of: "'", with: "''") + "'"
    }

    static func q(_ id: UUID?) -> String {
        guard let id else { return "null" }
        return "'\(id.uuidString.lowercased())'::uuid"
    }

    static func q(_ x: Int?) -> String { x.map(String.init) ?? "null" }
    static func q(_ b: Bool?) -> String { b.map { $0 ? "true" : "false" } ?? "null" }

    static func q(_ x: Double?) -> String {
        guard let x, x.isFinite else { return "null" }
        if x == x.rounded() && abs(x) < 1e15 { return String(Int(x)) }
        return String(x)
    }

    /// Tidsstempel fra PWA-en. Godtar bare ISO-lignende tekst; ellers `default`.
    static func ts(_ s: String?, default fallback: String = "null") -> String {
        guard let s, s.range(of: #"^\d{4}-\d{2}-\d{2}([T ][0-9:.]+([+-]\d{2}(:?\d{2})?|Z)?)?$"#, options: .regularExpression) != nil else {
            return fallback
        }
        return q(s) + "::timestamptz"
    }
}
