import Foundation

/// Leser en JSON-fixture fra testmålets `Fixtures/`-mappe.
enum Fixture {
    static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw FixtureError.missing(name)
        }
        return try Data(contentsOf: url)
    }

    static func load<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        try JSONDecoder().decode(T.self, from: data(name))
    }
}

enum FixtureError: Error {
    case missing(String)
}
