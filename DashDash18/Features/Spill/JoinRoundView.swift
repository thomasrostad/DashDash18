import Observation
import Supabase
import SwiftUI

/// «Bli med»: koden (fra lenken, QR eller skrevet inn), hva runden er, og «Er du X?».
@Observable
final class JoinRoundModel {
    enum Step: Equatable {
        case enterCode
        case loading
        case preview(InvitePreview)
        case failed(String)
    }

    var codeText: String
    private(set) var step: Step
    var choice: JoinChoice = .newPlayer
    private(set) var isJoining = false
    var joinError: String?
    private(set) var myName: String?
    private(set) var code: InviteCode?
    private let client: SupabaseClient?

    init(client: SupabaseClient, myName: String?, code: InviteCode?) {
        self.client = client
        self.myName = myName
        self.code = code
        codeText = code?.display ?? ""
        step = code == nil ? .enterCode : .loading
    }

    #if DEBUG
    init(preview: InvitePreview, code: InviteCode, myName: String?) {
        client = nil
        self.myName = myName
        self.code = code
        codeText = code.display
        step = .preview(preview)
        choice = JoinChoice.suggested(preview, myName: myName)
    }
    #endif

    /// Koden som er skrevet inn (eller limt inn som lenke), eller nil.
    var typedCode: InviteCode? { InviteCode.parse(codeText) }

    func lookUp() async {
        guard let client else { return }
        guard let code = code ?? typedCode else {
            step = .failed("Koden har 10 tegn, f.eks. ABCDE-FGH23.")
            return
        }
        self.code = code
        step = .loading
        do {
            // Navnet ditt, så gjesten med samme navn foreslås («Er du Per?»).
            if myName == nil { myName = try? await LooseRoundQueries.ensureProfile(client: client).displayName }
            let preview = try await LooseRoundQueries.preview(client: client, code: code)
            choice = JoinChoice.suggested(preview, myName: myName)
            step = .preview(preview)
        } catch {
            step = .failed(DataError.from(error).message)
        }
    }

    /// Ny kode skrevet inn: tilbake til feltet.
    func editCode() {
        code = nil
        step = .enterCode
    }

    /// Blir med (`claim_round_invite`). Gir rundens id.
    func join() async -> UUID? {
        guard let client, let code, case .preview(let preview) = step, !isJoining else { return nil }
        if case .alreadyIn = choice { return preview.roundID }
        isJoining = true
        joinError = nil
        defer { isJoining = false }
        do {
            let result = try await LooseRoundQueries.claim(client: client, code: code, participantID: choice.participantID)
            return result.roundID
        } catch {
            joinError = DataError.from(error).message
            return nil
        }
    }
}

struct JoinRoundView: View {
    @State var model: JoinRoundModel
    let onJoined: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var codeFocused: Bool

    var body: some View {
        DDForm {
            switch model.step {
            case .enterCode, .failed:
                codeSection
            case .loading:
                Section {
                    HStack { Spacer(); ProgressView("Finner runden …"); Spacer() }
                }
            case .preview(let preview):
                previewSections(preview)
            }
        }
        .navigationTitle("Bli med")
        .ddNavigationChrome()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Avbryt") { dismiss() }
            }
        }
        .task {
            if model.step == .loading { await model.lookUp() }
        }
    }

    private var codeSection: some View {
        Section {
            TextField("Kode, f.eks. ABCDE-FGH23", text: $model.codeText)
                .font(.dd(.mono, size: 20, relativeTo: .title3))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($codeFocused)
                .submitLabel(.go)
                .onSubmit { Task { await model.lookUp() } }
            Button("Finn runden") { Task { await model.lookUp() } }
                .disabled(model.typedCode == nil)
            if case .failed(let message) = model.step {
                Label(message, systemImage: "exclamationmark.triangle").ddErrorStyle()
            }
        } header: {
            DDHeader("Koden fra invitasjonen")
        } footer: {
            DDFooter("Den som startet runden, finner koden under «Inviter med lenke eller QR». Du kan også lime inn lenken.")
        }
        .onAppear { codeFocused = true }
    }

    @ViewBuilder
    private func previewSections(_ preview: InvitePreview) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(preview.courseName ?? "Runden")
                    .font(.ddTitle)
                    .foregroundStyle(Color.ddInk)
                Text(preview.summary)
                    .font(.ddCallout)
                    .foregroundStyle(Color.ddInkSecondary)
                if let owner = preview.ownerName {
                    Text("Startet av \(owner)")
                        .font(.ddCaption)
                        .foregroundStyle(Color.ddInkSecondary)
                }
            }
            .padding(.vertical, 4)
            ForEach(preview.players) { player in
                HStack {
                    DDAvatar(name: player.displayName)
                    Text(player.displayName)
                    Spacer()
                    if player.isGuest {
                        DDPill("Gjest", tone: .sun).fixedSize()
                    }
                }
            }
        } header: {
            DDHeader("Runden")
        }

        let options = JoinChoice.options(preview)
        Section {
            ForEach(options, id: \.self) { option in
                Button { model.choice = option } label: {
                    HStack {
                        Text(option.title(in: preview)).foregroundStyle(Color.ddInk)
                        Spacer()
                        Image(systemName: model.choice == option ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(model.choice == option ? Color.ddForestInk : Color.ddInkSecondary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(model.choice == option ? .isSelected : [])
            }
        } header: {
            DDHeader(options.count > 1 ? "Er du en av gjestene?" : "Du")
        } footer: {
            DDFooter(options.count > 1
                     ? "Tar du en gjesteplass, følger scorene som er ført, med til deg."
                     : "Du står allerede på lista.")
        }

        Section {
            Button(model.choice == .newPlayer || model.choice.participantID != nil ? "Bli med" : "Åpne runden") {
                Task {
                    if let id = await model.join() { onJoined(id) }
                }
            }
            .buttonStyle(.dd(.primary, fullWidth: true))
            .disabled(model.isJoining)
            .listRowBackground(Color.clear)
            if let error = model.joinError {
                Label(error, systemImage: "exclamationmark.triangle").ddErrorStyle()
            }
            Button("Annen kode") { model.editCode() }
                .buttonStyle(.dd(.text))
                .listRowBackground(Color.clear)
        }
    }
}

nonisolated extension InviteCode: Identifiable {
    var id: String { value }
}

/// Invitasjon fra en lenke (`dashdash://runde/KODE`): bli med, og gå rett til runden.
struct JoinFromLinkView: View {
    let client: SupabaseClient
    let userID: UUID
    let code: InviteCode

    @State private var joinedRound: UUID?

    var body: some View {
        NavigationStack {
            JoinRoundView(model: JoinRoundModel(client: client, myName: nil, code: code)) { roundID in
                joinedRound = roundID
            }
            .navigationDestination(item: $joinedRound) { roundID in
                LooseRoundScreen(context: LooseRoundContext(client: client, userID: userID, roundID: roundID))
            }
        }
        .tint(Color.ddForestInk)
    }
}
