import GolfgutuCore
import Supabase
import SwiftUI

/// Én konkurranse fra lista: lager modellen og henter.
struct CompetitionDetailScreen: View {
    let list: CompetitionsModel
    let competition: CompetitionRow

    var body: some View {
        if let client = list.client {
            CompetitionDetailView(model: CompetitionDetailModel(client: client, competition: competition,
                                                                participants: list.participants(competition),
                                                                access: list.access, main: list.main),
                                  list: list)
        }
    }
}

/// Tabellen for konkurransen: jakkeracet som på Tavla, ligatabellen, eller cuptreet.
struct CompetitionDetailView: View {
    @State var model: CompetitionDetailModel
    var list: CompetitionsModel?
    /// Vist inne i Tavla (velgeren): uten egen tittel.
    var embedded = false

    @State private var resultFor: CupStandings.Game?
    @State private var confirmsDraw = false
    @State private var showsInvite = false
    @State private var showsPaywall = false
    /// Økes når betalingsveggen lukkes, så siden spør serveren på nytt.
    @State private var unlockCheck = 0
    @Environment(PurchaseService.self) private var purchases: PurchaseService?

    var body: some View {
        content
            .task { await model.load() }
            .task(id: unlockCheck) { await model.checkUnlock(purchases: purchases) }
            .refreshable {
                await model.load()
                await list?.load()
            }
            .navigationTitle(embedded ? "" : model.competition.name)
            .ddNavigationChrome()
            .toolbar {
                if !embedded, let list, list.canInvite(model.competition) {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Inviter", systemImage: "person.badge.plus") { showsInvite = true }
                    }
                }
            }
            .sheet(isPresented: $showsInvite) {
                if let client = list?.client {
                    NavigationStack {
                        InviteView(model: inviteModel(client: client))
                    }
                }
            }
            .sheet(isPresented: $showsPaywall, onDismiss: { unlockCheck += 1 }) {
                PaywallView(service: purchases, competitionID: model.competition.id,
                            competitionName: model.competition.name, clubID: model.competition.clubID)
            }
            .sheet(item: $resultFor) { game in
                NavigationStack {
                    CupResultSheet(model: model, game: game) { resultFor = nil }
                }
                .presentationDetents([.medium, .large])
            }
            .alert("Det gikk ikke", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.error ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView("Henter tabellen …")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Fikk ikke hentet konkurransen", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Prøv igjen") { Task { await model.load() } }
                    .buttonStyle(.dd(.primary))
            }
        case .loaded:
            switch model.content {
            case .season(let standings?):
                TavlaList(standings: standings)
            case .league(let standings):
                scroll { LeagueTableSection(standings: standings) }
            case .cup(let cup):
                scroll { cupSections(cup) }
            case .season(nil), nil:
                scroll {
                    ContentUnavailableView("Ingen tabell ennå", systemImage: "trophy",
                                           description: Text("Tabellen fylles når første runde er spilt."))
                        .ddCard(.empty)
                }
            }
        }
    }

    private func scroll(@ViewBuilder _ body: () -> some View) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DDSpacing.cardGap) {
                CompetitionHeaderCard(competition: model.competition, clubName: list?.clubName(of: model.competition))
                CompetitionUnlockSection(notice: model.lockNotice(purchases: purchases), isWorking: model.isUnlocking,
                                         error: model.unlockError, onUnlock: unlock)
                if let list {
                    CompetitionSignupButton(model: list, competition: model.competition)
                }
                body()
            }
            .padding(.horizontal, DDSpacing.gutter)
            .padding(.vertical, DDSpacing.l)
        }
    }

    /// Låser opp konkurransen: betalingsveggen for akkurat denne, eller en ledig kreditt.
    private func unlock() {
        switch model.lockNotice(purchases: purchases) {
        case .purchase:
            showsPaywall = true
        case .useCredit:
            Task {
                if await model.useCredit(purchases: purchases) { await list?.load() }
            }
        case .hidden, .waitForOrganizer:
            break
        }
    }

    /// Koden til konkurransen. Eieren kan fornye og trekke den tilbake (sql/022).
    private func inviteModel(client: SupabaseClient) -> InviteModel {
        let id = model.competition.id
        let manage = model.isAdmin
            ? InviteModel.Manage(renew: { try await CompetitionQueries.invite(client: client, competitionID: id, renew: true) },
                                 revoke: { try await CompetitionQueries.revokeInvite(client: client, competitionID: id) })
            : nil
        return InviteModel(target: .competition(name: model.competition.name), manage: manage) {
            try await CompetitionQueries.invite(client: client, competitionID: id)
        }
    }

    // MARK: Cup

    @ViewBuilder
    private func cupSections(_ cup: CupStandings) -> some View {
        if let champion = cup.champion {
            HStack(spacing: 14) {
                DDJacketIcon()
                    .stroke(Color.ddGold, style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
                    .frame(width: 30, height: 36)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Vinner av \(model.competition.name)")
                        .font(.ddCallout)
                        .foregroundStyle(Color.ddOnDark.opacity(0.8))
                    Text(champion.name)
                        .font(.ddTitleSmall)
                }
                Spacer()
            }
            .ddCard(.hero)
            .accessibilityElement(children: .combine)
        } else if let next = cup.myNext {
            DDInfoStripe(tone: .sun) {
                Text(LocalizedStringKey(nextText(next, cup: cup)))
            }
        }

        if !cup.isDrawn {
            VStack(alignment: .leading, spacing: 10) {
                Text("Ikke trukket ennå")
                    .font(.ddBodyEmphasis)
                Text("Seeding: \(CompetitionText.seeding(model.competition.rules.competitionRules.cup.seeding)). "
                     + "Likt etter siste hull: \(CompetitionText.tie(model.competition.rules.competitionRules.cup.tie).lowercased()).")
                    .font(.ddCallout)
                    .foregroundStyle(Color.ddInkSecondary)
                if model.isAdmin {
                    Button("Trekk cupen") { confirmsDraw = true }
                        .buttonStyle(.dd(.primary, fullWidth: true))
                        .disabled(model.isWorking)
                        .confirmationDialog("Trekk cupen nå?", isPresented: $confirmsDraw, titleVisibility: .visible) {
                            Button("Trekk") { Task { await model.draw() } }
                        } message: {
                            Text("Alle påmeldte kommer med. Trekningen kan gjøres om til første resultat er ført.")
                        }
                }
            }
            .ddCard()
        } else {
            DDSectionLabel("Treet")
            CupTreeView(cup: cup, right: model.recordRight) { resultFor = $0 }
        }
    }

    private func nextText(_ game: CupStandings.Game, cup: CupStandings) -> String {
        let round = CompetitionText.cupRound(game.round, of: cup.rounds.count)
        guard let opponent = game.a?.isMe == true ? game.b : game.a else {
            return "**\(round)**: motstanderen din er ikke klar ennå."
        }
        return "**\(round)**: du møter \(opponent.name)."
    }
}

