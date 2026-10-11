import Foundation

/// Navnet på klubben fra Enhetsregisteret (Brønnøysundregistrene). Åpent API uten nøkkel:
/// `https://data.brreg.no/enhetsregisteret/api/enheter/{orgnr}`. Vi bruker bare `navn`.
nonisolated enum Enhetsregisteret {
    nonisolated enum LookupError: Error, Equatable {
        case invalidNumber
        case notFound
        case deleted
        case offline
        case failed

        var message: String {
            switch self {
            case .invalidNumber: "Organisasjonsnummeret må ha 9 siffer."
            case .notFound: "Fant ingen enhet med det nummeret."
            case .deleted: "Enheten er slettet i Enhetsregisteret."
            case .offline: "Ingen kontakt med Enhetsregisteret. Sjekk nettet."
            case .failed: "Fikk ikke svar fra Enhetsregisteret. Prøv igjen."
            }
        }
    }

    /// Nummeret uten mellomrom (også hardt mellomrom fra innliming). nil når det ikke er 9 siffer.
    static func normalized(_ raw: String) -> String? {
        let digits = String(raw.filter { !$0.isWhitespace })
        guard digits.wholeMatch(of: /[0-9]{9}/) != nil else { return nil }
        return digits
    }

    /// Lagres som `clubs.org_number`: tomt felt er null.
    static func storedValue(_ raw: String) -> Result<String?, LookupError> {
        if raw.allSatisfy(\.isWhitespace) { return .success(nil) }
        guard let number = normalized(raw) else { return .failure(.invalidNumber) }
        return .success(number)
    }

    static func url(for number: String) -> URL {
        URL(string: "https://data.brreg.no/enhetsregisteret/api/enheter/\(number)")!
    }

    /// Navnet fra svaret. 400: ugyldig nummer, 404: finnes ikke, 410: slettet.
    static func parse(status: Int, data: Data) -> Result<String, LookupError> {
        switch status {
        case 200:
            struct Entity: Decodable { let navn: String? }
            guard let entity = try? JSONDecoder().decode(Entity.self, from: data),
                  let name = entity.navn?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty
            else { return .failure(.failed) }
            return .success(name)
        case 400: return .failure(.invalidNumber)
        case 404: return .failure(.notFound)
        case 410: return .failure(.deleted)
        default: return .failure(.failed)
        }
    }

    /// Henter navnet. Navnet er i store bokstaver i registeret; brukeren bekrefter før det brukes.
    static func name(for raw: String, session: URLSession = .shared) async -> Result<String, LookupError> {
        guard let number = normalized(raw) else { return .failure(.invalidNumber) }
        var request = URLRequest(url: url(for: number))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        do {
            let (data, response) = try await session.data(for: request)
            return parse(status: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data)
        } catch is URLError {
            return .failure(.offline)
        } catch {
            return .failure(.failed)
        }
    }
}
