import SwiftUI

/// «Del regningen»: hva det gjelder, beløpet, hvem som la ut (mottaker i Vipps) og hvem som deler.
/// Hver ser sin del og trykker «Åpne Vipps». Bare felles utgifter, aldri veddemål (B10).
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

    /// `people`: navnene i runden (eller tomt). Den første er deg, som foreslås som mottaker.
    init(people: [String], amount: String = "", payer: String? = nil, phone: String = "") {
        let names = BillSplit.unique(people)
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
                        TextField("Hva gjelder det?", text: $note).ddField()
                    }
                } header: {
                    DDHeader("Hva skal deles")
                }

                Section {
                    TextField("Beløp i kroner", text: $amountText)
                        .keyboardType(.decimalPad)
                        .font(.ddNumberLarge)
                        .ddField()
                    if !amountText.isEmpty, total == nil {
                        Label("Skriv beløpet i kroner, for eksempel 1 250 eller 249,50.", systemImage: "exclamationmark.triangle")
                            .ddErrorStyle()
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
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            if payer == name {
                                DDPill("La ut", tone: .gold)
                            } else {
                                Button("La ut") { payer = name }
                                    .buttonStyle(.dd(.text, compact: true))
                            }
                        }
                    }
                    HStack {
                        TextField("Legg til navn", text: $newName)
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
                        .ddField()
                } header: {
                    DDHeader("Vipps til")
                } footer: {
                    DDFooter("Nummeret lagres ikke. Det står bare i teksten dere kopierer.")
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
                        Button {
                            openURL(VippsLink.app) { accepted in
                                if !accepted { openURL(VippsLink.appStore) }
                            }
                        } label: {
                            Label("Åpne Vipps", systemImage: "arrow.up.forward.app")
                        }
                        .buttonStyle(.dd(.money, fullWidth: true))
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
                }
            }
            .navigationTitle("Del regningen")
            .navigationBarTitleDisplayMode(.inline)
            .ddNavigationChrome()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Lukk") { dismiss() }
                        .tint(Color.ddOnDark)
                }
            }
        }
        .tint(Color.ddForestInk)
    }

    private func addName() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !people.contains(where: { $0.lowercased() == name.lowercased() }) else { return }
        people.append(name)
        included.insert(name)
        if payer == nil { payer = name }
        newName = ""
    }

    private func copy(_ share: BillShare) {
        UIPasteboard.general.string = share.amount.plain
        copied = share.name
    }
}
