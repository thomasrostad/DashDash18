import GolfgutuCore
import SwiftUI

/// «Ny runde» og «Rediger kladd»: én skjerm med sted, bane, start, tid og spillere, ferdig utfylt fra
/// forrige runde i sesongen (ellers regelsettet) og med gruppene fordelt fra de påmeldte. Alt annet
/// ligger under «Flere valg». Pushes i arrangørens navigasjon; «Spillere og båser» og «Flere valg» er
/// vanlige undernivåer. Tilbake spør før ulagrede endringer forkastes.
struct RundeQuickStartView: View {
    let model: RundeAdminModel
    @State var draft: RoundDraft
    /// Etter «Lagre som kladd» eller «Start runden», med meldingen som vises der man kom fra.
    let onDone: (String) -> Void

    @State private var bayCount = 1
    @State private var isBusy = false
    @State private var error: String?
    @State private var showsPlayers = false
    @State private var showsMore = false
    @State private var scrollTarget: String?
    /// Kladden slik den så ut da skjermen åpnet (etter forslagene), for å se om noe er endret.
    @State private var original: RoundDraft?
    /// «Teller også i …» slik det var da valget var hentet.
    @State private var originalLinks: Set<UUID>?
    /// «Teller også i …» (fase 15). Nil når `CompetitionsFeature` er av.
    @State var links: CompetitionLinkModel?

    private var rules: Ruleset { model.rules }
    private var term: GroupTerm { draft.groupTerm }
    private var selectedCourse: CourseListItem? { model.course(draft.courseID) }

    var body: some View {
        ScrollViewReader { proxy in
            DDForm {
                venueSection
                courseSection
                playersSection
                if let links {
                    CountsAlsoInSection(model: links, candidates: links.candidates(players: linkPlayers))
                }
                setupSection
            }
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                withAnimation { proxy.scrollTo(target, anchor: .top) }
                scrollTarget = nil
            }
        }
        // Klokka er Oslo-tid (som databasen), også når telefonen står i en annen tidssone.
        .environment(\.timeZone, EveningDates.osloTimeZone)
        .disabled(isBusy)
        .navigationTitle(draft.isSaved ? "Rediger kladd" : "Ny runde")
        .ddNavigationChrome()
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { bottomPanel }
        .discardChangesGuard(hasChanges: hasChanges && !isBusy)
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

    // MARK: Hvor

