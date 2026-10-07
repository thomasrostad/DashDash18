import Charts
import GolfgutuCore
import SwiftUI

/// Trend over tid: brutto mot par per fullført runde, med glidende snitt.
struct StatsTrendChart: View {
    let lines: [RoundLine]
    let window: Int

    private struct Point: Identifiable {
        let id: Int
        let date: Date
        let toPar: Int
        let average: Double
    }

    private var points: [Point] {
        let values = lines.map { Double($0.toPar) }
        let avg = PlayerStats.movingAverage(values, window: window)
        return lines.enumerated().compactMap { i, l in
            StatsFormat.date(l.date).map { Point(id: i, date: $0, toPar: l.toPar, average: avg[i]) }
        }
    }

    var body: some View {
        Chart {
            ForEach(points) { p in
                PointMark(x: .value("Dato", p.date), y: .value("Mot par", p.toPar))
                    .symbolSize(40)
                    .foregroundStyle(by: .value("Serie", "Runde"))
            }
            ForEach(points) { p in
                LineMark(x: .value("Dato", p.date), y: .value("Mot par", p.average))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(by: .value("Serie", "Snitt siste \(window)"))
            }
            RuleMark(y: .value("Par", 0))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(Color.ddHairline)
        }
        .chartForegroundStyleScale([
            "Runde": Color.ddInkSecondary.opacity(0.55),
            "Snitt siste \(window)": Color.ddForest,
        ])
        .chartLegend(position: .top, alignment: .leading)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(Color.ddRule)
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(StatsFormat.toPar(v)).font(.ddCaption) }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits)).font(.ddCaption)
            }
        }
        .frame(height: 190)
        .environment(\.locale, StatsFormat.locale)
        .accessibilityLabel("Brutto mot par per runde over tid")
    }
}

/// Fordelingen av hullene brutto mot par.
struct StatsDistributionChart: View {
    let distribution: ScoreDistribution

    var body: some View {
        Chart(ScoreBucket.allCases, id: \.self) { bucket in
            BarMark(x: .value("Resultat", bucket.label), y: .value("Andel", distribution.share(bucket) ?? 0))
                .cornerRadius(4)
                .foregroundStyle(Color.ddForest)
                .annotation(position: .top, spacing: 4) {
                    Text(StatsFormat.percent(distribution.share(bucket) ?? 0))
                        .font(.ddCaption)
                        .monospacedDigit()
                        .foregroundStyle(Color.ddInkSecondary)
                }
                .accessibilityLabel(bucket.label)
                .accessibilityValue("\(distribution.count(bucket)) hull, \(StatsFormat.percent(distribution.share(bucket) ?? 0))")
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks { _ in AxisValueLabel().font(.ddCaption) }
        }
        .frame(height: 160)
        .environment(\.locale, StatsFormat.locale)
    }
}

/// Handicapindeksen over tid (WHS), etter hver runde som ga en.
struct StatsHandicapChart: View {
    let revisions: [WHS.Revision]

    private struct Point: Identifiable {
        let id: String
        let date: Date
        let index: Double
    }

    private var points: [Point] {
        revisions.compactMap { r in
            guard let i = r.index, let d = StatsFormat.date(r.date) else { return nil }
            return Point(id: r.scoreID, date: d, index: i)
        }
    }

    var body: some View {
        Chart(points) { p in
            LineMark(x: .value("Dato", p.date), y: .value("Indeks", p.index))
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                .foregroundStyle(Color.ddForest)
            PointMark(x: .value("Dato", p.date), y: .value("Indeks", p.index))
                .symbolSize(36)
                .foregroundStyle(Color.ddForest)
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(Color.ddRule)
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(StatsFormat.index(v)).font(.ddCaption) }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits)).font(.ddCaption)
            }
        }
        .frame(height: 170)
        .environment(\.locale, StatsFormat.locale)
        .accessibilityLabel("Handicapindeks over tid")
    }
}
