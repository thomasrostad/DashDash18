import GolfgutuCore
import SwiftUI

// «Ferdig? Avslutt runden» nederst i føringen (`RoundEndPrompt`). En løs runde avsluttes med
// `finish_loose_round` (sql/018, bare eieren); en klubbrunde låses som «Lås runden» på arrangørsiden
// (`EveningCloser.lock`: `rounds.status`, rounds_update i sql/044 krever rettigheten «rounds»).

extension RundeModel {
    /// Eieren av en løs runde, eller arrangøren (rettigheten «rounds») av en klubbrunde som går.
    var canEndRound: Bool {
        guard let game, game.status == .active else { return false }
        if looseContext != nil { return canFinish }
        return clubContext != nil && viewer.isOrganizer
    }

    /// Det føringen viser nederst når kortet er ferdig.
    var endPrompt: RoundEndPrompt? {
        game?.endPrompt(viewer: viewer, canEnd: canEndRound, isLoose: looseContext != nil,
                        pending: pendingHoles, currentHole: currentHole)
    }

    /// «Avslutt runden …» i ⋯-menyen.
    var endOffer: RoundEndOffer? {
        game?.endOffer(viewer: viewer, canEnd: canEndRound, isLoose: looseContext != nil)
    }

    /// Avslutter runden. Løs runde: hentes på nytt og viser resultatet. Klubbrunde: låses og logges
    /// («Runde låst», plassbyttet i tabellen); den som kaller lukker føringen og henter etterpå, for
    /// runden er ikke lenger blant dem som går.
    func endRound() async throws(DataError) {
        guard canEndRound, let game else { return }
        if looseContext != nil {
            try await finish()
            return
        }
        guard let context = clubContext else { return }
        let locked = await EveningCloser.lock(context: context, roundIDs: [game.roundID])
        guard locked.contains(game.roundID) else {
            throw DataError.invalid("Runden ble ikke låst. Sjekk nettet og prøv igjen.")
        }
    }
}

/// Bekreftelsene før runden avsluttes: først hva som skjer, så en ekstra når noen ikke er ferdige.
struct RoundEndConfirmation: ViewModifier {
    @Binding var isPresented: Bool
    let offer: RoundEndOffer?
    let perform: () -> Void
    @State private var asksAgain = false

    func body(content: Content) -> some View {
        content
            .confirmationDialog(RoundEndOffer.confirmTitle, isPresented: $isPresented, titleVisibility: .visible) {
                Button(RoundEndOffer.confirmButton) {
                    if offer?.extraConfirm != nil { asksAgain = true } else { perform() }
                }
                Button("Avbryt", role: .cancel) {}
            } message: {
                Text(offer?.confirmMessage ?? "")
            }
            .confirmationDialog(offer?.extraConfirm?.title ?? "", isPresented: $asksAgain, titleVisibility: .visible) {
                Button(RoundEndOffer.extraButton, role: .destructive) { perform() }
                Button("Avbryt", role: .cancel) {}
            } message: {
                Text(offer?.extraConfirm?.message ?? "")
            }
    }
}

extension View {
    /// «Avslutte runden?» og, når noen ikke er ferdige, en bekreftelse til.
    func roundEndConfirmation(isPresented: Binding<Bool>, offer: RoundEndOffer?,
                              perform: @escaping () -> Void) -> some View {
        modifier(RoundEndConfirmation(isPresented: isPresented, offer: offer, perform: perform))
    }
}

/// Bunnlinja når kortet er ferdig: «Ferdig? Avslutt runden» for den som kan avslutte, ellers
/// «Kortet ditt er ferdig». Samme glass som `FoeringBunnlinje`.
struct RundeAvslutningLinje: View {
    let prompt: RoundEndPrompt
    let isEnding: Bool
    /// nil: du spiller ikke, ingen scorekort å vise.
    let onScorecard: (() -> Void)?
    let onEnd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DDSpacing.s) {
            switch prompt {
            case .offer(let offer):
                status(offer.statusText, systemImage: offer.hasUnfinished ? "clock" : "checkmark.circle")
                Button(action: onEnd) {
                    ZStack {
                        Label(RoundEndOffer.buttonTitle, systemImage: "flag.checkered")
                            .opacity(isEnding ? 0 : 1)
                        if isEnding { ProgressView().tint(DDToken.buttonPrimaryText.color) }
                    }
                }
                .buttonStyle(.ddPrimary)
                .disabled(isEnding)
                .accessibilityHint("Låser runden etter at du har bekreftet.")
            case .cardDone:
                Label(RoundEndPrompt.cardDoneTitle, systemImage: "checkmark.circle.fill")
                    .font(.dd(.sans, size: 17, weight: .semibold, relativeTo: .headline))
                    .foregroundStyle(Color.ddForestInk)
                status(prompt.cardDoneText, systemImage: nil)
            }
            if let onScorecard {
                Button("Se scorekortet →", action: onScorecard)
                    .buttonStyle(.dd(.secondary, fullWidth: true))
            }
        }
        .padding(.horizontal, DDSpacing.l)
        .padding(.vertical, DDSpacing.m)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: DDRadius.cardLarge))
        .padding(.horizontal, DDSpacing.s)
        .padding(.bottom, 4)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    @ViewBuilder
    private func status(_ text: String, systemImage: String?) -> some View {
        Group {
            if let systemImage {
                Label(text, systemImage: systemImage).foregroundStyle(Color.ddInkSecondary)
            } else {
                Text(text).foregroundStyle(Color.ddInkSecondary)
            }
        }
        .font(.ddStatus)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
