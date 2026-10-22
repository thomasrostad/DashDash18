import GolfgutuCore
import SwiftUI

// Toppen av Hjem (fase 19, utbedringsplanen V1, V2 og 4.1): filterpillene og «Neste kveld».
// Runden som pågår står i baren over fanelinja (`HjemLiveBar.swift`).

/// Filterpillene: vannrett rull, valgt i skog med hake (planen 1.3, `DDChoiceButtonStyle`).
struct HjemFilterBar: View {
    let pills: [HomeFeedPill]
    let select: (HomeFeedFilter) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(pills) { pill in
                    Button(pill.title) { select(pill.filter) }
                        .buttonStyle(DDChoiceButtonStyle(selected: pill.isSelected, chip: true))
                        .accessibilityAddTraits(pill.isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, DDSpacing.gutter)
            .padding(.top, 14)
            .padding(.bottom, 4)
        }
        .scrollIndicators(.hidden)
    }
}

/// «Neste kveld» som hero-kort øverst på Hjem (utbedringsplanen 4.1 og V2): etiketten med nedtellingen,
/// datoen, tid og sted, hvem som kommer og svaret ditt som segmentert kontroll. Under kortet står
/// arrangørens rad («Du arrangerer · Sett opp runden ›»), tråden og tipsen. Trykk på toppen åpner
/// Kveld-skjermen.
struct HjemEveningCard: View {
    @Environment(\.dayTerm) private var dayTerm
    @Environment(\.clubContext) private var context
    let evening: HomeNextEvening
    var error: String?
    let onOpen: () -> Void
    let onAnswer: (SignupStatus) -> Void
    /// Arrangørens neste steg.
    var organizer: HjemOrganizerStep?

    var body: some View {
        VStack(alignment: .leading, spacing: DDSpacing.s) {
            hero
            if evening.isOrganizer, let organizer {
                HjemOrganizerRow(step: organizer)
            }
            // Tråden og tippekupongen rett fra Hjem (09.10.2026: kupongen var gjemt bak Kveld-skjermen).
            if let context, context.clubID == evening.clubID {
                KveldExtrasButtons(model: KveldExtrasModel(context: context, eventID: evening.eventID))
                    .id(evening.eventID)
                if let previous = evening.previousEventID {
                    NavigationLink {
                        TipsView(eventID: previous)
                    } label: {
                        Label("Forrige kupong" + (evening.previousTitle.map { " · \($0)" } ?? ""), systemImage: "trophy")
                            .font(.ddCallout)
                    }
                    .buttonStyle(.ddText)
                }
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button(action: onOpen) { header }
                .buttonStyle(.plain)
                .accessibilityHint("Åpner \(dayTerm.the): hvem som kommer, tråden og tipsen.")
            HjemAnswerControl(answer: evening.answer, onAnswer: onAnswer)
            VStack(alignment: .leading, spacing: 6) {
                if let waitlist = evening.waitlistText {
                    Label(waitlist, systemImage: "hourglass")
                } else if let note = evening.answerNote {
                    Text(note)
                }
            }
            .font(.ddCallout)
            .foregroundStyle(Color.ddHeroSecondary)
            .fixedSize(horizontal: false, vertical: true)
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.ddCallout)
                    .foregroundStyle(Color.ddOnDark)
            }
        }
        .ddCard(.hero)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(evening.eyebrow)
                    .ddEyebrow(color: .ddHeroSecondary)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.ddHeroSecondary)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(evening.title)
                    .font(.dd(.sans, size: 26, weight: .medium, relativeTo: .title))
                    .foregroundStyle(Color.ddOnDark)
                Text(evening.detail)
                    .font(.ddCallout)
                    .foregroundStyle(Color.ddHeroSecondary)
            }
            if !evening.comingText.isEmpty {
                HStack(spacing: 10) {
                    HjemAvatarStack(names: evening.comingNames)
                    Text(evening.comingText)
                        .font(.ddCallout)
                        .foregroundStyle(Color.ddOnDark)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// Svaret ditt på hero-kortet: «Kommer» · «Usikker» · «Kommer ikke» som segmenter på 44 pt (V2).
/// Valgt er krem med skogtekst og hake, siden skog på skog ikke synes.
struct HjemAnswerControl: View {
    let answer: SignupStatus?
    let onAnswer: (SignupStatus) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 4))
            : AnyLayout(HStackLayout(spacing: 4))
        layout {
            ForEach(SignupStatus.allCases, id: \.self) { status in
                let selected = answer == status
                Button { onAnswer(status) } label: {
                    HStack(spacing: 4) {
                        if selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .accessibilityHidden(true)
                        }
                        Text(status.title)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .font(.dd(.sans, size: 15, weight: selected ? .semibold : .regular, relativeTo: .subheadline))
                    .foregroundStyle(selected ? Color.ddHeroCard : Color.ddOnDark)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background {
                        if selected { Capsule().fill(Color.ddOnDark) }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(status.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Capsule().fill(Color.ddOnDark.opacity(0.12)))
        .animation(.easeOut(duration: 0.15), value: answer)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Svaret ditt")
    }
}

/// Avatarene til de første som kommer, litt over hverandre.
struct HjemAvatarStack: View {
    let names: [String]
    var limit = 4

    var body: some View {
        HStack(spacing: -8) {
            ForEach(Array(names.prefix(limit).enumerated()), id: \.offset) { _, name in
                DDAvatar(name: name, size: 28)
                    .overlay(Circle().strokeBorder(Color.ddHeroCard, lineWidth: 2))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Arrangørens rad under «Neste kveld» (V2): «Du arrangerer · Sett opp runden ›». Hovedknappen
/// ligger ikke i spillerkortet.
struct HjemOrganizerRow: View {
    let step: HjemOrganizerStep

    var body: some View {
        Button(action: step.perform) {
            HStack(spacing: 10) {
                DDIconTile(systemImage: "slider.horizontal.3", size: 32)
                Text("Du arrangerer · \(Text(step.title).foregroundStyle(Color.ddForestInk).fontWeight(.semibold))")
                    .font(.ddCallout)
                    .foregroundStyle(Color.ddInkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if step.isBusy {
                    ProgressView()
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.ddInkSecondary)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(step.isBusy)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.ddCard, in: .rect(cornerRadius: DDRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DDRadius.card, style: .continuous)
            .strokeBorder(Color.ddCardBorder, lineWidth: 1))
        .accessibilityLabel("Du arrangerer. \(step.title)")
        .accessibilityHint(step.hint)
    }
}

/// Klubbvalget i verktøylinja på Hjem (planen 4.1): «Golfgutu Invitational ⌄» i systemets glass.
/// Vises bare når du er aktiv i flere klubber; samme valg som «Bytt klubb» på Deg.
struct HjemClubMenu: View {
    let memberships: [Membership]
    let current: UUID
    let select: (Membership) -> Void

    var body: some View {
        Menu {
            ForEach(memberships) { membership in
                Button {
                    select(membership)
                } label: {
                    if membership.clubID == current {
                        Label(membership.club.name, systemImage: "checkmark")
                    } else {
                        Text(membership.club.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(memberships.first { $0.clubID == current }?.club.name ?? "Klubb")
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .accessibilityHidden(true)
            }
            .font(.dd(.sans, size: 15, weight: .semibold, relativeTo: .subheadline))
            .foregroundStyle(Color.ddForestInk)
        }
        .accessibilityLabel("Klubb")
        .accessibilityValue(memberships.first { $0.clubID == current }?.club.name ?? "")
        .accessibilityHint("Bytter klubb.")
    }
}
