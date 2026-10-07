import GolfgutuCore
import SwiftUI

/// Veddemålene i sesongen: banken øverst, åpne (utfordret deg, dine, resten), avgjorte, og
/// veien til poengtabellen. Nytt veddemål fra verktøylinja. Bak `BetsFeature.isEnabled`.
struct BetsView: View {
    @Environment(\.clubContext) private var context
    /// Åpne vedd-arket med en gang (fra runden): på en spiller, eller på deg selv med din egen id.
    var against: UUID?

    var body: some View {
        if let context {
            BetsContent(model: BetsModel(context: context), openFor: against)
        } else {
            ContentUnavailableView("Ikke logget inn", systemImage: "person.crop.circle.badge.questionmark")
        }
    }
}

/// Hvem vedd-arket gjelder.
private struct SheetTarget: Identifiable {
    let against: UUID?
    var id: String { against?.uuidString ?? "meg" }
}

private struct BetsContent: View {
    @State var model: BetsModel
    var openFor: UUID?
    @State private var sheet: SheetTarget?
    @State private var openedInitial = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        content
            .navigationTitle("Veddemål")
            .ddNavigationChrome()
            .task {
                await model.load()
                if !openedInitial, let openFor, model.board != nil {
                    openedInitial = true
                    sheet = SheetTarget(against: openFor == model.clubContext.memberID ? nil : openFor)
                }
            }
            .refreshable { await model.load() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await model.load() } }
            }
            .toolbar {
                if let board = model.board {
                    ToolbarItem(placement: .topBarTrailing) {
                        NewBetMenu(board: board) { sheet = SheetTarget(against: $0) }
                    }
                }
            }
            .sheet(item: $sheet) { target in
                if let board = model.board {
                    VeddArk(model: model, draft: BetSheetDraft(board: board, against: target.against, game: board.activeGame))
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .disabled:
            ContentUnavailableView("Veddemål kommer", systemImage: "die.face.5",
                                   description: Text("Veddemål med poeng slås på når databasen er klar."))
        case .loading:
            ProgressView("Henter veddemålene …")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Fikk ikke hentet veddemålene", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Prøv igjen") { Task { await model.load() } }
                    .buttonStyle(.dd(.primary))
            }
        case .loaded:
            if let board = model.board {
                BetsList(model: model, board: board)
            } else {
                ContentUnavailableView("Ingen sesong i gang", systemImage: "trophy",
                                       description: Text("Veddemål hører til en sesong."))
            }
        }
    }
}

/// «+»: vedd på deg selv eller på en spiller i runden (ellers troppen).
private struct NewBetMenu: View {
    let board: BetsBoard
    let open: (UUID?) -> Void

    var body: some View {
        Menu {
            Button("Om meg selv") { open(nil) }
            Section("Vedd på") {
                ForEach(opponents, id: \.self) { id in
                    Button(board.names[id] ?? "Ukjent") { open(id) }
                }
            }
        } label: {
            Label("Nytt veddemål", systemImage: "plus")
        }
        .tint(Color.ddOnDark)
    }

    private var opponents: [UUID] {
        let ids = board.activeGame.map { $0.snapshot.players.map(\.memberID) } ?? Array(board.names.keys)
        return ids.filter { $0 != board.me }
            .sorted { NorwegianSort.areInIncreasingOrder(board.names[$0] ?? "", board.names[$1] ?? "") }
    }
}

private struct BetsList: View {
    let model: BetsModel
    let board: BetsBoard

