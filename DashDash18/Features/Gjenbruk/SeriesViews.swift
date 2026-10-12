import GolfgutuCore
import SwiftUI

/// «Lag serie»: første dato, ukedag, hvor ofte, antall, tid og sted, med datoene som forhåndsvisning.
/// Etter lagringen vises datoene som ble lagt inn og de som ble hoppet over.
struct EventSeriesSheet: View {
    /// Datoene turneringen alt har.
    let taken: Set<String>
    let create: (String, SeriesPlan) async throws(DataError) -> CreateSeriesResult
    let done: () -> Void

    @Environment(\.dayTerm) private var dayTerm
    @State private var start: Date
    @State private var plan: SeriesPlan
    @State private var hasTime: Bool
    @State private var time: Date
    @State private var venue: String
    @State private var result: CreateSeriesResult?
    @State private var error: String?
    @State private var isBusy = false

    init(plan: SeriesPlan?, taken: Set<String>, today: String = EveningDates.today(),
         create: @escaping (String, SeriesPlan) async throws(DataError) -> CreateSeriesResult,
         done: @escaping () -> Void) {
        self.taken = taken
        self.create = create
        self.done = done
        let startDate = EveningDates.date(from: today) ?? .now
        let weekday = EventSeriesDates.isoWeekday(today) ?? 4
        let initial = plan ?? SeriesPlan(weekday: weekday, count: 10)
        _start = State(initialValue: startDate)
        _plan = State(initialValue: initial)
        _hasTime = State(initialValue: initial.startTime != nil)
        _time = State(initialValue: initial.startTime.flatMap { EveningDates.time(from: $0) }
            ?? EveningDates.time(from: "18:00")!)
        _venue = State(initialValue: initial.venue ?? "")
    }

    private var startText: String { EveningDates.dateString(from: start) }

    private var wanted: SeriesPlan {
        var p = plan
        p.startTime = hasTime ? EveningDates.timeString(from: time) : nil
        p.venue = EventSeriesDates.cleanVenue(venue)
        return p
    }

    var body: some View {
        DDForm {
            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Color.ddError)
                }
            }
            if let result {
                resultSections(result)
            } else {
                planSection
                previewSection
            }
        }
        .environment(\.timeZone, EveningDates.osloTimeZone)
        .navigationTitle("Lag serie")
        .ddNavigationChrome()
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isBusy)
        .interactiveDismissDisabled(isBusy)
        .toolbar {
            if result == nil {
                DDCancelToolbarItem {
                    Button("Avbryt", action: done)
                }
            }
            DDConfirmToolbarItem {
                if isBusy {
                    ProgressView()
                } else if result != nil {
                    Button("Ferdig", action: done)
                } else {
                    Button("Lag", action: save)
                        .disabled(EventSeriesDates.preview(start: startText, plan: wanted, existing: taken).created.isEmpty)
                }
            }
        }
    }

    private var planSection: some View {
        Section {
            DatePicker("Første dato", selection: $start, displayedComponents: .date)
            Picker("Ukedag", selection: $plan.weekday) {
                ForEach(SeriesPlan.weekdayRange, id: \.self) { day in
                    Text(SeriesText.weekday(day).capitalized).tag(day)
                }
            }
            Picker("Hvor ofte", selection: $plan.everyWeeks) {
                ForEach(SeriesPlan.everyWeeksRange, id: \.self) { weeks in
                    Text(SeriesText.every(weeks)).tag(weeks)
                }
            }
            Stepper("Antall: \(plan.count)", value: $plan.count, in: SeriesPlan.countRange)
            Toggle("Klokkeslett", isOn: $hasTime)
            if hasTime {
                DatePicker("Starter", selection: $time, displayedComponents: .hourAndMinute)
            }
            TextField("Sted (valgfritt)", text: $venue)
                .textInputAutocapitalization(.words)
        } footer: {
            DDFooter("Første \(dayTerm.one) er første \(SeriesText.weekday(plan.weekday)) fra og med datoen.")
        }
    }

    private var previewSection: some View {
        let preview = EventSeriesDates.preview(start: startText, plan: wanted, existing: taken)
        let year = EveningDates.year(of: EveningDates.today())
        return Section {
            ForEach(EventSeriesDates.dates(start: startText, plan: wanted), id: \.self) { date in
                HStack {
                    Text(EveningDates.longText(date, referenceYear: year, capitalized: true))
                        .foregroundStyle(taken.contains(date) ? Color.ddInkSecondary : Color.ddInk)
                    Spacer()
                    if taken.contains(date) {
                        Text("Finnes alt")
                            .font(.ddCaption)
                            .foregroundStyle(Color.ddInkSecondary)
                    }
                }
            }
        } header: {
            DDHeader("Datoene (\(preview.created.count))")
        } footer: {
            if !preview.skipped.isEmpty {
                DDFooter("Datoer som alt er i bruk, hoppes over.")
            }
        }
    }

    @ViewBuilder
    private func resultSections(_ result: CreateSeriesResult) -> some View {
        let year = EveningDates.year(of: EveningDates.today())
        Section {
            if result.dates.isEmpty {
                Text("Ingen nye datoer.").foregroundStyle(Color.ddInkSecondary)
            }
            ForEach(result.dates, id: \.self) { date in
                Label(EveningDates.longText(date, referenceYear: year, capitalized: true), systemImage: "checkmark")
            }
        } header: {
            DDHeader("Lagt inn (\(result.dates.count))")
        }
        if !result.skipped.isEmpty {
            Section {
                ForEach(result.skipped, id: \.self) { date in
                    Text(EveningDates.longText(date, referenceYear: year, capitalized: true))
                        .foregroundStyle(Color.ddInkSecondary)
                }
            } header: {
                DDHeader("Hoppet over (\(result.skipped.count))")
            } footer: {
                DDFooter("Turneringen hadde alt en \(dayTerm.one) disse datoene.")
            }
        }
    }

    private func save() {
        isBusy = true
        error = nil
        Task {
            defer { isBusy = false }
            do throws(DataError) {
                result = try await create(startText, wanted)
            } catch {
                self.error = error.message
            }
        }
    }
}

