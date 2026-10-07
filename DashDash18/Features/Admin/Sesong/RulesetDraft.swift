import Foundation
import GolfgutuCore

/// Delene av regelsett-skjermen. Hver melding fra `Ruleset.validate()` hører til én del,
/// etter feltstien (`table.counting.best` → `.table`).
nonisolated enum RulesetSection: CaseIterable, Sendable {
    case season, scoring, table, sidePrizes, handicap, formats

    var title: String {
        switch self {
        case .season: "Sesongen"
        case .scoring: "Stableford"
        case .table: "Tabellen"
        case .sidePrizes: "Sidepremier"
        case .handicap: "Handicap"
        case .formats: "Former"
        }
    }

    static func section(for field: String) -> RulesetSection {
        let head = field.split(separator: ".").first.map(String.init) ?? field
        switch head {
        case "scoring": return .scoring
        case "table": return .table
        case "sidePrizes": return .sidePrizes
        case "handicap": return .handicap
        case "formats": return .formats
        default: return .season
        }
    }
}

/// Redigeringsmodellen for et regelsett. Holder `Ruleset` direkte, så alt regelmotoren kan uttrykke,
/// kan redigeres, og ingenting går tapt på veien. I tillegg husker den verdien i valgfrie felt
/// («beste N», avrunding, felles andel) når arrangøren slår dem av, så de kommer tilbake.
/// Alle startverdier kommer fra regelsettet selv eller fra `Ruleset.golfgutu`.
nonisolated struct RulesetDraft: Equatable, Sendable {
    private(set) var original: Ruleset
    var rules: Ruleset

    private var rememberedCountingBest: Int
    private var rememberedStablefordBest: Int
    private var rememberedRoundingStep: Double
    private var rememberedAllowance: Double

    init(_ rules: Ruleset) {
        original = rules
        self.rules = rules
        let g = Ruleset.golfgutu
        // Når «beste N» slås på, starter N på antall kvelder (eller det som sto der før).
        rememberedCountingBest = rules.table.counting.best ?? rules.evenings
        rememberedStablefordBest = rules.table.stablefordCounting.best ?? g.table.stablefordCounting.best ?? rules.evenings
        // Mangler avrunding i malen også, blir det 0, og valideringen ber om et tall.
        rememberedRoundingStep = rules.table.roundingStep ?? g.table.roundingStep ?? 0
        rememberedAllowance = rules.handicap.allowanceOverride
            ?? rules.allowance(for: CompetitionForm.form(id: rules.formats.defaultFormID))
    }

    // MARK: Status

    var issues: [RulesetIssue] { rules.validate() }
    var canSave: Bool { issues.isEmpty }
    var hasChanges: Bool { rules != original }

    /// Er regelsettet Golfgutu-oppsettet uendret?
    var isGolfgutu: Bool { RulesetSummary.isGolfgutu(rules) }

    /// «Endret · standard 1» ved et felt som ikke er som i Golfgutu-oppsettet.
    func changeNote(_ field: RulesetField) -> String? {
        field.changeNote(rules)
    }

    /// Hvor mange av de avanserte valgene som er endret fra Golfgutu-oppsettet.
    var changedAdvancedCount: Int {
        RulesetField.changed(rules).filter { !$0.isCommon }.count
    }

    func issues(in section: RulesetSection) -> [RulesetIssue] {
        issues.filter { RulesetSection.section(for: $0.field) == section }
    }

    /// Etter lagring: det lagrede er nytt utgangspunkt. Endringer gjort mens lagringen pågikk, beholdes.
    mutating func markSaved(_ saved: Ruleset) {
        original = saved
    }

    /// «Tilbakestill til Golfgutu». Utgangspunktet beholdes, så endringen kan lagres.
    mutating func resetToGolfgutu() {
        let original = original
        self = RulesetDraft(.golfgutu)
        self.original = original
    }

    // MARK: Tabell: telling

    var countsAllInTable: Bool {
        get { rules.table.counting.best == nil }
        set { rules.table.counting.best = Self.toggle(all: newValue, current: rules.table.counting.best, remembered: &rememberedCountingBest) }
    }

    var tableBest: Int {
        get { rules.table.counting.best ?? rememberedCountingBest }
        set { rules.table.counting.best = newValue; rememberedCountingBest = newValue }
    }

    var countsAllInStableford: Bool {
        get { rules.table.stablefordCounting.best == nil }
        set {
            rules.table.stablefordCounting.best = Self.toggle(all: newValue, current: rules.table.stablefordCounting.best,
                                                              remembered: &rememberedStablefordBest)
        }
    }

    var stablefordBest: Int {
        get { rules.table.stablefordCounting.best ?? rememberedStablefordBest }
        set { rules.table.stablefordCounting.best = newValue; rememberedStablefordBest = newValue }
    }

    private static func toggle(all: Bool, current: Int?, remembered: inout Int) -> Int? {
        if all {
            if let current { remembered = current }
            return nil
        }
        return current ?? remembered
    }

    /// Enhetene stablefordsummen kan telle (ikke matcher).
    static let stablefordUnits: [Ruleset.Counting.Unit] = Ruleset.Counting.Unit.allCases.filter { $0 != .match }

    // MARK: Tabell: avrunding og skilletegn

    var roundsTablePoints: Bool {
        get { rules.table.roundingStep != nil }
        set {
            if newValue {
                rules.table.roundingStep = rules.table.roundingStep ?? rememberedRoundingStep
            } else {
                if let step = rules.table.roundingStep { rememberedRoundingStep = step }
                rules.table.roundingStep = nil
            }
        }
    }

    var roundingStep: Double {
        get { rules.table.roundingStep ?? rememberedRoundingStep }
        set { rules.table.roundingStep = newValue; rememberedRoundingStep = newValue }
    }

    /// Skilletegn som ikke er i bruk, og kan legges til.
    var unusedTiebreaks: [Ruleset.Tiebreak] {
        Ruleset.Tiebreak.allCases.filter { !rules.table.tiebreaks.contains($0) }
    }

    mutating func addTiebreak(_ t: Ruleset.Tiebreak) {
        rules.table.tiebreaks.append(t)
    }

    mutating func removeTiebreaks(at offsets: IndexSet) {
        rules.table.tiebreaks.removeAll(at: offsets)
    }

    mutating func moveTiebreaks(from source: IndexSet, to destination: Int) {
        rules.table.tiebreaks.moveAll(from: source, to: destination)
    }

    // MARK: Handicap

    var usesCommonAllowance: Bool {
        get { rules.handicap.allowanceOverride != nil }
        set {
            if newValue {
                rules.handicap.allowanceOverride = rules.handicap.allowanceOverride ?? rememberedAllowance
            } else {
                if let a = rules.handicap.allowanceOverride { rememberedAllowance = a }
                rules.handicap.allowanceOverride = nil
            }
        }
    }

    /// Felles andel i prosent (95 = 0,95).
    var commonAllowancePercent: Double {
        get { (rules.handicap.allowanceOverride ?? rememberedAllowance) * 100 }
        set { rules.handicap.allowanceOverride = newValue / 100; rememberedAllowance = newValue / 100 }
    }

    /// Andelen en ny runde i formen får når det ikke er felles andel (regelmotorens regel, også når formen mangler).
    func formAllowance(_ form: CompetitionForm) -> Double {
        var perForm = rules
        perForm.handicap.allowanceOverride = nil
        return perForm.allowance(for: form)
    }

    mutating func setFormAllowance(_ form: CompetitionForm, percent: Double) {
        rules.handicap.formAllowances[form.id] = percent / 100
    }

    mutating func addSeedingGroup() {
        let groups = rules.handicap.seedingGroups
        let number = (groups.map(\.number).max() ?? 0) + 1
        let handicap = groups.max { $0.number < $1.number }?.handicap ?? 0
        rules.handicap.seedingGroups.append(SeedingGroup(number: number, handicap: handicap, name: "Gruppe \(number)"))
    }

    mutating func removeSeedingGroups(at offsets: IndexSet) {
        rules.handicap.seedingGroups.removeAll(at: offsets)
    }

    /// Formene der laget har ett handicap (mer enn én på laget).
    static var teamForms: [CompetitionForm] { CompetitionForm.all.filter { $0.teamSize > 1 } }

    func teamMethod(_ form: CompetitionForm) -> Ruleset.TeamHandicapRule.Method {
        rules.handicap.teamHandicapRule(for: form.id).method
    }

    /// Bytter metode. Vektet starter med vektene som sto der, ellers Golfgutu-vektene for formen (eller ingen).
    mutating func setTeamMethod(_ form: CompetitionForm, _ method: Ruleset.TeamHandicapRule.Method) {
        let current = rules.handicap.teamHandicapRule(for: form.id)
        guard current.method != method else { return }
        let weights = method == .weighted
            ? (current.weights ?? Ruleset.golfgutu.handicap.teamHandicapRule(for: form.id).weights ?? [])
            : nil
        rules.handicap.teamHandicap[form.id] = Ruleset.TeamHandicapRule(method: method, weights: weights)
    }

    func teamWeights(_ form: CompetitionForm) -> [Double] {
        rules.handicap.teamHandicapRule(for: form.id).weights ?? []
    }

    mutating func setTeamWeight(_ form: CompetitionForm, index: Int, percent: Double) {
        var rule = rules.handicap.teamHandicapRule(for: form.id)
        var weights = rule.weights ?? []
        guard weights.indices.contains(index) else { return }
        weights[index] = percent / 100
        rule.weights = weights
        rules.handicap.teamHandicap[form.id] = rule
    }

    /// Ny vekt for neste spiller. Starter på 0, arrangøren fyller inn.
    mutating func addTeamWeight(_ form: CompetitionForm) {
        var rule = rules.handicap.teamHandicapRule(for: form.id)
        rule.weights = (rule.weights ?? []) + [0]
        rules.handicap.teamHandicap[form.id] = rule
    }

    mutating func removeTeamWeights(_ form: CompetitionForm, at offsets: IndexSet) {
        var rule = rules.handicap.teamHandicapRule(for: form.id)
        var weights = rule.weights ?? []
        weights.removeAll(at: offsets)
        rule.weights = weights
        rules.handicap.teamHandicap[form.id] = rule
    }

    // MARK: Former

    func isAllowed(_ form: CompetitionForm) -> Bool {
        rules.formats.allowedFormIDs.contains(form.id)
    }

    /// Slår en form av eller på. Listen holdes i katalogens rekkefølge; ukjente id-er beholdes bakerst,
    /// så valideringen kan melde dem.
    mutating func setAllowed(_ form: CompetitionForm, _ allowed: Bool) {
        var set = Set(rules.formats.allowedFormIDs)
        if allowed { set.insert(form.id) } else { set.remove(form.id) }
        let known = CompetitionForm.all.map(\.id)
        let unknown = rules.formats.allowedFormIDs.filter { !known.contains($0) }
        rules.formats.allowedFormIDs = known.filter(set.contains) + unknown
    }

    // MARK: JSON

    /// Regelsettet slik det lagres i `seasons.rules` (GolfgutuCore sin koding, versjon 2).
    static func encoded(_ rules: Ruleset) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(rules)
    }
}

fileprivate extension Array {
    /// Som SwiftUI sin `remove(atOffsets:)`, uten SwiftUI.
    nonisolated mutating func removeAll(at offsets: IndexSet) {
        for i in offsets.sorted(by: >) where indices.contains(i) { remove(at: i) }
    }

    /// Som SwiftUI sin `move(fromOffsets:toOffset:)`, uten SwiftUI.
    nonisolated mutating func moveAll(from source: IndexSet, to destination: Int) {
        let moving = source.sorted().filter(indices.contains).map { self[$0] }
        let before = source.filter { $0 < destination }.count
        removeAll(at: source)
        insert(contentsOf: moving, at: Swift.min(Swift.max(destination - before, 0), count))
    }
}
