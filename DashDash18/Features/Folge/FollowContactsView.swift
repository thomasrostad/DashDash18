import Contacts
import ContactsUI
import Foundation
import MessageUI
import Observation
import Supabase
import SwiftUI

/// Kontaktene på telefonen (fornavn, etternavn, e-post og nummer). Leses bare når du har sagt ja,
/// og lagres ikke. Med begrenset tilgang (iOS 18) leses kontaktene du har valgt.
nonisolated enum ContactBook {
    enum Access: Equatable, Sendable {
        case notDetermined
        case denied
        case full
        case limited
    }

    static var access: Access {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .notDetermined: .notDetermined
        case .authorized: .full
        case .limited: .limited
        case .denied, .restricted: .denied
        @unknown default: .denied
        }
    }

    /// Spør om tilgang (første gang). Svarer tilgangen etterpå.
    static func requestAccess() async -> Access {
        _ = try? await CNContactStore().requestAccess(for: .contacts)
        return access
    }

    /// Alle kontaktene appen får se. Går utenfor hovedtråden.
    @concurrent
    static func fetch() async throws -> [PhoneContact] {
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactEmailAddressesKey,
                    CNContactPhoneNumbersKey] as [CNKeyDescriptor]
        var contacts: [PhoneContact] = []
        try CNContactStore().enumerateContacts(with: CNContactFetchRequest(keysToFetch: keys)) { contact, _ in
            let name = [contact.givenName, contact.familyName]
                .compactMap(followTrimmed)
                .joined(separator: " ")
            contacts.append(PhoneContact(id: contact.identifier, name: name,
                                         emails: contact.emailAddresses.map { $0.value as String },
                                         phones: contact.phoneNumbers.map { $0.value.stringValue }))
        }
        return contacts
    }
}

/// «Finn fra kontakter» (sql/077): tilgangen, oppslaget og de to listene.
@Observable
final class FollowContactsModel {
    enum LoadState: Equatable {
        /// Ikke spurt om tilgang ennå.
        case asking
        case denied
        case loading
        case loaded
        case failed(String)
    }

    private(set) var state: LoadState
    var results = ContactResults.empty
    /// Begrenset tilgang: «Velg flere kontakter».
    private(set) var isLimited = false
    /// Følgelenken i invitasjonen (`follow_code`, som «Min kode»).
    private(set) var link: FollowLink?
    var query = ""

    let client: SupabaseClient?
    let userID: UUID

    init(client: SupabaseClient, userID: UUID) {
        self.client = client
        self.userID = userID
        state = ContactBook.access == .denied ? .denied : .asking
    }

    /// Skjermprøve og tester: faste resultater, ingen kontakter og ingen nettverk.
    init(preview results: ContactResults, userID: UUID, link: FollowLink? = nil) {
        client = nil
        self.userID = userID
        self.results = results
        self.link = link
        state = .loaded
    }

    var invitation: String { ContactInvite.message(link: link?.url) }

    /// Når skjermen åpnes: har du alt gitt tilgang, sjekkes kontaktene med en gang.
    func start() async {
        guard client != nil, state == .asking || state == .denied else { return }
        switch ContactBook.access {
        case .full, .limited: await load()
        case .denied: state = .denied
        case .notDetermined: state = .asking
        }
    }

    /// «Fortsett»: spør om tilgang og sjekker.
    func allow() async {
        switch await ContactBook.requestAccess() {
        case .full, .limited: await load()
        case .denied: state = .denied
        case .notDetermined: state = .asking
        }
    }

    func load() async {
        guard let client else { return }
        let service = FollowService(client: client)
        isLimited = ContactBook.access == .limited
        state = .loading
        do {
            let contacts = try await ContactBook.fetch()
            let lookup = ContactLookup(contacts)
            async let code = try? service.code()
            let rows = lookup.isEmpty ? [] : try await service.findContacts(lookup)
            results = ContactResults(rows: rows, contacts: contacts, lookup: lookup)
            link = await code ?? link
            state = .loaded
        } catch {
            guard !DataError.isCancellation(error) else { return }
            state = .failed(FollowService.contactsMessage(error))
        }
    }
}

/// «Finn fra kontakter»: «I Atten» med Følg, og «Inviter til Atten» med Meldinger.
struct FollowContactsView: View {
    @State var model: FollowContactsModel
    @State private var picksMore = false
    @State private var composing: ContactInviteMessage?
    @Environment(\.openURL) private var openURL

    var body: some View {
        DDList {
            switch model.state {
            case .asking:
                Section {
                    VStack(alignment: .leading, spacing: DDSpacing.s) {
                        Text("Se hvem av kontaktene dine som er på Atten, og inviter resten.")
                            .font(.ddCallout)
                            .foregroundStyle(Color.ddInk)
                        Button("Fortsett") { Task { await model.allow() } }
                            .buttonStyle(.dd(.primary, compact: true))
                    }
                    .padding(.vertical, 4)
                } footer: {
                    DDFooter(Self.privacy)
                }
            case .denied:
                Section {
                    VStack(alignment: .leading, spacing: DDSpacing.s) {
                        Text("Atten har ikke tilgang til kontaktene. Slå det på i Innstillinger.")
                            .font(.ddCallout)
                            .foregroundStyle(Color.ddInk)
                        Button("Åpne Innstillinger") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                        .buttonStyle(.dd(.secondary, compact: true))
                    }
                    .padding(.vertical, 4)
                } footer: {
                    DDFooter(Self.privacy)
                }
            case .loading:
                Section {
                    HStack(spacing: DDSpacing.s) {
                        ProgressView()
                        Text("Sjekker kontaktene …").font(.ddCallout).foregroundStyle(Color.ddInkSecondary)
                    }
                }
            case .failed(let message):
                Section {
                    Label(message, systemImage: "exclamationmark.triangle").ddErrorStyle()
                    Button("Prøv igjen") { Task { await model.load() } }
                }
            case .loaded:
                loaded
            }
        }
        .navigationTitle("Finn fra kontakter")
        .navigationBarTitleDisplayMode(.inline)
        .ddNavigationChrome()
        .task { await model.start() }
        .contactAccessPicker(isPresented: $picksMore) { _ in Task { await model.load() } }
        .sheet(item: $composing) { message in
            ContactMessageComposer(message: message).ignoresSafeArea()
        }
    }

