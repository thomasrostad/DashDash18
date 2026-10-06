import GolfgutuCore
import SwiftUI

/// Et desimaltall med ledetekst til venstre og feltet til høyre.
struct RuleNumberField: View {
    let title: String
    @Binding var value: Double
    var suffix: String?

    init(_ title: String, value: Binding<Double>, suffix: String? = nil) {
        self.title = title
        _value = value
        self.suffix = suffix
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField(title, value: $value, format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 90)
                if let suffix {
                    Text(suffix).foregroundStyle(.secondary)
                }
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

    init(_ title: String, value: Binding<Int>, in range: ClosedRange<Int>? = nil) {
        self.title = title
        _value = value
        self.range = range
    }

    var body: some View {
        if let range {
            Stepper(value: $value, in: range) { label }
        } else {
            Stepper(value: $value) { label }
        }
    }

    private var label: some View {
        LabeledContent(title, value: "\(value)")
    }
}

/// Valideringsmeldingene, i rødt.
struct RuleIssuesList: View {
    let issues: [RulesetIssue]

    var body: some View {
        ForEach(issues, id: \.self) { issue in
            Label(issue.message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.footnote)
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
