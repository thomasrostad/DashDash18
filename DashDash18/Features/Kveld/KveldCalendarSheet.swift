import EventKit
import EventKitUI
import SwiftUI

/// Apples «Ny hendelse»-ark, forhåndsutfylt. Fra iOS 17 kjører arket utenfor appen, så det
/// trengs ingen kalendertilgang: vi ber aldri om tilgang og leser ingenting fra kalenderen.
/// Brukeren lagrer eller avbryter selv.
struct KveldCalendarSheet: UIViewControllerRepresentable {
    let entry: CalendarEntry
    let done: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(done: done)
    }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = context.coordinator.store
        let event = EKEvent(eventStore: store)
        event.title = entry.title
        event.startDate = entry.start
        event.endDate = entry.end
        event.isAllDay = entry.isAllDay
        event.timeZone = entry.timeZone
        event.location = entry.location
        event.notes = entry.notes
        if let offset = entry.alarmOffset {
            event.addAlarm(EKAlarm(relativeOffset: offset))
        }

        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let store = EKEventStore()
        let done: () -> Void

        init(done: @escaping () -> Void) {
            self.done = done
        }

        func eventEditViewController(_ controller: EKEventEditViewController,
                                     didCompleteWith action: EKEventEditViewAction) {
            done()
        }
    }
}

/// «Legg i kalender» under kortet for neste kveld.
struct AddToCalendarButton: View {
    let entry: CalendarEntry
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Label("Legg i kalender", systemImage: "calendar.badge.plus")
        }
        .buttonStyle(.dd(.secondary, fullWidth: true))
        .sheet(isPresented: $isPresented) {
            KveldCalendarSheet(entry: entry) { isPresented = false }
                .ignoresSafeArea()
        }
    }
}
