import GolfgutuCore
import Observation
import Supabase
import SwiftUI

// Den valgfrie føringen under slagtelleren (fase 16): fairway (par 4/5), green i regulering,
// putter, bunker og straffeslag. Vises bare når spilleren har slått det på under Deg.

nonisolated extension RoundGame {
    /// Paret på hullet slik det spilles i runden, til føringen under hullkortet.
    func statsPar(_ hole: Int) -> Int? {
        holes.indices.contains(hole) ? holes[hole].par : nil
    }
}

/// Trykkene i føringen, uten SwiftUI. Et nytt trykk på det som er valgt, tar det bort igjen.
nonisolated enum HoleStatsInput {
    static let maxCount = 9
    /// Første trykk på + for putter gir det vanligste (to putter).
    static let firstPutts = 2

    static func fairway(_ d: HoleDetail, _ value: FairwayResult) -> HoleDetail {
        var d = d
        d.fairway = d.fairway == value ? nil : value
        return d
    }

    /// Ikke ført → ja → nei → ikke ført.
    static func cycle(_ value: Bool?) -> Bool? {
        switch value {
        case nil: true
        case true?: false
        case false?: nil
        }
    }

    static func putts(_ d: HoleDetail, _ step: Int) -> HoleDetail {
        var d = d
        switch (d.putts, step > 0) {
        case (nil, true): d.putts = firstPutts
        case (nil, false): d.putts = firstPutts - 1
        case (let p?, true): d.putts = min(maxCount, p + 1)
        case (let p?, false): d.putts = p == 0 ? nil : p - 1
        }
        return d
    }

    static func penalties(_ d: HoleDetail, _ step: Int) -> HoleDetail {
        var d = d
        let next = (d.penalties ?? 0) + step
        d.penalties = next <= 0 ? nil : min(maxCount, next)
        return d
    }

    /// Fairway gjelder ikke på par 3; den fjernes hvis paret er endret.
    static func normalized(_ d: HoleDetail, par: Int) -> HoleDetail {
        var d = d
        if par < 4 { d.fairway = nil }
        return d
    }
}

/// Føringen for spilleren i runden som går: henter det som er ført, og lagrer hvert hull litt
/// etter siste trykk (siste trykk vinner).
@Observable
final class HoleStatsEntryModel {
    private(set) var details: [Int: HoleDetail] = [:]
    private(set) var error: String?
    private(set) var loadedRound: UUID?

    private let client: SupabaseClient
    let memberID: UUID
    private var saves: [Int: Task<Void, Never>] = [:]
    /// Ventetid før et hull lagres, så flere trykk blir én skriving.
    static let saveDelay: Duration = .milliseconds(700)

    init(client: SupabaseClient, memberID: UUID) {
        self.client = client
        self.memberID = memberID
    }

    func load(roundID: UUID) async {
        guard loadedRound != roundID else { return }
        do {
            let rows = try await StatsQueries.details(client: client, roundID: roundID, memberID: memberID)
            details = Dictionary(rows.map { ($0.holeIndex, $0.detail) }, uniquingKeysWith: { a, _ in a })
            loadedRound = roundID
            error = nil
        } catch {
            self.error = DataError.from(error).message
        }
    }

    func update(roundID: UUID, hole: Int, _ detail: HoleDetail) {
        details[hole] = detail
        saves[hole]?.cancel()
        let row = HoleStatRow(roundID: roundID, memberID: memberID, holeIndex: hole, detail: detail)
        saves[hole] = Task { [client] in
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled else { return }
            do {
                try await StatsQueries.save(client: client, row: row)
                self.error = nil
            } catch {
                self.error = "Fikk ikke lagret føringen: \(DataError.from(error).message)"
            }
        }
    }
}

/// Plassen under hullkortet. Tom når føringen er av (eller funksjonen ikke er slått på).
struct HoleStatsSlot: View {
    let context: ClubContext
    let roundID: UUID
    let memberID: UUID
    let holeIndex: Int
    let par: Int
    @State private var model: HoleStatsEntryModel?

    var body: some View {
        if StatsFeature.isEnabled, HoleStatsSetting().isOn(for: context.user.id) {
            Group {
                if let model {
                    HoleStatsEntryRow(par: par, holeNumberText: nil,
                                      detail: model.details[holeIndex] ?? HoleDetail(),
                                      error: model.error) { detail in
                        model.update(roundID: roundID, hole: holeIndex, HoleStatsInput.normalized(detail, par: par))
                    }
                } else {
                    Color.clear.frame(height: 0)
                }
            }
            .task(id: roundID) {
                let m = model ?? HoleStatsEntryModel(client: context.client, memberID: memberID)
                model = m
                await m.load(roundID: roundID)
            }
        }
    }
}

