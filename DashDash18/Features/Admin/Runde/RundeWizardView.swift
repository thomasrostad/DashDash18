import GolfgutuCore
import SwiftUI

/// «Start runde»-veiviseren i tre steg, som PWA-en: bane og tid, hvem og båser, oppsett.
/// Lagrer som kladd eller starter. Brukes også for «Rediger kladd».
struct RundeWizardView: View {
    enum Step: Int, CaseIterable {
        case course = 1, bays, setup

        var title: String {
            switch self {
            case .course: "Bane og tid"
            case .bays: "Hvem og båser"
            case .setup: "Oppsett"
            }
        }
    }

    let model: RundeAdminModel
    @State var draft: RoundDraft
    let onDone: (String?) -> Void

    @State private var step: Step = .course
    @State private var isBusy = false
    @State private var error: String?
    @State private var bayCount = 1

    var body: some View {
        Group {
            switch step {
            case .course: RundeCourseStep(model: model, draft: $draft)
            case .bays: RundeBaysStep(model: model, draft: $draft, bayCount: $bayCount)
            case .setup: RundeSetupStep(model: model, draft: $draft, bayCount: bayCount)
            }
        }
        .disabled(isBusy)
        .navigationTitle(draft.isSaved ? "Rediger kladd" : "Ny runde")
        .ddNavigationChrome()
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top) { indicator }
        .safeAreaInset(edge: .bottom) { buttons }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Avbryt") { onDone(nil) }
                    .disabled(isBusy)
            }
        }
        .onAppear {
            bayCount = max(1, draft.bays.bayCount)
        }
        .alert("Det gikk ikke", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    private var indicator: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.self) { s in
                VStack(spacing: 4) {
                    Capsule()
                        .fill(s.rawValue <= step.rawValue ? Color.ddLime : Color.ddEarthDeep)
                        .frame(height: 4)
                    Text((s.rawValue < step.rawValue ? "✓ " : "") + s.title)
                        .font(.dd(.sans, size: 11, relativeTo: .caption2))
                        .foregroundStyle(s == step ? Color.ddInk : Color.ddInkSecondary)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color.ddBackground)
    }

    /// Hvorfor «Neste» eller «Start runden» er sperret, rett over knappene.
    private var blockedReason: String? {
        switch step {
        case .course:
            return model.issues(draft, forStart: false).first(where: \.isCourseIssue)?.message
        case .bays:
            return draft.participants.isEmpty ? "«Neste» åpner når minst én er med." : nil
        case .setup:
            if let blocking = model.blockingRound(for: draft) {
                return "\(model.title(blocking)) går fortsatt. Lagre denne som kladd, og start den når den andre er låst."
            }
            return model.issues(draft, forStart: true).first?.message
        }
    }

    private var buttons: some View {
        VStack(spacing: 8) {
            if let reason = blockedReason {
                Text(reason)
                    .font(.dd(.sans, size: 13, relativeTo: .footnote))
                    .foregroundStyle(Color.ddInkSecondary)
                    .multilineTextAlignment(.center)
            }
            HStack {
                if step != .course {
                    Button("Tilbake") { go(to: Step(rawValue: step.rawValue - 1)!) }
                        .buttonStyle(.dd(.secondary))
                }
                Spacer()
                switch step {
                case .course, .bays:
                    Button("Neste") { go(to: Step(rawValue: step.rawValue + 1)!) }
                        .buttonStyle(.dd(.primary))
                        .disabled(blockedReason != nil)
                case .setup:
                    Button("Lagre som kladd") { save() }
                        .buttonStyle(.dd(.secondary))
                        .disabled(!model.issues(draft, forStart: false).isEmpty)
                    Button("Start runden") { start() }
                        .buttonStyle(.dd(.primary))
                        .disabled(blockedReason != nil)
                }
            }
            // Knapperaden ligger utenfor skjemaet (safeAreaInset), så den sperres her: to trykk
            // på «Start runden» skal ikke gi to forsøk.
            .disabled(isBusy)
            if isBusy { ProgressView() }
        }
        .padding()
        // Fast knapperad i glass over skjemaet.
        .glassEffect(.regular, in: .rect(cornerRadius: DDRadius.cardLarge))
        .padding(.horizontal, DDSpacing.s)
    }

    private func go(to next: Step) {
        if next == .setup {
            // Matchene står når de samme er med; ellers trekkes de på nytt (`behold` i handleStartRunde).
            let form = draft.form
            if form.isTeamForm && draft.teams.isEmpty {
                draft.teams = TeamPlanner.suggested(participants: draft.participants, form: form,
                                                    maxPerBay: model.rules.formats.maxPerBay)
            }
            if !MatchPlanner.canKeep(draft.matches, participants: draft.participants, teams: draft.teams,
                                     isTeamForm: form.isTeamForm) {
                draft.redrawMatches(roster: model.members)
            }
        }
        withAnimation { step = next }
    }

    private func save() {
        guard !isBusy else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                try await model.saveDraft(draft)
                onDone("\(RoundListing.title(roundNo: draft.roundNo, courseName: model.course(draft.courseID)?.course.name)) er lagret som kladd. Bare arrangørene ser den.")
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
                onDone("\(RoundListing.title(roundNo: draft.roundNo, courseName: model.course(draft.courseID)?.course.name)) er startet.")
            } catch {
                draft.isSaved = model.rounds.contains { $0.id == draft.roundID }
                self.error = DataError.from(error).message
            }
        }
    }
}

