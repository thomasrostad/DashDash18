import CryptoKit
import Foundation
import Security

/// Engangsverdi for Logg inn med Apple. Apple får SHA-256 av verdien, Supabase får råverdien,
/// og Supabase sjekker at de hører sammen. Det hindrer at et stjålet ID-token spilles av på nytt.
nonisolated enum AppleNonce {
    private static let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")

    static func random(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        precondition(status == errSecSuccess, "Fikk ikke tilfeldige bytes til nonce")
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
