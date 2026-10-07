import SwiftUI

/// Det som rapporteres fra tråden: meldingen (eller bildet) og hvem den er fra.
struct ReportTarget: Identifiable, Equatable {
    let kind: ReportKind
    let targetID: UUID
    /// Medlemmet bak innholdet, så det kan blokkeres samtidig.
    let memberID: UUID?
    let authorName: String
    var id: String { kind.rawValue + targetID.uuidString }
}

/// «Rapporter»: velg grunn, skriv en kommentar om du vil, og blokker gjerne samtidig.
struct ReportSheet: View {
    let target: ReportTarget
    /// Sender rapporten (og blokkerer når `block` er sann). Kaster med norsk tekst ved feil.
    let onSend: (_ reason: ReportReason, _ note: String, _ block: Bool) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var reason: ReportReason?
    @State private var note = ""
    @State private var alsoBlock = false
    @State private var isSending = false
    @State private var error: String?
    @State private var sent = false

    var body: some View {
        NavigationStack {
            DDList {
                if sent {
                    Section {
                        Label("Takk. Rapporten er sendt til arrangøren og oss, og vi ser på den innen 24 timer.",
                              systemImage: "checkmark.seal")
                            .font(.ddCallout)
                            .foregroundStyle(Color.ddForestInk)
                    }
                } else {
                    Section {
                        ForEach(ReportReason.options(for: target.kind)) { option in
                            Button {
                                reason = option
                            } label: {
                                HStack {
                                    Text(option.title).foregroundStyle(Color.ddInk)
                                    Spacer()
                                    if reason == option {
                                        Image(systemName: "checkmark").foregroundStyle(Color.ddForestInk)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(reason == option ? .isSelected : [])
                        }
                    } header: {
                        DDHeader("Hva er galt?")
                    }
                    Section {
                        TextField("Kommentar (valgfritt)", text: $note, axis: .vertical)
                            .lineLimit(2...4)
                            .ddField()
                        if target.memberID != nil {
                            Toggle("Blokker \(target.authorName) også", isOn: $alsoBlock)
                                .tint(Color.ddForestInk)
                        }
                    } footer: {
                        DDFooter("Den du rapporterer, får ikke vite hvem som rapporterte. Det du rapporterer, skjules for deg med en gang.")
                    }
                    Section {
                        Button {
                            send()
                        } label: {
                            HStack(spacing: DDSpacing.s) {
                                Text("Send rapporten")
                                if isSending { ProgressView() }
                            }
                        }
                        .buttonStyle(.dd(.primary, fullWidth: true))
                        .disabled(reason == nil || isSending)
                        if let error {
                            Label(error, systemImage: "exclamationmark.triangle").ddErrorStyle()
                        }
                    }
                }
            }
            .navigationTitle(target.kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .ddNavigationChrome()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(sent ? "Ferdig" : "Avbryt") { dismiss() }
                        .tint(Color.ddOnDark)
                }
            }
        }
        .tint(Color.ddForestInk)
    }

    private func send() {
        guard let reason else { return }
        isSending = true
        error = nil
        Task {
            do {
                try await onSend(reason, note, alsoBlock)
                sent = true
            } catch {
                self.error = DataError.from(error).message
            }
            isSending = false
        }
    }
}

/// «Rapporter» for arrangøren: åpne saker i klubben, eldste først, med «Fjern» og «Avvis».
struct ReportsAdminView: View {
    let service: ModerationService?
    let clubID: UUID
    @State private var cases: [ReportCase]?
    @State private var error: String?
    @State private var busy: UUID?

    init(service: ModerationService?, clubID: UUID, preview: [ContentReportRow]? = nil) {
        self.service = service
        self.clubID = clubID
        _cases = State(initialValue: preview.map(ReportCase.open))
    }

    var body: some View {
        DDList {
            if let cases, cases.isEmpty {
                Section {
                    Text("Ingen åpne rapporter.")
                        .font(.ddCallout)
                        .foregroundStyle(Color.ddInkSecondary)
                }
            }
            ForEach(cases ?? []) { item in
                Section {
                    VStack(alignment: .leading, spacing: DDSpacing.s) {
                        HStack {
                            DDPill(item.first.kind.label, tone: .earth)
                            if item.count > 1 { DDPill("\(item.count) rapporter", tone: .blush) }
                            Spacer()
                            let hours = item.hoursOpen(now: .now)
                            Text(hours < 1 ? "Nå nettopp" : "\(hours) t siden")
                                .font(.ddCaption)
                                .foregroundStyle(hours >= 20 ? Color.ddRustText : Color.ddInkSecondary)
                        }
                        if let snapshot = item.first.snapshot, item.first.kind != .image {
                            Text("«\(snapshot)»")
                                .font(.ddBody)
                                .foregroundStyle(Color.ddInk)
                        } else if item.first.kind == .image {
                            Label("Bilde i tråden", systemImage: "photo")
                                .font(.ddCallout)
                                .foregroundStyle(Color.ddInk)
                        }
                        Text(item.reasons.map(\.title).joined(separator: ", "))
                            .font(.ddCallout)
                            .foregroundStyle(Color.ddInkSecondary)
                        if let note = item.first.note {
                            Text(note).font(.ddCaption).foregroundStyle(Color.ddInkSecondary)
                        }
                        HStack(spacing: DDSpacing.s) {
                            if item.first.kind == .message || item.first.kind == .image {
                                Button("Fjern innholdet") { resolve(item, remove: true) }
                                    .buttonStyle(.dd(.danger, compact: true))
                            }
                            Button("Avvis") { resolve(item, remove: false) }
                                .buttonStyle(.dd(.secondary, compact: true))
                        }
                        .disabled(busy != nil)
                        .padding(.top, DDSpacing.xs)
                    }
                    .padding(.vertical, DDSpacing.xs)
                }
            }
            if let error {
                Section { Label(error, systemImage: "exclamationmark.triangle").ddErrorStyle() }
            }
            Section {
                EmptyView()
            } footer: {
                DDFooter("Rapporter skal følges opp innen 24 timer. Et navn endrer du eller arkiverer i troppen. Vi ser også alle rapportene.")
            }
        }
        .overlay { if cases == nil { ProgressView() } }
        .navigationTitle("Rapporter")
        .ddNavigationChrome()
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard let service else { return }
        do {
            cases = ReportCase.open(try await service.clubReports(clubID: clubID))
        } catch {
            self.error = DataError.from(error).message
            if cases == nil { cases = [] }
        }
    }

    private func resolve(_ item: ReportCase, remove: Bool) {
        guard let service else { cases?.removeAll { $0.id == item.id }; return }
        busy = item.id
        Task {
            defer { busy = nil }
            do {
                _ = try await service.resolve(item.first.id, remove: remove)
                await load()
            } catch {
                self.error = DataError.from(error).message
            }
        }
    }
}
