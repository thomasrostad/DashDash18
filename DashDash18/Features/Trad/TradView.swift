import PhotosUI
import SwiftUI

/// Kveldens tråd: praten om én kveld. Nyeste nederst, skrivefeltet fast i bunnen.
/// Pushes inn i en `NavigationStack` (tittelen settes her).
struct TradView: View {
    let eventID: UUID
    @Environment(\.clubContext) private var context

    var body: some View {
        if let context {
            TradContent(model: TradModel(context: context, eventID: eventID))
        } else {
            ContentUnavailableView("Ingen klubb valgt", systemImage: "bubble.left.and.bubble.right")
        }
    }
}

private struct TradContent: View {
    @State var model: TradModel
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var composerFocused: Bool
    @State private var photoItem: PhotosPickerItem?
    @State private var confirmingDelete: ThreadMessageRow?
    @State private var showsCamera = false
    @State private var cameraDenied = false
    /// Rapporter og blokker (fase 17, `ModerationFeature`).
    @State private var reportTarget: ReportTarget?
    @State private var confirmingBlock: TradModel.Item?

    var body: some View {
        messageList
            .overlay { stateOverlay }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                TradComposer(model: model, focused: $composerFocused, photoItem: $photoItem,
                             sources: TradImageSource.available(cameraAvailable: TradCameraPicker.isAvailable),
                             onCamera: openCamera)
            }
            .navigationTitle("Kveldens tråd")
            .ddNavigationChrome()
            .task { await model.load() }
            .onAppear {
                model.isVisible = true
                model.markReadIfVisible()
                PushInbox.visibleThreadEventID = model.eventID
            }
            .onDisappear {
                model.isVisible = false
                if PushInbox.visibleThreadEventID == model.eventID { PushInbox.visibleThreadEventID = nil }
                Task { await model.stopRealtime() }
            }
            .cameraDeniedAlert(isPresented: $cameraDenied)
            // Realtime sender ikke det som kom mens appen sto i bakgrunnen.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await model.load() } }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                photoItem = nil
                Task {
                    // Et bilde som bare ligger i iCloud og ikke kan hentes, gir nil eller feil.
                    guard let data = try? await item.loadTransferable(type: Data.self) else {
                        model.errorMessage = TradImageCompressor.Failure.unreadable.message
                        return
                    }
                    await model.attach(imageData: data)
                }
            }
            .fullScreenCover(isPresented: $showsCamera) {
                TradCameraPicker { data in
                    showsCamera = false
                    guard let data else { return }
                    Task { await model.attach(imageData: data) }
                }
                .ignoresSafeArea()
            }
            .confirmationDialog(
                "Slette meldingen?",
                isPresented: Binding(get: { confirmingDelete != nil }, set: { if !$0 { confirmingDelete = nil } }),
                titleVisibility: .visible,
                presenting: confirmingDelete
            ) { message in
                Button("Slett", role: .destructive) {
                    Task { await model.delete(message.id) }
                }
                Button("Avbryt", role: .cancel) {}
            } message: { message in
                Text(message.memberID == model.viewerID ? "Den forsvinner for alle." : "Du sletter en annens melding som arrangør.")
            }
            .sheet(item: $reportTarget) { target in
                ReportSheet(target: target) { reason, note, block in
                    try await model.report(target, reason: reason, note: note, block: block)
                }
            }
            .confirmationDialog(
                "Blokkere?",
                isPresented: Binding(get: { confirmingBlock != nil }, set: { if !$0 { confirmingBlock = nil } }),
                titleVisibility: .visible,
                presenting: confirmingBlock
            ) { item in
                Button("Blokker \(item.author)", role: .destructive) {
                    Task { await model.block(memberID: item.message.memberID) }
                }
                Button("Avbryt", role: .cancel) {}
            } message: { item in
                Text("Du ser ikke lenger meldingene til \(item.author), og dere kan ikke legge hverandre til i runder. \(item.author) får ikke vite det. Du kan oppheve det under Deg.")
            }
            .alert(
                "Tråden",
                isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
    }

    @ViewBuilder
    private func moderationButtons(for item: TradModel.Item) -> some View {
        if !item.message.body.isEmpty {
            Button("Rapporter meldingen", systemImage: "flag") {
                reportTarget = ReportTarget(kind: .message, targetID: item.id, memberID: item.message.memberID,
                                            authorName: item.author)
            }
        }
        if item.message.imagePath != nil {
            Button("Rapporter bildet", systemImage: "flag") {
                reportTarget = ReportTarget(kind: .image, targetID: item.id, memberID: item.message.memberID,
                                            authorName: item.author)
            }
        }
        Button("Blokker \(item.author)", systemImage: "hand.raised", role: .destructive) {
            confirmingBlock = item
        }
    }

    private func openCamera() {
        Task {
            if await CameraAccess.requestIfNeeded() { showsCamera = true } else { cameraDenied = true }
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(model.items) { item in
                        TradBubble(item: item, model: model)
                            .id(item.id)
                            .contextMenu {
                                if !item.message.body.isEmpty {
                                    Button("Kopier", systemImage: "doc.on.doc") {
                                        UIPasteboard.general.string = item.message.body
                                    }
                                }
                                if item.canDelete {
                                    Button("Slett", systemImage: "trash", role: .destructive) {
                                        confirmingDelete = item.message
                                    }
                                }
                                if ModerationFeature.isEnabled, !item.isMine, !item.isPending {
                                    moderationButtons(for: item)
                                }
                            }
                    }
                }
                .padding(.horizontal, DDSpacing.gutter)
                .padding(.vertical, DDSpacing.l)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await model.load() }
            .onChange(of: model.items.last?.id) { _, last in
                guard let last else { return }
                withAnimation { proxy.scrollTo(last, anchor: .bottom) }
            }
        }
    }

    @ViewBuilder
    private var stateOverlay: some View {
        switch model.state {
        case .loading:
            ProgressView("Henter tråden …")
        case .failed(let message):
            ContentUnavailableView {
                Label("Fikk ikke hentet tråden", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Prøv igjen") { Task { await model.load() } }
                    .buttonStyle(.dd(.primary))
            }
        case .loaded:
            if model.items.isEmpty {
                ContentUnavailableView(
                    "Ingen har skrevet ennå",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Blir du sen, eller trenger noen skyss? Skriv det her.")
                )
            }
        }
    }
}

