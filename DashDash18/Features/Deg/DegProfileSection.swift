import PhotosUI
import SwiftUI

/// Toppen av «Deg» (portrett, navn, handicap) og skjemaet for navn og handicap.
/// Spilleren endrer bare sin egen rad.
struct DegProfileSection: View {
    let membership: Membership
    @State private var model: DegProfileModel
    @Environment(ClubModel.self) private var club
    @State private var draft = DegProfileDraft(name: "", handicap: "")
    @State private var savedMessage: String?

    init(context: ClubContext) {
        membership = context.membership
        _model = State(initialValue: DegProfileModel(context: context))
    }

    var body: some View {
        Section {
            DegHeader(membership: membership, row: model.row, portrait: model.portrait)
                .padding(.vertical, 6)
            if model.row != nil {
                DegPortraitButtons(model: model)
            }
        } footer: {
            if model.row != nil {
                DDFooter("Portrettet står ved navnet ditt i appen.")
            }
        }
        Section {
            if let row = model.row {
                TextField("Navn i troppen", text: $draft.name)
                    .textContentType(.nickname)
                    .autocorrectionDisabled()
                TextField("Handicapindeks (valgfritt)", text: $draft.handicap)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                if draft.hasChanges(from: row) {
                    Button("Lagre") {
                        Task { await save() }
                    }
                    .buttonStyle(.dd(.primary, fullWidth: true, compact: true))
                    .disabled(model.isSaving)
                } else if let savedMessage {
                    Label(savedMessage, systemImage: "checkmark.circle")
                        .font(.ddCallout)
                        .foregroundStyle(Color.ddLimeInk)
                }
            } else if model.isLoading {
                ProgressView()
            } else {
                Button("Last inn på nytt") {
                    Task { await model.load() }
                }
                .fontWeight(.medium)
            }
        } header: {
            DDHeader("Navn og handicap")
        } footer: {
            DDFooter(footerText)
        }
        .task {
            if model.row == nil { await model.load() }
            if let row = model.row { draft = DegProfileDraft(row: row) }
        }
        .alert(
            "Kunne ikke lagre",
            isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } }),
            presenting: model.error
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.message)
        }
    }

    private var footerText: String {
        let format = "Komma eller punktum, f.eks. 12,4. Plusshandicap skrives med «+», f.eks. +2,3."
        if model.row?.seedGroup != nil {
            return "Du er seedet av arrangøren, så slagene følger gruppen din. " + format
        }
        return format
    }

    private func save() async {
        savedMessage = nil
        guard let saved = await model.save(draft) else { return }
        draft = DegProfileDraft(row: saved)
        savedMessage = "Lagret"
        // Navnet står også i medlemskapet (klubbvelger, «Navn i troppen»).
        if let userID = saved.userID {
            await club.load(userID: userID)
        }
    }
}

/// Øverst på Deg: portrett (eller initialer), navnet i troppen, handicap og rollen.
struct DegHeader: View {
    let membership: Membership
    var row: ClubMemberRow?
    var portrait: UIImage?

    var body: some View {
        HStack(spacing: 14) {
            DDAvatar(name: row?.displayName ?? membership.displayName, size: 56, image: portrait)
            VStack(alignment: .leading, spacing: 4) {
                Text(row?.displayName ?? membership.displayName)
                    .font(.ddTitle)
                    .foregroundStyle(Color.ddForestInk)
                Text(subtitle)
                    .font(.ddCallout)
                    .foregroundStyle(Color.ddInkSecondary)
            }
            Spacer(minLength: 8)
            if membership.isOrganizer {
                DDPill("Arrangør", tone: .lime)
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Klubben, og handicapet når raden er hentet (PWA: «hcp 12,4»).
    private var subtitle: String {
        guard let row else { return membership.club.name }
        return membership.club.name + " · " + DegHandicapText.short(row.handicapIndex)
    }
}

/// «Legg til bilde» / «Bytt bilde» fra bildebiblioteket eller kameraet, og «Fjern».
private struct DegPortraitButtons: View {
    let model: DegProfileModel
    @State private var photoItem: PhotosPickerItem?
    @State private var showsCamera = false
    @State private var confirmingRemove = false

    private var hasPortrait: Bool { model.row?.avatarPath != nil }

    var body: some View {
        Group {
            if model.isSavingPortrait {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Lagrer bildet …")
                        .foregroundStyle(Color.ddInkSecondary)
                }
            } else {
                ForEach(TradImageSource.available(cameraAvailable: TradCameraPicker.isAvailable), id: \.self) { source in
                    sourceButton(source)
                }
                if hasPortrait {
                    Button("Fjern bildet", role: .destructive) { confirmingRemove = true }
                        .foregroundStyle(Color.ddRustText)
                }
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else {
                    model.error = .invalid(DegPortraitCompressor.Failure.unreadable.message)
                    return
                }
                await model.savePortrait(imageData: data)
            }
        }
        .fullScreenCover(isPresented: $showsCamera) {
            TradCameraPicker { data in
                showsCamera = false
                guard let data else { return }
                Task { await model.savePortrait(imageData: data) }
            }
            .ignoresSafeArea()
        }
        .confirmationDialog(
            "Fjerne bildet? Da står initialene igjen.",
            isPresented: $confirmingRemove,
            titleVisibility: .visible
        ) {
            Button("Fjern bildet", role: .destructive) {
                Task { await model.removePortrait() }
            }
        }
    }

    @ViewBuilder
    private func sourceButton(_ source: TradImageSource) -> some View {
        switch source {
        case .library:
            let title = hasPortrait ? "Bytt bilde" : "Legg til bilde av deg"
            PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                Label(title, systemImage: source.systemImage)
                    .labelStyle(DDIconLabelStyle())
            }
        case .camera:
            Button { showsCamera = true } label: {
                Label("Ta bilde", systemImage: source.systemImage)
                    .labelStyle(DDIconLabelStyle())
            }
        }
    }
}