/// Type, eier, periode og hvem som er med.
struct CompetitionHeaderCard: View {
    let competition: CompetitionRow
    let clubName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(CompetitionText.subtitle(competition, clubName: clubName))
                .ddEyebrow()
            Text(CompetitionText.kindHelp(competition.kind))
                .font(.ddCallout)
                .foregroundStyle(Color.ddInkSecondary)
            Label(CompetitionText.entry(competition.entry), systemImage: "person.2")
                .font(.ddCallout)
                .labelStyle(DDIconLabelStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ddCard()
    }
}

/// Ligatabellen (også morroturnering).
struct LeagueTableSection: View {
    let standings: LeagueStandings

    var body: some View {
        DDSectionLabel("Tabellen") {
            Text(standings.roundCount == 1 ? "1 runde" : "\(standings.roundCount) runder")
                .ddEyebrow()
        }
        if standings.rows.isEmpty {
            ContentUnavailableView("Ingen er med ennå", systemImage: "person.3",
                                   description: Text("De påmeldte står her, og tabellen fylles når en runde teller."))
                .ddCard(.empty)
        } else {
            VStack(spacing: 0) {
                ForEach(standings.rows) { row in
                    DDRankRow(place: standings.placeText(row), name: row.name, detail: standings.detail(row),
                              isMe: row.isMe) {
                        DDRankValue(LeagueStandings.points(row.total))
                    }
                    if row.id != standings.rows.last?.id { DDDivider() }
                }
            }
            .ddCard(padding: DDSpacing.l)
        }
        Text(standings.rulesSummary)
            .font(.ddCaption)
            .foregroundStyle(Color.ddInkSecondary)
            .padding(.horizontal, DDSpacing.s)
    }
}

