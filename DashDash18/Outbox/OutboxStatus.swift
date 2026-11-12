import Foundation
import Observation

/// Det UI-et trenger å vise om utboksen, f.eks. «3 hull venter på nett».
@Observable
final class OutboxStatus {
    /// Hull (runde + hull) som venter på å bli sendt.
    private(set) var pendingCount = 0
    /// Hull serveren har avvist. Sendes ikke på nytt.
    private(set) var rejectedCount = 0
    /// Når serveren sist bekreftet et hull.
    private(set) var lastSentAt: Date?
    /// Siste feil fra et forsøk, til visning.
    private(set) var lastError: String?
    /// Siste feil som ikke er nettet (innloggingen har gått ut, serveren svarer med en ukjent feil).
    /// Da hjelper det ikke å vente på dekning, så føringen sier hva som er galt. Nil etter en sending.
    private(set) var problem: String?

    var isEmpty: Bool { pendingCount == 0 && rejectedCount == 0 }

    /// Kort tekst til UI, eller nil når det ikke er noe å si.
    var summary: String? {
        if pendingCount > 0 {
            return "\(pendingCount) hull venter på nett"
        }
        if rejectedCount > 0 {
            return rejectedCount == 1 ? "1 hull ble avvist" : "\(rejectedCount) hull ble avvist"
        }
        return nil
    }

    func update(pending: Int, rejected: Int) {
        pendingCount = pending
        rejectedCount = rejected
    }

    func didSend(at date: Date) {
        lastSentAt = date
        lastError = nil
        problem = nil
    }

    /// `isNetwork`: ingen kontakt eller tidsavbrudd. Ellers står feilen som `problem`.
    func didFail(_ message: String, isNetwork: Bool) {
        lastError = message
        problem = isNetwork ? nil : message
    }
}
