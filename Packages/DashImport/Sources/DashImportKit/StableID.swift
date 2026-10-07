import Foundation

/// Stabile id-er for importen: UUIDv5 (RFC 9562) av «<type>:<PWA-id>» i et fast navnerom.
/// Samme PWA-rad gir alltid samme UUID, så importen kan kjøres flere ganger og bare oppdatere.
public enum StableID {
    /// Fast navnerom for DashDash18-importen fra Golfgutu-PWA-en. Endres aldri: da får alle
    /// importerte rader nye id-er, og en ny import blir en kopi i stedet for en oppdatering.
    public static let namespace = UUID(uuidString: "6F1C2B9E-4D0A-5E37-9B21-3C8D7A5E1F40")!

    /// UUIDv5 av `name` i `namespace`.
    public static func v5(_ name: String, namespace: UUID = StableID.namespace) -> UUID {
        var bytes = withUnsafeBytes(of: namespace.uuid) { Array($0) }
        bytes.append(contentsOf: Array(name.utf8))
        var hash = SHA1.digest(bytes)
        hash[6] = (hash[6] & 0x0F) | 0x50
        hash[8] = (hash[8] & 0x3F) | 0x80
        return UUID(uuid: (hash[0], hash[1], hash[2], hash[3], hash[4], hash[5], hash[6], hash[7],
                           hash[8], hash[9], hash[10], hash[11], hash[12], hash[13], hash[14], hash[15]))
    }

    public static func club(_ key: String) -> UUID { v5("club:\(key)") }
    public static func member(_ pwaID: String) -> UUID { v5("player:\(pwaID.lowercased())") }
    public static func season(_ key: String) -> UUID { v5("season:\(key)") }
    public static func course(_ pwaID: String) -> UUID { v5("course:\(pwaID)") }
    public static func event(_ pwaID: String) -> UUID { v5("schedule:\(pwaID.lowercased())") }
    /// Kveld for en rundedato uten rad i terminlista.
    public static func eventForDate(_ date: String) -> UUID { v5("schedule-date:\(date)") }
    public static func round(_ pwaID: String) -> UUID { v5("round:\(pwaID.lowercased())") }
    public static func sideClaim(_ pwaID: String) -> UUID { v5("side_claim:\(pwaID.lowercased())") }
    public static func threadMessage(_ pwaID: String) -> UUID { v5("melding:\(pwaID.lowercased())") }
}

/// SHA-1 i ren Swift (bare til UUIDv5; ingen sikkerhet hviler på den).
enum SHA1 {
    static func digest(_ message: [UInt8]) -> [UInt8] {
        var h0: UInt32 = 0x67452301, h1: UInt32 = 0xEFCDAB89, h2: UInt32 = 0x98BADCFE
        var h3: UInt32 = 0x10325476, h4: UInt32 = 0xC3D2E1F0
        var data = message
        let bitLength = UInt64(message.count) * 8
        data.append(0x80)
        while data.count % 64 != 56 { data.append(0) }
        for i in (0..<8).reversed() { data.append(UInt8((bitLength >> (UInt64(i) * 8)) & 0xFF)) }

        var w = [UInt32](repeating: 0, count: 80)
        for chunk in stride(from: 0, to: data.count, by: 64) {
            for i in 0..<16 {
                let b = chunk + i * 4
                w[i] = UInt32(data[b]) << 24 | UInt32(data[b + 1]) << 16 | UInt32(data[b + 2]) << 8 | UInt32(data[b + 3])
            }
            for i in 16..<80 {
                let x = w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16]
                w[i] = (x << 1) | (x >> 31)
            }
            var a = h0, b = h1, c = h2, d = h3, e = h4
            for i in 0..<80 {
                let f: UInt32, k: UInt32
                switch i {
                case 0..<20: f = (b & c) | (~b & d); k = 0x5A827999
                case 20..<40: f = b ^ c ^ d; k = 0x6ED9EBA1
                case 40..<60: f = (b & c) | (b & d) | (c & d); k = 0x8F1BBCDC
                default: f = b ^ c ^ d; k = 0xCA62C1D6
                }
                let t = ((a << 5) | (a >> 27)) &+ f &+ e &+ k &+ w[i]
                e = d; d = c; c = (b << 30) | (b >> 2); b = a; a = t
            }
            h0 = h0 &+ a; h1 = h1 &+ b; h2 = h2 &+ c; h3 = h3 &+ d; h4 = h4 &+ e
        }
        return [h0, h1, h2, h3, h4].flatMap { v in (0..<4).map { UInt8((v >> (24 - UInt32($0) * 8)) & 0xFF) } }
    }

    static func hex(_ message: [UInt8]) -> String {
        digest(message).map { String(format: "%02x", $0) }.joined()
    }
}
