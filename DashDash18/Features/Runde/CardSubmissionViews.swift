import GolfgutuCore
import SwiftUI

// «Lever kortet» i føringen og «Leverte kort» for arrangøren (sql/058, `play.lockSubmittedCards`).
// Serveren håndhever låsen (can_score); føringen viser den.

extension RundeModel {
    /// Det føringen viser under kortet, eller nil.
    var cardSubmission: CardSubmission? {
        game?.cardSubmission(viewer: viewer, pending: pendingHoles)
    }

    /// «Lever kortet»: leverer `members` og henter runden på nytt.
    func submitCard(_ members: [UUID]) async throws(DataError) {
        guard let game, let access = statsAccess else { return }
        do {
            try await CardLockQueries.submit(client: access.client, roundID: game.roundID, members: members)
        } catch {
            throw DataError.from(error)
        }
        await load()
    }

    /// «Åpne kortet igjen» (arrangøren).
    func reopenCard(_ members: [UUID]) async throws(DataError) {
        guard let game, let access = statsAccess, viewer.isOrganizer else { return }
        do {
            try await CardLockQueries.reopen(client: access.client, roundID: game.roundID, members: members)
        } catch {
            throw DataError.from(error)
        }
        await load()
    }
}

/// Under hullkortet: «Lever kortet», hva som mangler, eller at kortet er levert.
struct CardSubmissionSection: View {
    let model: RundeModel
    let submission: CardSubmission
    @State private var confirms = false
    @State private var isWorking = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DDSpacing.s) {
            switch submission {
            case .ready(let members):
                DDInfoStripe(submission.text, tone: .lime)
                Button("Lever kortet") { confirms = true }
                    .buttonStyle(.dd(.secondary, fullWidth: true))
                    .disabled(isWorking)
                    .confirmationDialog("Levere kortet?", isPresented: $confirms, titleVisibility: .visible) {
                        Button("Lever kortet") { run { try await model.submitCard(members) } }
                    } message: {
                        Text("Etterpå kan bare arrangøren endre eller åpne kortet.")
                    }
            case .notReady:
                if !submission.text.isEmpty {
                    Text(submission.text)
                        .font(.ddCaption)
                        .foregroundStyle(Color.ddInkSecondary)
                }
            case .submitted(let members, let canReopen):
                DDInfoStripe(tone: .earth) {
                    HStack {
                        Label(submission.text, systemImage: "lock.fill")
                        Spacer(minLength: 8)
                        if canReopen {
                            Button("Åpne igjen") { run { try await model.reopenCard(members) } }
                                .buttonStyle(.dd(.secondary, compact: true))
                                .disabled(isWorking)
                        }
                    }
                }
            }
            if let error {
                Text(error).font(.ddCaption).foregroundStyle(Color.ddError)
            }
        }
    }

    private func run(_ action: @escaping () async throws -> Void) {
        isWorking = true
        error = nil
        Task {
            do {
                try await action()
            } catch {
                self.error = DataError.from(error).message
            }
            isWorking = false
        }
    }
}

/// «Leverte kort» under Stilling: arrangøren ser kortene som er levert og kan åpne dem igjen.
struct SubmittedCardsSection: View {
    let model: RundeModel
    let cards: [SubmittedCard]
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DDSpacing.s) {
            Text("Leverte kort").ddEyebrow()
            ForEach(cards) { card in
                HStack {
                    Label(card.title, systemImage: "lock.fill")
                    Spacer(minLength: 8)
                    Button("Åpne igjen") {
                        Task {
                            do { try await model.reopenCard(card.members) } catch { self.error = DataError.from(error).message }
                        }
                    }
                    .buttonStyle(.dd(.secondary, compact: true))
                }
            }
            if let error {
                Text(error).font(.ddCaption).foregroundStyle(Color.ddError)
            }
        }
        .ddCard(.large)
    }
}
