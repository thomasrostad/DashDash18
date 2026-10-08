import GolfgutuCore
import SwiftUI

/// Tall i regelfeltene som tekst: norsk komma eller punktum inn, komma ut.
nonisolated enum RuleNumberText {
    private static let locale = Locale(identifier: "nb_NO")

    /// «1,5», «1.5», « 95 », «-2». `nil` for tomt eller noe som ikke er et vanlig desimaltall.
    static func parse(_ raw: String) -> Double? {
        let text = String(raw.filter { !$0.isWhitespace })
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "\u{2212}", with: "-")
        guard text.wholeMatch(of: /-?([0-9]+(\.[0-9]*)?|\.[0-9]+)/) != nil,
              let value = Double(text), value.isFinite else { return nil }
        return value
    }

    /// Høyst to desimaler, uten tusenskille: 0,5 og 95.
    static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never).locale(locale))
    }

    /// Teksten feltet skal vise når verdien er endret utenfra (f.eks. «Tilbakestill»).
    /// `nil` når teksten alt betyr det samme, så «1,» ikke mister kommaet mens du skriver.
    static func text(replacing current: String, for value: Double) -> String? {
        if let typed = parse(current), format(typed) == format(value) { return nil }
        return format(value)
    }
}

/// Et desimaltall med ledetekst til venstre og feltet til høyre. Verdien oppdateres for hvert
/// tegn. `TextField(value:format:)` tar den først ved retur, og talltastaturet har ingen retur,
/// så «Lagre» rett etter skriving lagret den gamle verdien (eller var grå).
struct RuleNumberField: View {
    let title: String
    @Binding var value: Double
    var suffix: String?
    var help: String?
    var changeNote: String?
    @State private var text: String

    init(_ title: String, value: Binding<Double>, suffix: String? = nil, help: String? = nil, changeNote: String? = nil) {
        self.title = title
        _value = value
        self.suffix = suffix
        self.help = help
        self.changeNote = changeNote
        _text = State(initialValue: RuleNumberText.format(value.wrappedValue))
    }

    private var isValid: Bool { RuleNumberText.parse(text) != nil }

    var body: some View {
        LabeledContent {
            HStack(spacing: 4) {
                TextField(title, text: $text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(isValid ? Color.ddInk : Color.ddError)
                    .frame(maxWidth: 90)
                    .accessibilityValue(isValid ? text : "\(text), ikke et tall")
                if let suffix {
                    Text(suffix).foregroundStyle(Color.ddInkSecondary)
                }
            }
        } label: {
            RuleFieldLabel(title: title, help: help, changeNote: changeNote)
        }
        .onChange(of: text) { _, new in
            if let parsed = RuleNumberText.parse(new), parsed != value {
                value = parsed
            }
        }
        .onChange(of: value) { _, new in
            if let replacement = RuleNumberText.text(replacing: text, for: new) {
                text = replacement
            }
        }
    }
}

/// En andel vist i prosent (0,95 lagres, 95 vises).
struct RulePercentField: View {
    let title: String
    let get: () -> Double
    let set: (Double) -> Void

    var body: some View {
        RuleNumberField(title, value: Binding(get: { get() * 100 }, set: { set($0 / 100) }), suffix: "%")
    }
}

/// Et heltall med pluss og minus.
struct RuleStepper: View {
    let title: String
    @Binding var value: Int
    var range: ClosedRange<Int>?
    var help: String?
    var changeNote: String?

    init(_ title: String, value: Binding<Int>, in range: ClosedRange<Int>? = nil, help: String? = nil,
         changeNote: String? = nil) {
        self.title = title
        _value = value
        self.range = range
        self.help = help
        self.changeNote = changeNote
    }

    var body: some View {
        if let range {
            Stepper(value: $value, in: range) { label }
        } else {
            Stepper(value: $value) { label }
        }
    }

    private var label: some View {
        LabeledContent {
            Text("\(value)").monospacedDigit()
        } label: {
            RuleFieldLabel(title: title, help: help, changeNote: changeNote)
        }
    }
}

/// Ledeteksten i et regelfelt: navnet, en kort forklaring under, og «Endret · standard 1»
/// når valget ikke er som i oppsettet.
struct RuleFieldLabel: View {
    let title: String
    var help: String?
    var changeNote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
            if let help {
                Text(help)
                    .font(.dd(.sans, size: 13, relativeTo: .footnote))
                    .foregroundStyle(Color.ddInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let changeNote {
                RuleChangeBadge(text: changeNote)
            }
        }
    }
}

/// Seksjonsoverskrift med «Endret · standard …» når delen ikke er som i oppsettet.
struct RuleSectionHeader: View {
    let title: String
    var changeNote: String?

    var body: some View {
        HStack(spacing: 8) {
            DDHeader(title)
            if let changeNote {
                RuleChangeBadge(text: changeNote)
                    .textCase(nil)
            }
        }
    }
}

/// Lite merke for et valg som er endret fra standard.
struct RuleChangeBadge: View {
    let text: String

    var body: some View {
        DDChip(text, tone: .sun, compact: true)
            .fixedSize()
            .accessibilityLabel(text)
    }
}

/// Valideringsmeldingene, i rødt.
struct RuleIssuesList: View {
    let issues: [RulesetIssue]

    var body: some View {
        ForEach(issues, id: \.self) { issue in
            Label(issue.message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.ddError)
                .font(.dd(.sans, size: 13, relativeTo: .footnote))
        }
    }
}

/// Bunnteksten i en del: forklaringen, og meldingene for delen under.
struct RuleSectionFooter: View {
    var text: String?
    let issues: [RulesetIssue]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let text { Text(text) }
            RuleIssuesList(issues: issues)
        }
    }
}