/// Cuptreet: én kolonne per runde, kampene sentrert mot kampen de leder til.
struct CupTreeView: View {
    let cup: CupStandings
    /// Hvem kan føre hva (`CupRecording`): spillerne sin egen kamp, arrangøren alle.
    let right: (CupStandings.Game) -> CupRecording.Right
    let onRecord: (CupStandings.Game) -> Void

    private let cardHeight: CGFloat = 126
    private let gap: CGFloat = 10

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(Array(cup.rounds.enumerated()), id: \.offset) { index, games in
                    let unit = cardHeight + gap
                    let step = unit * CGFloat(1 << index)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(cup.roundTitles[index])
                            .ddEyebrow()
                            .padding(.bottom, 8)
                        VStack(spacing: step - cardHeight) {
                            ForEach(games) { game in
                                CupGameCard(game: game, right: right(game), onRecord: { onRecord(game) })
                                    .frame(height: cardHeight)
                            }
                        }
                        .padding(.top, (step - unit) / 2)
                    }
                    .frame(width: 190)
                }
            }
            .padding(.vertical, 4)
        }
        .scrollClipDisabled()
    }
}

struct CupGameCard: View {
    let game: CupStandings.Game
    let right: CupRecording.Right
    let onRecord: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            line(game.a)
            if game.isBye {
                Text("Walkover (bye)")
                    .font(.ddCaption)
                    .foregroundStyle(Color.ddInkSecondary)
            } else {
                line(game.b)
            }
            HStack {
                Text(footer)
                    .font(.ddCaption)
                    .foregroundStyle(Color.ddInkSecondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if right != .none {
                    Button(game.winner == nil ? "Før" : "Endre", action: onRecord)
                        .buttonStyle(.dd(.text, compact: true))
                        .fixedSize()
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.ddCard, in: .rect(cornerRadius: 18))
        .clipShape(.rect(cornerRadius: 18))
        .overlay {
            if game.a?.isMe == true || game.b?.isMe == true {
                RoundedRectangle(cornerRadius: 18).stroke(Color.ddForestInk.opacity(0.5), lineWidth: 1.5)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var footer: String {
        if game.walkover { return "Walkover" }
        if let result = game.result { return result }
        switch game.state {
        case .waiting: return "Venter"
        case .ready: return "Klar"
        case .decided: return game.isBye ? "" : "Avgjort"
        }
    }

    @ViewBuilder
    private func line(_ side: CupStandings.Side?) -> some View {
        let won = side != nil && side?.participantID == game.winner
        HStack(spacing: 6) {
            if let seed = side?.seed {
                Text("\(seed)")
                    .font(.ddCaption)
                    .monospacedDigit()
                    .foregroundStyle(Color.ddInkSecondary)
                    .frame(minWidth: 14, alignment: .trailing)
            }
            Text(side?.name ?? "—")
                .font(won ? .ddBodyEmphasis : .ddBody)
                .foregroundStyle(side == nil ? Color.ddInkSecondary : Color.ddInk)
                .lineLimit(1)
            if won {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.ddForestInk)
                    .accessibilityLabel("vant")
            }
        }
    }
}

/// Vinneren av en kamp: forslag fra runden de spilte, walkover og tekst. Spillerne fører selv én
/// gang; arrangøren eller eieren kan også rette og fjerne.
struct CupResultSheet: View {
    let model: CompetitionDetailModel
    let game: CupStandings.Game
    let onDone: () -> Void

    @State private var winner: UUID?
    @State private var walkover = false
    @State private var text = ""
    @State private var roundID: UUID?

    var body: some View {
        DDForm {
            if let s = suggestion {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(suggestionText(s.decision))
                            .font(.ddBodyEmphasis)
                        if let title = model.roundTitle(s.roundID) {
                            Text("Fra runden \(title)")
                                .font(.ddCaption)
                                .foregroundStyle(Color.ddInkSecondary)
                        }
                    }
                    if case .won(let w, _, _, _) = s.decision, let id = participant(entrantKey: w) {
                        Button("Bruk forslaget") {
                            winner = id
                            walkover = false
                            text = CompetitionText.cupResult(s.decision) ?? ""
                            roundID = s.roundID
                        }
                    }
                } header: {
                    DDHeader("Forslag")
                }
            }
            Section {
                Picker("Vinner", selection: $winner) {
                    // Bare arrangøren fjerner et resultat. Spilleren må velge en vinner.
                    Text(model.isAdmin ? "Ikke avgjort" : "Ikke valgt").tag(UUID?.none)
                    ForEach([game.a, game.b].compactMap(\.self), id: \.participantID) { side in
                        Text(side.name).tag(Optional(side.participantID))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                Toggle("Walkover", isOn: $walkover)
                    .disabled(winner == nil)
                TextField("Resultat, f.eks. 3&2", text: $text)
                    .disabled(winner == nil)
            } header: {
                DDHeader("Vinner")
            } footer: {
                DDFooter(model.isAdmin
                         ? "Vinneren går videre i treet. Spillerne kan føre selv. Du kan rette til neste kamp er avgjort."
                         : "Vinneren går videre i treet. Første resultat som føres, gjelder. Bare arrangøren eller eieren kan endre det etterpå.")
            }
        }
        .navigationTitle("\(game.a?.name ?? "") – \(game.b?.name ?? "")")
        .navigationBarTitleDisplayMode(.inline)
        .ddNavigationChrome()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Avbryt", action: onDone)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Lagre") { save() }
                    .disabled(model.isWorking || (winner == nil && game.winner == nil))
            }
        }
        .onAppear {
            winner = game.winner
            walkover = game.walkover
            text = game.result ?? ""
        }
    }

