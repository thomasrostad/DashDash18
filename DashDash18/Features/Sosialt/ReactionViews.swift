import SwiftUI
import UIKit

/// Brikkene og «Legg til reaksjon» (44 pt) under et innlegg, en melding eller en kommentar (sql/050).
/// Trykk på en brikke setter eller fjerner din. Knappen gir de fem faste, «Annen emoji …» (når
/// serveren har 050) og «Hvem har reagert». Langt trykk på en brikke viser hvem.
struct ReactionBar: View {
    let chips: [ReactionChip]
    var showsAddButton = true
    let toggle: (String) -> Void
    /// «Annen emoji …». nil: bare de fem faste (uten 050).
    var pickOther: (() -> Void)?
    /// «Hvem har reagert». nil: ingen slik knapp.
    var showWho: (() -> Void)?
    /// «Kommenter» med antallet. nil: ingen kommentarer her.
    var comments: ReactionBarComments?

    var body: some View {
        HStack(spacing: 6) {
            ForEach(chips) { chip in
                Button {
                    toggle(chip.emoji)
                } label: {
                    DDReactionChip(emoji: chip.emoji, count: chip.count, isMine: chip.isMine)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if let showWho {
                        Button("Hvem har reagert", systemImage: "person.2", action: showWho)
                    }
                }
                .accessibilityLabel(ReactionText.chipLabel(chip))
                .accessibilityAddTraits(chip.isMine ? .isSelected : [])
                .accessibilityAction(named: "Hvem har reagert") { showWho?() }
            }
            if showsAddButton {
                Menu {
                    ReactionMenuItems(isMine: { e in chips.contains { $0.emoji == e && $0.isMine } }, toggle: toggle,
                                      pickOther: pickOther, showWho: chips.isEmpty ? nil : showWho)
                } label: {
                    DDAddReactionLabel()
                }
                .accessibilityLabel("Legg til reaksjon")
            }
            if let comments {
                Button(action: comments.open) {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.left")
                        if comments.count > 0 {
                            Text("\(comments.count)").monospacedDigit()
                        }
                    }
                    .font(.ddChip)
                    .foregroundStyle(Color.ddForestInk)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 36)
                    .background(Capsule().fill(Color.ddChipFill))
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ReactionText.commentsLabel(comments.count))
            }
        }
    }
}

struct ReactionBarComments {
    let count: Int
    let open: () -> Void
}

/// Menyen: de fem faste først, så «Annen emoji …» og «Hvem har reagert». Brukes i «Reager»-knappen
/// og i kontekstmenyene (langt trykk).
struct ReactionMenuItems: View {
    let isMine: (String) -> Bool
    let toggle: (String) -> Void
    var pickOther: (() -> Void)?
    var showWho: (() -> Void)?

    var body: some View {
        ForEach(ReactionPalette.quick, id: \.self) { emoji in
            Button {
                toggle(emoji)
            } label: {
                Text(emoji + "  " + (isMine(emoji) ? "Fjern" : ReactionText.name(emoji)))
            }
        }
        if let pickOther {
            Button("Annen emoji …", systemImage: "plus", action: pickOther)
        }
        if let showWho {
            Button("Hvem har reagert", systemImage: "person.2", action: showWho)
        }
    }
}

nonisolated enum ReactionText {
    static func name(_ emoji: String) -> String {
        ActivityReaction(rawValue: emoji)?.accessibilityName ?? emoji
    }

    static func chipLabel(_ chip: ReactionChip) -> String {
        var text = "\(chip.accessibilityName), \(chip.count)"
        if !chip.names.isEmpty { text += ": " + NorwegianList.join(chip.names) }
        return text
    }

    static func commentsLabel(_ count: Int) -> String {
        switch count {
        case 0: "Kommenter"
        case 1: "1 kommentar"
        default: "\(count) kommentarer"
        }
    }
}

// MARK: - Emojivelgeren

