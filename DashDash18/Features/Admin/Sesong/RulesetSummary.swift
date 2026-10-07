import Foundation
import GolfgutuCore

/// Kortversjonen av et regelsett i klart språk, til toppen av «Sesong og regler».
/// Hele forklaringen står i `RulesetExplanation`. Alle tall kommer fra regelsettet.
nonisolated enum RulesetSummary {
    /// Er dette Golfgutu-oppsettet uendret?
    static func isGolfgutu(_ rules: Ruleset) -> Bool {
        rules == .golfgutu
    }

    /// Merket ved sammendraget: «Golfgutu-oppsettet» eller hvor mye som er endret.
    static func badge(for rules: Ruleset) -> String {
        let changed = RulesetField.changed(rules).count
        if changed == 0 { return "Golfgutu-oppsettet" }
        return changed == 1 ? "1 valg endret fra Golfgutu" : "\(changed) valg endret fra Golfgutu"
    }

    /// Det viktigste, én linje per tema: form, kvelder og telling, poeng, handicap, sidepremier.
    static func lines(for rules: Ruleset) -> [String] {
        var out: [String] = []
        let form = CompetitionForm.form(id: rules.formats.defaultFormID)
        out.append("\(form.name), høyst \(rules.formats.maxPerBay) per bås")
        out.append(eveningsAndCounting(rules))
        let mp = rules.table.matchPoints
        out.append("Seier \(RuleFormat.number(mp.win)) poeng, uavgjort \(RuleFormat.number(mp.draw)), tap \(RuleFormat.number(mp.loss))")
        out.append(handicap(rules, form: form))
        let groups = rules.handicap.seedingGroups.sorted { $0.number < $1.number }
        if !groups.isEmpty {
            let values = RuleFormat.list(groups.map { RuleFormat.number($0.handicap) })
            out.append(groups.count == 1 ? "Seeding i 1 gruppe (\(values))" : "Seeding i \(groups.count) grupper (\(values))")
        }
        out.append(sidePrizes(rules.sidePrizes))
        return out
    }

    /// Én kort linje til sesonglista: «7 kvelder, alle matcher teller».
    static func short(for rules: Ruleset) -> String {
        eveningsAndCounting(rules)
    }

    // MARK: Deler

    /// «7 kvelder, alle matcher teller», «Beste 5 av 7 kvelder teller», «7 kvelder, beste 5 matcher teller».
    static func eveningsAndCounting(_ rules: Ruleset) -> String {
        let c = rules.table.counting
        let evenings = rules.evenings == 1 ? "1 kveld" : "\(rules.evenings) kvelder"
        let noun = RuleNames.nouns(c.unit)
        guard let best = c.best else { return "\(evenings), alle \(noun.plural) teller" }
        if c.unit == .evening {
            return best == 1 ? "Beste kveld av \(rules.evenings) teller" : "Beste \(best) av \(evenings) teller"
        }
        return best == 1 ? "\(evenings), beste \(noun.definite) teller" : "\(evenings), beste \(best) \(noun.plural) teller"
    }

    static func handicap(_ rules: Ruleset, form: CompetitionForm) -> String {
        if rules.handicap.externalHandicap { return "Simulatoren deler ut slagene" }
        if let common = rules.handicap.allowanceOverride {
            return "\(RuleFormat.percent(common)) handicap i alle former"
        }
        return "\(RuleFormat.percent(rules.allowance(for: form))) handicap i \(form.name.lowercased()), egen andel per form"
    }

    static func sidePrizes(_ s: Ruleset.SidePrizeRules) -> String {
        let ld = s.longestDrive, kp = s.closestToPin
        switch (ld.enabled, kp.enabled) {
        case (false, false): return "Ingen sidepremier"
        case (true, true) where ld.points == kp.points:
            return "Longest drive og nærmest pinnen gir \(RuleFormat.number(ld.points)) poeng hver"
        case (true, true):
            return "Longest drive gir \(RuleFormat.number(ld.points)) poeng, nærmest pinnen \(RuleFormat.number(kp.points))"
        case (true, false): return "Longest drive gir \(RuleFormat.number(ld.points)) poeng"
        case (false, true): return "Nærmest pinnen gir \(RuleFormat.number(kp.points)) poeng"
        }
    }
}

