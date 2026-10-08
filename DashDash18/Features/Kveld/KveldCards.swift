import SwiftUI

/// Dato, tid, sted, sosialkomité og nedtelling for neste kveld.
struct NextEveningCard: View {
    let event: EventRow
    let committee: [String]
    let daysUntil: Int?
    let referenceYear: Int?
    /// Morroturneringene kvelden hører til (fase 15).
    var funCompetitions: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(EveningDates.longText(event.eventDate, referenceYear: referenceYear, capitalized: true))
                    .font(.ddTitle)
                    .foregroundStyle(Color.ddForestInk)
                Spacer()
                if let daysUntil {
                    // Nedtellingen i sol-gult, som «12 DAGER» i PWA-en.
                    DDPill(EveningDates.countdownText(days: daysUntil), tone: .sun)
                        .fixedSize()
                }
            }
            if !funCompetitions.isEmpty {
                HStack(spacing: 6) {
                    ForEach(funCompetitions, id: \.self) { name in
                        DDPill(name, tone: .lime, systemImage: "party.popper")
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Teller også i \(NorwegianList.join(funCompetitions))")
            }
            if let time = EveningDates.timeText(event.startTime) {
                Label("Kl. \(time)", systemImage: "clock")
            }
            if let venue = event.venue {
                Label(venue, systemImage: "mappin.and.ellipse")
            }
            if !committee.isEmpty {
                Label("Sosialkomité: \(NorwegianList.join(committee))", systemImage: "fork.knife")
            }
            if let note = event.note {
                Text(note)
                    .font(.ddCallout)
                    .foregroundStyle(Color.ddInkSecondary)
            }
        }
        .labelStyle(DDIconLabelStyle())
        .accessibilityElement(children: .combine)
    }
}

/// Mitt svar: tre knapper og en kommentar.
struct SignupSection: View {
    let model: KveldModel
    @State private var commentText = ""
    @State private var isEditingComment = false
    @State private var isBusy = false
    @State private var error: String?
    @FocusState private var commentFocused: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    private var current: SignupStatus? { model.mySignup?.status }

    var body: some View {
        VStack(alignment: .leading, spacing: DDSpacing.cardGap) {
            DDSectionLabel(current == nil ? "Kommer du?" : "Ditt svar")
            VStack(alignment: .leading, spacing: DDSpacing.m) {
                // Med stor tekst står knappene under hverandre, så «Kommer ikke» ikke kappes.
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
                layout {
                    ForEach(SignupStatus.allCases, id: \.self) { status in
                        answerButton(status)
                    }
                }
                .disabled(isBusy)

                if let pending = model.pendingAnswer {
                    HStack {
                        Text(SignupUndo.text(pending.status))
                            .font(.ddCallout)
                            .foregroundStyle(Color.ddInkSecondary)
                        Spacer()
                        Button("Angre") { model.undoAnswer() }
                            .buttonStyle(.ddText)
                    }
                    .accessibilityElement(children: .combine)
                    .transition(.opacity)
                }

                if current != nil {
                    DDDivider()
                    commentRow
                }
                if let error = error ?? model.answerError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .ddErrorStyle()
                }
            }
            .animation(.default, value: model.pendingAnswer?.status)
            .ddCard()
        }
    }

    @ViewBuilder
    private func answerButton(_ status: SignupStatus) -> some View {
        let selected = current == status
        Button {
            answer(status)
        } label: {
            Text(status.title)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .buttonStyle(DDChoiceButtonStyle(selected: selected, tint: status.tint))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var commentRow: some View {
        if isEditingComment {
            VStack(alignment: .trailing, spacing: 6) {
                TextField("Kommentar (valgfritt)", text: $commentText, axis: .vertical)
                    .lineLimit(1...3)
                    .focused($commentFocused)
                    .ddField()
                    .onChange(of: commentText) { _, text in
                        if text.count > SignupInput.commentMax {
                            commentText = String(text.prefix(SignupInput.commentMax))
                        }
                    }
                HStack {
                    Text("\(commentText.count)/\(SignupInput.commentMax)")
                        .font(.dd(.sans, size: 12, relativeTo: .caption))
                        .foregroundStyle(Color.ddInkSecondary)
                    Spacer()
                    Button("Avbryt") { isEditingComment = false }
                        .buttonStyle(.ddText)
                    Button("Lagre", action: saveComment)
                        .buttonStyle(.dd(.primary, compact: true))
                }
            }
            .disabled(isBusy)
        } else {
            Button {
                commentText = model.mySignup?.comment ?? ""
                isEditingComment = true
                commentFocused = true
            } label: {
                if let comment = model.mySignup?.comment {
                    HStack {
                        Text("«\(comment)»").foregroundStyle(Color.ddInk)
                        Spacer()
                        Text("Endre").fontWeight(.semibold)
                    }
                } else {
                    Label("Legg til en kommentar", systemImage: "text.bubble")
                        .fontWeight(.medium)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.ddForestInk)
            .frame(minHeight: 44)
        }
    }

    private func answer(_ status: SignupStatus) {
        error = nil
        model.answer(status)
    }

    private func saveComment() {
        let text = commentText
        run { () async throws(DataError) in
            try await model.saveComment(text)
            isEditingComment = false
        }
    }

    private func run(_ action: @escaping () async throws(DataError) -> Void) {
        isBusy = true
        error = nil
        Task {
            defer { isBusy = false }
            do throws(DataError) {
                try await action()
            } catch {
                self.error = "Klarte ikke å lagre svaret. \(error.message)"
            }
        }
    }
}

/// Hvem som kommer, er usikre, ikke kommer og ikke har svart.
struct SignupOverviewSection: View {
    let summary: SignupSummary
    let myID: UUID

    var body: some View {
        ForEach(summary.groups, id: \.title) { group in
            if !group.entries.isEmpty {
                DDSectionLabel("\(group.title) · \(group.entries.count)")
                    .padding(.top, DDSpacing.l)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(group.entries) { entry in
                        HStack(spacing: 12) {
                            DDAvatar(name: entry.name)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.name)
                                    .font(entry.memberID == myID ? .ddBodyEmphasis : .ddBody)
                                if let comment = entry.comment {
                                    Text("«\(comment)»")
                                        .font(.ddCaption)
                                        .foregroundStyle(Color.ddInkSecondary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 10)
                        .accessibilityElement(children: .combine)
                        if entry.id != group.entries.last?.id { DDDivider() }
                    }
                }
                .ddCard(padding: DDSpacing.l)
            }
        }
    }
}

private extension SignupStatus {
    /// Kommer = grønn pille (golfee), usikker = sol, kommer ikke = blush.
    var tint: DDChoiceTint {
        switch self {
        case .yes: .forest
        case .maybe: .sun
        case .no: .blush
        }
    }
}