    private var venueSection: some View {
        Section {
            Picker("Hvor spiller dere?", selection: Binding(
                get: { draft.venue },
                set: { draft.setVenue($0, rules: rules) }
            )) {
                ForEach(Venue.allCases, id: \.self) { venue in
                    Text(venue.title).tag(venue)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            DDHeader("Hvor spiller dere?")
        } footer: {
            DDFooter(venueFooter)
        }
    }

    private var venueFooter: String {
        var text = draft.venue == .simulator
            ? "Gruppene heter båser, og Trackman kan dele ut slagene."
            : "Gruppene heter flighter. Dere fører brutto, og appen gir slagene."
        if !VenueFeature.isEnabled && draft.venue == .course {
            text += " Valget huskes ikke på runden ennå (venter på en databaseoppdatering)."
        }
        return text
    }

    // MARK: Bane, start og tid

    private var courseSection: some View {
        Section {
            if model.courses.isEmpty {
                Text("Ingen baner er klare. Legg inn parene under «Banene» først.")
                    .foregroundStyle(Color.ddInkSecondary)
            } else {
                Picker("Bane", selection: Binding(
                    get: { draft.courseID },
                    set: { QuickStart.setCourse($0, on: &draft, courseHoles: model.course($0)?.holeCount) }
                )) {
                    if draft.courseID == nil {
                        Text("Velg").tag(UUID?.none)
                    }
                    if let selected = selectedCourse, !selected.isReady {
                        Text("\(selected.course.name) (ikke klar)").tag(Optional(selected.id))
                    }
                    ForEach(QuickStart.courses(model.courses, for: draft.venue, selected: draft.courseID)) { course in
                        Text(course.course.name).tag(Optional(course.id))
                    }
                }
                .id("course")
            }
            if let selected = selectedCourse {
                Text(courseNote(selected))
                    .font(.ddCaption)
                    .foregroundStyle(Color.ddInkSecondary)
            }
            Picker("Start", selection: Binding(
                get: { QuickStartStart(firstHole: draft.firstHole, holeCount: draft.holeCount) },
                set: { QuickStart.setStart($0, on: &draft, courseHoles: selectedCourse?.holeCount) }
            )) {
                ForEach(startOptions, id: \.self) { option in
                    Text(option.title).tag(option)
                }
            }
            if let tee = draft.teeTime {
                DatePicker("Første tee", selection: Binding(
                    get: { EveningDates.time(from: tee) ?? .now },
                    set: { draft.teeTime = EveningDates.timeString(from: $0) }
                ), displayedComponents: .hourAndMinute)
            } else {
                Button("Legg til første tee", systemImage: "clock") {
                    draft.teeTime = model.selectedEvent?.startTime ?? "17:00:00"
                }
            }
        } header: {
            DDHeader("Bane og start")
        } footer: {
            if let event = model.selectedEvent {
                DDFooter("\(EveningDates.longText(event.eventDate, capitalized: true)). Runden blir «\(RoundListing.title(roundNo: draft.roundNo, courseName: selectedCourse?.course.name))».")
            }
        }
    }

    /// Startvalgene, med det kladden har selv om det ikke lenger passer banen.
    private var startOptions: [QuickStartStart] {
        var options = QuickStart.startOptions(courseHoles: selectedCourse?.holeCount)
        let current = QuickStartStart(firstHole: draft.firstHole, holeCount: draft.holeCount)
        if !options.contains(current) { options.append(current) }
        return options
    }

    private func courseNote(_ course: CourseListItem) -> String {
        var text = course.summary
        if draft.venue == .simulator, let external = course.differentExternalName {
            text += ". Heter «\(external)» i simulatoren."
        }
        return text
    }

    // MARK: Spillere

    private var playersSection: some View {
        Section {
            Button {
                showsPlayers = true
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(QuickStart.playersSummary(draft))
                            .font(.ddBodyEmphasis)
                            .foregroundStyle(Color.ddInk)
                        ForEach(QuickStart.groupLines(draft, name: model.memberName), id: \.self) { line in
                            Text(line)
                                .font(.ddCaption)
                                .foregroundStyle(Color.ddInkSecondary)
                        }
                    }
                    Spacer()
                    Text("Endre")
                        .font(.ddCallout)
                        .foregroundStyle(Color.ddForestInk)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .id("players")
        } header: {
            DDHeader("Spillere")
        } footer: {
            DDFooter(playersFooter)
        }
    }

    private var playersFooter: String {
        switch draft.participantSource {
        case .signups: "De som har svart «Kommer», fordelt med duellpartnerne i samme \(term.singular) og én markør i hver."
        case .everyone: "Ingen har svart «Kommer» ennå, så hele troppen står som med. Trykk «Endre» og ta ut dem som ikke kommer."
        case .saved: "Slik kladden er satt opp."
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

    // MARK: Oppsett

    private var setupSection: some View {
        Section {
            LabeledContent("Form", value: draft.form.name)
            Button {
                showsMore = true
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Flere valg")
                            .foregroundStyle(Color.ddInk)
                        Text(moreSummary)
                            .font(.ddCaption)
                            .foregroundStyle(Color.ddInkSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.ddInkSecondary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .id("more")
        } header: {
            DDHeader("Oppsett")
        } footer: {
            DDFooter("Formen og resten kommer fra sesongens regelsett. «Flere valg» har form, lag, matcher, sidepremier, vekt og handicap.")
        }
    }

    /// «6 matcher · LD hull 7 · KP hull 3 · vanlig runde».
    private var moreSummary: String {
        let core = selectedCourse?.coreCourse
        let offset = draft.firstHole == 10 ? 10 : 1
        var parts: [String] = []
        let matches = draft.matches.count
        parts.append(matches == 0 ? "Ingen matcher" : matches == 1 ? "1 match" : "\(matches) matcher")
        if draft.ldEnabled { parts.append("LD hull \(draft.ldHole(course: core) + offset)") }
        if draft.kpEnabled { parts.append("KP hull \(draft.kpHole(course: core) + offset)") }
        if let weight = RundeSetupStep.weights.first(where: { $0.value == draft.weight }), draft.weight != 1 {
            parts.append(weight.title.lowercased())
        }
        if draft.externalHandicap { parts.append("Trackman gir slagene") }
        return parts.joined(separator: " · ")
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
        case .course: scrollTarget = "course"
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
