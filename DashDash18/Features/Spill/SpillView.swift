import SwiftUI

/// «Spill»-fanen (fase 13): ny runde på sekunder, bli med med kode, dine løse runder (pågår og
/// ferdige) og det felles banebiblioteket. Vises bare når `LooseRoundsFeature` er på.
struct SpillView: View {
    @State var model: SpillModel
    @State private var showsNew = false
    @State private var showsJoin = false
    @State private var openRound: UUID?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        DDList {
            Section {
                VStack(alignment: .leading, spacing: DDSpacing.s) {
                    Text("Spill en runde")
                        .font(.ddTitle)
                        .foregroundStyle(Color.ddInk)
                    Text("Med venner, uten klubb. Velg bane, legg til folk og gjester, og før på telefonen.")
                        .font(.ddCallout)
                        .foregroundStyle(Color.ddInkSecondary)
                    Button("Ny runde", systemImage: "plus") { showsNew = true }
                        .buttonStyle(.dd(.primary, fullWidth: true))
                        .disabled(model.client == nil)
                    Button("Bli med med kode", systemImage: "qrcode.viewfinder") { showsJoin = true }
                        .buttonStyle(.dd(.secondary, fullWidth: true))
                        .disabled(model.client == nil)
                }
                .padding(.vertical, DDSpacing.s)
            }

            if case .failed(let message) = model.state {
                Section {
                    Label(message, systemImage: "wifi.exclamationmark").ddErrorStyle()
                }
            }

            roundsSection("Pågår", items: model.ongoing,
                          empty: model.state == .loaded ? "Ingen runder går nå." : nil)
            roundsSection("Ferdige", items: model.finished,
                          empty: model.state == .loaded ? "Rundene du avslutter, havner her med resultatet." : nil)

            Section {
                NavigationLink {
                    if let client = model.client {
                        LibraryCoursesView(model: CourseLibraryModel(shared: client, userID: model.userID))
                    }
                } label: {
                    Label("Banebiblioteket", systemImage: "map")
                }
            } footer: {
                DDFooter("Banene alle kan spille. Mangler banen din, legger du den inn selv.")
            }
        }
        .overlay {
            if model.state == .loading { ProgressView() }
        }
        .task { await model.load() }
        .refreshable { await model.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.load() } }
        }
        .navigationDestination(item: $openRound) { roundID in
            if let context = model.looseContext(roundID) {
                LooseRoundScreen(context: context)
                    .onDisappear { Task { await model.load() } }
            }
        }
        .sheet(isPresented: $showsNew) {
            if let client = model.client {
                NavigationStack {
                    NyRundeView(model: NyRundeModel(client: client, userID: model.userID, me: model.me)) { roundID in
                        showsNew = false
                        openRound = roundID
                        Task { await model.load() }
                    }
                }
                .tint(Color.ddForestInk)
            }
        }
        .sheet(isPresented: $showsJoin) {
            if let client = model.client {
                NavigationStack {
                    JoinRoundView(model: JoinRoundModel(client: client, myName: model.me?.displayName, code: nil)) { roundID in
                        showsJoin = false
                        openRound = roundID
                        Task { await model.load() }
                    }
                }
                .tint(Color.ddForestInk)
            }
        }
    }

    @ViewBuilder
    private func roundsSection(_ title: String, items: [MyRoundItem], empty: String?) -> some View {
        if !items.isEmpty || empty != nil {
            Section {
                if items.isEmpty, let empty {
                    Text(empty)
                        .font(.ddCallout)
                        .foregroundStyle(Color.ddInkSecondary)
                }
                ForEach(items) { item in
                    Button { openRound = item.id } label: { MyRoundRow(item: item) }
                        .buttonStyle(.plain)
                }
            } header: {
                DDHeader(title)
            }
        }
    }
}