// MARK: - Boble

private struct TradBubble: View {
    let item: TradModel.Item
    let model: TradModel

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if item.isMine {
                Spacer(minLength: 48)
            } else {
                TradAvatar(name: item.author, path: item.avatarPath, model: model)
            }
            VStack(alignment: item.isMine ? .trailing : .leading, spacing: 4) {
                if !item.isMine {
                    Text(item.author)
                        .font(.dd(.sans, size: 13, weight: .semibold, relativeTo: .caption))
                        .foregroundStyle(Color.ddForestInk)
                        .padding(.horizontal, 4)
                }
                if let path = item.message.imagePath {
                    TradImageView(path: path, author: item.author, model: model)
                }
                if !item.message.body.isEmpty {
                    Text(attributedBody)
                        .ddBubble(mine: item.isMine)
                }
                Text(item.isPending ? "Sender …" : TradTimeLabel.text(for: item.message.createdAt, now: Date()))
                    .font(.dd(.sans, size: 12, relativeTo: .caption2))
                    .foregroundStyle(Color.ddInkSecondary)
                    .padding(.horizontal, 4)
            }
            .opacity(item.isPending ? 0.6 : 1)
            if !item.isMine { Spacer(minLength: 48) }
        }
        .accessibilityElement(children: .combine)
    }

    /// @navn for de nevnte er uthevet, ditt eget litt mer.
    private var attributedBody: AttributedString {
        var result = AttributedString()
        for segment in model.directory.segments(of: item.message.body, mentions: item.message.mentions) {
            var part = AttributedString(segment.text)
            if let id = segment.mention {
                part.font = Font.ddBodyEmphasis
                // Ditt eget navn i gult på grønn boble, rust på hvit (begge over 4,5:1).
                if id == model.viewerID { part.foregroundColor = item.isMine ? Color.ddYellow : Color.ddRustText }
            }
            result += part
        }
        return result
    }
}