/// Den kompakte raden: fairway, GIR og bunker øverst, putter og straffeslag under.
struct HoleStatsEntryRow: View {
    let par: Int
    var holeNumberText: String?
    let detail: HoleDetail
    var error: String?
    let onChange: (HoleDetail) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Din føring").ddEyebrow()
                if let holeNumberText { Text("· \(holeNumberText)").ddEyebrow() }
                Spacer()
                Text("valgfritt").ddEyebrow()
            }
            HStack(spacing: 8) {
                if par >= 4 {
                    fairway
                }
                toggle("GIR", value: detail.greenInRegulation, label: "Green i regulering") {
                    var d = detail; d.greenInRegulation = HoleStatsInput.cycle(d.greenInRegulation); onChange(d)
                }
                toggle("Bunker", value: detail.bunker, label: "Bunker") {
                    var d = detail; d.bunker = HoleStatsInput.cycle(d.bunker); onChange(d)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 16) {
                counter("Putter", value: detail.putts) { onChange(HoleStatsInput.putts(detail, $0)) }
                counter("Straff", value: detail.penalties) { onChange(HoleStatsInput.penalties(detail, $0)) }
                Spacer(minLength: 0)
            }
            if let error {
                Text(error).font(.ddCaption).ddWarningStyle()
            }
        }
        .padding(.vertical, DDSpacing.m)
        .padding(.horizontal, DDSpacing.l)
        .background(Color.ddCard, in: .rect(cornerRadius: DDRadius.input))
        .overlay(RoundedRectangle(cornerRadius: DDRadius.input).strokeBorder(Color.ddCardBorder, lineWidth: 1))
    }

    private var fairway: some View {
        HStack(spacing: 2) {
            ForEach(FairwayResult.allCases, id: \.self) { value in
                Button {
                    onChange(HoleStatsInput.fairway(detail, value))
                } label: {
                    Image(systemName: icon(value))
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 34, height: 30)
                        .foregroundStyle(detail.fairway == value ? DDTone.lime.foreground : Color.ddInkSecondary)
                        .background(detail.fairway == value ? DDTone.lime.background : Color.clear,
                                    in: .rect(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(fairwayLabel(value))
                .accessibilityAddTraits(detail.fairway == value ? .isSelected : [])
            }
        }
        .padding(2)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.ddCardBorder, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Fairway")
    }

    private func icon(_ value: FairwayResult) -> String {
        switch value {
        case .left: "arrow.up.left"
        case .hit: "checkmark"
        case .right: "arrow.up.right"
        }
    }

    private func fairwayLabel(_ value: FairwayResult) -> String {
        switch value {
        case .left: "Fairway: bom til venstre"
        case .hit: "Fairway: treff"
        case .right: "Fairway: bom til høyre"
        }
    }

    private func toggle(_ title: String, value: Bool?, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                if let value {
                    Image(systemName: value ? "checkmark" : "xmark").imageScale(.small)
                }
            }
            .font(.dd(.sans, size: 13, weight: .semibold, relativeTo: .footnote))
            .padding(.horizontal, 12)
            .frame(height: 34)
            .foregroundStyle(value == true ? DDTone.lime.foreground : value == false ? DDTone.blush.foreground : Color.ddInkSecondary)
            .background(Capsule().fill(value == true ? DDTone.lime.background : value == false ? DDTone.blush.background : Color.clear))
            .overlay(Capsule().strokeBorder(value == nil ? Color.ddCardBorder : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(value == nil ? "ikke ført" : value! ? "ja" : "nei")
    }

    private func counter(_ title: String, value: Int?, step: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.ddCallout).foregroundStyle(Color.ddInkSecondary)
            Button { step(-1) } label: { Image(systemName: "minus") }
                .buttonStyle(.ddCompactStepper)
                .accessibilityLabel("\(title): én mindre")
            Text(value.map(String.init) ?? "–")
                .font(.ddNumber)
                .monospacedDigit()
                .frame(minWidth: 18)
                .foregroundStyle(value == nil ? Color.ddInkSecondary : Color.ddInk)
            Button { step(1) } label: { Image(systemName: "plus") }
                .buttonStyle(.ddCompactStepper)
                .accessibilityLabel("\(title): én mer")
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue(value.map { "\($0)" } ?? "ikke ført")
    }
}

/// Små runde steppere i føringen (mindre enn slagtellerens).
struct DDCompactStepperStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .frame(width: 30, height: 30)
            .foregroundStyle(Color.ddForestInk)
            .background(Circle().fill(configuration.isPressed ? Color.ddEarthDeep : Color.ddEarth))
            .contentShape(Circle())
    }
}

extension ButtonStyle where Self == DDCompactStepperStyle {
    static var ddCompactStepper: DDCompactStepperStyle { DDCompactStepperStyle() }
}