/// Valgene i regelsettet slik arrangøren ser dem, med «endret fra standard» per valg.
/// De vanligste står først i redigeringen; resten ligger under «Avanserte valg».
/// Sammen dekker valgene hele `Ruleset`, så ingen endring i regelsettet blir usynlig.
nonisolated enum RulesetField: CaseIterable, Hashable, Sendable {
    // Det vanligste
    case evenings, counting, win, draw, loss, allowance, longestDrive, closestToPin, splitTies
    // Avanserte valg
    case scoring, trianglePoints, stablefordCounting, tiebreaks, rounding
    case seeding, externalHandicap, teamHandicap
    case defaultForm, allowedForms, maxPerBay, matchStrokes
    /// Tippekupong, veddemål og ledelsesmeldinger: ikke i skjemaet her, men med i sammenligningen.
    case other

    var isCommon: Bool {
        switch self {
        case .evenings, .counting, .win, .draw, .loss, .allowance, .longestDrive, .closestToPin, .splitTies: true
        default: false
        }
    }

    var title: String {
        switch self {
        case .evenings: "Kvelder"
        case .counting: "Hva teller"
        case .win: "Seier"
        case .draw: "Uavgjort"
        case .loss: "Tap"
        case .allowance: "Handicapandel"
        case .longestDrive: "Longest drive"
        case .closestToPin: "Nærmest pinnen"
        case .splitTies: "Del poenget ved likt"
        case .scoring: "Stableford"
        case .trianglePoints: "Trekant"
        case .stablefordCounting: "Stablefordsummen"
        case .tiebreaks: "Ved likt poeng"
        case .rounding: "Avrunding"
        case .seeding: "Seeding"
        case .externalHandicap: "Ekstern handicap"
        case .teamHandicap: "Lagshandicap"
        case .defaultForm: "Standardform"
        case .allowedForms: "Tillatte former"
        case .maxPerBay: "Maks per bås"
        case .matchStrokes: "Slag i match"
        case .other: "Tips, veddemål og ledelse"
        }
    }

    /// Er valget forskjellig i `a` og `b`?
    func differs(_ a: Ruleset, _ b: Ruleset) -> Bool {
        switch self {
        case .evenings: a.evenings != b.evenings
        case .counting: a.table.counting != b.table.counting
        case .win: a.table.matchPoints.win != b.table.matchPoints.win
        case .draw: a.table.matchPoints.draw != b.table.matchPoints.draw
        case .loss: a.table.matchPoints.loss != b.table.matchPoints.loss
        case .allowance:
            a.handicap.allowanceOverride != b.handicap.allowanceOverride
                || a.handicap.formAllowances != b.handicap.formAllowances
        case .longestDrive: a.sidePrizes.longestDrive != b.sidePrizes.longestDrive
        case .closestToPin: a.sidePrizes.closestToPin != b.sidePrizes.closestToPin
        case .splitTies: a.sidePrizes.splitTies != b.sidePrizes.splitTies
        case .scoring: a.scoring != b.scoring
        case .trianglePoints: a.table.trianglePoints != b.table.trianglePoints
        case .stablefordCounting: a.table.stablefordCounting != b.table.stablefordCounting
        case .tiebreaks: a.table.tiebreaks != b.table.tiebreaks
        case .rounding: a.table.roundingStep != b.table.roundingStep
        case .seeding: a.handicap.seedingGroups != b.handicap.seedingGroups
        case .externalHandicap: a.handicap.externalHandicap != b.handicap.externalHandicap
        case .teamHandicap: a.handicap.teamHandicap != b.handicap.teamHandicap
        case .defaultForm: a.formats.defaultFormID != b.formats.defaultFormID
        case .allowedForms: a.formats.allowedFormIDs != b.formats.allowedFormIDs
        case .maxPerBay: a.formats.maxPerBay != b.formats.maxPerBay
        case .matchStrokes: a.formats.matchStrokes != b.formats.matchStrokes
        case .other: a.tips != b.tips || a.bets != b.bets || a.leadCheckpoints != b.leadCheckpoints
        }
    }

    /// Verdien i `rules` i klart språk, til «standard: …» ved feltet.
    func valueText(_ rules: Ruleset) -> String {
        switch self {
        case .evenings: return "\(rules.evenings)"
        case .counting:
            let c = rules.table.counting
            let noun = RuleNames.nouns(c.unit)
            return c.best.map { "beste \($0) \(noun.plural)" } ?? "alle \(noun.plural)"
        case .win: return RuleFormat.number(rules.table.matchPoints.win)
        case .draw: return RuleFormat.number(rules.table.matchPoints.draw)
        case .loss: return RuleFormat.number(rules.table.matchPoints.loss)
        case .allowance:
            return rules.handicap.allowanceOverride.map { "\(RuleFormat.percent($0)) for alle" } ?? "per form"
        case .longestDrive: return Self.prize(rules.sidePrizes.longestDrive)
        case .closestToPin: return Self.prize(rules.sidePrizes.closestToPin)
        case .splitTies: return rules.sidePrizes.splitTies ? "på" : "av"
        case .scoring: return "netto par \(rules.scoring.netParPoints), laveste \(rules.scoring.minimumPoints)"
        case .trianglePoints: return rules.table.trianglePoints.map(RuleFormat.number).joined(separator: " / ")
        case .stablefordCounting:
            let c = rules.table.stablefordCounting
            let noun = RuleNames.nouns(c.unit)
            return c.best.map { "beste \($0) \(noun.plural)" } ?? "alle \(noun.plural)"
        case .tiebreaks:
            return rules.table.tiebreaks.isEmpty ? "ingen" : rules.table.tiebreaks.map(RuleNames.inSentence).joined(separator: ", ")
        case .rounding: return rules.table.roundingStep.map(RuleFormat.number) ?? "av"
        case .seeding:
            let groups = rules.handicap.seedingGroups.sorted { $0.number < $1.number }
            return groups.isEmpty ? "ingen" : groups.map { RuleFormat.number($0.handicap) }.joined(separator: " / ")
        case .externalHandicap: return rules.handicap.externalHandicap ? "på" : "av"
        case .teamHandicap: return "Golfgutu-vektene"
        case .defaultForm: return CompetitionForm.form(id: rules.formats.defaultFormID).name
        case .allowedForms: return "\(rules.allowedForms.count) av \(CompetitionForm.all.count)"
        case .maxPerBay: return "\(rules.formats.maxPerBay)"
        case .matchStrokes: return RuleNames.title(rules.formats.matchStrokes).lowercased()
        case .other: return "Golfgutu"
        }
    }

    private static func prize(_ p: Ruleset.SidePrize) -> String {
        p.enabled ? "\(RuleFormat.number(p.points)) poeng" : "av"
    }

    /// Valgene som er endret fra `base` (standard: Golfgutu-oppsettet).
    static func changed(_ rules: Ruleset, from base: Ruleset = .golfgutu) -> [RulesetField] {
        allCases.filter { $0.differs(rules, base) }
    }

    /// «Endret · standard 1», eller nil når valget er som i `base`.
    func changeNote(_ rules: Ruleset, from base: Ruleset = .golfgutu) -> String? {
        guard differs(rules, base) else { return nil }
        if self == .teamHandicap || self == .other { return "Endret fra standard" }
        return "Endret · standard \(valueText(base))"
    }
}
