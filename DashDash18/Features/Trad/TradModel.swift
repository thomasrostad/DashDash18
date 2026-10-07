import Foundation
import Observation
import Supabase

/// Kveldens tråd for én kveld: meldingene, utkastet, vedlegget og bildelenkene.
///
/// Sending vises med en gang og trekkes tilbake med teksten og bildet i behold om serveren
/// sier nei. Bildet lastes opp først, så meldingen; feiler meldingen, fjernes bildet igjen.
@Observable
final class TradModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    /// En melding slik skjermen viser den.
    struct Item: Identifiable, Equatable {
        let message: ThreadMessageRow
        let author: String
        let isMine: Bool
        /// Vises fra telefonen og er ikke bekreftet av serveren ennå.
        let isPending: Bool
        let canDelete: Bool
        /// Portrettet til den som skrev (bøtta `avatars`), eller nil: initialene.
        var avatarPath: String? = nil
        var id: UUID { message.id }
    }

    private(set) var state: LoadState = .loading
    /// Meldingene slik serveren har dem.
    private(set) var messages: [ThreadMessageRow] = []
    /// Sendt fra denne telefonen, ikke bekreftet ennå.
    private(set) var pending: [ThreadMessageRow] = []
    var draft = ""
    /// Bildet som legges ved, krympet og klart.
    private(set) var attachment: TradImageCompressor.Output?
    private(set) var isPreparingImage = false
    private(set) var isSending = false
    var errorMessage: String?
    private(set) var directory = MentionDirectory(people: [])
    private(set) var names: [UUID: String] = [:]
    private(set) var signedURLs = TradSignedURLCache()
    /// Portrettene i troppen, per medlem. Ny fil får ny sti, så et byttet portrett vises.
    private(set) var avatarPaths: [UUID: String] = [:]
    private(set) var avatarURLs = TradSignedURLCache()
    /// Realtime-kanalen er oppe.
    private(set) var isLive = false
    /// Skjermen står framme. Da merkes tråden som lest når nye meldinger kommer.
    var isVisible = false

    let eventID: UUID
    let images: TradImageStore

    private let clubID: UUID
    private let viewer: UUID
    private let isOrganizer: Bool
    private let backend: any TradBackend
    private let readStore: any TradReadStoring
    private let now: () -> Date
    private let client: SupabaseClient?

    private var isLoading = false
    private var reloadAgain = false
    private var isSigning = false
    private var channel: RealtimeChannelV2?
    private var listenTasks: [Task<Void, Never>] = []

    convenience init(context: ClubContext, eventID: UUID) {
        self.init(eventID: eventID, clubID: context.clubID, viewer: context.memberID,
                  isOrganizer: context.isOrganizer, backend: SupabaseTradBackend(client: context.client),
                  client: context.client)
    }

    init(eventID: UUID, clubID: UUID, viewer: UUID, isOrganizer: Bool, backend: any TradBackend,
         readStore: any TradReadStoring = UserDefaultsTradReadStore(), images: TradImageStore = .shared,
         client: SupabaseClient? = nil, now: @escaping () -> Date = Date.init) {
        self.eventID = eventID
        self.clubID = clubID
        self.viewer = viewer
        self.isOrganizer = isOrganizer
        self.backend = backend
        self.readStore = readStore
        self.images = images
        self.client = client
        self.now = now
    }

    var viewerID: UUID { viewer }

    var items: [Item] {
        let confirmed = Set(messages.map(\.id))
        let shown = TradOrder.sorted(messages).map { ($0, false) }
            + pending.filter { !confirmed.contains($0.id) }.map { ($0, true) }
        return shown.map { message, isPending in
            Item(message: message, author: names[message.memberID] ?? "Ukjent",
                 isMine: message.memberID == viewer, isPending: isPending,
                 canDelete: !isPending && TradPermissions.canDelete(message, viewer: viewer, isOrganizer: isOrganizer),
                 avatarPath: avatarPaths[message.memberID])
        }
    }

    var suggestions: [MentionDirectory.Suggestion] { directory.suggestions(for: draft, viewer: viewer) }

    var canSend: Bool {
        guard !isSending, !isPreparingImage else { return false }
        if case .ready = TradDraft.check(draft, hasImage: attachment != nil) { return true }
        return false
    }

    /// Tegn igjen, når det nærmer seg grensen.
    var remainingCharacters: Int? {
        let left = TradDraft.maxLength - draft.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count
        return left < 50 ? left : nil
    }

    var unreadCount: Int {
        TradUnread.count(messages, viewer: viewer, lastSeen: readStore.lastSeen(memberID: viewer, eventID: eventID))
    }

    var summary: TradSummary {
        TradSummary.make(messages: messages, names: names, viewer: viewer,
                         lastSeen: readStore.lastSeen(memberID: viewer, eventID: eventID))
    }

    // MARK: Henting

    /// Henter tråden. Kommer et nytt kall mens en henting pågår, kjøres én til etterpå.
    func load() async {
        if isLoading { reloadAgain = true; return }
        isLoading = true
        defer { isLoading = false }
        repeat {
            reloadAgain = false
            await fetch()
        } while reloadAgain
    }

    private func fetch() async {
        do {
            async let messageRows = backend.messages(eventID: eventID)
            async let memberRows = backend.members(clubID: clubID)
            let fresh = try await messageRows
            let members = try await memberRows
            apply(members: members)
            messages = fresh
            let confirmed = Set(fresh.map(\.id))
            pending.removeAll { confirmed.contains($0.id) }
            state = .loaded
            markReadIfVisible()
            signedURLs.retryFailed()
            avatarURLs.retryFailed()
            await refreshImageURLs()
            await refreshAvatarURLs()
            await startRealtime()
        } catch {
            // Behold det som vises når en oppfrisking feiler.
            if state == .loaded { return }
            state = .failed(DataError.from(error).message)
        }
    }

    private func apply(members: [ClubMemberRow]) {
        names = Dictionary(members.map { ($0.id, $0.displayName) }, uniquingKeysWith: { a, _ in a })
        avatarPaths = Dictionary(members.compactMap { m in m.avatarPath.map { (m.id, $0) } },
                                 uniquingKeysWith: { a, _ in a })
        // Arkiverte vises med navn i gamle meldinger, men kan ikke nevnes.
        let people = members.filter { $0.status != .archived }.map { TradPerson(id: $0.id, name: $0.displayName) }
        directory = MentionDirectory(people: people)
    }

    /// Alt i tråden er lest (andres nyeste melding, med serverens tid).
    func markReadIfVisible() {
        guard isVisible else { return }
        let current = readStore.lastSeen(memberID: viewer, eventID: eventID)
        if let mark = TradUnread.readMark(messages, viewer: viewer, current: current) {
            readStore.setLastSeen(mark, memberID: viewer, eventID: eventID)
        }
    }

    // MARK: Utkast og vedlegg

    func insertMention(_ handle: String) {
        draft = MentionDirectory.inserting(handle, into: draft)
    }

    /// Krymper bildet utenfor hovedtråden og legger det ved.
    func attach(imageData data: Data) async {
        isPreparingImage = true
        defer { isPreparingImage = false }
        let result = await Task.detached(priority: .userInitiated) {
            Result { () throws(TradImageCompressor.Failure) -> TradImageCompressor.Output in
                try TradImageCompressor.compress(data)
            }
        }.value
        switch result {
        case .success(let output): attachment = output
        case .failure(let failure): errorMessage = failure.message
        }
    }

    func removeAttachment() {
        attachment = nil
    }

    // MARK: Sending

    func send() async {
        guard !isSending, !isPreparingImage else { return }
        let image = attachment
        let text: String
        switch TradDraft.check(draft, hasImage: image != nil) {
        case .empty: return
        case .tooLong:
            errorMessage = TradDraft.Check.tooLong.message
            return
        case .ready(let trimmed): text = trimmed
        }

        let id = UUID()
        let path = image.map { _ in TradImagePath.make(memberID: viewer, messageID: id) }
        let insert = ThreadMessageInsert(id: id, clubID: clubID, eventID: eventID, memberID: viewer, body: text,
                                         mentions: directory.mentions(in: text, sender: viewer), imagePath: path)
        pending.append(ThreadMessageRow(id: id, clubID: clubID, eventID: eventID, memberID: viewer, body: text,
                                        mentions: insert.mentions, imagePath: path, createdAt: now()))
        // Til den signerte lenka finnes, vises bildet fra telefonen selv.
        if let image, let path { images.storeLocal(image.data, for: path) }
        draft = ""
        attachment = nil
        isSending = true
        defer { isSending = false }

        if let image, let path {
            do {
                try await backend.uploadImage(path: path, jpeg: image.data)
            } catch {
                rollBack(id: id, text: text, image: image, path: path,
                         message: "Klarte ikke å laste opp bildet: " + DataError.from(error).message)
                return
            }
        }
        do {
            let saved = try await backend.insert(insert)
            pending.removeAll { $0.id == id }
            messages.removeAll { $0.id == saved.id }
            messages.append(saved)
        } catch {
            // Svaret kan ha gått tapt etter at meldingen ble lagret (dårlig dekning). Da er den
            // sendt; å legge teksten tilbake ville gitt den dobbelt når du sender igjen.
            if let rows = try? await backend.messages(eventID: eventID), rows.contains(where: { $0.id == id }) {
                await load()
                return
            }
            if let path { try? await backend.removeImages(paths: [path]) }
            rollBack(id: id, text: text, image: image, path: path,
                     message: "Klarte ikke å sende: " + DataError.from(error).message)
            return
        }
        await load()
    }

    private func rollBack(id: UUID, text: String, image: TradImageCompressor.Output?, path: String?, message: String) {
        pending.removeAll { $0.id == id }
        if let path { images.forget(path) }
        draft = TradDraft.restored(sent: text, typedSince: draft)
        // Et nytt vedlegg valgt i mellomtiden går foran det gamle.
        if attachment == nil { attachment = image }
        errorMessage = message
    }

    // MARK: Sletting

    func delete(_ id: UUID) async {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        let message = messages[index]
        guard TradPermissions.canDelete(message, viewer: viewer, isOrganizer: isOrganizer) else { return }
        messages.remove(at: index)
        do {
            let deleted = try await backend.delete(messageID: id)
            if !deleted {
                // Ingen rad slettet: borte allerede, eller ikke lov. Hentingen avgjør.
                await load()
                if messages.contains(where: { $0.id == id }) {
                    errorMessage = "Klarte ikke å slette: " + DataError.notAllowed.message
                }
                return
            }
        } catch {
            if !messages.contains(where: { $0.id == id }) { messages.append(message) }
            errorMessage = "Klarte ikke å slette: " + DataError.from(error).message
            return
        }
        // Bildet går med. Feiler det, ligger fila igjen i bøtta uten at noen ser den.
        if let path = message.imagePath {
            try? await backend.removeImages(paths: [path])
            images.forget(path)
            signedURLs.forget(path)
        }
    }

    // MARK: Bilder

    func imageURL(for path: String) -> URL? { signedURLs.url(for: path, now: now()) }
    func imageFailed(_ path: String) -> Bool { signedURLs.failed.contains(path) }

    /// Henter signerte lenker samlet for bildene i tråden som mangler en fersk lenke.
    func refreshImageURLs() async {
        guard !isSigning else { return }
        let paths = messages.compactMap(\.imagePath).filter { !images.hasLocal($0) }
        let needed = signedURLs.pathsToSign(paths, now: now())
        guard !needed.isEmpty else { return }
        isSigning = true
        defer { isSigning = false }
        do {
            let urls = try await backend.signedURLs(paths: needed, expiresIn: TradSignedURLCache.lifetimeSeconds)
            signedURLs.store(signed: urls, requested: needed, now: now())
        } catch {
            signedURLs.markFailed(needed)
        }
    }

    func avatarURL(for path: String) -> URL? { avatarURLs.url(for: path, now: now()) }

    /// Signerte lenker til portrettene til dem som har skrevet i tråden, uten de som alt er
    /// hentet. Feiler det, står initialene.
    func refreshAvatarURLs() async {
        let authors = Set(messages.map(\.memberID))
        let paths = authors.compactMap { avatarPaths[$0] }.sorted().filter { images.cached($0) == nil }
        let needed = avatarURLs.pathsToSign(paths, now: now())
        guard !needed.isEmpty else { return }
        do {
            let urls = try await backend.avatarURLs(paths: needed, expiresIn: TradSignedURLCache.lifetimeSeconds)
            avatarURLs.store(signed: urls, requested: needed, now: now())
        } catch {
            avatarURLs.markFailed(needed)
        }
    }

    // MARK: Realtime

    private func startRealtime() async {
        guard let client, channel == nil else { return }
        let channel = client.channel("trad-\(eventID.uuidString.lowercased())")
        let changes = channel.postgresChange(AnyAction.self, schema: "public", table: "thread_messages",
                                             filter: .eq("event_id", value: eventID))
        // Sletting kan ikke filtreres på kveld i Supabase Realtime (bare primærnøkkelen følger
        // med), så den lyttes på for hele tabellen og sjekkes mot id-ene her.
        let deletions = channel.postgresChange(DeleteAction.self, schema: "public", table: "thread_messages")
        let statuses = channel.statusChange
        self.channel = channel
        listenTasks = [
            Task { [weak self] in
                for await status in statuses {
                    // Oppe igjen (første gang, eller etter brudd i nettet): hent det som kom
                    // mens kanalen var nede.
                    if self?.setLive(status == .subscribed) == true { await self?.load() }
                }
            },
            Task { [weak self] in
                for await _ in changes {
                    await self?.load()
                }
            },
            Task { [weak self] in
                for await action in deletions {
                    guard let raw = action.oldRecord["id"]?.stringValue, let id = UUID(uuidString: raw) else { continue }
                    self?.removeDeleted(id)
                }
            },
            Task {
                try? await channel.subscribeWithError()
            },
        ]
    }

    /// Gir true når kanalen nettopp kom opp.
    private func setLive(_ live: Bool) -> Bool {
        defer { isLive = live }
        return live && !isLive
    }

    private func removeDeleted(_ id: UUID) {
        guard let message = messages.first(where: { $0.id == id }) else { return }
        messages.removeAll { $0.id == id }
        if let path = message.imagePath {
            images.forget(path)
            signedURLs.forget(path)
        }
    }

    func stopRealtime() async {
        listenTasks.forEach { $0.cancel() }
        listenTasks = []
        if let channel, let client { await client.removeChannel(channel) }
        channel = nil
        isLive = false
    }
}
