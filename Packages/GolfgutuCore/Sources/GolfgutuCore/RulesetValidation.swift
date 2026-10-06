import Foundation

/// Et problem i et regelsett, med feltet det gjelder og en norsk melding til arrangøren.
public struct RulesetIssue: Hashable, Sendable {
    /// Stien til feltet i JSON-en, f.eks. `table.counting.best`.
    public var field: String
    public var message: String

    public init(field: String, message: String) {
        self.field = field
        self.message = message
    }
}

extension Ruleset {
    /// Gyldighetssjekk før regelsettet lagres (admin-panelet). Tom liste: alt er i orden.
    public func validate() -> [RulesetIssue] {
        var issues: [RulesetIssue] = []
        func add(_ field: String, _ message: String) { issues.append(RulesetIssue(field: field, message: message)) }
        func notNegative(_ x: Double, _ field: String, _ what: String) {
            if x < 0 || !x.isFinite { add(field, "\(what) kan ikke være negativt.") }
        }

        // Sesong og telling.
        if evenings < 1 { add("evenings", "Sesongen må ha minst én kveld.") }
        func checkCounting(_ c: Counting, _ field: String, _ what: String) {
            guard let best = c.best else { return }
            if best < 1 {
                add("\(field).best", "\(what): «beste N» må være minst 1. La feltet stå tomt for at alt skal telle.")
            } else if c.unit == .evening, evenings >= 1, best > evenings {
                add("\(field).best", "\(what): beste \(best) kvelder er flere enn de \(evenings) kveldene i sesongen.")
            }
        }
        checkCounting(table.counting, "table.counting", "Tabellen")
        checkCounting(table.stablefordCounting, "table.stablefordCounting", "Stablefordsummen")
        if table.stablefordCounting.unit == .match {
            add("table.stablefordCounting.unit", "Stablefordsummen kan ikke telle matcher. Velg runder eller kvelder.")
        }

        // Poeng.
        let mp = table.matchPoints
        notNegative(mp.win, "table.matchPoints.win", "Poeng for seier")
        notNegative(mp.draw, "table.matchPoints.draw", "Poeng for uavgjort")
        notNegative(mp.loss, "table.matchPoints.loss", "Poeng for tap")
        if mp.win < mp.draw || mp.draw < mp.loss {
            add("table.matchPoints", "Seier må gi minst like mye som uavgjort, og uavgjort minst like mye som tap.")
        }
        if table.trianglePoints.count != 3 {
            add("table.trianglePoints", "Trekanten trenger poeng for tre plasser, ikke \(table.trianglePoints.count).")
        }
        if table.trianglePoints.contains(where: { $0 < 0 || !$0.isFinite }) {
            add("table.trianglePoints", "Trekantpoeng kan ikke være negative.")
        }
        if zip(table.trianglePoints, table.trianglePoints.dropFirst()).contains(where: { $0 < $1 }) {
            add("table.trianglePoints", "En bedre plass i trekanten må gi minst like mye som en dårligere.")
        }
        if let step = table.roundingStep, !(step > 0) || !step.isFinite {
            add("table.roundingStep", "Avrundingen må være større enn 0, eller tom for ingen avrunding.")
        }
        if Set(table.tiebreaks).count != table.tiebreaks.count {
            add("table.tiebreaks", "Det samme skilletegnet står flere ganger.")
        }
        if scoring.netParPoints < 0 { add("scoring.netParPoints", "Poeng for netto par kan ikke være negativt.") }
        if scoring.minimumPoints > scoring.netParPoints {
            add("scoring.minimumPoints", "Laveste poeng på et hull kan ikke være høyere enn poeng for netto par.")
        }

        // Sidepremier.
        notNegative(sidePrizes.longestDrive.points, "sidePrizes.longestDrive.points", "Poeng for longest drive")
        notNegative(sidePrizes.closestToPin.points, "sidePrizes.closestToPin.points", "Poeng for nærmest pinnen")

        // Handicap.
        func checkAllowance(_ a: Double, _ field: String) {
            if !(0...1).contains(a) { add(field, "Handicapandelen må være mellom 0 og 100 %.") }
        }
        if let a = handicap.allowanceOverride { checkAllowance(a, "handicap.allowanceOverride") }
        for (id, a) in handicap.formAllowances.sorted(by: { $0.key < $1.key }) {
            checkAllowance(a, "handicap.formAllowances.\(id)")
        }
        let numbers = handicap.seedingGroups.map(\.number)
        if Set(numbers).count != numbers.count {
            add("handicap.seedingGroups", "To seedinggrupper har samme nummer.")
        }
        for (id, rule) in handicap.teamHandicap.sorted(by: { $0.key < $1.key }) where rule.method == .weighted {
            let weights = rule.weights ?? []
            if weights.isEmpty {
                add("handicap.teamHandicap.\(id)", "Vektet lagshandicap trenger vekter.")
            } else if weights.contains(where: { $0 < 0 || !$0.isFinite }) {
                add("handicap.teamHandicap.\(id)", "Vektene i lagshandicapet kan ikke være negative.")
            }
        }

        // Former.
        if formats.maxPerBay < 1 { add("formats.maxPerBay", "Det må være plass til minst én spiller per bås.") }
        if formats.allowedFormIDs.isEmpty {
            add("formats.allowedFormIDs", "Minst én konkurranseform må være tillatt.")
        }
        let known = Set(CompetitionForm.all.map(\.id))
        for id in formats.allowedFormIDs where !known.contains(id) {
            add("formats.allowedFormIDs", "Ukjent konkurranseform: «\(id)».")
        }
        if !formats.allowedFormIDs.isEmpty, !formats.allowedFormIDs.contains(formats.defaultFormID) {
            add("formats.defaultFormID", "Standardformen må være blant de tillatte formene.")
        }

        // Tippekupongen. Grensene er databasens (events.tips_stake_points, events.tips_line).
        if Tips.startTime(tips.defaultStartTime, rules: .golfgutu) != tips.defaultStartTime
            || tips.defaultStartTime.count != 5 {
            add("tips.defaultStartTime", "Fristen må være et klokkeslett som 17:00.")
        }
        if !Tips.stakeLimits.contains(tips.defaultStakePoints) {
            add("tips.defaultStakePoints", "Innsatsen må være mellom 0 og \(Tips.stakeLimits.upperBound) poeng.")
        }
        if tips.stakeOptions.isEmpty || tips.stakeOptions.contains(where: { !Tips.stakeLimits.contains($0) }) {
            add("tips.stakeOptions", "Innsatsvalgene må være mellom 0 og \(Tips.stakeLimits.upperBound) poeng.")
        }
        if !Tips.isValidLine(tips.defaultLine) {
            add("tips.defaultLine", "Linja må være et halvt slag (som 2,5) mellom −9,5 og +18,5.")
        }
        if !(tips.lineStep > 0) || tips.lineStep != tips.lineStep.rounded() {
            add("tips.lineStep", "Linja må flyttes i hele slag, så den blir stående på et halvt.")
        }

        // Ledelsen underveis.
        if leadCheckpoints.contains(where: { !(1...18).contains($0) }) {
            add("leadCheckpoints", "Sjekkpunktene for ledelsen må være hull fra 1 til 18.")
        }
        if zip(leadCheckpoints, leadCheckpoints.dropFirst()).contains(where: { $0 >= $1 }) {
            add("leadCheckpoints", "Sjekkpunktene for ledelsen må stå i stigende rekkefølge, uten like.")
        }
        return issues
    }
}
