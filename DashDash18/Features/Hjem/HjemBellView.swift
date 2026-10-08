import SwiftUI

/// Bjella i verktøylinja (fase 19): tallet er det som angår deg (`HomeBell`) på tvers av klubbene,
/// og den åpner Varsler med de linjene. Henter når den vises, når appen blir aktiv og når en push
/// kommer mens appen står åpen.
struct HjemBell: View {
    let model: HomeFeedModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationLink {
            HjemVarslerView(model: model)
        } label: {
            // Bjella med rust tallmerke (PWA-ens bjelle i headeren). Fargen følger verktøylinja.
            Image(systemName: "bell")
                .overlay(alignment: .topTrailing) {
                    if let label = HomeBell.label(model.bellCount) {
                        DDCountBadge(label)
                            .fixedSize()
                            .offset(x: 10, y: -9)
                    }
                }
        }
        .accessibilityLabel(model.bellCount > 0 ? "Varsler, \(model.bellCount) uleste" : "Varsler")
        .task { await model.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.load() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: PushInbox.received)) { _ in
            Task { await model.load() }
        }
    }
}

/// Varsler bak bjella: bare det som angår deg (nevnt, utfordret, purret på, melding til alle, din
/// runde, din bragd, plassbytte), med reaksjoner. Arrangøren kan sende «Melding til alle».
struct HjemVarslerView: View {
    let model: HomeFeedModel
    @Environment(\.clubContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var announcement: VarslerModel?

    var body: some View {
        content
            .navigationTitle("Varsler")
            .ddNavigationChrome()
            .toolbar {
                if let context, context.isOrganizer {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Melding til alle", systemImage: "megaphone") {
                            announcement = VarslerModel(context: context)
                        }
                    }
                }
            }
            .sheet(item: $announcement, onDismiss: { Task { await model.load() } }) { sheetModel in
                AnnouncementSheet(model: sheetModel)
            }
            .alert("Noe gikk galt", isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
            .onAppear { model.openBell() }
            .task { await model.load() }
            .refreshable { await model.load() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await model.load() } }
            }
            // Skjermen er åpen: det som kommer, er sett.
            .onChange(of: model.bellRows.first?.id) { _, _ in model.markBellSeen() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView("Henter varslene …")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("Fikk ikke hentet varslene", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Prøv igjen") { Task { await model.load() } }
                    .buttonStyle(.dd(.primary))
            }
        case .loaded:
            let sections = model.bellSections()
            if sections.isEmpty {
                ContentUnavailableView("Ingenting ennå", systemImage: "bell",
                                       description: Text("Her kommer det som angår deg: når du blir nevnt, utfordret eller purret på, meldinger til alle og rundene dine. Resten står på Hjem."))
            } else {
                DDList {
                    ForEach(sections) { section in
                        DDSection(section.title) {
                            ForEach(section.items) { item in
                                ActivityLineView(display: item.display, time: item.time, isUnread: item.isUnread,
                                                 chips: item.chips,
                                                 hasReacted: { model.hasReacted($0, on: item.target) },
                                                 toggle: { reaction in
                                                     Task { await model.toggle(reaction, on: item.target) }
                                                 })
                            }
                        }
                    }
                }
            }
        }
    }
}

extension VarslerModel: Identifiable {
    nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }
}
