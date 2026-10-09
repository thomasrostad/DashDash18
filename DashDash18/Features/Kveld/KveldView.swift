import GolfgutuCore
import SwiftUI

/// Kveld-skjermen: neste kveld, ditt svar med angre, hvem som kommer, tråd/tips/veddemål og
/// arrangørens purring. Fra fase 19 åpnes den fra «Neste kveld» på Hjem, med samme `KveldModel`
/// som Hjem (svaret står likt begge steder). Runden som går, åpnes fra «Pågår nå».
struct KveldView: View {
    @Environment(\.dayTerm) private var dayTerm
    let model: KveldModel

    var body: some View {
        KveldContent(model: model)
            .navigationTitle(DayTerm.capitalized(dayTerm.the))
            .ddNavigationChrome()
    }
}

/// Innholdet. Hjem eier modellen og følger endringene (realtime og retur fra bakgrunnen); her
/// hentes det bare på nytt når skjermen åpnes eller dras ned.
private struct KveldContent: View {
    @Environment(\.dayTerm) private var dayTerm
    let model: KveldModel

    var body: some View {
        content
            .task { await model.load() }
            .refreshable { await model.load() }
            .onChange(of: dayTerm, initial: true) { _, term in model.dayTerm = term }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView("Henter \(dayTerm.the) …")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Fikk ikke hentet \(dayTerm.the)", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Prøv igjen") { Task { await model.load() } }
                    .buttonStyle(.dd(.primary))
            }
        case .loaded:
            // ScrollView, så «dra ned for å hente på nytt» virker i begge tilfeller.
            ScrollView {
                VStack(alignment: .leading, spacing: DDSpacing.cardGap) {
                    if let event = model.event {
                        DDSectionLabel("Neste \(dayTerm.one)")
                        NextEveningCard(
                            event: event,
                            committee: model.committee,
                            daysUntil: model.daysUntil,
                            referenceYear: EveningDates.year(of: model.today),
                            funCompetitions: model.funCompetitions
                        )
                        .ddCard(.large)
                        if TournamentCoreFeature.isActive {
                            // Fase 23: gruppa mi i startlista (bås, tid, starthull).
                            MyStartGroupCard(model: MyStartGroupModel(client: model.clubContext.client,
                                                                      clubID: model.clubContext.clubID,
                                                                      memberID: model.memberID, eventID: event.id))
                                .id(event.id)
                        }
                        if let entry = model.calendarEntry {
                            AddToCalendarButton(entry: entry)
                        }
                        KveldExtrasCards(model: KveldExtrasModel(context: model.clubContext, eventID: event.id),
                                         refresh: model.loadCount)
                            .id(event.id)
                        SignupSection(model: model)
                            .padding(.top, DDSpacing.l)
                        if Nudge.isOffered(isOrganizer: model.isOrganizer, summary: model.summary) {
                            NudgeSection(targets: model.nudgeTargets) { () async throws(DataError) -> String in
                                try await model.nudge()
                            }
                        }
                        SignupOverviewSection(summary: model.summary, myID: model.memberID)
                    } else {
                        EmptyKveldView()
                            .ddCard(.empty)
                    }
                }
                .padding(.horizontal, DDSpacing.gutter)
                .padding(.vertical, DDSpacing.l)
            }
        }
    }
}

struct EmptyKveldView: View {
    @Environment(\.dayTerm) private var dayTerm
    var body: some View {
        ContentUnavailableView(
            "Ingen \(dayTerm.one) satt opp",
            systemImage: "flag",
            description: Text("Arrangøren legger inn neste \(dayTerm.one) i terminlista.")
        )
    }
}