    var body: some View {
        DDList {
            Section {
                BankHeader(board: board)
                    .listRowBackground(Color.ddHeroCard)
                NavigationLink {
                    BetPointsTableView(board: board)
                } label: {
                    Label("Poengtabell for veddemål", systemImage: "list.number")
                        .font(.ddBodyEmphasis)
                        .foregroundStyle(Color.ddForestInk)
                }
            }
            if board.openCount == 0 {
                Section {
                    ContentUnavailableView("Ingen åpne veddemål", systemImage: "die.face.5",
                                           description: Text(board.settled.isEmpty
                                                             ? "Noen må jo starte. Trykk + for å vedde på en spiller eller deg selv."
                                                             : "Alt er gjort opp. Trykk + for et nytt."))
                }
            }
            itemSection("Utfordret deg", board.challenged)
            itemSection("Dine", board.mine)
            itemSection("Åpne veddemål", board.others)
            if !board.settled.isEmpty {
                DDSection("Avgjort") {
                    ForEach(board.settled) { item in
                        SettledRow(item: item)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func itemSection(_ title: String, _ items: [BetsBoard.Item]) -> some View {
        if !items.isEmpty {
            DDSection("\(title) · \(items.count)") {
                ForEach(items) { item in
                    BetCard(model: model, board: board, item: item)
                }
            }
        }
    }
}

/// Saldo og ledig, i grønt hero-kort.
private struct BankHeader: View {
    let board: BetsBoard

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Poengbanken · \(board.seasonName)").ddEyebrow(color: .ddGold)
            if let row = board.myRow {
                HStack(alignment: .firstTextBaseline) {
                    Text(board.hasBank ? "Saldo" : "Netto")
                        .font(.ddCallout)
                    Spacer(minLength: 8)
                    Text(board.hasBank ? BetTexts.points(row.balance ?? 0) : BetTexts.signed(row.net))
                        .font(.ddNumberLarge)
                        .monospacedDigit()
                        .foregroundStyle(Color.ddGold)
                }
                Text(detail(row))
                    .font(.ddCallout)
                    .foregroundStyle(Color.ddOnDark.opacity(0.8))
            } else {
                Text("Du er ikke med i tabellen.")
                    .font(.ddCallout)
            }
        }
        .foregroundStyle(Color.ddOnDark)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private func detail(_ row: BetTableRow) -> String {
        var parts: [String] = []
        if let available = row.available { parts.append("\(BetTexts.points(available)) ledig") }
        if row.atStake > 0 { parts.append("\(BetTexts.points(row.atStake)) står i åpne veddemål") }
        parts.append("netto \(BetTexts.signed(row.net))")
        return parts.joined(separator: " · ")
    }
}

// MARK: - Kortet

/// Statuspillens farge: åpent lime, stengt sol, avgjort og annullert sand (C7).
private func tone(_ phase: BetPhase) -> DDTone {
    switch phase {
    case .open: .lime
    case .closed: .sun
    case .resolvedYes, .resolvedNo, .void: .earth
    }
}

private struct BetCard: View {
    let model: BetsModel
    let board: BetsBoard
    let item: BetsBoard.Item
    @State private var side: BetSide = .yes
    @State private var points: Int?
    @State private var error: String?
    @State private var showStakers = false
    @State private var confirmResolve = false
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                DDPill(BetTexts.phase(item.phase), tone: tone(item.phase))
                if item.challengesMe {
                    DDPill("Utfordret deg", tone: .blush)
                } else if let mySide = item.mySide {
                    DDPill("Din: \(BetTexts.sideShort(mySide)) \(BetTexts.points(item.myPoints))", tone: .outlineRust)
                }
                Spacer(minLength: 4)
                Text(item.creatorName)
                    .font(.ddCaption)
                    .foregroundStyle(Color.ddInkSecondary)
            }
            Text("«\(item.row.question)»")
                .font(.ddBodyEmphasis)
                .foregroundStyle(Color.ddInk)
            PoolBar(yes: item.yesPool, no: item.noPool, share: item.yesShare)
            if let reason = item.closedReason {
                Text(reason + (item.bet.condition == nil ? " Venter på arrangøren." : " Avgjøres av scorene."))
                    .font(.ddCaption)
                    .foregroundStyle(Color.ddInkSecondary)
            }
            if !item.stakers.isEmpty {
                Button(showStakers ? "Skjul hvem som har satset" : "Vis hvem som har satset (\(item.stakers.count))") {
                    showStakers.toggle()
                }
                .buttonStyle(.dd(.text, compact: true))
                if showStakers {
                    ForEach(Array(item.stakers.enumerated()), id: \.offset) { _, s in
                        HStack {
                            Text(s.name).font(.ddCallout)
                            Spacer()
                            Text("\(BetTexts.sideShort(s.side)) \(BetTexts.points(s.points))")
                                .font(.ddMonoSmall)
                                .foregroundStyle(s.side == .yes ? Color.ddLimeInk : Color.ddRustText)
                        }
                    }
                }
            }
            if item.acceptsStakes {
                stakeControls
            }
            if let error {
                Text(error).ddErrorStyle()
            }
            if item.resolverHasStake {
                Text("Du har satset på dette, så en annen arrangør må avgjøre det.")
                    .font(.ddCaption)
                    .foregroundStyle(Color.ddInkSecondary)
            } else if item.canResolve {
                Button("Avgjør veddemålet …") { confirmResolve = true }
                    .buttonStyle(.dd(.text, compact: true))
                    .disabled(busy || model.isSaving)
                    .confirmationDialog("Avgjør «\(item.row.question)»", isPresented: $confirmResolve, titleVisibility: .visible) {
                        Button("JA vant") { resolve(.yes) }
                        Button("NEI vant") { resolve(.no) }
                        Button("Annuller (alle får innsatsen tilbake)", role: .destructive) { resolve(.void) }
                    } message: {
                        Text("Kan ikke angres.")
                    }
            }
        }
        .padding(.vertical, 6)
        .onAppear {
            side = item.mySide ?? .yes
        }
    }

    private var amount: Int { points ?? board.rules.bets.defaultStake }

    /// Hva som er galt med innsatsen som er valgt, før den sendes (samme sjekk som databasen).
    private var problem: String? {
        BetStakeCheck.problem(item, side: item.mySide ?? side, points: amount, board: board)
    }

    @ViewBuilder
    private var stakeControls: some View {
        if item.mySide == nil {
            HStack(spacing: 8) {
                ForEach(BetSide.allCases, id: \.self) { s in
                    Button(BetTexts.sideShort(s)) { side = s }
                        .buttonStyle(DDChoiceButtonStyle(selected: side == s, tint: s == .yes ? .lime : .blush))
                }
            }
        }
        HStack(spacing: 8) {
            ForEach(board.rules.bets.stakeOptions, id: \.self) { n in
                Button("\(n)") { points = n }
                    .buttonStyle(DDChoiceButtonStyle(selected: amount == n))
                    .accessibilityLabel("\(n) poeng")
            }
        }
        Text(board.stakeHint(already: item.myPoints))
            .font(.ddCaption)
            .foregroundStyle(Color.ddInkSecondary)
        Button("Sats \(amount) poeng på \(BetTexts.sideShort(item.mySide ?? side))") {
            stake()
        }
        .buttonStyle(.dd(.money, fullWidth: true))
        .disabled(busy || model.isSaving || problem != nil)
        if error == nil, let problem {
            Text(problem).ddErrorStyle()
        }
    }

    /// `busy` settes med en gang trykket kommer, så et dobbelttrykk ikke sender to ganger.
    private func stake() {
        guard !busy else { return }
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                try await model.stake(item, side: item.mySide ?? side, points: amount)
            } catch {
                self.error = DataError.from(error).message
            }
        }
    }

    private func resolve(_ verdict: BetVerdict) {
        guard !busy else { return }
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                try await model.resolve(item, verdict: verdict)
            } catch {
                self.error = DataError.from(error).message
            }
        }
    }
}

