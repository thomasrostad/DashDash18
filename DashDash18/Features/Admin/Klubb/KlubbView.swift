import Observation
import Supabase
import SwiftUI

/// Klubbens navn og organisasjonsnummer (steg 2). «Hent navn» slår opp nummeret i Enhetsregisteret
/// og tilbyr navnet derfra; brukeren bekrefter før det fylles inn. Lagres med vanlig update på
/// `clubs` (`clubs_update`). Uten 044 finnes ikke `org_number`, og bare navnet vises.
@Observable
final class KlubbModel {
    private(set) var name = ""
    private(set) var orgNumber: String?
    /// `clubs.org_number` finnes (044 er kjørt).
    private(set) var supportsOrgNumber = true
    private(set) var hasLoaded = false
    private(set) var isSaving = false
    private(set) var isLookingUp = false
    var error: String?

    let context: ClubContext

    init(context: ClubContext) {
        self.context = context
    }

    private struct Row: Codable {
        let name: String
        var orgNumber: String?

        enum CodingKeys: String, CodingKey {
            case name
            case orgNumber = "org_number"
        }
    }

    private struct NameOnly: Codable { let name: String }

    func load() async {
        do {
            let rows: [Row] = try await context.client.from("clubs").select("name, org_number")
                .eq("id", value: context.clubID).limit(1).execute().value
            guard let row = rows.first else { throw DataError.notAllowed }
            name = row.name
            orgNumber = row.orgNumber
            supportsOrgNumber = true
            hasLoaded = true
        } catch {
            // Uten 044 finnes ikke kolonnen: hent bare navnet.
            do {
                let rows: [NameOnly] = try await context.client.from("clubs").select("name")
                    .eq("id", value: context.clubID).limit(1).execute().value
                guard let row = rows.first else { throw DataError.notAllowed }
                name = row.name
                orgNumber = nil
                supportsOrgNumber = false
                hasLoaded = true
            } catch {
                self.error = DataError.from(error).message
            }
        }
    }

    /// Navnet fra Enhetsregisteret, eller nil (feilen står i `error`).
    func lookUp(_ raw: String) async -> String? {
        isLookingUp = true
        defer { isLookingUp = false }
        switch await Enhetsregisteret.name(for: raw) {
        case .success(let name): return name
        case .failure(let failure):
            error = failure.message
            return nil
        }
    }

    func save(name rawName: String, orgNumber rawNumber: String) async -> Bool {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...60).contains(name.count) else {
            error = "Klubben må ha et navn (1–60 tegn)."
            return false
        }
        isSaving = true
        defer { isSaving = false }
        do {
            if supportsOrgNumber {
                let number: String?
                switch Enhetsregisteret.storedValue(rawNumber) {
                case .success(let value): number = value
                case .failure(let failure):
                    error = failure.message
                    return false
                }
                // Null sendes som null, så nummeret kan fjernes.
                struct Patch: Encodable {
                    let name: String
                    let org_number: String?
                    func encode(to encoder: any Encoder) throws {
                        var c = encoder.container(keyedBy: CodingKeys.self)
                        try c.encode(name, forKey: .name)
                        try c.encode(org_number, forKey: .org_number)
                    }
                    enum CodingKeys: String, CodingKey { case name, org_number }
                }
                let rows: [Row] = try await context.client.from("clubs")
                    .update(Patch(name: name, org_number: number))
                    .eq("id", value: context.clubID).select("name, org_number").execute().value
                guard let row = rows.first else { throw DataError.notAllowed }
                self.name = row.name
                orgNumber = row.orgNumber
            } else {
                let rows: [NameOnly] = try await context.client.from("clubs")
                    .update(NameOnly(name: name))
                    .eq("id", value: context.clubID).select("name").execute().value
                guard let row = rows.first else { throw DataError.notAllowed }
                self.name = row.name
            }
            error = nil
            return true
        } catch {
            self.error = "Klarte ikke å lagre: \(DataError.from(error).message)"
            return false
        }
    }
}

struct KlubbView: View {
    @Environment(\.clubContext) private var context
    @Environment(ClubModel.self) private var club: ClubModel?
    @State private var model: KlubbModel?
    @State private var name = ""
    @State private var orgNumber = ""
    @State private var offered: String?

    var body: some View {
        Group {
            if let model, model.hasLoaded {
                form(model)
            } else if let model, let error = model.error {
                ContentUnavailableView("Fikk ikke hentet klubben", systemImage: "wifi.exclamationmark",
                                       description: Text(error))
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Klubben")
        .ddNavigationChrome()
        .navigationBarTitleDisplayMode(.inline)
        .task(id: context?.clubID) {
            guard let context else { return }
            let model = KlubbModel(context: context)
            self.model = model
            await model.load()
            name = model.name
            orgNumber = model.orgNumber ?? ""
        }
    }

    private func form(_ model: KlubbModel) -> some View {
        let edited = name != model.name || orgNumber != (model.orgNumber ?? "")
        return DDForm {
            Section {
                TextField("Navn på klubben", text: $name)
                    .textInputAutocapitalization(.words)
            } header: {
                DDHeader("Navn")
            }
            if model.supportsOrgNumber {
                Section {
                    TextField("Organisasjonsnummer (valgfritt)", text: $orgNumber)
                        .keyboardType(.numberPad)
                    Button("Hent navn") {
                        Task {
                            if let found = await model.lookUp(orgNumber) { offered = found }
                        }
                    }
                    .disabled(Enhetsregisteret.normalized(orgNumber) == nil || model.isLookingUp)
                } header: {
                    DDHeader("Enhetsregisteret")
                } footer: {
                    DDFooter("9 siffer. «Hent navn» henter navnet fra Brønnøysundregistrene.")
                }
            }
            Section {
                Button("Lagre") {
                    Task {
                        if await model.save(name: name, orgNumber: orgNumber) {
                            name = model.name
                            orgNumber = model.orgNumber ?? ""
                            if let user = context?.user { await club?.load(userID: user.id) }
                        }
                    }
                }
                .disabled(!edited || model.isSaving)
            }
        }
        .disabled(model.isSaving)
        .alert("Bruke dette navnet?", isPresented: Binding(get: { offered != nil }, set: { if !$0 { offered = nil } }),
               presenting: offered) { found in
            Button("Bruk navnet") { name = found }
            Button("Avbryt", role: .cancel) {}
        } message: { found in
            Text(found)
        }
        .messageAlert("Det gikk ikke", text: Bindable(model).error)
    }
}
