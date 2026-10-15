import Foundation
import Observation
import Supabase

/// Det «I kveld» trenger mens runden går, utover det `RundeAdminModel` har: scorene med tidspunkt,
/// startlista (tid, starthull, funksjonær) og innmeldte sidepremier. Bare lesing. Feiler hentingen,
/// står det som sist, og båsene vises uten synkstatus.
@Observable
final class TonightLiveModel {
    private(set) var scores: [HoleScoreRow] = []
    private(set) var groups: [UUID: [StartGroupDraft]] = [:]
    private(set) var claims: [SideClaimRow] = []
    private(set) var scorerNames: [UUID: String] = [:]
    /// Åpne markørkonflikter i rundene (K6/6.3, sql/055): nyeste per spiller og hull.
    private(set) var conflicts: [HoleConflictRow] = []
    /// Klokka båsene regnes mot. Oppdateres ved hver henting.
    private(set) var now: Date
    /// Har vi hentet minst én gang? Uten det står synklinja som ukjent.
    private(set) var hasLoaded = false

    private let client: SupabaseClient?

    init(client: SupabaseClient) {
        self.client = client
        now = .now
    }

    #if DEBUG
    /// Skjermprøvene, uten nett.
    init(preview scores: [HoleScoreRow], groups: [UUID: [StartGroupDraft]] = [:], claims: [SideClaimRow] = [],
         scorerNames: [UUID: String] = [:], conflicts: [HoleConflictRow] = [], now: Date) {
        client = nil
        self.conflicts = MarkerConflicts.open(conflicts)
        self.scores = scores
        self.groups = groups
        self.claims = claims
        self.scorerNames = scorerNames
        self.now = now
        hasLoaded = true
    }
    #endif

    /// Henter for rundene som går. `players` er deltakerne fra `RundeAdminModel`.
    func load(rounds: [RoundRow], players: [UUID: [RoundPlayerRow]]) async {
        guard let client else { return }
        let ids = rounds.map(\.id.uuidString)
        guard !ids.isEmpty else { return }
        do {
            async let scoreRows: [HoleScoreRow] = client.from("hole_scores")
                .select(HoleScoreRow.columns)
                .in("round_id", values: ids)
                .execute().value
            async let claimRows: [SideClaimRow] = client.from("side_claims")
                .select(SideClaimRow.columns)
                .in("round_id", values: ids)
                .execute().value
            async let conflictRows = MarkerConflictQueries.conflicts(client: client, roundIDs: rounds.map(\.id))
            scores = try await scoreRows
            claims = (try? await claimRows) ?? claims
            // Mangler tabellen (sql/055 ikke kjørt), står det som sist.
            if let rows = try? await conflictRows { conflicts = MarkerConflicts.open(rows) }
            if TournamentCoreFeature.isActive {
                await loadStartList(client: client, rounds: rounds, players: players)
            }
            now = .now
            hasLoaded = true
        } catch is CancellationError {
        } catch {
            now = .now  // står som sist
        }
    }

    /// Startlista (sql/032) og navnene på funksjonærene. Mangler den, brukes rundens tee-tid.
    private func loadStartList(client: SupabaseClient, rounds: [RoundRow], players: [UUID: [RoundPlayerRow]]) async {
        guard let saved = try? await TournamentCoreQueries.startGroups(client: client, roundIDs: rounds.map(\.id)) else {
            return
        }
        var out: [UUID: [StartGroupDraft]] = [:]
        for round in rounds {
            out[round.id] = StartList.groups(players: players[round.id] ?? [],
                                             saved: saved.filter { $0.roundID == round.id }, venue: round.venue)
        }
        groups = out
        let scorerIDs = Set(saved.compactMap(\.scorerID)).subtracting(scorerNames.keys)
        if !scorerIDs.isEmpty,
           let names = try? await TournamentCoreQueries.profileNames(client: client, ids: Array(scorerIDs)) {
            scorerNames.merge(names) { _, new in new }
        }
    }
}

#if DEBUG
extension TonightLiveModel {
    /// «I kveld» i skjermprøvene (`arrangorpagar`): bås 1 på hull 14 og synket for 2 min siden, bås 2 på
    /// hull 11 uten data på 18 min (med funksjonær), bås 3 og 4 starter om 25 og 35 min.
    static func sample(from admin: RundeAdminModel, now fixedNow: Date? = nil, conflicts: Bool = false) -> TonightLiveModel {
        // Kl. 19:35 i dag, så tidene blir som i skissen (18:00, 18:10, om 25 og 35 min).
        let now = fixedNow ?? EveningDates.time(from: "19:35", on: .now) ?? .now
        guard let round = admin.activeRound, let players = admin.playersByRound[round.id] else {
            return TonightLiveModel(preview: [], now: now)
        }
        let byBay = Dictionary(grouping: players, by: { $0.bayNo ?? 0 })
        var scores: [HoleScoreRow] = []
        func play(_ bay: Int, holes: Int, lastMinutesAgo: Double) {
            for member in byBay[bay] ?? [] {
                for hole in 0..<holes {
                    let ago = lastMinutesAgo + Double(holes - 1 - hole) * 9
                    scores.append(HoleScoreRow(roundID: round.id, memberID: member.memberID, holeIndex: hole,
                                               strokes: 4, recordedAt: now.addingTimeInterval(-ago * 60),
                                               updatedBy: nil, updatedAt: nil))
                }
            }
        }
        play(1, holes: 13, lastMinutesAgo: 2)
        play(2, holes: 10, lastMinutesAgo: 18)
        let scorer = UUID()
        let starts: [Int: (String, UUID?)] = [1: ("18:00", nil), 2: ("18:10", scorer), 3: ("20:00", nil), 4: ("20:10", nil)]
        let groups = byBay.keys.sorted().map { no in
            StartGroupDraft(groupNo: no, startsAt: starts[no]?.0, startHole: 1, resourceLabel: "Bås \(no)",
                            scorerID: starts[no]?.1, memberIDs: (byBay[no] ?? []).map(\.memberID))
        }
        let claim = SideClaimRow(id: UUID(), roundID: round.id, memberID: players[0].memberID, kind: .kp, meters: 2.4,
                                 holeIndex: round.kpHoleIndex)
        // `arrangorkonflikt`: to markører førte ulikt for en i bås 1 på hull 12 (K6/6.3).
        var conflictRows: [HoleConflictRow] = []
        if conflicts, let member = byBay[1]?.first?.memberID {
            let at = now.addingTimeInterval(-4 * 60)
            conflictRows.append(HoleConflictRow(id: UUID(), roundID: round.id, memberID: member, holeIndex: 11,
                                                keptStrokes: 4, keptBy: nil, keptAt: at, otherStrokes: 5, otherBy: nil,
                                                otherAt: at.addingTimeInterval(-60), createdAt: at, resolvedAt: nil))
        }
        return TonightLiveModel(preview: scores, groups: [round.id: groups], claims: [claim],
                                scorerNames: [scorer: "Bjørn"], conflicts: conflictRows, now: now)
    }
}
#endif