/// JA mot NEI som en delt stolpe, med summene under.
private struct PoolBar: View {
    let yes: Double
    let no: Double
    let share: Double

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    Capsule().fill(Color.ddLime).frame(width: max(4, geo.size.width * share))
                    Capsule().fill(Color.ddRust)
                }
            }
            .frame(height: 8)
            HStack {
                Text("JA \(BetTexts.points(yes))").foregroundStyle(Color.ddLimeInk)
                Spacer()
                Text("NEI \(BetTexts.points(no))").foregroundStyle(Color.ddRustText)
            }
            .font(.ddMonoSmall)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("JA \(BetTexts.points(yes)) poeng, NEI \(BetTexts.points(no)) poeng")
    }
}

/// Et avgjort veddemål, komprimert: utfallet og ditt resultat.
private struct SettledRow: View {
    let item: BetsBoard.Item

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.row.question)
                    .font(.ddCallout)
                    .lineLimit(2)
                Text(detail)
                    .font(.ddCaption)
                    .foregroundStyle(Color.ddInkSecondary)
            }
            Spacer(minLength: 8)
            if let result = item.myResult {
                Text(BetTexts.signed(result))
                    .font(.ddNumber)
                    .monospacedDigit()
                    .foregroundStyle(result >= 0 ? Color.ddLimeInk : Color.ddRustText)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        let outcome = BetTexts.phase(item.phase)
        if let side = item.mySide {
            return "\(outcome) · du satset \(BetTexts.points(item.myPoints)) på \(BetTexts.sideShort(side))"
        }
        return outcome + " · " + BetTexts.resolvedBy(item.resolvedByName)
    }
}

// MARK: - Poengtabellen

/// Poengtabellen for veddemål, separat fra jakketabellen.
struct BetPointsTableView: View {
    let board: BetsBoard

    var body: some View {
        DDList {
            DDSection("Poengtabell · \(board.seasonName)") {
                ForEach(board.table) { r in
                    DDRankRow(place: "\(r.place).", name: r.row.name, detail: detail(r.row), isMe: r.isMe) {
                        DDRankValue(board.hasBank ? BetTexts.points(r.row.balance ?? 0) : BetTexts.signed(r.row.net))
                    }
                }
            }
            Section {
                DDFooter(footer)
            }
        }
        .navigationTitle("Poengtabell")
        .ddNavigationChrome()
    }

    private func detail(_ row: BetTableRow) -> String {
        var parts = ["netto \(BetTexts.signed(row.net))"]
        if row.atStake > 0 { parts.append("\(BetTexts.points(row.atStake)) ute") }
        parts.append(row.bets == 1 ? "1 veddemål" : "\(row.bets) veddemål")
        if row.won > 0 { parts.append("\(row.won) vunnet") }
        return parts.joined(separator: " · ")
    }

    private var footer: String {
        let start = board.rules.bets.startingPoints.map { "Alle starter sesongen med \($0) poeng, og ny sesong gir ny bank. " } ?? ""
        let whole = board.rules.bets.payoutDecimals == 0 ? " Oppgjøret er i hele poeng." : ""
        return start + "Vinnersiden deler taperpotten etter innsats." + whole + " Tabellen teller ikke i jakkeracet."
    }
}