    private var suggestion: (roundID: UUID, decision: Cup.Decision)? { model.suggestion(for: game) }

    /// Forslaget peker på personen (`Entrant.key`); finn påmeldingen.
    private func participant(entrantKey: String) -> UUID? {
        guard let detail = model.detail else { return nil }
        return [game.a, game.b].compactMap(\.self).first { side in
            detail.participants.first { $0.id == side.participantID }
                .flatMap { detail.scope.entrant(for: $0, directory: detail.directory) }?.key == entrantKey
        }?.participantID
    }

    private func suggestionText(_ d: Cup.Decision) -> String {
        switch d {
        case .won(let w, _, _, _):
            let name = participant(entrantKey: w).flatMap { id in [game.a, game.b].first { $0?.participantID == id } }??.name
            return "\(name ?? "Ukjent") vant \(CompetitionText.cupResult(d) ?? "")"
        case .tied: return "Likt etter siste hull. Før vinneren etter omspillet."
        case .inProgress: return "Pågår: \(CompetitionText.cupResult(d) ?? "")"
        case .notStarted: return "Ingen hull spilt ennå."
        }
    }

    private func save() {
        Task {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            let ok = await model.record(game, winner: winner, walkover: walkover && winner != nil,
                                        result: winner == nil || trimmed.isEmpty ? nil : trimmed,
                                        roundID: winner == nil ? nil : roundID)
            if ok { onDone() }
        }
    }
}
