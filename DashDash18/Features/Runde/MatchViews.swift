import SwiftUI

private extension MatchTone {
    var color: Color {
        switch self {
        case .neutral: .primary
        case .up: .green
        case .down: .orange
        }
    }
}

private struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Matchkortet

/// «Matcher»: mine først og uthevet, så de andre. Min match har hull for hull.
struct MatchkortSection: View {
    let card: MatchCard

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Matcher")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(card.mine) { MatchLineRow(line: $0) }
                if !card.mine.isEmpty && !card.others.isEmpty {
                    Divider().padding(.vertical, 6)
                }
                ForEach(card.others) { MatchLineRow(line: $0) }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(.background.secondary, in: .rect(cornerRadius: 16))
            if let hint = card.decidedHint {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct MatchLineRow: View {
    let line: MatchLine

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(line.matchNo).")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 22, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    title
                    if let subtitle = line.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Text(line.text)
                    .font(.subheadline.monospacedDigit().weight(line.isMine ? .semibold : .regular))
                    .foregroundStyle(line.text == "Ikke startet" ? .secondary : line.tone.color)
            }
            .accessibilityElement(children: .combine)
            if !line.holes.isEmpty {
                MatchHoleStrip(holes: line.holes)
                    .padding(.leading, 30)
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var title: some View {
        if let opponent = line.opponent {
            let a = Text(line.title).fontWeight(line.leader == .a ? .semibold : .regular)
            let b = Text(opponent).fontWeight(line.leader == .b ? .semibold : .regular)
            Text("\(a) – \(b)")
                .font(.subheadline)
        } else {
            Text(line.title)
                .font(.subheadline.weight(line.isMine ? .semibold : .regular))
        }
    }
}

/// Hull for hull: grønn vunnet, rust tapt, grå delt, tom ikke spilt.
private struct MatchHoleStrip: View {
    let holes: [MatchHoleMark]

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 9)
        LazyVGrid(columns: columns, spacing: 3) {
            ForEach(holes) { mark in
                Text("\(mark.number)")
                    .font(.caption2.monospacedDigit())
                    .frame(maxWidth: .infinity, minHeight: 20)
                    .foregroundStyle(mark.result == .won || mark.result == .lost ? .white : .primary)
                    .background(fill(mark.result), in: .rect(cornerRadius: 4))
                    .accessibilityLabel(mark.accessibilityLabel)
            }
        }
    }

    private func fill(_ result: MatchHoleMark.Result) -> Color {
        switch result {
        case .won: .green
        case .lost: .orange
        case .halved: .secondary.opacity(0.35)
        case .open: .secondary.opacity(0.1)
        }
    }
}

/// Linjene under hullkortet: hvem som vant hullet, og hvor matchen står.
struct HullMatchLinjer: View {
    let lines: [HoleMatchLine]

    var body: some View {
        VStack(spacing: 6) {
            ForEach(lines) { line in
                HStack {
                    Text(line.what)
                        .font(.subheadline)
                    Spacer(minLength: 8)
                    Text(line.standing)
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(line.tone.color)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(12)
        .background(.background.secondary, in: .rect(cornerRadius: 12))
    }
}

// MARK: - Bayen nå

/// «Bayen nå»: plass og poeng, eller stilling når runden avgjøres hull for hull.
struct BayenNaaListe: View {
    let rows: [BayenRow]
    let onSelect: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Bayen nå")
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                    Button { onSelect(row.memberID) } label: {
                        HStack(spacing: 10) {
                            Text(row.place.map { "\($0)." } ?? "")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 28, alignment: .leading)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.name + (row.isMe ? " (deg)" : ""))
                                    .font(.body.weight(row.isMe ? .semibold : .regular))
                                Text("thru \(row.thru)" + (row.bay.map { " · bås \($0)" } ?? ""))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(row.value)
                                .font(.title3.monospacedDigit().bold())
                                .foregroundStyle(row.tone.color)
                        }
                        .padding(.vertical, 8)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Åpner scorekortet")
                    if i < rows.count - 1 { Divider() }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(.background.secondary, in: .rect(cornerRadius: 16))
        }
    }
}

// MARK: - Longest drive og nærmest pinnen

/// Boksen på LD- eller KP-hullet: hvem leder, lista, og «Meld inn» for meg (arrangøren for alle).
struct SidepremieBoks: View {
    let box: SidePrizeBox
    let viewer: UUID
    /// Navn til velgeren (alle i runden).
    let names: [UUID: String]
    /// Det som er meldt inn for spilleren, til feltet.
    let existing: (UUID) -> Double?
    let onSubmit: (UUID, String) async throws -> Void
    let onDelete: (UUID) async throws -> Void

    @State private var member: UUID?
    @State private var text = ""
    @State private var isBusy = false
    @State private var error: String?
    @FocusState private var focused: Bool

    private var selected: UUID? {
        if let member, box.claimants.contains(member) { return member }
        return box.claimants.first { $0 == viewer } ?? box.claimants.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(box.title, systemImage: box.kind == .drive ? "ruler" : "scope")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text(box.leader)
                .font(.title3.weight(.semibold))
            if let note = box.tieNote {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if !box.lines.isEmpty {
                VStack(spacing: 0) {
                    ForEach(box.lines) { line in
                        HStack(spacing: 8) {
                            Text("\(line.rank).")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 24, alignment: .leading)
                            Text(line.name + (line.isMe ? " (deg)" : ""))
                                .font(.subheadline.weight(line.isLeader ? .semibold : .regular))
                            Spacer()
                            Text(line.meters)
                                .font(.subheadline.monospacedDigit())
                            if line.canDelete {
                                Button(role: .destructive) {
                                    run { try await onDelete(line.claimID) }
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Slett innmeldingen til \(line.name)")
                                .disabled(isBusy)
                            }
                        }
                        .padding(.vertical, 6)
                        .accessibilityElement(children: .contain)
                    }
                }
            }
            if box.canClaim, let selected {
                if box.claimants.count > 1 {
                    Picker("For hvem", selection: Binding(get: { selected }, set: { member = $0 })) {
                        ForEach(box.claimants, id: \.self) { id in
                            Text(name(id) + (id == viewer ? " (deg)" : "")).tag(id)
                        }
                    }
                    .pickerStyle(.menu)
                }
                HStack(spacing: 8) {
                    TextField(fieldLabel(selected), text: $text)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .focused($focused)
                    Text("m").foregroundStyle(.secondary)
                    Button(existing(selected) == nil ? "Meld inn" : "Oppdater") {
                        let who = selected
                        let value = text
                        run {
                            try await onSubmit(who, value)
                            focused = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy || text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(14)
        .background(box.kind == .drive ? Color.yellow.opacity(0.18) : Color.blue.opacity(0.12),
                    in: .rect(cornerRadius: 14))
        .onAppear { fill(selected) }
        .onChange(of: selected) { _, new in fill(new) }
    }

    private func name(_ id: UUID) -> String {
        names[id] ?? "Ukjent"
    }

    private func fieldLabel(_ id: UUID) -> String {
        let what = box.kind == .drive ? "Drive" : "Avstand"
        return id == viewer ? "Din \(what.lowercased())" : "\(what) for \(name(id))"
    }

    private func fill(_ id: UUID?) {
        text = id.flatMap(existing).map(MeterInput.text) ?? ""
        error = nil
    }

    private func run(_ action: @escaping () async throws -> Void) {
        Task {
            isBusy = true
            defer { isBusy = false }
            do {
                try await action()
                error = nil
            } catch {
                self.error = DataError.from(error).message
            }
        }
    }
}
