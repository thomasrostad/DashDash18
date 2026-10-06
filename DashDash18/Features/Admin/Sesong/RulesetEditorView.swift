import GolfgutuCore
import SwiftUI

/// Redigering av hele regelsettet for en sesong. Meldingene fra `Ruleset.validate()` vises mens
/// arrangøren endrer, og lagring er sperret så lenge det er feil.
struct RulesetEditorView: View {
    let model: SesongAdminModel
    let season: SeasonRow

    @State private var draft: RulesetDraft
    @State private var isSaving = false
    @State private var error: DataError?
    @State private var savedMessage: String?
    @State private var confirmsReset = false

    init(model: SesongAdminModel, season: SeasonRow) {
        self.model = model
        self.season = season
        _draft = State(initialValue: RulesetDraft(season.rules))
    }

    private var isReadOnly: Bool { season.status == .finished }

    var body: some View {
        DDForm {
            DDSection("Slik telles det") {
                Text(RulesetExplanation.text(for: draft.rules))
                    .font(.dd(.sans, size: 15, relativeTo: .callout))
            }
            if !draft.issues.isEmpty {
                DDSection("Må rettes før lagring") {
                    RuleIssuesList(issues: draft.issues)
                }
            }
            Group {
                seasonSection
                scoringSection
                RulesetTableSections(draft: $draft)
                sidePrizeSection
                RulesetHandicapSection(draft: $draft)
                RulesetFormatSection(draft: $draft)
            }
            .disabled(isReadOnly)
            if !isReadOnly {
                Section {
                    Button("Tilbakestill til Golfgutu", role: .destructive) { confirmsReset = true }
                } footer: {
                    DDFooter("Setter alle reglene til Golfgutu-oppsettet. Ingenting lagres før du trykker «Lagre».")
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
        .confirmationDialog("Tilbakestille til Golfgutu?", isPresented: $confirmsReset, titleVisibility: .visible) {
            Button("Tilbakestill", role: .destructive) { draft.resetToGolfgutu() }
        } message: {
            Text("Alle endringer i reglene erstattes av Golfgutu-oppsettet.")
        }
    }

    // MARK: Delene

    private var seasonSection: some View {
        Section {
            RuleStepper("Kvelder", value: $draft.rules.evenings)
        } header: {
            DDHeader(RulesetSection.season.title)
        } footer: {
            RuleSectionFooter(text: "Antall kvelder i sesongen.", issues: draft.issues(in: .season))
        }
    }

    private var scoringSection: some View {
        Section {
            RuleStepper("Netto par gir", value: $draft.rules.scoring.netParPoints)
            RuleStepper("Laveste poeng", value: $draft.rules.scoring.minimumPoints)
        } header: {
            DDHeader(RulesetSection.scoring.title)
        } footer: {
            RuleSectionFooter(text: "Poeng per hull: netto par gir det første tallet, ett slag bedre gir ett mer. Et hull gir aldri mindre enn laveste poeng.",
                              issues: draft.issues(in: .scoring))
        }
    }

    private var sidePrizeSection: some View {
        Section {
            Toggle("Longest drive", isOn: $draft.rules.sidePrizes.longestDrive.enabled)
            if draft.rules.sidePrizes.longestDrive.enabled {
                RuleNumberField("Poeng for longest drive", value: $draft.rules.sidePrizes.longestDrive.points)
            }
            Toggle("Nærmest pinnen", isOn: $draft.rules.sidePrizes.closestToPin.enabled)
            if draft.rules.sidePrizes.closestToPin.enabled {
                RuleNumberField("Poeng for nærmest pinnen", value: $draft.rules.sidePrizes.closestToPin.points)
            }
            Toggle("Del poenget ved likt", isOn: $draft.rules.sidePrizes.splitTies)
        } header: {
            DDHeader(RulesetSection.sidePrizes.title)
        } footer: {
            RuleSectionFooter(text: "Delt: to på likt får halvparten hver. Ikke delt: alle på delt førsteplass får fullt.",
                              issues: draft.issues(in: .sidePrizes))
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