    static let privacy = "Kontaktene sendes ikke. E-post og nummer gjøres om til koder på telefonen, og bare kodene sjekkes."

    @ViewBuilder
    private var loaded: some View {
        Section {
            if model.results.inAtten.isEmpty {
                Text("Ingen av kontaktene dine er på Atten ennå.")
                    .font(.ddCallout)
                    .foregroundStyle(Color.ddInkSecondary)
            }
            ForEach($model.results.inAtten) { $match in
                ContactMatchView(client: model.client, userID: model.userID, match: $match)
            }
        } header: {
            DDHeader("I Atten")
        } footer: {
            DDFooter("Bare dem som kan finnes i søk. Navnet fra kontaktene står under, så du ser at det er rett person.")
        }
        if model.isLimited {
            Section {
                Button { picksMore = true } label: {
                    Label("Velg flere kontakter", systemImage: "person.crop.circle.badge.plus")
                        .labelStyle(DDIconLabelStyle())
                }
            } footer: {
                DDFooter("Atten ser bare kontaktene du har valgt.")
            }
        }
        if !model.results.invite.isEmpty {
            let people = model.results.invite(matching: model.query)
            Section {
                if model.results.invite.count > ContactResults.searchThreshold {
                    HStack(spacing: DDSpacing.s) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Color.ddInkSecondary)
                            .accessibilityHidden(true)
                        TextField("Søk i kontaktene", text: $model.query)
                            .autocorrectionDisabled()
                    }
                }
                if people.isEmpty {
                    Text("Fant ingen med det navnet.").font(.ddCallout).foregroundStyle(Color.ddInkSecondary)
                }
                ForEach(people) { contact in inviteRow(contact) }
            } header: {
                DDHeader("Inviter til Atten")
            } footer: {
                DDFooter("Invitasjonen har lenken din. Åpner de den med appen, følger de deg.")
            }
        }
    }

    private func inviteRow(_ contact: PhoneContact) -> some View {
        HStack(spacing: DDSpacing.s) {
            FollowPersonLabel(client: nil, name: contact.name)
            Spacer(minLength: 0)
            if let phone = contact.messagePhone, ContactMessageComposer.canSend {
                Button("Inviter") {
                    composing = ContactInviteMessage(id: contact.id, recipient: phone, body: model.invitation)
                }
                .buttonStyle(.dd(.secondary, compact: true))
                .fixedSize()
            } else {
                ShareLink(item: model.invitation) { Text("Inviter") }
                    .buttonStyle(.dd(.secondary, compact: true))
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// En kontakt i Atten: navnet i Atten (åpner profilen), navnet i kontaktene, og Følg / Venter / Følger.
private struct ContactMatchView: View {
    let client: SupabaseClient?
    let userID: UUID
    @Binding var match: ContactMatch

    var body: some View {
        HStack(spacing: DDSpacing.s) {
            if let client {
                NavigationLink {
                    PersonProfileView(client: client, userID: userID, profileID: match.row.id,
                                      name: match.row.displayName, avatarPath: match.row.avatarPath)
                } label: {
                    label
                }
                FollowStatusButton(client: client, profileID: match.row.id, name: match.row.displayName,
                                   status: $match.row.myStatus, source: .suggestion, followsMe: match.row.followsMe)
                    .fixedSize()
            } else {
                label
                Spacer(minLength: 0)
                // Skjermprøve: knappen uten nettverk.
                Button(FollowButton.title(match.row.myStatus, followsMe: match.row.followsMe)) {}
                    .buttonStyle(.dd(match.row.myStatus == .none ? .primary : .secondary, compact: true))
                    .fixedSize()
            }
        }
    }

    private var label: some View {
        FollowPersonLabel(client: client, name: match.row.displayName, avatarPath: match.row.avatarPath,
                          subtitle: match.subtitle)
    }
}

/// Invitasjonen som skal til Meldinger.
struct ContactInviteMessage: Identifiable {
    let id: String
    let recipient: String
    let body: String
}

/// Meldinger med nummeret og teksten ferdig utfylt.
struct ContactMessageComposer: UIViewControllerRepresentable {
    let message: ContactInviteMessage
    @Environment(\.dismiss) private var dismiss

    static var canSend: Bool { MFMessageComposeViewController.canSendText() }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let composer = MFMessageComposeViewController()
        composer.recipients = [message.recipient]
        composer.body = message.body
        composer.messageComposeDelegate = context.coordinator
        return composer
    }

    func updateUIViewController(_ composer: MFMessageComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let dismiss: DismissAction

        init(dismiss: DismissAction) { self.dismiss = dismiss }

        func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                          didFinishWith result: MessageComposeResult) {
            dismiss()
        }
    }
}
