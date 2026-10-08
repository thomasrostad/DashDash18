import SwiftUI

/// Betalingsveggen «Kjør turneringen». Prisen kommer fra App Store (`Product.displayPrice`), aldri
/// fra koden. Vises av «Ny konkurranse» (fase 15) når en liga eller cup ikke er låst opp. Da finnes
/// turneringen ikke ennå (`competitionID` nil): kjøpet blir en ledig kreditt, som kobles til
/// turneringen når den lages (`CompetitionPurchase.needsCredit`).
struct PaywallView: View {
    let service: PurchaseService?
    let competitionID: UUID?
    let competitionName: String
    /// Klubben et abonnement gjelder for (arrangøren kjøper for klubben). nil = for deg.
    var clubID: UUID?
    /// Skjermprøve: pris uten App Store.
    var previewPrices: [PurchaseProduct: String] = [:]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DDSpacing.l) {
                    header
                    VStack(alignment: .leading, spacing: DDSpacing.m) {
                        benefit("trophy", "Tabell, terminliste og regelsett for hele turneringen")
                        benefit("person.3", "Så mange deltakere og runder du vil")
                        benefit("bell.badge", "Varsler, tråd og resultatdeling for alle som er med")
                        benefit("figure.golf", "Løse runder, morroturneringer og spill på runden er alltid gratis")
                    }
                    .padding(DDSpacing.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: DDRadius.card).fill(Color.ddCard))
                    offer(.tournament, primary: true)
                    offer(.yearly, primary: false)
                    if let message = statusMessage {
                        Label(message.text, systemImage: message.icon)
                            .font(.ddCallout)
                            .foregroundStyle(message.isError ? Color.ddError : Color.ddForestInk)
                    }
                    footer
                }
                .padding(DDSpacing.gutter)
            }
            .ddScreenBackground()
            .navigationTitle("Kjør turneringen")
            .navigationBarTitleDisplayMode(.inline)
            .ddNavigationChrome()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Lukk") { dismiss() }
                        .tint(Color.ddOnDark)
                }
            }
            .task { await service?.loadProducts() }
        }
        .tint(Color.ddForestInk)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DDSpacing.s) {
            Text(competitionName)
                .ddEyebrow(color: Color.ddInkSecondary)
            Text("Kjør turneringen")
                .font(.ddTitle)
                .foregroundStyle(Color.ddInk)
                .accessibilityAddTraits(.isHeader)
            Text("Appen er gratis å spille i. Det koster bare å kjøre en liga eller cup, og det betales én gang per turnering.")
                .font(.ddCallout)
                .foregroundStyle(Color.ddInkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func benefit(_ icon: String, _ text: String) -> some View {
        Label {
            Text(text).font(.ddCallout).foregroundStyle(Color.ddInk)
        } icon: {
            Image(systemName: icon).foregroundStyle(Color.ddForestInk)
        }
    }

    private func offer(_ product: PurchaseProduct, primary: Bool) -> some View {
        let price = service?.displayPrice(product) ?? previewPrices[product]
        return VStack(alignment: .leading, spacing: DDSpacing.s) {
            Button {
                Task { await service?.purchase(product, competitionID: product.kind == .consumable ? competitionID : nil, clubID: clubID) }
            } label: {
                HStack {
                    Text(product.title)
                    Spacer()
                    if isBusy {
                        ProgressView()
                    } else {
                        Text(price ?? "…").monospacedDigit()
                    }
                }
            }
            .buttonStyle(.dd(primary ? .money : .secondary, fullWidth: true))
            .disabled(price == nil || isBusy)
            .accessibilityLabel("\(product.title), \(price ?? "pris hentes")")
            Text(product.subtitle)
                .font(.ddCaption)
                .foregroundStyle(Color.ddInkSecondary)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: DDSpacing.s) {
            Button("Gjenopprett kjøp") {
                Task { await service?.restore() }
            }
            .buttonStyle(.dd(.text))
            .disabled(isBusy)
            Text("Betales med Apple-ID-en din. Abonnementet fornyes automatisk til du sier det opp i Innstillinger senest et døgn før perioden er over. Veddemål og spill er bare poeng, aldri penger.")
                .font(.ddCaption)
                .foregroundStyle(Color.ddInkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            LegalLinksRow()
        }
    }

    private var isBusy: Bool {
        switch service?.state {
        case .purchasing, .restoring, .loadingProducts: true
        default: false
        }
    }

    private var statusMessage: (text: String, icon: String, isError: Bool)? {
        if let competitionID, service?.lastUnlocked == competitionID {
            return ("Turneringen er låst opp. God runde!", "checkmark.seal", false)
        }
        if competitionID == nil, let service, CompetitionUnlock.unusedCredit(in: service.entitlements, owner: service.profileID) != nil {
            return ("Kjøpet er klart. Lukk og trykk «Lag», så brukes det på turneringen.", "checkmark.seal", false)
        }
        if case .failed(let error) = service?.state {
            return (error.message, "exclamationmark.triangle", error != .pending)
        }
        return nil
    }
}
