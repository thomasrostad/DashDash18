import SwiftUI

/// Dato, tid, sted, sosialkomité og nedtelling for neste kveld.
struct NextEveningCard: View {
    let event: EventRow
    let committee: [String]
    let daysUntil: Int?
    let referenceYear: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(EveningDates.longText(event.eventDate, referenceYear: referenceYear, capitalized: true))
                    .font(.title2.bold())
                Spacer()
                if let daysUntil {
                    Text(EveningDates.countdownText(days: daysUntil))
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.yellow.opacity(0.25), in: .capsule)
                }
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
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
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

    private var current: SignupStatus? { model.mySignup?.status }

    var body: some View {
        Section {
            HStack(spacing: 8) {
                ForEach(SignupStatus.allCases, id: \.self) { status in
                    answerButton(status)
                }
            }
            .buttonBorderShape(.capsule)
            .disabled(isBusy)

            if current != nil {
                commentRow
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        } header: {
            Text(current == nil ? "Kommer du?" : "Ditt svar")
        }
    }

    @ViewBuilder
    private func answerButton(_ status: SignupStatus) -> some View {
        let selected = current == status
        let button = Button {
            answer(status)
        } label: {
            Text(status.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
        }
        .tint(status.tint)
        .accessibilityAddTraits(selected ? .isSelected : [])
        if selected {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var commentRow: some View {
        if isEditingComment {
            VStack(alignment: .trailing, spacing: 6) {
                TextField("Kommentar (valgfritt)", text: $commentText, axis: .vertical)
                    .lineLimit(1...3)
                    .focused($commentFocused)
                    .onChange(of: commentText) { _, text in
                        if text.count > SignupInput.commentMax {
                            commentText = String(text.prefix(SignupInput.commentMax))
                        }
                    }
                HStack {
                    Text("\(commentText.count)/\(SignupInput.commentMax)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Avbryt") { isEditingComment = false }
                        .buttonStyle(.borderless)
                    Button("Lagre", action: saveComment)
                        .buttonStyle(.borderless)
                        .bold()
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
                        Text("«\(comment)»").foregroundStyle(.primary)
                        Spacer()
                        Text("Endre")
                    }
                } else {
                    Label("Legg til en kommentar", systemImage: "text.bubble")
                }
            }
        }
    }

    private func answer(_ status: SignupStatus) {
        run { () async throws(DataError) in try await model.answer(status) }
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
                Section("\(group.title) · \(group.entries.count)") {
                    ForEach(group.entries) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name)
                                .fontWeight(entry.memberID == myID ? .semibold : .regular)
                            if let comment = entry.comment {
                                Text("«\(comment)»")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}

private extension SignupStatus {
    var tint: Color {
        switch self {
        case .yes: .green
        case .maybe: .orange
        case .no: .red
        }
    }
}
