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

    var body: some View {
        messageList
            .overlay { stateOverlay }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                TradComposer(model: model, focused: $composerFocused, photoItem: $photoItem)
            }
            .navigationTitle("Kveldens tråd")
            .navigationBarTitleDisplayMode(.inline)
            .task { await model.load() }
            .onAppear {
                model.isVisible = true
                model.markReadIfVisible()
            }
            .onDisappear {
                model.isVisible = false
                Task { await model.stopRealtime() }
            }
            // Realtime sender ikke det som kom mens appen sto i bakgrunnen.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await model.load() } }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                photoItem = nil
                Task {
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self) else { return }
                        await model.attach(imageData: data)
                    } catch {
                        model.errorMessage = TradImageCompressor.Failure.unreadable.message
                    }
                }
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
            .alert(
                "Tråden",
                isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
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
                            }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
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
                    .buttonStyle(.borderedProminent)
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
        HStack {
            if item.isMine { Spacer(minLength: 48) }
            VStack(alignment: item.isMine ? .trailing : .leading, spacing: 4) {
                if !item.isMine {
                    Text(item.author)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                if let path = item.message.imagePath {
                    TradImageView(path: path, author: item.author, model: model)
                }
                if !item.message.body.isEmpty {
                    Text(attributedBody)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(item.isMine ? Color.accentColor.opacity(0.2) : Color(.secondarySystemBackground),
                                    in: .rect(cornerRadius: 16))
                }
                Text(item.isPending ? "Sender …" : TradTimeLabel.text(for: item.message.createdAt, now: Date()))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
                part.font = .body.weight(.semibold)
                if id == model.viewerID { part.foregroundColor = .accentColor }
            }
            result += part
        }
        return result
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
                    .clipShape(.rect(cornerRadius: 16))
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
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(width: 200, height: 150)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 16))
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
                            .buttonStyle(.bordered)
                            .accessibilityHint(suggestion.name)
                        }
                    }
                }
            }
            if model.isPreparingImage {
                HStack {
                    ProgressView()
                    Text("Gjør klar bildet …").font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                }
            } else if let attachment = model.attachment, let preview = UIImage(data: attachment.data) {
                HStack(alignment: .top) {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(.rect(cornerRadius: 10))
                        .accessibilityLabel("Bildet som legges ved")
                    Button("Fjern", role: .destructive) { model.removeAttachment() }
                        .font(.footnote)
                    Spacer()
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                // Bare bildebiblioteket nå. Kamera kommer i fase 8 (trenger NSCameraUsageDescription).
                PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                    Image(systemName: "photo")
                        .font(.title3)
                        .frame(width: 36, height: 36)
                }
                .disabled(model.isSending || model.isPreparingImage)
                .accessibilityLabel("Legg ved bilde")

                TextField("Skriv til kvelden …", text: $model.draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused(focused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 18))

                Button {
                    Task { await model.send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                }
                .disabled(!model.canSend)
                .accessibilityLabel("Send")
            }
            if let left = model.remainingCharacters {
                Text(left >= 0 ? "\(left) tegn igjen" : "\(-left) tegn for mye")
                    .font(.caption2)
                    .foregroundStyle(left >= 0 ? Color.secondary : Color.red)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
