import GolfgutuCore
import SwiftUI

/// Redigering av regelsettet for en sesong. Sammendraget står øverst, så de vanligste valgene med
/// forklaring, og resten under «Avanserte valg». Valg som ikke er som i Golfgutu-oppsettet, får
/// merket «Endret · standard …». Meldingene fra `Ruleset.validate()` vises mens arrangøren endrer,
/// og lagring er sperret så lenge det er feil.
struct RulesetEditorView: View {
    let model: SesongAdminModel
    let season: SeasonRow

    @State private var draft: RulesetDraft
    @State private var isSaving = false
    @State private var error: DataError?
    @State private var savedMessage: String?
    @State private var confirmsReset = false
    @State private var showsAdvanced: Bool

    init(model: SesongAdminModel, season: SeasonRow) {
        self.model = model
        self.season = season
        let draft = RulesetDraft(season.rules)
        _draft = State(initialValue: draft)
        // Avanserte valg er åpne når noe der er endret eller må rettes, så ingenting skjules.
        _showsAdvanced = State(initialValue: draft.changedAdvancedCount > 0 || Self.hasAdvancedIssues(draft))
    }

    /// Feil i delene som ligger under «Avanserte valg».
    private static func hasAdvancedIssues(_ draft: RulesetDraft) -> Bool {
        draft.issues.contains { issue in
            let f = issue.field
            return f.hasPrefix("scoring") || f.hasPrefix("table.trianglePoints") || f.hasPrefix("table.stablefordCounting")
                || f.hasPrefix("table.tiebreaks") || f.hasPrefix("table.roundingStep") || f.hasPrefix("handicap.seedingGroups")
                || f.hasPrefix("handicap.teamHandicap") || f.hasPrefix("formats")
        }
    }

    private var isReadOnly: Bool { season.status == .finished }

    var body: some View {
        DDForm {
            RulesetSummarySection(rules: draft.rules, title: draft.hasChanges ? "Slik blir det" : "Slik er det nå")
            if !draft.issues.isEmpty {
                DDSection("Må rettes før lagring") {
                    RuleIssuesList(issues: draft.issues)
                }
            }
            Group {
                RulesetCommonSections(draft: $draft)
                advancedToggle
                if showsAdvanced {
                    scoringSection
                    RulesetTableSections(draft: $draft)
                    RulesetHandicapSection(draft: $draft)
                    RulesetFormatSection(draft: $draft)
                }
            }
            .disabled(isReadOnly)
            if !isReadOnly {
                Section {
                    Button("Tilbakestill til Golfgutu-oppsettet", role: .destructive) { confirmsReset = true }
                        .disabled(draft.isGolfgutu)
                } footer: {
                    DDFooter(draft.isGolfgutu
                             ? "Reglene er Golfgutu-oppsettet."
                             : "Setter alle valgene tilbake til Golfgutu-oppsettet, også de avanserte. Ingenting lagres før du trykker «Lagre».")
                }
            }
            if let error {
                Section {
                    Label(error.message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Color.ddError)
                }
            }
        }
        .navigationTitle("Regler")
        .ddNavigationChrome()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isReadOnly {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lagre") { save() }
                        .disabled(!draft.canSave || !draft.hasChanges || isSaving)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let savedMessage {
                Text(savedMessage)
                    .font(.dd(.sans, size: 13, relativeTo: .footnote))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .glassEffect()
                    .padding(.bottom, 16)
            }
        }
        .discardChangesGuard(hasChanges: !isReadOnly && draft.hasChanges && !isSaving)
        .confirmationDialog("Tilbakestille til Golfgutu-oppsettet?", isPresented: $confirmsReset, titleVisibility: .visible) {
            Button("Tilbakestill", role: .destructive) { draft.resetToGolfgutu() }
        } message: {
            let count = RulesetField.changed(draft.rules).count
            Text(count == 1
                 ? "1 valg settes tilbake til standard. Du ser resultatet før du lagrer."
                 : "\(count) valg settes tilbake til standard. Du ser resultatet før du lagrer.")
        }
    }

    // MARK: Delene

    /// «Avanserte valg»: åpner og lukker resten av regelsettet.
    private var advancedToggle: some View {
        Section {
            Button {
                withAnimation { showsAdvanced.toggle() }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Avanserte valg")
                            .foregroundStyle(Color.ddInk)
                        Text("Stableford, trekant, skilletegn, avrunding, seeding, lagshandicap og former.")
                            .font(.dd(.sans, size: 13, relativeTo: .footnote))
                            .foregroundStyle(Color.ddInkSecondary)
                        if draft.changedAdvancedCount > 0 {
                            RuleChangeBadge(text: draft.changedAdvancedCount == 1
                                            ? "1 endret fra standard"
                                            : "\(draft.changedAdvancedCount) endret fra standard")
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(showsAdvanced ? 0 : -90))
                        .foregroundStyle(Color.ddInkSecondary)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityValue(showsAdvanced ? "Åpne" : "Lukket")
        }
    }

    private var scoringSection: some View {
        Section {
            RuleStepper("Netto par gir", value: $draft.rules.scoring.netParPoints)
            RuleStepper("Laveste poeng", value: $draft.rules.scoring.minimumPoints)
        } header: {
            RuleSectionHeader(title: RulesetSection.scoring.title, changeNote: draft.changeNote(.scoring))
        } footer: {
            RuleSectionFooter(text: "Poeng per hull: netto par gir det første tallet, ett slag bedre gir ett mer. Et hull gir aldri mindre enn laveste poeng.",
                              issues: draft.issues(in: .scoring))
        }
    }

    // MARK: Lagring

    private func save() {
        guard draft.canSave else { return }
        let rules = draft.rules
        error = nil
        isSaving = true
        Task {
            do {
                try await model.saveRules(rules, for: season)
                isSaving = false
                draft.markSaved(rules)
                savedMessage = "Reglene er lagret."
                try? await Task.sleep(for: .seconds(2))
                savedMessage = nil
            } catch {
                isSaving = false
                self.error = DataError.from(error)
            }
        }
    }
}
