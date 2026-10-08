import Foundation
import Observation
import Supabase
import UIKit

/// Egen rad i troppen: henter navn, handicap og portrett, og lagrer endringer.
/// Lagringen ber om raden tilbake og sjekker den, så vi vet at RLS slapp den gjennom.
@Observable
final class DegProfileModel {
    private(set) var row: ClubMemberRow?
    private(set) var isLoading = false
    private(set) var isSaving = false
    /// Portrettet som vises, hentet fra bøtta eller nettopp lastet opp fra telefonen.
    private(set) var portrait: UIImage?
    private(set) var isSavingPortrait = false
    var error: DegProfileError?

    let context: ClubContext

    init(context: ClubContext) {
        self.context = context
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let rows: [ClubMemberRow] = try await context.client
                .from("club_members")
                .select(ClubMemberRow.columns)
                .eq("id", value: context.memberID)
                .eq("club_id", value: context.clubID)
                .execute()
                .value
            guard let own = rows.first else {
                error = .notSaved
                return
            }
            row = own
            await loadPortrait()
        } catch {
            self.error = Self.profileError(from: error)
        }
    }

    /// Lagrer skjemaet. Returnerer raden fra serveren når den er lagret og stemmer.
    func save(_ draft: DegProfileDraft) async -> ClubMemberRow? {
        let change: DegProfileChange
        switch draft.validate() {
        case .success(let valid): change = valid
        case .failure(let failure):
            error = failure
            return nil
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let returned: [ClubMemberRow] = try await context.client
                .from("club_members")
                .update(change.patch)
                .eq("id", value: context.memberID)
                .eq("club_id", value: context.clubID)
                .select(ClubMemberRow.columns)
                .execute()
                .value
            switch DegProfile.verify(returned: returned, memberID: context.memberID, change: change) {
            case .success(let saved):
                row = saved
                return saved
            case .failure(let failure):
                error = failure
                return nil
            }
        } catch {
            self.error = Self.profileError(from: error)
            return nil
        }
    }

    fileprivate static func profileError(from error: any Error) -> DegProfileError {
        if let postgrest = error as? PostgrestError {
            return DegProfileError.from(sqlState: postgrest.code, message: postgrest.message)
        }
        return .other(DataError.from(error))
    }
}

// MARK: - Portrett

extension DegProfileModel {
    /// Signerte lenker varer en time, som i PWA-en.
    private static let signedURLLifetime = 3600

    private var avatars: StorageFileApi { context.client.storage.from(DegAvatarPath.bucket) }

    /// Henter portrettet fra bøtta (hurtigbufret per sti). Uten portrett vises initialene.
    func loadPortrait() async {
        guard let path = row?.avatarPath else {
            portrait = nil
            return
        }
        if let cached = TradImageStore.shared.cached(path) {
            portrait = cached
            return
        }
        do {
            let url = try await avatars.createSignedURL(path: path, expiresIn: Self.signedURLLifetime)
            let image = try await TradImageStore.shared.image(for: path, url: url)
            if row?.avatarPath == path { portrait = image }
        } catch {
            // Initialene står til bildet kan hentes. Ingen feilmelding for et portrett.
        }
    }

    /// Nytt portrett (PWA: `velgKlubbilde`): krymp og skjær kvadratisk, last opp fila, pek
    /// raden på den og sjekk raden, fjern så den gamle fila. Feiler raden, fjernes den nye fila.
    func savePortrait(imageData: Data) async {
        guard let current = row, !isSavingPortrait else { return }
        isSavingPortrait = true
        defer { isSavingPortrait = false }
        let jpeg: Data
        do {
            jpeg = try await Task.detached(priority: .userInitiated) {
                try DegPortraitCompressor.compress(imageData).data
            }.value
        } catch let failure as DegPortraitCompressor.Failure {
            error = .invalid(failure.message)
            return
        } catch {
            self.error = .invalid(DegPortraitCompressor.Failure.unreadable.message)
            return
        }
        let path = DegAvatarPath.make(memberID: context.memberID)
        do {
            _ = try await avatars.upload(path, data: jpeg, options: FileOptions(contentType: "image/jpeg", upsert: false))
        } catch {
            self.error = .other(DataError.from(error))
            return
        }
        guard let saved = await updateAvatarPath(path) else {
            _ = try? await avatars.remove(paths: [path])
            return
        }
        TradImageStore.shared.storeLocal(jpeg, for: path)
        portrait = UIImage(data: jpeg)
        row = saved
        await removeStaleFile(old: current.avatarPath, new: path)
    }

    /// Fjerner portrettet: raden først, så fila. Initialene står igjen.
    func removePortrait() async {
        guard let current = row, current.avatarPath != nil, !isSavingPortrait else { return }
        isSavingPortrait = true
        defer { isSavingPortrait = false }
        guard let saved = await updateAvatarPath(nil) else { return }
        row = saved
        portrait = nil
        await removeStaleFile(old: current.avatarPath, new: nil)
    }

    private func updateAvatarPath(_ path: String?) async -> ClubMemberRow? {
        do {
            let returned: [ClubMemberRow] = try await context.client
                .from("club_members")
                .update(AvatarPatch(avatarPath: path))
                .eq("id", value: context.memberID)
                .eq("club_id", value: context.clubID)
                .select(ClubMemberRow.columns)
                .execute()
                .value
            switch DegPortrait.verify(returned: returned, memberID: context.memberID, path: path) {
            case .success(let saved): return saved
            case .failure(let failure):
                error = failure
                return nil
            }
        } catch {
            self.error = Self.profileError(from: error)
            return nil
        }
    }

    /// Den gamle fila ryddes etter beste evne. Blir den liggende, gjør det ingen skade.
    private func removeStaleFile(old: String?, new: String?) async {
        guard let stale = DegPortrait.staleFile(old: old, new: new, memberID: context.memberID) else { return }
        TradImageStore.shared.forget(stale)
        _ = try? await avatars.remove(paths: [stale])
    }
}
