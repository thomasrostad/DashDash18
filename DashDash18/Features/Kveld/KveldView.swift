import SwiftUI

/// Kveld-fanen: runden som går, ellers neste kveld, ditt svar og hvem som kommer.
struct KveldView: View {
    @Environment(\.clubContext) private var context

    var body: some View {
        if let context {
            // Går en runde, vises den i stedet for neste kveld.
            RundeGate(context: context) {
                KveldContent(model: KveldModel(context: context))
            }
        } else {
            EmptyKveldView()
        }
    }
}

private struct KveldContent: View {
    @State var model: KveldModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        content
            .task { await model.load() }
            .refreshable { await model.load() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await model.load() }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView("Henter kvelden …")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Fikk ikke hentet kvelden", systemImage: "wifi.exclamationmark")
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
                        DDSectionLabel("Neste kveld")
                        NextEveningCard(
                            event: event,
                            committee: model.committee,
                            daysUntil: model.daysUntil,
                            referenceYear: EveningDates.year(of: model.today)
                        )
                        .ddCard(.large)
                        SignupSection(model: model)
                            .padding(.top, DDSpacing.l)
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

private struct EmptyKveldView: View {
    var body: some View {
        ContentUnavailableView(
            "Ingen kveld satt opp",
            systemImage: "flag",
            description: Text("Arrangøren legger inn neste kveld i terminlista.")
        )
    }
}

#Preview {
    NavigationStack {
        KveldView()
    }
}
