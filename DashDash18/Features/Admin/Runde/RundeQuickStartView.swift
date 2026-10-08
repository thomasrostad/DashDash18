import GolfgutuCore
import SwiftUI

/// «Sett opp runden» og «Fortsett kladd»: én rolig bekreftelse. Øverst står forslaget som rader (bane, start,
/// spillere), ferdig utfylt fra forrige runde i sesongen (ellers regelsettet) og med gruppene fordelt fra
/// de påmeldte. Hver rad åpner et vanlig undernivå; alt annet ligger under «Flere valg». Tilbake spør før
/// ulagrede endringer forkastes.
struct RundeQuickStartView: View {
    let model: RundeAdminModel
    @State var draft: RoundDraft
    /// Etter «Lagre som kladd» eller «Start runden», med meldingen som vises der man kom fra.
    let onDone: (String) -> Void

    @State private var bayCount = 1
    @State private var isBusy = false
    @State private var error: String?
    @State private var showsCourse = false
    @State private var showsTee = false
    @State private var showsStart = false
    @State private var showsPlayers = false
    @State private var showsMore = false
    /// Kladden slik den så ut da skjermen åpnet (etter forslagene), for å se om noe er endret.
    @State private var original: RoundDraft?
    /// «Teller også i …» slik det var da valget var hentet.
    @State private var originalLinks: Set<UUID>?
    /// «Teller også i …» (fase 15). Nil når `CompetitionsFeature` er av.
    @State var links: CompetitionLinkModel?

    private var rules: Ruleset { model.rules }
    private var term: GroupTerm { draft.groupTerm }
    private var selectedCourse: CourseListItem? { model.course(draft.courseID) }
    private var showsVenue: Bool { RoundConfirm.showsVenueChoice(model.courses) }

    var body: some View {
        DDForm {
            summarySection
            if let links {
                // Skjules av seg selv når det ikke finnes noe å koble til.
                CountsAlsoInSection(model: links, candidates: links.candidates(players: linkPlayers))
            }
            moreSection
        }
        // Klokka er Oslo-tid (som databasen), også når telefonen står i en annen tidssone.
        .environment(\.timeZone, EveningDates.osloTimeZone)
        .disabled(isBusy)
        .navigationTitle(draft.isSaved ? "Fortsett kladd" : "Sett opp runden")
        .ddNavigationChrome()
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { bottomPanel }
        .discardChangesGuard(hasChanges: hasChanges && !isBusy)
        .navigationDestination(isPresented: $showsCourse) {
            RundeCourseStep(model: model, draft: $draft, showsVenue: showsVenue)
                .navigationTitle("Bane")
                .ddNavigationChrome()
                .navigationBarTitleDisplayMode(.inline)
        }
        .navigationDestination(isPresented: $showsTee) {
            TeePickerView(tees: selectedCourse?.tees ?? [], selected: $draft.teeID)
        }
        .navigationDestination(isPresented: $showsStart) {
            RundeStartStep(model: model, draft: $draft)
                .environment(\.timeZone, EveningDates.osloTimeZone)
                .navigationTitle("Start")
                .ddNavigationChrome()
                .navigationBarTitleDisplayMode(.inline)
        }
        .navigationDestination(isPresented: $showsPlayers) {
            RundeBaysStep(model: model, draft: $draft, bayCount: $bayCount)
                .navigationTitle("Spillere og \(term.plural)")
                .ddNavigationChrome()
                .navigationBarTitleDisplayMode(.inline)
        }
        .navigationDestination(isPresented: $showsMore) {
            RundeSetupStep(model: model, draft: $draft, bayCount: bayCount)
                .navigationTitle("Flere valg")
                .ddNavigationChrome()
                .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            draft.prepareSetup(rules: rules, roster: model.members)
            bayCount = max(1, draft.bays.bayCount)
            // Uten valg mellom simulator og ekte bane følger stedet banen (bare i en ny runde).
            if original == nil, !draft.isSaved, !showsVenue, let course = selectedCourse {
                draft.setVenue(RoundConfirm.venue(for: course), rules: rules)
            }
            // onAppear kommer også når man går tilbake fra et undernivå; utgangspunktet settes én gang.
            if original == nil { original = draft }
            if originalLinks == nil, let links, links.isLoaded { originalLinks = links.selected }
        }
        .task {
            guard CompetitionsFeature.isActive, links == nil else { return }
            let context = model.clubContext
            let links = CompetitionLinkModel(client: context.client, access: context.competitionAccess)
            self.links = links
            await links.load(clubID: context.clubID, roundID: draft.isSaved ? draft.roundID : nil)
            if originalLinks == nil, links.isLoaded { originalLinks = links.selected }
        }
        .onChange(of: draft.participants) { _, _ in
            draft.prepareSetup(rules: rules, roster: model.members)
        }
        .messageAlert("Det gikk ikke", text: $error)
    }

    /// Noe er endret siden skjermen åpnet: kladden eller «Teller også i …».
    private var hasChanges: Bool {
        if let original, original != draft { return true }
        if let originalLinks, let links, originalLinks != links.selected { return true }
        return false
    }

    // MARK: Forslaget

