import Observation
import Supabase
import SwiftUI

// Bryteren «Veddemål» (sql/052): av som standard, slås på per turnering i innstillingene og per
// enkeltrunde i oppsettet (`bets_set_enabled`). Vises ikke før 052 er kjørt.

/// På eller av for én bank.
@Observable
final class BetsSwitchModel {
    /// nil: ikke hentet ennå, eller 052 mangler (da vises ikke bryteren).
    private(set) var enabled: Bool?
    private(set) var isSaving = false
    var error: String?

    let client: SupabaseClient
    let scope: BetScope

    init(client: SupabaseClient, scope: BetScope) {
        self.client = client
        self.scope = scope
    }

    func load() async {
        guard BetsFeature.isEnabled else { return }
        do {
            switch scope {
            case .competition(let id): enabled = try await BetsQueries.competitionEnabled(client: client, id: id)
            case .round(let id): enabled = try await BetsQueries.roundEnabled(client: client, id: id)
            }
        } catch {
            // Bryteren står skjult til neste henting.
        }
    }

    func set(_ on: Bool) async {
        guard enabled != nil, !isSaving else { return }
        let before = enabled
        enabled = on
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            try await BetsQueries.setEnabled(client: client, scope: scope, enabled: on)
        } catch {
            enabled = before
            if let postgrest = error as? PostgrestError,
               let text = BetErrors.text(sqlState: postgrest.code, message: postgrest.message) {
                self.error = text
            } else {
                self.error = DataError.from(error).message
            }
        }
    }
}

/// Bryteren som rad i en liste (turneringens innstillinger, arrangørsiden, runden).
struct BetsSwitchRow: View {
    @State var model: BetsSwitchModel
    var subtitle = "Poeng på hull, runder og hverandre. Egen poengbank."

    var body: some View {
        Group {
            if let enabled = model.enabled {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: Binding(get: { enabled }, set: { on in Task { await model.set(on) } })) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Veddemål")
                                    .foregroundStyle(Color.ddInk)
                                Text(subtitle)
                                    .font(.ddCaption)
                                    .foregroundStyle(Color.ddInkSecondary)
                            }
                        } icon: {
                            Image(systemName: "die.face.5")
                        }
                        .labelStyle(DDIconLabelStyle())
                    }
                    .disabled(model.isSaving)
                    if let error = model.error {
                        Text(error).ddErrorStyle()
                    }
                }
            }
        }
        .task { await model.load() }
    }
}

/// Bryteren som egen seksjon i et skjema, med forklaringen under.
struct BetsSwitchSection: View {
    let model: BetsSwitchModel

    var body: some View {
        Section {
            BetsSwitchRow(model: model)
        } footer: {
            if model.enabled != nil { DDFooter(BetTexts.toggleFooter) }
        }
    }
}
