import Supabase
import SwiftUI

/// «Mine oppgjør» (sql/051): regningene du får penger for, og de du skal betale. Mottakeren sier
/// «Fikk den» eller «Kom ikke». Den som skal betale, trykker «Betal med Vipps», og delen merkes
/// sendt når appen blir aktiv igjen.
struct BillSettlementsView: View {
    let client: SupabaseClient
    let userID: UUID
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var settlements: [BillSettlement]?
    @State private var error: String?
    @State private var busy: Set<UUID> = []
    @State private var tracker = VippsReturnTracker()
    @State private var copied: UUID?
    @State private var deleting: BillSettlement?

    private var owedToMe: [BillSettlement] { (settlements ?? []).filter { $0.isPayee(userID) } }
    private var iOwe: [BillSettlement] {
        (settlements ?? []).filter { !$0.isPayee(userID) && $0.myShare(userID) != nil }
    }

    var body: some View {
        DDList {
            if let error, settlements != nil {
                Section { Label(error, systemImage: "exclamationmark.triangle").ddErrorStyle() }
            }
            if let settlements, settlements.isEmpty {
                Section {
                    Text("Ingen oppgjør ennå. Lagre en regning fra «Del regningen» i runden.")
                        .font(.ddCallout)
                        .foregroundStyle(Color.ddInkSecondary)
                }
            }
            ForEach(iOwe) { settlement in
                if let share = settlement.myShare(userID) {
                    debtorSection(settlement, share: share)
                }
            }
            ForEach(owedToMe) { settlement in
                payeeSection(settlement)
            }
        }
        .overlay {
            if settlements == nil {
                if let error {
                    ContentUnavailableView {
                        Label("Fikk ikke hentet oppgjørene", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Prøv igjen") {
                            self.error = nil
                            Task { await load() }
                        }
                        .buttonStyle(.dd(.primary))
                    }
                } else {
                    ProgressView("Henter oppgjørene …")
                }
            }
        }
        .navigationTitle("Mine oppgjør")
        .ddNavigationChrome()
        .refreshable { await load() }
        .task { await load() }
        .onChange(of: scenePhase) { _, phase in
            let mapped: AppPhase = switch phase {
            case .active: .active
            case .background: .background
            default: .inactive
            }
            if let share = tracker.phaseChanged(to: mapped) {
                Task { await markSent(share) }
            }
        }
        .confirmationDialog("Slette regningen?", isPresented: Binding(get: { deleting != nil },
                                                                      set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { settlement in
            Button("Slett", role: .destructive) { Task { await delete(settlement) } }
            Button("Avbryt", role: .cancel) {}
        } message: { _ in
            Text("Alle som er med, mister den.")
        }
    }

    // MARK: Du skal betale

    private func debtorSection(_ settlement: BillSettlement, share: BillShareRow) -> some View {
        let split = settlement.split
        return Section {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(split.title).font(.ddBodyEmphasis)
                    Text(share.status.debtorText(payee: split.payeeName))
                        .font(.ddCallout)
                        .foregroundStyle(share.status == .disputed ? Color.ddRustText : Color.ddInkSecondary)
                }
                Spacer()
                Text(share.amount.text).font(.ddNumber).monospacedDigit()
            }
            if share.status.canPay {
                if let phone = split.payeeVipps {
                    LabeledContent("Vipps til \(split.payeeName)", value: VippsRecipient.formatted(phone))
                }
                Button {
                    pay(share)
                } label: {
                    Label(copied == share.id ? "Beløpet er kopiert" : "Betal med Vipps", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.dd(.money, fullWidth: true))
                .disabled(busy.contains(share.id))
            }
        } header: {
            DDHeader("Du skal betale")
        } footer: {
            if share.status.canPay {
                DDFooter("Beløpet kopieres. Lim det inn i Vipps. Delen merkes sendt når du kommer tilbake.")
            }
        }
    }

    // MARK: Du får

    private func payeeSection(_ settlement: BillSettlement) -> some View {
        let split = settlement.split
        return Section {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(split.title).font(.ddBodyEmphasis)
                    Text(settlement.progressText).font(.ddCallout).foregroundStyle(Color.ddInkSecondary)
                }
                Spacer()
                Text(NOK(ore: split.totalOre).text).font(.ddNumber).monospacedDigit()
            }
            ForEach(settlement.owed) { share in
                VStack(alignment: .leading, spacing: DDSpacing.xs) {
                    HStack {
                        Text(share.name)
                        Spacer()
                        Text(share.amount.text).font(.ddNumber).monospacedDigit()
                    }
                    HStack {
                        DDPill(share.status.payeeText, tone: tone(share.status))
                        Spacer()
                        if share.status.canConfirm {
                            Button("Fikk den") { Task { await confirm(share, received: true) } }
                                .buttonStyle(.dd(.text, compact: true))
                        }
                        if share.status.canDispute {
                            Button("Kom ikke") { Task { await confirm(share, received: false) } }
                                .buttonStyle(.dd(.text, compact: true))
                        }
                    }
                    .disabled(busy.contains(share.id))
                }
                .padding(.vertical, 2)
            }
            if settlement.canDelete(userID) {
                Button("Slett regningen", role: .destructive) { deleting = settlement }
                    .foregroundStyle(Color.ddRustText)
            }
        } header: {
            DDHeader("Du får")
        } footer: {
            DDFooter(split.payeeVipps == nil
                     ? "Sjekk Vipps før du trykker «Fikk den»."
                     : "Sjekk Vipps før du trykker «Fikk den». Nummeret ditt slettes når alle har betalt.")
        }
    }

    private func tone(_ status: BillShareStatus) -> DDTone {
        switch status {
        case .open: .earth
        case .sent: .sun
        case .confirmed: .lime
        case .disputed: .blush
        }
    }

    // MARK: Handlinger

    private func load() async {
        do {
            settlements = try await BillService.settlements(client: client)
            error = nil
        } catch {
            // Uten data vises feilen med «Prøv igjen», ikke «Ingen oppgjør ennå».
            self.error = error.message
        }
    }

    /// Kopier beløpet, åpne Vipps (ellers vipps.no, ellers App Store) og husk delen til du er tilbake.
    private func pay(_ share: BillShareRow) {
        UIPasteboard.general.string = share.amount.plain
        copied = share.id
        tracker.opened(share: share.id)
        openURL(VippsLink.app) { accepted in
            guard !accepted else { return }
            openURL(VippsLink.web) { accepted in
                guard !accepted else { return }
                openURL(VippsLink.appStore) { accepted in
                    if !accepted { tracker.openFailed() }
                }
            }
        }
    }

    private func markSent(_ shareID: UUID) async {
        busy.insert(shareID)
        defer { busy.remove(shareID) }
        do {
            try await BillService.markSent(client: client, shareID: shareID)
            await load()
        } catch {
            self.error = error.message
        }
    }

    private func confirm(_ share: BillShareRow, received: Bool) async {
        busy.insert(share.id)
        defer { busy.remove(share.id) }
        do {
            try await BillService.confirm(client: client, shareID: share.id, received: received)
            await load()
        } catch {
            self.error = error.message
        }
    }

    private func delete(_ settlement: BillSettlement) async {
        do {
            try await BillService.delete(client: client, splitID: settlement.id)
            await load()
        } catch {
            self.error = error.message
        }
    }
}
