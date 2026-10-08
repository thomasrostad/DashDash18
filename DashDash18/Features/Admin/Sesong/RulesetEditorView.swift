import GolfgutuCore
import SwiftUI

/// Redigering av regelsettet for en sesong (en serie i klubben). Sammendraget står øverst, så de
/// vanligste valgene og resten under «Avanserte valg». Valg som ikke er som i oppsettet, får merket
/// «Endret · standard …». Meldingene fra `Ruleset.validate()` vises mens arrangøren endrer, og
/// lagring er sperret så lenge det er feil.
struct RulesetEditorView: View {
    let model: SesongAdminModel
    let season: SeasonRow

    @State private var draft: RulesetDraft
    @State private var isSaving = false
    @State private var error: DataError?
    @State private var savedMessage: String?

    init(model: SesongAdminModel, season: SeasonRow) {
        self.model = model
        self.season = season
        _draft = State(initialValue: RulesetDraft(season.rules))
    }

    private var isReadOnly: Bool { season.status == .finished }

    var body: some View {
        RulesetForm(draft: $draft, isReadOnly: isReadOnly) {
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
    }

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

/// «Tilpass reglene» i «Ny turnering»: samme skjema, uten lagring. Endringene følger med når
/// turneringen lages.
struct RulesetCustomizeView: View {
    @Binding var rules: Ruleset
    let base: RulesetTemplate
    @Environment(\.dismiss) private var dismiss
    @State private var draft: RulesetDraft

    init(rules: Binding<Ruleset>, base: RulesetTemplate) {
        _rules = rules
        self.base = base
        _draft = State(initialValue: RulesetDraft(rules.wrappedValue, base: base))
    }

    var body: some View {
        RulesetForm(draft: $draft, isReadOnly: false) { EmptyView() }
            .navigationTitle("Tilpass reglene")
            .ddNavigationChrome()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ferdig") {
                        rules = draft.rules
                        dismiss()
                    }
                    .disabled(!draft.canSave)
                }
            }
    }
}

/// Skjemaet for et regelsett: sammendraget, det som må rettes, de vanligste valgene, «Avanserte valg»
/// og «Tilbakestill til <oppsett>». Seksjonene som bare gjelder matcher, vises bare når tabellen
/// teller matcher.
struct RulesetForm<Bottom: View>: View {
    @Binding var draft: RulesetDraft
    let isReadOnly: Bool
    @ViewBuilder let bottom: () -> Bottom

    @State private var confirmsReset = false
    @State private var showsAdvanced: Bool

    init(draft: Binding<RulesetDraft>, isReadOnly: Bool, @ViewBuilder bottom: @escaping () -> Bottom) {
        _draft = draft
        self.isReadOnly = isReadOnly
        self.bottom = bottom
        // Avanserte valg er åpne når noe der er endret eller må rettes, så ingenting skjules.
        let d = draft.wrappedValue
        _showsAdvanced = State(initialValue: d.changedAdvancedCount > 0 || Self.hasAdvancedIssues(d))
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
                    Button("Tilbakestill til \(draft.base.title)", role: .destructive) { confirmsReset = true }
                        .disabled(draft.isTemplate)
                } footer: {
                    DDFooter(draft.isTemplate
                             ? "Reglene er som i \(draft.base.title)."
                             : "Alle valgene settes tilbake, også de avanserte.")
                }
            }
            bottom()
        }
        .confirmationDialog("Tilbakestille til \(draft.base.title)?", isPresented: $confirmsReset, titleVisibility: .visible) {
            Button("Tilbakestill", role: .destructive) { draft.resetToTemplate() }
        } message: {
            let count = draft.changedFields.count
            Text(count == 1
                 ? "1 valg settes tilbake. Du ser resultatet før du lagrer."
                 : "\(count) valg settes tilbake. Du ser resultatet før du lagrer.")
        }
    }

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
            RuleSectionFooter(text: "Ett slag bedre enn netto par gir ett poeng mer.",
                              issues: draft.issues(in: .scoring))
        }
    }
}
