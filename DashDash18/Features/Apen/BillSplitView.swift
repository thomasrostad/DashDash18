import SwiftUI

/// «Del regningen»: hva det gjelder, beløpet, hvem som la ut (mottaker i Vipps) og hvem som deler.
/// Hver ser sin del og trykker «Åpne Vipps». Bare felles utgifter, aldri veddemål (B10).
/// Med `saveContext` og sql/051 kan regningen lagres og følges opp i «Mine oppgjør». Uten 051
/// deles den som før, uten lagring.
struct BillSplitView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var purpose: BillPurpose = .simulator
    @State private var note = ""
    @State private var amountText: String
    @State private var people: [String]
    @State private var included: Set<String>
    @State private var payer: String?
    @State private var phoneText = ""
    @State private var newName = ""
    @State private var copied: String?
    /// Navn → profil for dem med innlogging (lagres som profil på delen).
    private let profiles: [String: UUID]
    private let saveContext: BillService.SaveContext?
    /// sql/051 finnes. nil til det er sjekket.
    @State private var canSave: Bool?
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var saved = false
    /// Feltet med tastaturet. Tall- og telefontastaturet har ingen returtast, så «Ferdig» over
    /// tastaturet, dra i lista og knappene under lukker det.
    @FocusState private var focused: Field?

    private enum Field: Hashable { case note, amount, name, phone }

    /// `people`: navnene i runden (eller tomt). Den første er deg, som foreslås som mottaker.
    /// `profiles`: navn → profil-id for dem med innlogging. `saveContext`: hvor regningen lagres.
    init(people: [String], amount: String = "", payer: String? = nil, phone: String = "",
         profiles: [String: UUID] = [:], saveContext: BillService.SaveContext? = nil) {
        let names = BillSplit.unique(people)
        self.profiles = profiles
        self.saveContext = saveContext
        _people = State(initialValue: names)
        _included = State(initialValue: Set(names))
        _payer = State(initialValue: payer ?? names.first)
        _amountText = State(initialValue: amount)
        _phoneText = State(initialValue: phone)
    }

    private var total: NOK? { NOK(parsing: amountText) }
    private var sharing: [String] { people.filter { included.contains($0) } }
    private var phone: String? { VippsRecipient.normalizedPhone(phoneText) }
    private var shares: [BillShare] {
        guard let total else { return [] }
        return BillSplit.shares(total: total, people: sharing, payer: payer)
    }

    var body: some View {
        NavigationStack {
            DDList {
                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                        ForEach(BillPurpose.allCases) { option in
                            Button(option.title) { purpose = option }
                                .buttonStyle(DDChoiceButtonStyle(selected: purpose == option))
                        }
                    }
                    .padding(.vertical, 4)
                    if purpose == .other {
                        TextField("Hva gjelder det?", text: $note)
                            .focused($focused, equals: .note)
                            .submitLabel(.done)
                            .ddField()
                    }
                } header: {
                    DDHeader("Hva skal deles")
                }

                Section {
                    HStack(alignment: .firstTextBaseline, spacing: DDSpacing.s) {
                        TextField("0", text: $amountText)
                            .keyboardType(.decimalPad)
                            .focused($focused, equals: .amount)
                            .font(.ddNumberLarge)
                            .monospacedDigit()
                            .accessibilityLabel("Beløp i kroner")
                        Text("kr")
                            .font(.ddNumberLarge)
                            .foregroundStyle(Color.ddInkSecondary)
                            .accessibilityHidden(true)
                    }
                    .ddField()
                    if !amountText.isEmpty, total == nil {
                        Label("Skriv beløpet i kroner, for eksempel 1 250 eller 249,50.", systemImage: "exclamationmark.triangle")
                            .ddErrorStyle()
                    } else if let total, let line = BillSplitSummary.perPerson(total: total, count: sharing.count) {
                        // Live under feltet (V14): «312,50 kr hver (4 personer)».
                        Text(line)
                            .font(.ddStatus)
                            .monospacedDigit()
                            .foregroundStyle(Color.ddForestInk)
                            .contentTransition(.numericText())
                    }
                } header: {
                    DDHeader("Totalt")
                }

                Section {
                    ForEach(people, id: \.self) { name in
                        HStack {
                            Button {
                                if included.contains(name) { included.remove(name) } else { included.insert(name) }
                            } label: {
                                Label(name, systemImage: included.contains(name) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(included.contains(name) ? Color.ddForestInk : Color.ddInkSecondary)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(included.contains(name) ? .isSelected : [])
                            .accessibilityHint("Deler regningen")
                            // Samme valg på hver rad (V14): radioknapp for den som la ut.
                            Button {
                                payer = name
                            } label: {
                                Label("La ut", systemImage: payer == name ? "largecircle.fill.circle" : "circle")
                                    .font(.ddStatus)
                                    .foregroundStyle(payer == name ? Color.ddForestInk : Color.ddInkSecondary)
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(name) la ut")
                            .accessibilityAddTraits(payer == name ? .isSelected : [])
                        }
                    }
                    HStack {
                        TextField("Legg til navn", text: $newName)
                            .focused($focused, equals: .name)
                            .submitLabel(.done)
                            .onSubmit(addName)
                        Button("Legg til", action: addName)
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    DDHeader("Hvem deler")
                } footer: {
                    DDFooter("Alle som er huket av, deler likt. Den som la ut, får pengene og betaler ikke seg selv.")
                }

                Section {
                    TextField("Mobilnummer til \(payer ?? "mottakeren")", text: $phoneText)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .focused($focused, equals: .phone)
                        .ddField()
                } header: {
                    DDHeader("Vipps til")
                } footer: {
                    DDFooter(phoneFooter)
                }

                if let total, !shares.isEmpty {
                    Section {
                        ForEach(shares) { share in
                            HStack {
                                Text(share.name)
                                Spacer()
                                Text(share.amount.text)
                                    .font(.ddNumber)
                                    .monospacedDigit()
                                Button {
                                    copy(share)
                                } label: {
                                    Image(systemName: copied == share.name ? "checkmark" : "doc.on.doc")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Kopier beløpet til \(share.name)")
                            }
                        }
                        ShareLink(item: VippsLink.summary(shares: shares, total: total, recipientName: payer ?? "",
                                                          phone: phone, purpose: purpose, note: note)) {
                            Label("Del oppgjøret", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.dd(.secondary, fullWidth: true))
                    } header: {
                        DDHeader("Hver betaler")
                    } footer: {
                        DDFooter("Vipps fyller ikke inn beløpet for private betalinger. Kopier beløpet, åpne Vipps og send til \(payer ?? "mottakeren")\(phone.map { " på \(VippsRecipient.formatted($0))" } ?? ""). Veddemål gjøres opp i poeng, aldri her.")
                    }
                    if canSave == true, saveContext != nil {
                        saveSection(total: total)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            // Hovedknappen i bunnen (V8), så den aldri dekker lista. Skjules mens tastaturet er oppe.
            .safeAreaInset(edge: .bottom) {
                if total != nil, !shares.isEmpty, focused == nil {
                    Button {
                        openVipps()
                    } label: {
                        Label("Åpne Vipps", systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(.dd(.money, fullWidth: true))
                    .modifier(BottomActionBar())
                }
            }
            .onChange(of: focused) { old, _ in
                // «1250» blir «1 250» når feltet forlates.
                if old == .amount, let total { amountText = BillSplitSummary.fieldText(total) }
            }
            .navigationTitle("Del regningen")
            .navigationBarTitleDisplayMode(.inline)
            .ddNavigationChrome()
            .toolbar {
                DDCancelToolbarItem {
                    Button("Lukk") { dismiss() }
                        .tint(Color.ddForestInk)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Ferdig") { focused = nil }
                }
            }
        }
        .tint(Color.ddForestInk)
        .task {
            if canSave == nil, let saveContext {
                canSave = await BillService.isAvailable(client: saveContext.client)
            }
        }
    }

    // MARK: Lagre (sql/051)

    private var payeePerson: BillPerson? {
        payer.map { BillPerson(name: $0, profileID: profiles[$0]) }
    }

    /// Du er selv mottakeren: bare da kan nummeret lagres på regningen.
    private var payeeIsMe: Bool {
        guard let saveContext, let id = payeePerson?.profileID else { return false }
        return id == saveContext.userID
    }

    private var phoneFooter: String {
        guard canSave == true, saveContext != nil else {
            return "Nummeret lagres ikke. Det står bare i teksten dere kopierer."
        }
        return payeeIsMe
            ? "Lagrer du regningen, står nummeret på den til alle har betalt. Så slettes det."
            : "Bare mottakeren kan lagre sitt eget nummer. Det står i teksten dere kopierer."
    }

    @ViewBuilder
    private func saveSection(total: NOK) -> some View {
        Section {
            if saved, let saveContext {
                Label("Lagret", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color.ddForestInk)
                NavigationLink {
                    BillSettlementsView(client: saveContext.client, userID: saveContext.userID)
                } label: {
                    Label("Mine oppgjør", systemImage: "list.bullet.rectangle")
                }
            } else {
                Button {
                    focused = nil
                    Task { await save(total: total) }
                } label: {
                    HStack(spacing: DDSpacing.s) {
                        Text("Lagre og følg opp")
                        if isSaving { ProgressView() }
                    }
                }
                .buttonStyle(.dd(.secondary, fullWidth: true))
                .disabled(isSaving || payeePerson == nil)
                if let saveError {
                    Label(saveError, systemImage: "exclamationmark.triangle").ddErrorStyle()
                }
            }
        } footer: {
            DDFooter("De med innlogging ser sin del i «Mine oppgjør» under Deg. Delen merkes sendt når de kommer tilbake fra Vipps.")
        }
    }

    private func save(total: NOK) async {
        guard let saveContext, let payee = payeePerson else { return }
        let plan = BillSplit.plan(total: total, people: sharing, payer: payer)
        guard !plan.shares.isEmpty, plan.sum == total.ore else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            _ = try await BillService.create(
                context: saveContext, title: BillSplit.title(purpose: purpose, note: note), total: total,
                payee: payee, payeeShare: plan.payeeShare,
                shares: plan.shares.map { (BillPerson(name: $0.name, profileID: profiles[$0.name]), $0.amount) },
                payeeVipps: phone)
            saved = true
        } catch {
            saveError = error.message
        }
    }

    private func addName() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !people.contains(where: { $0.lowercased() == name.lowercased() }) else { return }
        people.append(name)
        included.insert(name)
        if payer == nil { payer = name }
        newName = ""
    }

    /// Vipps-appen, ellers vipps.no (åpner appen når den finnes), ellers App Store.
    private func openVipps() {
        openURL(VippsLink.app) { accepted in
            guard !accepted else { return }
            openURL(VippsLink.web) { accepted in
                if !accepted { openURL(VippsLink.appStore) }
            }
        }
    }

    private func copy(_ share: BillShare) {
        focused = nil
        UIPasteboard.general.string = share.amount.plain
        copied = share.name
    }
}

/// Tekstene under beløpet i «Del regningen» (V14).
nonisolated enum BillSplitSummary {
    /// «312,50 kr hver (4 personer)». Går det ikke opp i øre, får noen ett øre mer:
    /// «333,33–333,34 kr hver (3 personer)». nil uten noen å dele på.
    static func perPerson(total: NOK, count: Int) -> String? {
        guard count > 0 else { return nil }
        let people = count == 1 ? "1 person" : "\(count) personer"
        let low = NOK(ore: total.ore / count)
        guard total.ore % count != 0 else { return "\(low.text) hver (\(people))" }
        let high = NOK(ore: low.ore + 1)
        return "\(fieldText(low))–\(high.text) hver (\(people))"
    }

    /// Beløpet i feltet, med tusenskille og uten «kr»: «1 250» eller «249,50».
    static func fieldText(_ amount: NOK) -> String {
        String(amount.text.dropLast(" kr".count))
    }
}
