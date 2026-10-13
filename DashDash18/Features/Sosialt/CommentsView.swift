import SwiftUI

/// Kommentarene som ark: lista, «Følg tråden» og skrivefeltet med @-forslag.
struct CommentsSheet: View {
    @State var model: CommentsModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @State private var confirmingDelete: CommentRow?
    @State private var reportTarget: CommentReport?
    @State private var emojiTarget: CommentTarget?
    @State private var whoTarget: CommentTarget?

    var body: some View {
        NavigationStack {
            list
                .overlay { overlay }
                .safeAreaInset(edge: .bottom, spacing: 0) { composer }
                .navigationTitle("Kommentarer")
                .navigationBarTitleDisplayMode(.inline)
                .ddNavigationChrome()
                .toolbar {
                    DDConfirmToolbarItem {
                        Button("Ferdig") { dismiss() }
                            .tint(Color.ddForestInk)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task { await model.toggleFollow() }
                        } label: {
                            Label(model.following ? "Følger tråden" : "Følg tråden",
                                  systemImage: model.following ? "bell.fill" : "bell.slash")
                        }
                        .accessibilityHint(model.following ? "Du får varsel om nye kommentarer. Trykk for å slå av."
                                                           : "Trykk for å få varsel om nye kommentarer.")
                    }
                }
        }
        .task { await model.load() }
        .onDisappear { Task { await model.stopRealtime() } }
        .confirmationDialog(
            "Slette kommentaren?",
            isPresented: Binding(get: { confirmingDelete != nil }, set: { if !$0 { confirmingDelete = nil } }),
            titleVisibility: .visible,
            presenting: confirmingDelete
        ) { comment in
            Button("Slett", role: .destructive) { Task { await model.delete(comment) } }
            Button("Avbryt", role: .cancel) {}
        } message: { comment in
            Text(comment.authorID == model.me ? "Den forsvinner for alle." : "Du sletter en annens kommentar som moderator.")
        }
        .sheet(item: $reportTarget) { report in
            ReportSheet(target: report.target) { reason, note, block in
                try await model.report(report.comment, reason: reason, note: note, block: block)
            }
        }
        .sheet(item: $emojiTarget) { target in
            EmojiPickerSheet { emoji in Task { await model.toggle(emoji, on: target.id) } }
        }
        .sheet(item: $whoTarget) { target in
            ReactionWhoSheet { try await model.who(target.id) }
        }
        .alert("Kommentarer",
               isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                Text(model.following ? "Du får varsel når noen kommenterer." : "Du får ikke varsel om nye kommentarer.")
                    .font(.ddCaption)
                    .foregroundStyle(Color.ddInkSecondary)
                ForEach(model.items) { item in
                    CommentRowView(item: item, model: model,
                                   pickOther: { emojiTarget = CommentTarget(id: item.id) },
                                   showWho: { whoTarget = CommentTarget(id: item.id) })
                        .contextMenu { menu(item) }
                }
            }
            .padding(.horizontal, DDSpacing.gutter)
            .padding(.vertical, DDSpacing.l)
        }
        .defaultScrollAnchor(.bottom)
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await model.load() }
        .ddScreenBackground()
    }

    @ViewBuilder
    private func menu(_ item: CommentItem) -> some View {
        if !item.isDeleted {
            Button("Kopier", systemImage: "doc.on.doc") { UIPasteboard.general.string = item.comment.body }
        }
        if item.canEdit {
            Button("Endre", systemImage: "pencil") {
                model.startEditing(item.comment)
                focused = true
            }
        }
        if item.canDelete {
            Button("Slett", systemImage: "trash", role: .destructive) { confirmingDelete = item.comment }
        }
        if item.canReport, ModerationFeature.isEnabled {
            Button("Rapporter kommentaren", systemImage: "flag") {
                reportTarget = CommentReport(comment: item.comment, author: item.author)
            }
        }
    }

    @ViewBuilder
    private var overlay: some View {
        switch model.state {
        case .loading:
            ProgressView("Henter kommentarene …")
        case .failed(let message):
            ContentUnavailableView {
                Label("Fikk ikke hentet kommentarene", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("Prøv igjen") { Task { await model.load() } }
                    .buttonStyle(.dd(.primary))
            }
        case .loaded:
            if model.items.isEmpty {
                ContentUnavailableView("Ingen kommentarer ennå", systemImage: "bubble.left",
                                       description: Text("Skriv den første."))
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if !model.suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(model.suggestions) { suggestion in
                            Button("@" + suggestion.handle) {
                                model.insertMention(suggestion.handle)
                                focused = true
                            }
                            .buttonStyle(.dd(.secondary, compact: true))
                            .accessibilityHint(suggestion.name)
                        }
                    }
                }
            }
            if model.editing != nil {
                HStack {
                    Label("Endrer kommentaren", systemImage: "pencil")
                        .font(.ddCaption)
                        .foregroundStyle(Color.ddInkSecondary)
                    Spacer()
                    Button("Avbryt") { model.cancelEditing() }
                        .font(.ddCaption)
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Skriv en kommentar …", text: $model.draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($focused)
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
                    Image(systemName: model.editing == nil ? "arrow.up" : "checkmark")
                }
                .buttonStyle(DDSendButtonStyle())
                .disabled(!model.canSend)
                .accessibilityLabel(model.editing == nil ? "Send" : "Lagre")
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
}

private struct CommentTarget: Identifiable {
    let id: UUID
}

private struct CommentReport: Identifiable {
    let comment: CommentRow
    let author: String
    var id: UUID { comment.id }

    var target: ReportTarget {
        ReportTarget(kind: .comment, targetID: comment.id, memberID: comment.memberID, authorName: author)
    }
}

/// Én kommentar: navn, tid, tekst (med @navn uthevet) og reaksjonene.
private struct CommentRowView: View {
    let item: CommentItem
    let model: CommentsModel
    let pickOther: () -> Void
    let showWho: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            DDAvatar(name: item.author, size: 30)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.isMine ? "\(item.author) (deg)" : item.author)
                        .font(.dd(.sans, size: 13, weight: .semibold, relativeTo: .caption))
                        .foregroundStyle(Color.ddForestInk)
                    Text(ActivityFeed.relativeTime(item.comment.createdAt) + (item.isEdited ? " · endret" : ""))
                        .font(.dd(.sans, size: 12, relativeTo: .caption2))
                        .foregroundStyle(Color.ddInkSecondary)
                }
                if item.isDeleted {
                    Text(item.text)
                        .font(.ddBody)
                        .italic()
                        .foregroundStyle(Color.ddInkSecondary)
                } else {
                    Text(attributedBody)
                        .font(.ddBody)
                        .foregroundStyle(Color.ddInk)
                        .fixedSize(horizontal: false, vertical: true)
                    let chips = model.chips(for: item.id)
                    ReactionBar(chips: chips, showsAddButton: true,
                                toggle: { emoji in Task { await model.toggle(emoji, on: item.id) } },
                                pickOther: pickOther, showWho: chips.isEmpty ? nil : showWho)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }

    private var attributedBody: AttributedString {
        var result = AttributedString()
        for segment in model.directory.segments(of: item.comment.body, mentions: item.comment.mentions) {
            var part = AttributedString(segment.text)
            if let id = segment.mention {
                part.font = Font.ddBodyEmphasis
                if id == model.me { part.foregroundColor = Color.ddRustText }
            }
            result += part
        }
        return result
    }
}