/// Identifiserbar innpakning, så en plan kan styre et ark.
struct SeriesSheetItem: Identifiable {
    let id = UUID()
    let plan: SeriesPlan?
}

/// «Fast spilledag» i Ny turnering: planen som lagres i malen og tilbys som «Lag serie» etter «Lag».
struct SchedulePlanSection: View {
    @Binding var plan: SeriesPlan?

    var body: some View {
        Section {
            Toggle("Fast spilledag", isOn: Binding(
                get: { plan != nil },
                set: { plan = $0 ? (plan ?? SeriesPlan(weekday: EventSeriesDates.isoWeekday(EveningDates.today()) ?? 4,
                                                       count: 10, startTime: "18:00")) : nil }))
            if let current = plan {
                Picker("Ukedag", selection: field(\.weekday, current)) {
                    ForEach(SeriesPlan.weekdayRange, id: \.self) { Text(SeriesText.weekday($0).capitalized).tag($0) }
                }
                Picker("Hvor ofte", selection: field(\.everyWeeks, current)) {
                    ForEach(SeriesPlan.everyWeeksRange, id: \.self) { Text(SeriesText.every($0)).tag($0) }
                }
                Stepper("Antall: \(current.count)", value: field(\.count, current), in: SeriesPlan.countRange)
                DatePicker("Starter", selection: Binding(
                    get: { current.startTime.flatMap { EveningDates.time(from: $0) } ?? EveningDates.time(from: "18:00")! },
                    set: { plan?.startTime = EveningDates.timeString(from: $0) }),
                           displayedComponents: .hourAndMinute)
                TextField("Sted (valgfritt)", text: Binding(
                    get: { current.venue ?? "" },
                    set: { plan?.venue = $0.isEmpty ? nil : $0 }))
                    .textInputAutocapitalization(.words)
            }
        } header: {
            DDHeader("Spilledager")
        } footer: {
            DDFooter(plan == nil ? "Legg inn datoene selv etterpå."
                     : "Etter «Lag» velger du første dato, og datoene legges inn.")
        }
        .environment(\.timeZone, EveningDates.osloTimeZone)
    }

    private func field(_ key: WritableKeyPath<SeriesPlan, Int>, _ current: SeriesPlan) -> Binding<Int> {
        Binding(get: { plan?[keyPath: key] ?? current[keyPath: key] }, set: { plan?[keyPath: key] = $0 })
    }
}
