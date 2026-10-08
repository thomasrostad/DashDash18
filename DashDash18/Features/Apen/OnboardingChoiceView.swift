import SwiftUI

/// Første gang etter innlogging (med `OpenAppFeature`): spill med venner med en gang, eller bli
/// med i eller lag en klubb (dagens flyt). Valget kan endres under Deg.
struct OnboardingChoiceView: View {
    /// Kalles med valget. Godtar vilkårene på serveren først når `ModerationFeature` er på (019).
    let onChoose: (AppHomeChoice) -> Void

    var body: some View {
        NavigationStack {
            DDList {
                Section {
                    VStack(alignment: .leading, spacing: DDSpacing.s) {
                        Text("Hvordan vil du spille?")
                            .font(.ddTitle)
                            .foregroundStyle(Color.ddInk)
                            .accessibilityAddTraits(.isHeader)
                        Text("Du trenger ingen klubb for å spille. Klubben kan du bli med i senere.")
                            .font(.ddCallout)
                            .foregroundStyle(Color.ddInkSecondary)
                    }
                    .padding(.vertical, DDSpacing.s)
                }
                Section {
                    OnboardingChoiceRow(
                        title: "Spill med venner",
                        detail: "Rett inn. Start en runde, inviter med lenke eller QR, og før på telefonen.",
                        systemImage: "figure.golf"
                    ) { onChoose(.friends) }
                    OnboardingChoiceRow(
                        title: "Bli med i eller lag en klubb",
                        detail: "For en fast gjeng med terminliste, kvelder og en egen tavle.",
                        systemImage: "person.3"
                    ) { onChoose(.club) }
                }
                Section {
                    LegalNotice()
                }
            }
            .navigationTitle("Velkommen")
            .ddNavigationChrome()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SignOutButton()
                }
            }
        }
    }
}

private struct OnboardingChoiceRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: DDSpacing.m) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(Color.ddForestInk)
                    .frame(width: 36)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.ddNameSmall)
                        .foregroundStyle(Color.ddInk)
                    Text(detail)
                        .font(.ddCallout)
                        .foregroundStyle(Color.ddInkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.ddInkSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, DDSpacing.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// «Ved å fortsette godtar du vilkårene og personvernerklæringen», med lenker når de er publisert.
struct LegalNotice: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DDSpacing.s) {
            Text("Ved å bruke Atten godtar du vilkårene. Det er null toleranse for støtende innhold og trakassering; det kan rapporteres, og brukere kan blokkeres.")
                .font(.ddCaption)
                .foregroundStyle(Color.ddInkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            LegalLinksRow()
        }
    }
}

/// Lenkene til vilkårene og personvernerklæringen (`LegalLinks`).
struct LegalLinksRow: View {
    var body: some View {
        HStack(spacing: DDSpacing.l) {
            link("Vilkår", url: LegalLinks.terms)
            link("Personvern", url: LegalLinks.privacy)
        }
        .font(.dd(.sans, size: 14, weight: .semibold, relativeTo: .callout))
    }

    @ViewBuilder
    private func link(_ title: String, url: URL?) -> some View {
        if let url {
            Link(title, destination: url)
                .foregroundStyle(Color.ddForestInk)
        } else {
            Text("\(title) (publiseres før lansering)")
                .foregroundStyle(Color.ddInkSecondary)
        }
    }
}