/// Portrettet ved meldingen, eller initialene til det er hentet (eller når det ikke finnes).
private struct TradAvatar: View {
    let name: String
    let path: String?
    let model: TradModel
    @State private var loaded: (path: String, image: UIImage)?

    private var image: UIImage? {
        guard let path else { return nil }
        if let loaded, loaded.path == path { return loaded.image }
        return model.images.cached(path)
    }

    var body: some View {
        DDAvatar(name: name, size: 30, image: image)
            .task(id: path.flatMap(model.avatarURL)) {
                guard let path, image == nil, let url = model.avatarURL(for: path),
                      let fetched = try? await model.images.image(for: path, url: url) else { return }
                loaded = (path, fetched)
            }
    }
}

// MARK: - Bilde

private struct TradImageView: View {
    let path: String
    let author: String
    let model: TradModel
    @State private var image: UIImage?
    @State private var failed = false
    @State private var showsFull = false

    private var url: URL? { model.imageURL(for: path) }

    var body: some View {
        Group {
            if let image = image ?? model.images.cached(path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: 240, maxHeight: 300)
                    .clipShape(.rect(cornerRadius: 20, style: .continuous))
                    .onTapGesture { showsFull = true }
                    .accessibilityLabel("Bilde fra \(author)")
                    .accessibilityAddTraits(.isButton)
                    .fullScreenCover(isPresented: $showsFull) {
                        TradFullImage(image: image)
                    }
            } else if failed || model.imageFailed(path) {
                placeholder(Label("Bildet kunne ikke hentes", systemImage: "photo.badge.exclamationmark"))
            } else {
                placeholder(ProgressView("Henter bildet …"))
            }
        }
        .task(id: url) {
            guard image == nil, let url else { return }
            do {
                image = try await model.images.image(for: path, url: url)
                failed = false
            } catch {
                failed = !Task.isCancelled
            }
        }
    }

    private func placeholder(_ content: some View) -> some View {
        content
            .font(.ddCaption)
            .foregroundStyle(Color.ddInkSecondary)
            .frame(width: 200, height: 150)
            .background(Color.ddEarth, in: .rect(cornerRadius: 20, style: .continuous))
    }
}

private struct TradFullImage: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Lukk") { dismiss() }
                    }
                }
                .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

// MARK: - Skrivefeltet

