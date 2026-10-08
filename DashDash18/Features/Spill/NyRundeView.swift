import GolfgutuCore
import SwiftUI

/// «Ny runde» på sekunder: bane, start, form, spillere (deg, venner og gjester) og hvem som fører.
/// Andel, sidepremier, flighter og matcher kommer fra regelsettet. «Start runden» sender alt i ett kall.
struct NyRundeView: View {
    @State var model: NyRundeModel
    let onStarted: (UUID) -> Void
    @Environment(\.clubContext) private var clubContext

    @Environment(\.dismiss) private var dismiss
    @State private var guestName = ""
    @State private var guestHandicap = ""
    @FocusState private var guestFocused: Bool

    var body: some View {
        DDForm {
            courseSection
            playersSection
            guestsSection
            scoringSection
            formSection
            if let links = model.links {
                CountsAlsoInSection(model: links, candidates: links.candidates(players: model.linkPlayers))
            }
        }
        .navigationTitle("Ny runde")
        .ddNavigationChrome()
        .navigationBarTitleDisplayMode(.inline)
        .disabled(model.isStarting)
        .safeAreaInset(edge: .bottom) { bottomPanel }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Avbryt") { dismiss() }
            }
        }
        .task { await model.load() }
        .task { await model.prepareLinks(access: clubContext?.competitionAccess, clubID: clubContext?.clubID) }
    }

    // MARK: Bane og start

    private var courseSection: some View {
        Section {
            NavigationLink {
                CoursePickerView(model: model.library, selected: model.draft.courseID) { course in
                    model.select(course: course)
                }
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.course?.course.name ?? "Velg bane")
                        .font(.ddBodyEmphasis)
                        .foregroundStyle(model.course == nil ? Color.ddForestInk : Color.ddInk)
                    if let course = model.course {
                        Text("\(course.kind.title) · \(course.summary)")
                            .font(.ddCaption)
                            .foregroundStyle(Color.ddInkSecondary)
                    }
                }
            }
            if let course = model.course, !course.tees.isEmpty {
                NavigationLink {
                    TeePickerView(tees: course.tees, selected: $model.draft.teeID)
                } label: {
                    LabeledContent("Tee", value: TeeChoice.value(course.tee(model.draft.teeID)))
                }
            }
            if model.course != nil {
                Picker("Start", selection: Binding(
                    get: { model.draft.start },
                    set: { model.draft.setStart($0, courseHoles: model.course?.holeCount) }
                )) {
                    ForEach(model.startOptions, id: \.self) { Text($0.title).tag($0) }
                }
            }
        } header: {
            DDHeader("Bane")
        } footer: {
            if let course = model.course, !course.tees.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    DDFooter("Teens course rating og slope gir banehandicapet.")
                    SlopeNoCreditLink()
                }
            } else {
                DDFooter("Fra det felles biblioteket. Mangler banen, legger du den inn med «Ny bane».")
            }
        }
    }

    // MARK: Spillere

    private var playersSection: some View {
        Section {
            HStack {
                DDAvatar(name: model.myName)
                Text(model.myName)
                Spacer()
                Text(handicapText(model.me?.handicapIndex))
                    .font(.ddCaption)
                    .foregroundStyle(Color.ddInkSecondary)
            }
            ForEach(model.draft.friends, id: \.self) { id in
                HStack {
                    DDAvatar(name: model.friendName(id))
                    Text(model.friendName(id))
                    Spacer()
                    Button("Fjern", systemImage: "minus.circle") { model.draft.toggleFriend(id) }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(Color.ddInkSecondary)
                }
            }
            NavigationLink {
                FriendsPickerView(model: model)
            } label: {
                Label(model.friends.isEmpty ? "Ingen venner ennå" : "Legg til venner", systemImage: "person.badge.plus")
            }
            .disabled(model.friends.isEmpty)
        } header: {
            DDHeader("Spillere")
        } footer: {
            DDFooter("Venner er folk du har spilt med eller er i klubb med. Andre inviterer du med lenke eller QR når runden er startet, eller legger til som gjest.")
        }
    }

    private var guestsSection: some View {
        Section {
            ForEach($model.draft.guests) { $guest in
                HStack {
                    TextField("Navn", text: $guest.name)
                        .textInputAutocapitalization(.words)
                    TextField("Hcp", text: $guest.handicapText)
                        .keyboardType(.numbersAndPunctuation)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 64)
                    Button("Fjern \(guest.trimmedName)", systemImage: "minus.circle") {
                        model.draft.removeGuest(guest.id)
                    }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(Color.ddInkSecondary)
                }
            }
            HStack {
                TextField("Gjest (bare navn)", text: $guestName)
                    .textInputAutocapitalization(.words)
                    .focused($guestFocused)
                    .submitLabel(.done)
                    .onSubmit(addGuest)
                TextField("Hcp", text: $guestHandicap)
                    .keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                Button("Legg til gjest", systemImage: "plus.circle.fill", action: addGuest)
                    .labelStyle(.iconOnly)
                    .disabled(guestName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            DDHeader("Gjester")
        } footer: {
            DDFooter("Gjester trenger ikke appen. Handicap er valgfritt (+ for plusshandicap). En gjest kan senere ta plassen sin med invitasjonen («Er du Per?»).")
        }
    }

    private func addGuest() {
        if model.draft.addGuest(name: guestName, handicapText: guestHandicap) {
            guestName = ""
            guestHandicap = ""
            guestFocused = true
        }
    }

    // MARK: Føring og form

    private var scoringSection: some View {
        Section {
            Picker("Hvem fører?", selection: $model.draft.scoring) {
                ForEach(LooseRoundDraft.Scoring.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            DDHeader("Hvem fører?")
        } footer: {
            DDFooter(model.draft.scoring == .oneCard
                     ? "Du er markør og fører alle på din telefon. De andre ser stillingen live."
                     : "Du fører for deg selv og gjestene. Hver venn fører sitt eget kort på sin telefon.")
        }
    }

    private var formSection: some View {
        Section {
            Picker("Form", selection: $model.draft.formID) {
                ForEach(model.forms) { Text($0.name).tag($0.id) }
            }
            if model.rules.sidePrizes.longestDrive.enabled || model.rules.sidePrizes.closestToPin.enabled {
                Toggle("Longest drive og nærmest pinnen", isOn: $model.draft.sidePrizes)
            }
        } header: {
            DDHeader("Spill")
        } footer: {
            DDFooter(model.draft.form.help)
        }
    }

    // MARK: Start

    private var bottomPanel: some View {
        let issues = model.issues
        return VStack(spacing: 10) {
            if let first = issues.first {
                Label(first.message, systemImage: "exclamationmark.triangle")
                    .font(.ddCallout)
                    .foregroundStyle(Color.ddRustText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let error = model.error {
                Label(error, systemImage: "xmark.octagon").ddErrorStyle()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(startTitle) { start() }
                .buttonStyle(.dd(.primary, fullWidth: true))
                .disabled(!issues.isEmpty || model.isStarting)
            if model.isStarting { ProgressView() }
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: DDRadius.cardLarge))
        .padding(.horizontal, DDSpacing.s)
    }

    private var startTitle: String {
        let count = model.draft.playerCount
        return count == 1 ? "Start runden" : "Start runden · \(count) spillere"
    }

    private func start() {
        Task {
            if let id = await model.start() { onStarted(id) }
        }
    }

    private func handicapText(_ index: Double?) -> String {
        index.map { "hcp " + TroppInput.handicapText($0) } ?? "uten hcp"
    }
}

/// Velg venner: profilene du kan se (felles klubb, runde eller konkurranse), med søk.
struct FriendsPickerView: View {
    @Bindable var model: NyRundeModel
    @State private var search = ""

    private var shown: [ProfileRow] {
        let key = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !key.isEmpty else { return model.friends }
        return model.friends.filter { ($0.displayName ?? "").lowercased().contains(key) }
    }

    var body: some View {
        DDList {
            Section {
                ForEach(shown) { friend in
                    let name = LooseRoundInfo.name(friend.displayName)
                    let chosen = model.draft.friends.contains(friend.id)
                    Button { model.draft.toggleFriend(friend.id) } label: {
                        HStack {
                            DDAvatar(name: name)
                            Text(name).foregroundStyle(Color.ddInk)
                            Spacer()
                            Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(chosen ? Color.ddForestInk : Color.ddInkSecondary)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                }
            } footer: {
                DDFooter("Bare folk du deler en klubb, en runde eller en turnering med. Andre inviterer du med lenke eller QR.")
            }
        }
        .searchable(text: $search, prompt: "Søk på navn")
        .navigationTitle("Venner")
        .ddNavigationChrome()
        .navigationBarTitleDisplayMode(.inline)
    }
}
