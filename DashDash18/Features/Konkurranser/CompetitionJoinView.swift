import Observation
import Supabase
import SwiftUI

/// «Bli med med kode» i en privat konkurranse (sql/022): koden fra lenken, QR eller skrevet inn,
/// hva konkurransen er (navn, type, eier og antall påmeldte), og «Bli med», som melder deg på.
@Observable
final class JoinCompetitionModel {
    enum Step: Equatable {
        case enterCode
        case loading
        case preview(CompetitionInvitePreview)
        case joined(CompetitionInvitePreview)
        case failed(String)
    }

    var codeText: String
    private(set) var step: Step
    private(set) var isJoining = false
    var joinError: String?
    private(set) var code: InviteCode?
    private let client: SupabaseClient?

    init(client: SupabaseClient, code: InviteCode?) {
        self.client = client
        self.code = code
        codeText = code?.display ?? ""
        step = code == nil ? .enterCode : .loading
    }

    #if DEBUG
    init(preview: CompetitionInvitePreview, code: InviteCode) {
        client = nil
        self.code = code
        codeText = code.display
        step = .preview(preview)
    }
    #endif

    /// Koden som er skrevet inn (eller limt inn som lenke), eller nil.
    var typedCode: InviteCode? { InviteCode.parse(codeText, host: InviteTarget.competitionHost) }

    func lookUp() async {
        guard let client else { return }
        guard let code = code ?? typedCode else {
            step = .failed("Koden har 10 tegn, f.eks. ABCDE-FGH23.")
            return
        }
        self.code = code
        step = .loading
        do {
            let preview = try await CompetitionQueries.invitePreview(client: client, code: code)
            step = preview.entered ? .joined(preview) : .preview(preview)
        } catch {
            step = .failed(CompetitionInviteErrors.message(for: error))
        }
    }

    /// Ny kode skrevet inn: tilbake til feltet.
    func editCode() {
        code = nil
        step = .enterCode
    }

    /// Melder deg på (`claim_competition_invite`). Gir konkurransens id.
    func join() async -> UUID? {
        guard let client, let code, case .preview(let preview) = step, !isJoining else { return nil }
        isJoining = true
        joinError = nil
        defer { isJoining = false }
        do {
            let result = try await CompetitionQueries.claimInvite(client: client, code: code)
            step = .joined(preview)
            return result.competitionID
        } catch {
            joinError = CompetitionInviteErrors.message(for: error)
            return nil
        }
    }
}

struct JoinCompetitionView: View {
    @State var model: JoinCompetitionModel
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
                    HStack { Spacer(); ProgressView("Finner konkurransen …"); Spacer() }
                }
            case .preview(let preview):
                summary(preview)
                joinSection
            case .joined(let preview):
                summary(preview)
                Section {
                    Label("Du er påmeldt. Finn den under Konkurranser.", systemImage: "checkmark.seal")
                        .foregroundStyle(Color.ddForestInk)
                    Button("Ferdig") { dismiss() }
                        .buttonStyle(.dd(.primary, fullWidth: true))
                        .listRowBackground(Color.clear)
                }
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
            Button("Finn konkurransen") { Task { await model.lookUp() } }
                .disabled(model.typedCode == nil)
            if case .failed(let message) = model.step {
                Label(message, systemImage: "exclamationmark.triangle").ddErrorStyle()
            }
        } header: {
            DDHeader("Koden fra invitasjonen")
        } footer: {
            DDFooter("Eieren og de påmeldte finner koden under «Inviter» i konkurransen. Du kan også lime inn lenken.")
        }
        .onAppear { codeFocused = true }
    }

    private func summary(_ preview: CompetitionInvitePreview) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(preview.name)
                    .font(.ddTitle)
                    .foregroundStyle(Color.ddInk)
                Text(preview.summary)
                    .font(.ddCallout)
                    .foregroundStyle(Color.ddInkSecondary)
                if let owner = preview.ownerName, !owner.isEmpty {
                    Text("Eier: \(owner)")
                        .font(.ddCaption)
                        .foregroundStyle(Color.ddInkSecondary)
                }
            }
            .padding(.vertical, 4)
        } header: {
            DDHeader("Konkurransen")
        }
    }

    private var joinSection: some View {
        Section {
            Button("Bli med") {
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
        } footer: {
            DDFooter("Du meldes på og ser tabellen og rundene som teller.")
        }
    }
}

/// Invitasjon fra en lenke (`dashdash://konkurranse/KODE`): se konkurransen og bli med.
struct JoinCompetitionFromLinkView: View {
    let client: SupabaseClient
    let code: InviteCode

    var body: some View {
        NavigationStack {
            JoinCompetitionView(model: JoinCompetitionModel(client: client, code: code)) { _ in }
        }
        .tint(Color.ddForestInk)
    }
}