/// Står fast nederst. Feltet beholder fokus og teksten når nye meldinger kommer, fordi
/// utkastet ligger i modellen og hentingen aldri rører det.
private struct TradComposer: View {
    @Bindable var model: TradModel
    var focused: FocusState<Bool>.Binding
    @Binding var photoItem: PhotosPickerItem?
    let sources: [TradImageSource]
    let onCamera: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if !model.suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(model.suggestions) { suggestion in
                            Button("@" + suggestion.handle) {
                                model.insertMention(suggestion.handle)
                                focused.wrappedValue = true
                            }
                            .buttonStyle(.dd(.secondary, compact: true))
                            .accessibilityHint(suggestion.name)
                        }
                    }
                }
            }
            if model.isPreparingImage {
                HStack {
                    ProgressView()
                    Text("Gjør klar bildet …").font(.ddCaption).foregroundStyle(Color.ddInkSecondary)
                    Spacer()
                }
            } else if let attachment = model.attachment, let preview = UIImage(data: attachment.data) {
                HStack(alignment: .top) {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(.rect(cornerRadius: 14, style: .continuous))
                        .accessibilityLabel("Bildet som legges ved")
                    Button("Fjern", role: .destructive) { model.removeAttachment() }
                        .buttonStyle(.dd(.danger, compact: true))
                    Spacer()
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(sources, id: \.self) { source in
                    imageButton(source)
                        // Utenfor etiketten: den er en Sendable-closure og kan ikke lese fargene.
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Color.ddForestInk)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .disabled(model.isSending || model.isPreparingImage)
                        .accessibilityLabel(source.accessibilityLabel)
                }

                TextField("Skriv til kvelden …", text: $model.draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused(focused)
                    .font(.ddBody)
                    .foregroundStyle(Color.ddInk)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .frame(minHeight: 44)
                    .background(Color.ddCard, in: .rect(cornerRadius: 22, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.ddHairline, lineWidth: 1)
                    }

                Button {
                    Task { await model.send() }
                } label: {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(DDSendButtonStyle())
                .disabled(!model.canSend)
                .accessibilityLabel("Send")
            }
            if let left = model.remainingCharacters {
                Text(left >= 0 ? "\(left) tegn igjen" : "\(-left) tegn for mye")
                    .font(.dd(.sans, size: 12, relativeTo: .caption2))
                    .foregroundStyle(left >= 0 ? Color.ddInkSecondary : Color.ddError)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, DDSpacing.l)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background {
            Color.ddBackground
                .overlay(alignment: .top) { DDDivider() }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    @ViewBuilder
    private func imageButton(_ source: TradImageSource) -> some View {
        switch source {
        case .library:
            PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                Image(systemName: source.systemImage)
                    .frame(width: 44, height: 44)
            }
        case .camera:
            Button(action: onCamera) {
                Image(systemName: source.systemImage)
                    .frame(width: 44, height: 44)
            }
        }
    }
}

// MARK: - Skjermprøve

#if DEBUG
/// Tråden med oppdiktede meldinger, uten nett (`-DDDesignScreen trad`).
struct TradSampleScreen: View {
    var body: some View {
        NavigationStack {
            TradContent(model: TradModel(eventID: SampleTradBackend.event, clubID: SampleTradBackend.club,
                                         viewer: SampleTradBackend.thomas, isOrganizer: false,
                                         backend: SampleTradBackend()))
        }
    }
}

private struct SampleTradBackend: TradBackend {
    static let club = UUID(), event = UUID(), thomas = UUID(), kare = UUID(), ola = UUID()

    func messages(eventID: UUID) async throws -> [ThreadMessageRow] {
        let now = Date.now
        func m(_ who: UUID, _ text: String, _ minutes: Double, mentions: [UUID] = []) -> ThreadMessageRow {
            ThreadMessageRow(id: UUID(), clubID: Self.club, eventID: Self.event, memberID: who, body: text,
                             mentions: mentions, imagePath: nil, createdAt: now.addingTimeInterval(-minutes * 60))
        }
        return [
            m(Self.kare, "Blir litt sen, starter dere uten meg?", 42),
            m(Self.thomas, "Vi venter ved båsen 👍", 40),
            m(Self.ola, "@Thomas tar du med ekstra baller?", 12, mentions: [Self.thomas]),
            m(Self.thomas, "Klart det. Ses 17:00.", 5),
        ]
    }

    func members(clubID: UUID) async throws -> [ClubMemberRow] {
        [(Self.thomas, "Thomas"), (Self.kare, "Kåre"), (Self.ola, "Ola")].map { id, name in
            ClubMemberRow(id: id, clubID: Self.club, userID: nil, displayName: name, handicapIndex: nil, seedGroup: nil,
                          isOrganizer: false, isTreasurer: false, status: .active, avatarPath: nil)
        }
    }

    func insert(_ message: ThreadMessageInsert) async throws -> ThreadMessageRow {
        ThreadMessageRow(id: message.id, clubID: message.clubID, eventID: message.eventID, memberID: message.memberID,
                         body: message.body, mentions: message.mentions, imagePath: message.imagePath, createdAt: .now)
    }

    func delete(messageID: UUID) async throws -> Bool { true }
    func uploadImage(path: String, jpeg: Data) async throws {}
    func removeImages(paths: [String]) async throws {}
    func signedURLs(paths: [String], expiresIn: Int) async throws -> [String: URL] { [:] }
}
#endif