    private var summarySection: some View {
        Section {
            summaryRow("Bane", value: model.courses.isEmpty && selectedCourse == nil
                       ? "Ingen klare baner"
                       : RoundConfirm.courseValue(name: selectedCourse?.course.name, venue: draft.venue,
                                                  showsVenue: showsVenue)) {
                showsCourse = true
            }
            // Teene finnes bare når sql/029 er kjørt og `SlopeNoFeature` er på (lastes ellers ikke).
            if let course = selectedCourse, !course.tees.isEmpty {
                summaryRow("Tee", value: TeeChoice.value(course.tee(draft.teeID))) {
                    showsTee = true
                }
            }
            summaryRow("Start", value: RoundConfirm.startValue(firstHole: draft.firstHole, holeCount: draft.holeCount,
                                                               teeTime: draft.teeTime)) {
                showsStart = true
            }
            summaryRow("Spillere", value: QuickStart.playersSummary(draft)) {
                showsPlayers = true
            }
        } header: {
            if let event = model.selectedEvent {
                DDHeader(EveningDates.longText(event.eventDate, capitalized: true))
            }
        } footer: {
            // Den eneste hjelpelinja: når ingen har svart, står hele troppen som med.
            if draft.participantSource == .everyone {
                DDFooter("Ingen har svart «Kommer» ennå, så hele troppen står som med.")
            }
        }
    }

    /// Én rad i forslaget: tittel, verdien og pil. Trykk åpner undernivået.
    private func summaryRow(_ title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title)
                    .foregroundStyle(Color.ddInk)
                Spacer(minLength: 8)
                Text(value)
                    .foregroundStyle(Color.ddInkSecondary)
                    .multilineTextAlignment(.trailing)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.ddInkSecondary)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Endre")
    }

    // MARK: Flere valg

    private var moreSection: some View {
        Section {
            Button {
                showsMore = true
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Flere valg")
                            .foregroundStyle(Color.ddInk)
                        Text(RoundConfirm.moreSummary(draft, course: model.coreCourse(for: draft),
                                                      showsMatches: RoundSetupOptions(draft: draft, rules: rules).showsMatches))
                            .font(.ddCaption)
                            .foregroundStyle(Color.ddInkSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.ddInkSecondary)
                        .accessibilityHidden(true)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    /// Spillerne slik konkurransene kjenner dem: medlemmene i klubben, med innloggingen.
    private var linkPlayers: [CompetitionLinking.Player] {
        draft.participants.map { id in
            CompetitionLinking.Player(playerID: id, clubID: model.clubContext.clubID,
                                      profileID: model.members.first { $0.id == id }?.userID)
        }
    }

    /// Lagrer «Teller også i …» etter at runden er lagret eller startet. Gir en tilleggsmelding når
    /// koblingen feilet.
    private func saveLinks() async -> String? {
        guard let links else { return nil }
        return await links.save(roundID: draft.roundID, players: linkPlayers)
    }

    // MARK: Mangler og knapper

    private var problems: [QuickStartProblem] {
        QuickStart.problems(model.issues(draft, forStart: true), term: term,
                            blockingTitle: model.blockingRound(for: draft).map(model.title))
    }

    private var bottomPanel: some View {
        let problems = problems
        let canSave = model.issues(draft, forStart: false).isEmpty
        return VStack(spacing: 10) {
            if !problems.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Før runden kan starte")
                            .ddEyebrow()
                        ForEach(problems) { problem in
                            problemRow(problem)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: 150)
                .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Button("Lagre som kladd") { save() }
                    .buttonStyle(.dd(.secondary))
                    .disabled(!canSave)
                Button("Start runden") { start() }
                    .buttonStyle(.dd(.primary, fullWidth: true))
                    .disabled(!problems.isEmpty)
            }
            // Knapperaden ligger utenfor skjemaet, så den sperres her: to trykk skal ikke gi to forsøk.
            .disabled(isBusy)
            if isBusy { ProgressView() }
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: DDRadius.cardLarge))
        .padding(.horizontal, DDSpacing.s)
    }

    private func problemRow(_ problem: QuickStartProblem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Color.ddRustText)
                .accessibilityHidden(true)
            Text(problem.message)
                .font(.ddCallout)
                .foregroundStyle(Color.ddInk)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let target = problem.target {
                Button(target.shortcutTitle) { go(to: target) }
                    .buttonStyle(.dd(.text, compact: true))
                    .fixedSize()
            }
        }
    }

    private func go(to target: QuickStartTarget) {
        switch target {
        case .course: showsCourse = true
        case .players: showsPlayers = true
        case .moreOptions: showsMore = true
        }
    }

    private func save() {
        guard !isBusy else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                try await model.saveDraft(draft)
                let extra = await saveLinks().map { " " + $0 } ?? ""
                onDone("\(RoundListing.title(roundNo: draft.roundNo, courseName: selectedCourse?.course.name)) er lagret som kladd. Bare arrangørene ser den." + extra)
            } catch {
                draft.isSaved = model.rounds.contains { $0.id == draft.roundID }
                self.error = DataError.from(error).message
            }
        }
    }

    private func start() {
        guard !isBusy else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                try await model.start(draft)
                let extra = await saveLinks().map { " " + $0 } ?? ""
                onDone("\(RoundListing.title(roundNo: draft.roundNo, courseName: selectedCourse?.course.name)) er startet." + extra)
            } catch {
                draft.isSaved = model.rounds.contains { $0.id == draft.roundID }
                self.error = DataError.from(error).message
            }
        }
    }
}
