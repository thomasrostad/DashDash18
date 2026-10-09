import GolfgutuCore
import SwiftUI

extension EnvironmentValues {
    /// Hva en dag i turneringen heter (`DayTerm`): «kveld» for Golfgutu, «spilledag» for nye
    /// turneringer. Settes av arrangørsiden og Hjem fra turneringens regelsett.
    @Entry var dayTerm: DayTerm = .evening
}

/// Stegrekka for kvelden: Påmelding → Oppsett → Spilles → Ferdig, med ✓ for det som er gjort og
/// steget kvelden står på markert. Øverst på arrangørsiden og på Kvelden.
struct EveningStepsBar: View {
    let progress: EveningProgress
    @Environment(\.dayTerm) private var dayTerm

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(progress.steps.enumerated()), id: \.element.id) { index, step in
                VStack(spacing: 6) {
                    HStack(spacing: 0) {
                        line(visible: index > 0, done: step.state != .upcoming)
                        marker(step, number: index + 1)
                        line(visible: index < progress.steps.count - 1,
                             done: index + 1 < progress.steps.count && progress.steps[index + 1].state != .upcoming)
                    }
                    Text(step.stage.title)
                        .font(.dd(.sans, size: 12, weight: step.state == .current ? .semibold : .regular,
                                  relativeTo: .caption))
                        .foregroundStyle(step.state == .upcoming ? Color.ddInkSecondary : Color.ddInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func marker(_ step: EveningStepMark, number: Int) -> some View {
        ZStack {
            switch step.state {
            case .done:
                Circle().fill(Color.ddForest)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.ddOnDark)
            case .current:
                Circle().fill(Color.ddLime)
                Text("\(number)")
                    .font(.dd(.sans, size: 12, weight: .semibold, relativeTo: .caption))
                    .foregroundStyle(Color.ddLimeOnAccent)
            case .upcoming:
                Circle().strokeBorder(Color.ddHairline, lineWidth: 1.5)
                Text("\(number)")
                    .font(.dd(.sans, size: 12, relativeTo: .caption))
                    .foregroundStyle(Color.ddInkSecondary)
            }
        }
        .frame(width: 24, height: 24)
    }

    private func line(visible: Bool, done: Bool) -> some View {
        Rectangle()
            .fill(visible ? (done ? Color.ddForest : Color.ddHairline) : Color.clear)
            .frame(height: 2)
            .frame(maxWidth: .infinity)
    }

    private var accessibilityText: String {
        let parts = progress.steps.map { step in
            switch step.state {
            case .done: "\(step.stage.title): ferdig"
            case .current: "\(step.stage.title): nå"
            case .upcoming: step.stage.title
            }
        }
        return DayTerm.capitalized(dayTerm.the) + ": " + parts.joined(separator: ", ")
    }
}

/// Hovedknappen for neste steg. «Avslutt kvelden» har sin egen flyt (spørsmål og avkorting), og
/// «Purr» spør før purringen sendes når `nudge` er gitt. Ellers kalles `perform`.
struct EveningNextStepButton: View {
    let action: TonightAction
    /// Kveldens runder, til «Avslutt kvelden».
    var rounds: [RoundRow] = []
    var title: (RoundRow) -> String = { _ in "Runden" }
    /// De som ikke har svart, til spørsmålet før purringen.
    var nudgeNames: [String] = []
    var isBusy = false
    /// Sender purringen og gir teksten som vises etterpå. nil: «Purr» kaller `perform`.
    var nudge: (() async throws(DataError) -> String)?
    let perform: (TonightAction) -> Void
    /// Etter avslutning eller purring: meldingen som skal vises.
    var onMessage: (String) async -> Void = { _ in }

    @Environment(\.dayTerm) private var dayTerm
    @State private var confirmingNudge = false
    @State private var sending = false

    var body: some View {
        switch action {
        case .closeEvening:
            AvsluttKveldenButton(rounds: rounds, title: title, prominent: true, onDone: onMessage)
        default:
            if let buttonTitle = action.buttonTitle(dayTerm) {
                Button {
                    if case .nudge = action, nudge != nil {
                        confirmingNudge = true
                    } else {
                        perform(action)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(buttonTitle)
                        if isBusy || sending { ProgressView() }
                    }
                }
                .buttonStyle(.dd(.primary, fullWidth: true))
                .disabled(isBusy || sending)
                .confirmationDialog(Nudge.confirmMessage(names: nudgeNames), isPresented: $confirmingNudge,
                                    titleVisibility: .visible) {
                    Button(Nudge.confirmButton) { send() }
                    Button("Avbryt", role: .cancel) {}
                }
            }
        }
    }

    private func send() {
        guard let nudge else { return }
        sending = true
        Task {
            defer { sending = false }
            do throws(DataError) {
                await onMessage(try await nudge())
            } catch {
                await onMessage("Klarte ikke å purre. \(error.message)")
            }
        }
    }
}

/// Kvelden som står for tur: dato og nedtelling, tid og sted, påmeldte, stegrekka og status.
struct EveningNowCard: View {
    let event: EventRow
    let signups: String
    let progress: EveningProgress
    let status: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(EveningDates.longText(event.eventDate, capitalized: true))
                    .font(.ddTitle)
                    .foregroundStyle(Color.ddForestInk)
                Spacer()
                if let days = EveningDates.daysBetween(EveningDates.today(), event.eventDate), days >= 0 {
                    DDPill(EveningDates.countdownText(days: days), tone: .sun)
                        .fixedSize()
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.ddInkSecondary)
            }
            if let line = timeAndPlace {
                Label(line, systemImage: "clock")
            }
            Label(signups, systemImage: "person.2")
            EveningStepsBar(progress: progress)
                .padding(.vertical, 4)
            DDPill(status, tone: EveningStatusTone.tone(progress.action))
        }
        .labelStyle(DDIconLabelStyle())
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var timeAndPlace: String? {
        let parts = [EveningDates.timeText(event.startTime).map { "Kl. \($0)" }, event.venue].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
