import SwiftUI

private extension MatchTone {
    /// På lyst kort.
    var color: Color {
        switch self {
        case .neutral: .ddInk
        case .up: .ddForestInk
        case .down: .ddRustText
        }
    }

    /// På svart statistikk-kort: grønn som i golfee, rust lysnet.
    var statColor: Color {
        switch self {
        case .neutral: .ddStatText
        case .up: .ddLime
        case .down: .ddStatRust
        }
    }
}

private struct SectionLabel: View {
    let text: String

    var body: some View {
        DDSectionLabel(text)
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
                    Rectangle().fill(Color.ddStatText.opacity(0.15)).frame(height: 1).padding(.vertical, 6)
                }
                ForEach(card.others) { MatchLineRow(line: $0) }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .ddCard(.stat, padding: 0)
            if let hint = card.decidedHint {
                Text(hint)
                    .font(.dd(.sans, size: 13, relativeTo: .footnote))
                    .foregroundStyle(Color.ddInkSecondary)
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
                    .font(.dd(.sans, size: 12, relativeTo: .caption)).monospacedDigit()
                    .foregroundStyle(Color.ddStatSecondary)
                    .frame(width: 22, alignment: .leading)
                VStack(alignment: .leading, spacing: 1) {
                    title
                    if let subtitle = line.subtitle {
                        Text(subtitle)
                            .font(.dd(.sans, size: 12, relativeTo: .caption))
                            .foregroundStyle(Color.ddStatSecondary)
                    }
                }
                .foregroundStyle(Color.ddStatText)
                Spacer(minLength: 8)
                Text(line.text)
                    .font(.dd(.sans, size: 15, weight: line.isMine ? .semibold : .regular, relativeTo: .subheadline))
                    .monospacedDigit()
                    .foregroundStyle(line.text == "Ikke startet" ? Color.ddStatSecondary : line.tone.statColor)
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
                .font(.dd(.sans, size: 14, relativeTo: .subheadline))
        } else {
            Text(line.title)
                .font(.dd(.sans, size: 14, weight: line.isMine ? .semibold : .regular, relativeTo: .subheadline))
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
                    .font(.dd(.sans, size: 11, relativeTo: .caption2)).monospacedDigit()
                    .frame(maxWidth: .infinity, minHeight: 22)
                    .foregroundStyle(foreground(mark.result))
                    .background(fill(mark.result), in: .capsule)
                    .accessibilityLabel(mark.accessibilityLabel)
            }
        }
    }

    private func fill(_ result: MatchHoleMark.Result) -> Color {
        switch result {
        case .won: .ddLime
        case .lost: .ddStatRust
        case .halved: Color.ddStatText.opacity(0.28)
        case .open: Color.ddStatText.opacity(0.08)
        }
    }

    private func foreground(_ result: MatchHoleMark.Result) -> Color {
        switch result {
        case .won: .ddLimeOnAccent
        case .lost: .black
        case .halved, .open: .ddStatText
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
                        .font(.dd(.sans, size: 14, relativeTo: .subheadline))
                    Spacer(minLength: 8)
                    Text(line.standing)
                        .font(.dd(.sans, size: 14, weight: .semibold, relativeTo: .subheadline)).monospacedDigit()
                        .foregroundStyle(line.tone.color)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .ddCard(padding: 12)
    }
}

// MARK: - Bayen nå

