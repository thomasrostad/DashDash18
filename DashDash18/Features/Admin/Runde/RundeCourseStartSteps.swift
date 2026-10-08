import GolfgutuCore
import SwiftUI

/// «Bane» bak bane-raden på «Ny runde»: banene med hull, par, CR og slope. «Hvor spiller dere?» står
/// øverst bare når klubben har både simulatorbaner og ekte baner; ellers følger stedet banen.
struct RundeCourseStep: View {
    let model: RundeAdminModel
    @Binding var draft: RoundDraft
    let showsVenue: Bool

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let choices = RoundConfirm.courseChoices(model.courses, selected: model.course(draft.courseID),
                                                 venue: draft.venue, showsVenue: showsVenue)
        DDForm {
            if showsVenue {
                Section {
                    Picker("Hvor spiller dere?", selection: Binding(
                        get: { draft.venue },
                        set: { draft.setVenue($0, rules: model.rules) }
                    )) {
                        ForEach(Venue.allCases, id: \.self) { venue in
                            Text(venue.title).tag(venue)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    DDHeader("Hvor spiller dere?")
                }
            }
            Section {
                if choices.isEmpty {
                    Text("Ingen baner er klare. Legg inn parene under «Banene» først.")
                        .foregroundStyle(Color.ddInkSecondary)
                }
                ForEach(choices) { course in
                    courseRow(course)
                }
            } header: {
                DDHeader(showsVenue ? (draft.venue == .course ? "Ekte baner" : "Simulatorbaner") : "Baner")
            }
        }
    }

    private func courseRow(_ course: CourseListItem) -> some View {
        Button {
            let changed = course.id != draft.courseID
            RoundConfirm.selectCourse(course, on: &draft, rules: model.rules)
            if changed { draft.teeID = model.suggestedTeeID(for: course) }
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(course.course.name + (course.isReady ? "" : " (ikke klar)"))
                        .foregroundStyle(Color.ddInk)
                    Text(RoundConfirm.courseDetail(course))
                        .font(.ddCaption)
                        .foregroundStyle(Color.ddInkSecondary)
                }
                Spacer()
                if course.id == draft.courseID {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.ddForestInk)
                        .accessibilityLabel("Valgt")
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!course.isReady)
    }
}

/// «Start» bak start-raden på «Ny runde»: hvor runden starter, hvor mange hull, og første tee.
struct RundeStartStep: View {
    let model: RundeAdminModel
    @Binding var draft: RoundDraft

    private var selectedCourse: CourseListItem? { model.course(draft.courseID) }

    var body: some View {
        DDForm {
            Section {
                Picker("Start", selection: Binding(
                    get: { QuickStartStart(firstHole: draft.firstHole, holeCount: draft.holeCount) },
                    set: { QuickStart.setStart($0, on: &draft, courseHoles: selectedCourse?.holeCount) }
                )) {
                    ForEach(startOptions, id: \.self) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                DDHeader("Hull")
            }
            Section {
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
                DDHeader("Tid")
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
}