// MARK: - Steg 1: bane og tid

struct RundeCourseStep: View {
    let model: RundeAdminModel
    @Binding var draft: RoundDraft

    var body: some View {
        let selected = model.course(draft.courseID)
        DDForm {
            Section {
                if model.courses.isEmpty {
                    Text("Ingen baner er klare. Legg inn parene under «Banene» først.")
                        .foregroundStyle(Color.ddInkSecondary)
                } else {
                    Picker("Bane", selection: $draft.courseID) {
                        if let selected, !selected.isReady {
                            Text("\(selected.course.name) (ikke klar)").tag(Optional(selected.id))
                        }
                        ForEach(model.courses) { course in
                            Text(course.course.name).tag(Optional(course.id))
                        }
                    }
                }
                if let selected {
                    Text(selected.summary)
                        .font(.dd(.sans, size: 13, relativeTo: .footnote))
                        .foregroundStyle(Color.ddInkSecondary)
                    if let external = selected.differentExternalName {
                        Text("Heter «\(external)» i simulatoren.")
                            .font(.dd(.sans, size: 13, relativeTo: .footnote))
                            .foregroundStyle(Color.ddInkSecondary)
                    }
                }
            } footer: {
                DDFooter("Bare baner med par på alle hull står her. Uten kjenner ikke appen parene.")
            }

            DDSection("Hull") {
                Picker("Antall hull", selection: $draft.holeCount) {
                    Text("18 hull").tag(18)
                    Text("9 hull").tag(9)
                }
                .pickerStyle(.segmented)
                if RoundDraft.canStartAtTen(holeCount: draft.holeCount, courseHoles: selected?.holeCount) {
                    Picker("Første hull", selection: $draft.firstHole) {
                        Text("Hull 1").tag(1)
                        Text("Hull 10").tag(10)
                    }
                    .pickerStyle(.segmented)
                }
            }

            Section {
                Toggle("Første tee", isOn: Binding(
                    get: { draft.teeTime != nil },
                    set: { on in draft.teeTime = on ? (model.selectedEvent?.startTime ?? "17:00:00") : nil }
                ))
                if let tee = draft.teeTime {
                    DatePicker("Klokka", selection: Binding(
                        get: { EveningDates.time(from: tee) ?? .now },
                        set: { draft.teeTime = EveningDates.timeString(from: $0) }
                    ), displayedComponents: .hourAndMinute)
                }
            } header: {
                DDHeader("Tid")
            } footer: {
                if let event = model.selectedEvent {
                    Text("\(EveningDates.longText(event.eventDate, capitalized: true)). Runden blir «\(RoundListing.title(roundNo: draft.roundNo, courseName: selected?.course.name))».")
                }
            }
        }
        // Klokka er Oslo-tid (som databasen), også når telefonen står i en annen tidssone.
        .environment(\.timeZone, EveningDates.osloTimeZone)
        .onChange(of: draft.holeCount) { _, _ in fixHoles() }
        .onChange(of: draft.courseID) { _, _ in fixHoles() }
    }

    /// Hull 10 bare for 9 hull på 18-hullsbane; LD/KP innenfor runden.
    private func fixHoles() {
        if !RoundDraft.canStartAtTen(holeCount: draft.holeCount, courseHoles: model.course(draft.courseID)?.holeCount) {
            draft.firstHole = 1
        }
        if let ld = draft.ldHoleIndex, ld >= draft.holeCount { draft.ldHoleIndex = nil }
        if let kp = draft.kpHoleIndex, kp >= draft.holeCount { draft.kpHoleIndex = nil }
    }
}