/// «Bayen nå»: plass og poeng, eller stilling når runden avgjøres hull for hull.
struct BayenNaaListe: View {
    let rows: [BayenRow]
    /// «bås» / «flight» etter hvor runden spilles.
    var term: GroupTerm = .bay
    let onSelect: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Bayen nå")
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                    Button { onSelect(row.memberID) } label: {
                        HStack(spacing: 10) {
                            Text(row.place.map { "\($0)." } ?? "")
                                .font(.dd(.sans, size: 14, relativeTo: .subheadline)).monospacedDigit()
                                .foregroundStyle(Color.ddStatSecondary)
                                .frame(width: 28, alignment: .leading)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.name + (row.isMe ? " (deg)" : ""))
                                    .font(row.isMe ? .ddBodyEmphasis : .ddBody)
                                    .foregroundStyle(Color.ddStatText)
                                Text("thru \(row.thru)" + (row.bay.map { " · \(term.numberedLower($0))" } ?? ""))
                                    .font(.dd(.sans, size: 12, relativeTo: .caption))
                                    .foregroundStyle(Color.ddStatSecondary)
                            }
                            Spacer()
                            // Ditt tall i gult, de andre hvite (golfee).
                            Text(row.value)
                                .font(.dd(.sans, size: 20, weight: .medium, relativeTo: .title3)).monospacedDigit()
                                .foregroundStyle(row.isMe && row.tone == .neutral ? Color.ddYellow : row.tone.statColor)
                        }
                        .padding(.vertical, 8)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Åpner scorekortet")
                    if i < rows.count - 1 {
                        Rectangle().fill(Color.ddStatText.opacity(0.12)).frame(height: 1)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .ddCard(.stat, padding: 0)
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
                    .ddEyebrow()
                Spacer()
            }
            Text(box.leader)
                .font(.ddTitleSmall)
                .foregroundStyle(Color.ddForestInk)
            if let note = box.tieNote {
                Text(note)
                    .font(.dd(.sans, size: 13, relativeTo: .footnote))
                    .foregroundStyle(Color.ddInkSecondary)
            }
            if !box.lines.isEmpty {
                VStack(spacing: 0) {
                    ForEach(box.lines) { line in
                        HStack(spacing: 8) {
                            Text("\(line.rank).")
                                .font(.dd(.sans, size: 14, relativeTo: .subheadline)).monospacedDigit()
                                .foregroundStyle(Color.ddInkSecondary)
                                .frame(width: 24, alignment: .leading)
                            Text(line.name + (line.isMe ? " (deg)" : ""))
                                .font(line.isLeader ? .ddBodyEmphasis : .ddBody)
                            Spacer()
                            Text(line.meters)
                                .font(.ddNumber).monospacedDigit()
                                .foregroundStyle(line.isLeader ? Color.ddForestInk : Color.ddInk)
                            if line.canDelete {
                                Button(role: .destructive) {
                                    run { try await onDelete(line.claimID) }
                                } label: {
                                    Image(systemName: "trash")
                                        .frame(minWidth: 44, minHeight: 44)
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(DDToken.buttonDangerText.color)
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
                    // Gul nedtrekkspille (golfee).
                    Menu {
                        Picker("For hvem", selection: Binding(get: { selected }, set: { member = $0 })) {
                            ForEach(box.claimants, id: \.self) { id in
                                Text(name(id) + (id == viewer ? " (deg)" : "")).tag(id)
                            }
                        }
                    } label: {
                        DDDropdownPill(name(selected) + (selected == viewer ? " (deg)" : ""))
                    }
                    .accessibilityLabel("For hvem: \(name(selected))")
                }
                HStack(spacing: 8) {
                    TextField(fieldLabel(selected), text: $text)
                        .keyboardType(.decimalPad)
                        .focused($focused)
                        .ddField()
                    Text("m").foregroundStyle(Color.ddInkSecondary)
                    Button(existing(selected) == nil ? "Meld inn" : "Oppdater") {
                        let who = selected
                        let value = text
                        run {
                            try await onSubmit(who, value)
                            focused = false
                        }
                    }
                    // Gull-knappen er LD/KP sin (knappelogikken).
                    .buttonStyle(.ddGold)
                    .disabled(isBusy || text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.dd(.sans, size: 13, relativeTo: .footnote))
                    .foregroundStyle(Color.ddError)
            }
        }
        .padding(16)
        .background(Color.ddDriveBox, in: .rect(cornerRadius: DDRadius.card))
        .overlay(RoundedRectangle(cornerRadius: DDRadius.card).strokeBorder(Color.ddGold, lineWidth: 1))
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
