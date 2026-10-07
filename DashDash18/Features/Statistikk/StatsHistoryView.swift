import GolfgutuCore
import SwiftUI

/// Alle runder i utvalget, nyeste først, med samme filter som oversikten.
struct StatsHistoryView: View {
    @Bindable var model: StatsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DDSpacing.cardGap) {
                StatsFilterBar(model: model)
                let rounds = model.summary.rounds
                if rounds.isEmpty {
                    StatsEmptyCard(text: "Ingen runder i dette utvalget.",
                                   resetAction: model.isFiltered ? { model.resetFilter() } : nil)
                } else {
                    DDSectionLabel("\(rounds.count) runder") { Text("brutto · stableford").ddEyebrow() }
                        .padding(.top, DDSpacing.s)
                    VStack(spacing: 0) {
                        ForEach(rounds) { line in
                            StatsRoundRowView(line: line)
                            if line.id != rounds.last?.id { DDDivider() }
                        }
                    }
                    .ddCard(padding: DDSpacing.l)
                }
            }
            .padding(.horizontal, DDSpacing.gutter)
            .padding(.vertical, DDSpacing.l)
        }
        .ddScreenBackground()
        .navigationTitle("Runder")
        .ddNavigationChrome()
    }
}

/// Én runde: dato, bane og type, brutto mot par og stableford.
struct StatsRoundRowView: View {
    let line: RoundLine

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(line.courseName ?? line.title ?? "Runde")
                    .font(.ddBody)
                    .foregroundStyle(Color.ddInk)
                HStack(spacing: 6) {
                    Text(StatsFormat.shortDate(line.date))
                    Text("·")
                    Text(line.kind == .club ? (line.clubName ?? "Klubb") : "Løs runde")
                    if line.holeCount != 18 { Text("· \(line.holeCount) hull") }
                }
                .font(.ddCaption)
                .foregroundStyle(Color.ddInkSecondary)
                if !line.isComplete {
                    DDPill("\(line.holesPlayed) av \(line.holeCount) hull", tone: .earth)
                        .fixedSize()
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(line.gross)")
                    .font(.ddNumber)
                    .monospacedDigit()
                Text(StatsFormat.toPar(line.toPar))
                    .font(.ddCaption)
                    .monospacedDigit()
                    .foregroundStyle(Color.ddInkSecondary)
            }
            .frame(minWidth: 40, alignment: .trailing)
            Text("\(line.stableford) p")
                .font(.ddBody)
                .monospacedDigit()
                .foregroundStyle(Color.ddInkSecondary)
                .frame(minWidth: 44, alignment: .trailing)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

/// Spillerens beste brutto og netto per bane.
struct StatsRecordsView: View {
    @Bindable var model: StatsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DDSpacing.cardGap) {
                StatsFilterBar(model: model)
                let records = model.summary.courseRecords
                if records.isEmpty {
                    StatsEmptyCard(text: "Banerekordene kommer når du har fullført en runde.",
                                   resetAction: model.isFiltered ? { model.resetFilter() } : nil)
                } else {
                    ForEach(records) { record in
                        StatsRecordCard(record: record)
                    }
                    DDFooter("Bare fullførte runder. Netto er brutto minus slagene du fikk i runden.")
                        .padding(.horizontal, 2)
                }
            }
            .padding(.horizontal, DDSpacing.gutter)
            .padding(.vertical, DDSpacing.l)
        }
        .ddScreenBackground()
        .navigationTitle("Banerekorder")
        .ddNavigationChrome()
    }
}

struct StatsRecordCard: View {
    let record: CourseRecord

    var body: some View {
        VStack(alignment: .leading, spacing: DDSpacing.m) {
            HStack(alignment: .firstTextBaseline) {
                Text(StatsFormat.layout(courseName: record.courseName, layoutKey: record.layoutKey,
                                        holeCount: record.holeCount))
                    .font(.ddNameSmall)
                    .foregroundStyle(Color.ddForestInk)
                Spacer(minLength: 8)
                Text(record.rounds == 1 ? "1 runde" : "\(record.rounds) runder").ddEyebrow()
            }
            HStack(spacing: DDSpacing.cardGap) {
                cell("Brutto", value: "\(record.bestGross.gross)",
                     detail: "\(StatsFormat.toPar(record.bestGross.toPar)) · \(StatsFormat.shortDate(record.bestGross.date))")
                cell("Netto", value: "\(record.bestNet.net)",
                     detail: StatsFormat.shortDate(record.bestNet.date))
            }
        }
        .ddCard()
        .accessibilityElement(children: .combine)
    }

    private func cell(_ label: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).ddEyebrow()
            Text(value)
                .font(.ddNumberLarge)
                .monospacedDigit()
                .foregroundStyle(Color.ddInk)
            Text(detail)
                .font(.ddCaption)
                .foregroundStyle(Color.ddInkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