/// «Annen emoji …»: et lite utvalg, og et felt med emojitastaturet for alt annet. Én emoji.
struct EmojiPickerSheet: View {
    let pick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""
    @State private var invalid = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 8)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DDSpacing.l) {
                    HStack(spacing: 8) {
                        EmojiTextField(text: $typed, placeholder: "Skriv en emoji")
                            .frame(height: 44)
                            .padding(.horizontal, 14)
                            .background(Color.ddCard, in: .rect(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color.ddHairline, lineWidth: 1)
                            }
                            .accessibilityLabel("Emoji")
                        Button("Bruk") { useTyped() }
                            .buttonStyle(.dd(.primary, compact: true))
                            .disabled(EmojiCheck.lastEmoji(in: typed) == nil)
                    }
                    if invalid {
                        Text("Velg én emoji.")
                            .font(.ddCaption)
                            .foregroundStyle(Color.ddError)
                    }
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(ReactionPalette.quick + ReactionPalette.more, id: \.self) { emoji in
                            Button {
                                choose(emoji)
                            } label: {
                                Text(emoji)
                                    .font(.system(size: 28))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(ReactionText.name(emoji))
                        }
                    }
                }
                .padding(DDSpacing.gutter)
            }
            .navigationTitle("Velg emoji")
            .navigationBarTitleDisplayMode(.inline)
            .ddNavigationChrome()
            .toolbar {
                DDCancelToolbarItem {
                    Button("Avbryt") { dismiss() }
                        .tint(Color.ddForestInk)
                }
            }
            .ddScreenBackground()
        }
        .presentationDetents([.medium, .large])
        .onChange(of: typed) { _, text in
            invalid = false
            // Ett trykk på emojitastaturet holder.
            if EmojiCheck.isSingleEmoji(text) { choose(text) }
        }
    }

    private func useTyped() {
        guard let emoji = EmojiCheck.lastEmoji(in: typed) else { invalid = true; return }
        choose(emoji)
    }

    private func choose(_ emoji: String) {
        guard EmojiCheck.isSingleEmoji(emoji) else { invalid = true; return }
        pick(emoji)
        dismiss()
    }
}

/// Tekstfelt som åpner med emojitastaturet (når brukeren har det slått på).
struct EmojiTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String

    func makeUIView(context: Context) -> EmojiUITextField {
        let field = EmojiUITextField()
        field.placeholder = placeholder
        field.font = .preferredFont(forTextStyle: .title2)
        field.adjustsFontForContentSizeCategory = true
        field.returnKeyType = .done
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        DispatchQueue.main.async { field.becomeFirstResponder() }
        return field
    }

    func updateUIView(_ field: EmojiUITextField, context: Context) {
        if field.text != text { field.text = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        @objc func changed(_ field: UITextField) { text.wrappedValue = field.text ?? "" }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            field.resignFirstResponder()
            return true
        }
    }
}

final class EmojiUITextField: UITextField {
    override var textInputContextIdentifier: String? { "" }

    override var textInputMode: UITextInputMode? {
        UITextInputMode.activeInputModes.first { $0.primaryLanguage == "emoji" } ?? super.textInputMode
    }
}

// MARK: - Hvem har reagert

/// Navnene per emoji. Henter radene (RLS skjuler blokkerte), eller viser det som alt er kjent.
struct ReactionWhoSheet: View {
    let load: () async throws -> [ReactionWhoGroup]
    @Environment(\.dismiss) private var dismiss
    @State private var groups: [ReactionWhoGroup]?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if let groups, groups.isEmpty {
                    ContentUnavailableView("Ingen reaksjoner ennå", systemImage: "face.smiling")
                } else if let groups {
                    DDList {
                        ForEach(groups) { group in
                            DDSection(group.emoji + "  " + "\(group.names.count)") {
                                ForEach(Array(group.names.enumerated()), id: \.offset) { _, name in
                                    Text(name)
                                        .font(.ddBody)
                                        .foregroundStyle(Color.ddInk)
                                }
                            }
                        }
                    }
                } else if let error {
                    ContentUnavailableView {
                        Label("Fikk ikke hentet reaksjonene", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Prøv igjen") { Task { await reload() } }.buttonStyle(.dd(.primary))
                    }
                } else {
                    ProgressView("Henter …")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Har reagert")
            .navigationBarTitleDisplayMode(.inline)
            .ddNavigationChrome()
            .toolbar {
                DDConfirmToolbarItem {
                    Button("Ferdig") { dismiss() }
                        .tint(Color.ddForestInk)
                }
            }
            .ddScreenBackground()
        }
        .presentationDetents([.medium, .large])
        .task { await reload() }
    }

    private func reload() async {
        error = nil
        do {
            groups = try await load()
        } catch {
            guard !DataError.isCancellation(error) else { return }
            self.error = DataError.from(error).message
        }
    }
}
