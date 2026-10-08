import Foundation
import GolfgutuCore

// MARK: - Ny runde: bekreftelsesskjermen (fase 18)

/// Oppsummeringen øverst på «Ny runde»: én rad per ting som varierer (bane, start, spillere, flere valg).
nonisolated enum RoundConfirm {
    /// «Hvor spiller dere?» vises bare når klubben har klare baner av begge typer. Ellers følger stedet banen.
    static func showsVenueChoice(_ courses: [CourseListItem]) -> Bool {
        Set(courses.filter(\.isReady).map(\.kind)).count > 1
    }

    /// Stedet en bane gir: simulatorbane → Simulator, ekte bane → Ekte bane.
    static func venue(for course: CourseListItem) -> Venue {
        course.kind == .course ? .course : .simulator
    }

    /// Banene i bane-velgeren: de klare banene for stedet når klubben har begge typer, ellers alle.
    /// Valgt bane står først når den ikke er blant dem (f.eks. ikke klar lenger), så valget synes.
    static func courseChoices(_ ready: [CourseListItem], selected: CourseListItem?, venue: Venue,
                              showsVenue: Bool) -> [CourseListItem] {
        var choices = showsVenue ? ready.filter { self.venue(for: $0) == venue } : ready
        if let selected, !choices.contains(where: { $0.id == selected.id }) { choices.insert(selected, at: 0) }
        return choices
    }

    /// Linja under en bane i velgeren: «18 hull · par 72 · CR 72 · slope 128 · med indeks», og navnet i
    /// simulatoren når det er et annet.
    static func courseDetail(_ course: CourseListItem) -> String {
        var text = course.summary
        if course.kind == .simulator, let external = course.differentExternalName {
            text += ". Heter «\(external)» i simulatoren."
        }
        return text
    }

    /// Velger banen og stedet den hører til. LD og KP går tilbake til forslaget for banen.
    static func selectCourse(_ course: CourseListItem, on draft: inout RoundDraft, rules: Ruleset) {
        draft.setVenue(venue(for: course), rules: rules)
        QuickStart.setCourse(course.id, on: &draft, courseHoles: course.holeCount)
    }

    /// Verdien i bane-raden: «Pebble Beach», med stedet når klubben har begge typer
    /// («Pebble Beach · Simulator»). Uten bane: «Velg».
    static func courseValue(name: String?, venue: Venue, showsVenue: Bool) -> String {
        guard let name, !name.isEmpty else { return "Velg" }
        return showsVenue ? "\(name) · \(venue.title)" : name
    }

    /// Verdien i start-raden: «Hull 1 · 18 hull · 18:00», uten tid når første tee ikke er satt.
    static func startValue(firstHole: Int, holeCount: Int, teeTime: String?) -> String {
        let start = QuickStartStart(firstHole: firstHole, holeCount: holeCount).title
        guard let time = EveningDates.timeText(teeTime) else { return start }
        return "\(start) · \(time)"
    }

    /// Linja under «Flere valg»: formen og det som skiller seg fra en vanlig runde.
    /// «Stableford (netto) · 6 matcher · LD hull 18 · KP hull 7».
    static func moreSummary(_ draft: RoundDraft, course: Course?, showsMatches: Bool) -> String {
        let offset = draft.firstHole == 10 ? 10 : 1
        var parts = [draft.form.name]
        if showsMatches {
            let matches = draft.matches.count
            parts.append(matches == 0 ? "ingen matcher" : matches == 1 ? "1 match" : "\(matches) matcher")
        }
        if draft.ldEnabled { parts.append("LD hull \(draft.ldHole(course: course) + offset)") }
        if draft.kpEnabled { parts.append("KP hull \(draft.kpHole(course: course) + offset)") }
        if draft.weight != 1, let weight = RoundSetupOptions.weights.first(where: { $0.value == draft.weight }) {
            parts.append(weight.title.lowercased())
        }
        if draft.externalHandicap { parts.append("Trackman gir slagene") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - «Flere valg»

/// Hva «Flere valg» viser. Det som ikke gjelder formen eller stedet, skjules (men nullstilles ikke).
nonisolated struct RoundSetupOptions: Equatable, Sendable {
    let form: CompetitionForm
    let venue: Venue
    let externalHandicap: Bool
    let rules: Ruleset

    init(draft: RoundDraft, rules: Ruleset) {
        form = draft.form
        venue = draft.venue
        externalHandicap = draft.externalHandicap
        self.rules = rules
    }

    /// Lag bare i lagformer.
    var showsTeams: Bool { form.isTeamForm }

    /// Matcher vises når de gir tabellpoeng. Teller tabellen stableford (fase 18), trekkes de ikke.
    var showsMatches: Bool { rules.table.pointsSource == .matches }

    /// «Trackman fordeler slagene» finnes bare i simulatoren.
    var showsTrackmanToggle: Bool { venue == .simulator }

    /// Handicapandelen gjelder bare når appen gir slagene.
    var showsAllowance: Bool { !externalHandicap }

    /// Vekten og handicapet ligger under «Avansert». Den åpnes av seg selv når noe der er endret fra
    /// standarden, så arrangøren ser det.
    func advancedIsChanged(weight: Double, allowance: Double) -> Bool {
        weight != 1 || (showsAllowance && allowance != rules.allowance(for: form))
    }

    /// En sidepremie som én rad: av, eller hullet (rundens hullindeks). `nil` = av.
    static func sidePrizeChoice(enabled: Bool, holeIndex: Int?, suggestion: Int) -> Int? {
        enabled ? (holeIndex ?? suggestion) : nil
    }

    /// Lagrer valget fra raden: av slår premien av og beholder hullet; forslaget lagres som `nil`,
    /// så det følger banen (som før).
    static func applySidePrize(_ choice: Int?, enabled: inout Bool, holeIndex: inout Int?, suggestion: Int) {
        guard let choice else {
            enabled = false
            return
        }
        enabled = true
        holeIndex = choice == suggestion ? nil : choice
    }

    struct Weight: Equatable, Sendable {
        let value: Double
        let title: String
    }

    /// Valgene fra PWA-ens `vektValg`.
    static let weights = [
        Weight(value: 1, title: "Vanlig runde"),
        Weight(value: 1.5, title: "Halvannen"),
        Weight(value: 2, title: "Dobbelt · avsluttende runde"),
        Weight(value: 3, title: "Tredobbelt"),
        Weight(value: 0, title: "Teller ikke sammenlagt"),
    ]
}