/// Én runde i lista: bane, dato og resultat.
struct MyRoundRow: View {
    let item: MyRoundItem

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.ddBodyEmphasis)
                    .foregroundStyle(Color.ddInk)
                Text(item.subtitle)
                    .font(.ddCaption)
                    .foregroundStyle(Color.ddInkSecondary)
                if let mine = item.mine {
                    Text(mine)
                        .font(.ddCallout)
                        .foregroundStyle(Color.ddInk)
                }
                if let leader = item.leader {
                    Text(leader)
                        .font(.ddCaption)
                        .foregroundStyle(Color.ddInkSecondary)
                }
            }
            Spacer(minLength: 8)
            if item.status == .active {
                DDPill("Pågår", tone: .live)
                    .fixedSize()
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.ddInkSecondary)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// En løs runde: samme runde-skjerm og føring som kvelden (hullkort, utboks, realtime), hentet på id.
struct LooseRoundScreen: View {
    @State private var model: RundeModel
    @Environment(\.scoreSubmitter) private var submitter
    @Environment(\.scenePhase) private var scenePhase
    @Environment(OutboxStatus.self) private var outbox: OutboxStatus?

    init(context: LooseRoundContext) {
        _model = State(initialValue: RundeModel(loose: context))
    }

    var body: some View {
        content
            .task {
                model.submitter = submitter
                await model.load()
            }
            // Som kvelden: hent hvert 30. sekund når realtime ikke dekker det.
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    if Task.isCancelled { break }
                    if !model.isLive || !model.pendingHoles.isEmpty {
                        await model.load()
                    }
                }
            }
            .onChange(of: outbox?.pendingCount) { old, new in
                if let old, let new, new < old, !model.isLive {
                    Task { await model.load() }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await model.load() } }
            }
            .onDisappear { Task { await model.stopRealtime() } }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .checking:
            ProgressView("Henter runden …")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            RundeView(model: model)
        case .none:
            ContentUnavailableView("Fant ikke runden", systemImage: "flag.slash",
                                   description: Text("Den kan være slettet, eller du er ikke med lenger."))
        case .failed(let message):
            ContentUnavailableView {
                Label("Fikk ikke hentet runden", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Prøv igjen") { Task { await model.load() } }
                    .buttonStyle(.dd(.primary))
            }
        }
    }
}

/// Under en løs runde: inviter, avslutt (eieren) og del resultatet.
struct LooseRoundActions: View {
    let model: RundeModel
    @State private var showsInvite = false
    /// «Del regningen» (fase 17, `BillSplitFeature`).
    @State private var showsBill = false
    @State private var confirmsFinish = false
    @State private var isFinishing = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DDSpacing.s) {
            if let game = model.game, game.status == .locked {
                ResultShareButton(share: game.share(viewer: model.viewer))
                    .buttonStyle(.dd(.primary, fullWidth: true))
            }
            if model.canInvite {
                Button("Inviter med lenke eller QR", systemImage: "qrcode") { showsInvite = true }
                    .buttonStyle(.dd(.secondary, fullWidth: true))
            }
            if BillSplitFeature.isEnabled {
                Button("Del regningen", systemImage: "creditcard") { showsBill = true }
                    .buttonStyle(.dd(.secondary, fullWidth: true))
            }
            if model.canFinish {
                Button("Avslutt runden", systemImage: "flag.checkered") { confirmsFinish = true }
                    .buttonStyle(.dd(.secondary, fullWidth: true))
                    .disabled(isFinishing)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle").ddErrorStyle()
            }
        }
        .padding(.top, DDSpacing.s)
        .sheet(isPresented: $showsInvite) {
            if let loose = model.looseContext {
                NavigationStack {
                    InviteView(model: InviteModel(client: loose.client, roundID: loose.roundID,
                                                  courseName: model.game?.snapshot.course?.name))
                }
                .tint(Color.ddForestInk)
            }
        }
        .sheet(isPresented: $showsBill) {
            BillSplitView(people: billNames)
        }
        .confirmationDialog("Avslutte runden?", isPresented: $confirmsFinish, titleVisibility: .visible) {
            Button("Avslutt runden") { finish() }
            Button("Avbryt", role: .cancel) {}
        } message: {
            Text("Ingen kan føre mer, og invitasjonen slutter å virke. Resultatet står i «Mine runder».")
        }
    }

    /// Navnene i runden, med deg først.
    private var billNames: [String] {
        guard let snapshot = model.game?.snapshot else { return [] }
        return BillSplit.names(players: snapshot.players.map(\.memberID), names: snapshot.names, me: model.viewer.memberID)
    }

    private func finish() {
        isFinishing = true
        error = nil
        Task {
            defer { isFinishing = false }
            do throws(DataError) {
                try await model.finish()
            } catch {
                self.error = error.message
            }
        }
    }
}
