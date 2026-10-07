import Foundation
import GolfgutuCore

// Skjemaet for én bane og sjekken av det, som rene typer uten SwiftUI og nettverk.
// Tallfeltene holdes som tekst, så komma fra norsk tastatur og tomme felt tolkes
// her (testbart) og ikke i viewet. Grensene er databasens (`sql/001_skjema_v1.sql`)
// og PWA-ens (`handleLagreBane`, `baneSkjema`), ikke regelverdier.

/// Ett hull i skjemaet. `par == nil` betyr «ikke skrevet inn», som PWA-ens tomme felt:
/// appen gjetter ikke par (se `baneSkjema` i `app-nytt.js`, meldt 16.09.2026).
nonisolated struct HoleDraft: Equatable, Identifiable, Sendable {
    var number: Int
    var par: Int?
    var strokeIndexText: String = ""
    var lengthText: String = ""

    var id: Int { number }
}

/// Banen slik arrangøren redigerer den.
nonisolated struct CourseDraft: Equatable, Sendable {
    var name: String = ""
    var externalName: String = ""
    var courseRatingText: String = ""
    var slopeText: String = ""
    var inUse: Bool = true
    /// Simulator eller ekte bane. Lagres bare når `CourseKindFeature.isEnabled` (sql/016).
    var kind: CourseKind = .simulator
    var holes: [HoleDraft]

    /// Hvor mange hull en bane kan ha (`baneErKlar`).
    static let holeCounts = [9, 18]

    /// Ny, tom bane. Par står tomt til det leses av skjermen.
    init(holeCount: Int = 18) {
        holes = (1...holeCount).map { HoleDraft(number: $0) }
    }

    /// Fra lagrede rader. Hull som mangler i databasen blir tomme.
    init(course: CourseRow, holes rows: [CourseHoleRecord], kind: CourseKind = .simulator) {
        name = course.name
        self.kind = kind
        externalName = course.externalName ?? ""
        courseRatingText = course.courseRating.map(CourseInput.decimalText) ?? ""
        slopeText = course.slopeRating.map(String.init) ?? ""
        inUse = course.inUse
        let count = rows.count > 9 ? 18 : (rows.isEmpty ? 18 : 9)
        let byNumber = Dictionary(rows.map { ($0.holeNumber, $0) }, uniquingKeysWith: { first, _ in first })
        holes = (1...count).map { number in
            guard let row = byNumber[number] else { return HoleDraft(number: number) }
            return HoleDraft(
                number: number,
                par: row.par,
                strokeIndexText: row.strokeIndex.map(String.init) ?? "",
                lengthText: row.lengthM.map(String.init) ?? ""
            )
        }
    }

    var holeCount: Int { holes.count }

    /// Bytter mellom 9 og 18 hull. Det som er skrevet inn på hull 1–9 beholdes.
    mutating func setHoleCount(_ count: Int) {
        guard Self.holeCounts.contains(count), count != holes.count else { return }
        if count < holes.count {
            holes = Array(holes.prefix(count))
        } else {
            holes += (holes.count + 1...count).map { HoleDraft(number: $0) }
        }
    }

    /// Summen av parene som er skrevet inn, eller nil hvis noen mangler.
    var par: Int? { CourseMath.par(holes.map(\.par)) }

    /// «Klar» eller hva som mangler, slik banen blir hvis den lagres nå.
    var readiness: CourseReadiness { CourseReadiness(pars: holes.map(\.par)) }

    /// Navnet i simulatoren gjelder bare simulatorbaner.
    var usesExternalName: Bool { kind == .simulator }

    /// Hullene som ikke har par ennå.
    var holesMissingPar: [Int] { holes.filter { $0.par == nil }.map(\.number) }

    /// Standardbanen (`DEFAULT_PAR`, par 72 over 18 hull, par 36 over 9) for antall hull.
    var standardPars: [Int] { Array(Course.defaultPar.prefix(holes.count)) }

    /// Summen av standardparene, til knappen «Fyll standard par 72».
    var standardPar: Int { standardPars.reduce(0, +) }

    /// Et forslag arrangøren ber om selv: fyller hullene uten par med standardbanen.
    /// Par som alt er skrevet inn, røres ikke. Appen gjetter ellers aldri par (`baneSkjema`).
    mutating func fillStandardPar() {
        let pars = standardPars
        for i in holes.indices where holes[i].par == nil && pars.indices.contains(i) {
            holes[i].par = pars[i]
        }
    }

    /// Hurtigknappen for par: trykk på valgt par igjen tømmer hullet.
    mutating func tapPar(_ par: Int, hole number: Int) {
        guard let i = holes.firstIndex(where: { $0.number == number }) else { return }
        holes[i].par = holes[i].par == par ? nil : par
    }

    /// Sjekker skjemaet. Gir banen klar til lagring når ingen feil sperrer.
    func validate() -> CourseValidation {
        var issues: [CourseIssue] = []

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            issues.append(.nameMissing)
        } else if trimmedName.count > CourseInput.maxNameLength {
            issues.append(.nameTooLong)
        }
        let trimmedExternal = usesExternalName ? externalName.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        if trimmedExternal.count > CourseInput.maxNameLength {
            issues.append(.externalNameTooLong)
        }

        var courseRating: Double?
        switch CourseInput.decimal(courseRatingText) {
        case .success(let value):
            if let value, !CourseInput.courseRatingRange.contains(value) {
                issues.append(.courseRatingOutOfRange)
            } else {
                courseRating = value
            }
        case .failure: issues.append(.courseRatingOutOfRange)
        }

        var slope: Int?
        switch CourseInput.integer(slopeText) {
        case .success(let value):
            if let value, !CourseInput.slopeRange.contains(value) {
                issues.append(.slopeOutOfRange)
            } else {
                slope = value
            }
        case .failure: issues.append(.slopeOutOfRange)
        }

        let count = holes.count
        if !Self.holeCounts.contains(count) {
            issues.append(.holeCount(count))
        }

        let noParAtAll = holes.allSatisfy { $0.par == nil }
        if noParAtAll {
            issues.append(.notSetUp)
        }

        var validHoles: [CourseHoleInput] = []
        var missingPar: [Int] = []
        var missingIndex: [Int] = []
        var holesByIndex: [Int: [Int]] = [:]
        for hole in holes {
            let number = hole.number
            if hole.par == nil {
                if !noParAtAll { missingPar.append(number) }
            } else if !Course.isValidPar(hole.par) {
                issues.append(.invalidPar(hole: number))
            }

            var strokeIndex: Int?
            switch CourseInput.integer(hole.strokeIndexText) {
            case .success(let value):
                if let value {
                    if (1...count).contains(value) {
                        strokeIndex = value
                        holesByIndex[value, default: []].append(number)
                    } else {
                        issues.append(.strokeIndexOutOfRange(hole: number, max: count))
                    }
                } else {
                    missingIndex.append(number)
                }
            case .failure:
                issues.append(.strokeIndexOutOfRange(hole: number, max: count))
            }

            var length: Int?
            switch CourseInput.integer(hole.lengthText) {
            case .success(let value):
                if let value, !CourseInput.lengthRange.contains(value) {
                    issues.append(.lengthOutOfRange(hole: number))
                } else {
                    length = value
                }
            case .failure:
                issues.append(.lengthOutOfRange(hole: number))
            }

            if let par = hole.par {
                validHoles.append(CourseHoleInput(number: number, par: par, strokeIndex: strokeIndex, lengthM: length))
            }
        }
        if !missingPar.isEmpty {
            issues.append(.missingPar(holes: missingPar))
        }
        for (index, numbers) in holesByIndex.sorted(by: { $0.key < $1.key }) where numbers.count > 1 {
            issues.append(.duplicateStrokeIndex(index, holes: numbers))
        }
        if !noParAtAll, !missingIndex.isEmpty {
            issues.append(.missingStrokeIndex(holes: missingIndex))
        }

        // Advarsel som i PWA-en (`hullMedRarLengde`): lagres likevel.
        let coreHoles = validHoles.map { CourseHole(par: $0.par, si: $0.strokeIndex, meters: $0.lengthM.map(Double.init)) }
        let odd = Course.holesWithOddLength(coreHoles)
        for hole in odd {
            let number = validHoles[hole.number - 1].number
            issues.append(.oddLength(hole: number, par: hole.par ?? 0, meters: Int(hole.meters ?? 0)))
        }

        let blocking = issues.contains { $0.isBlocking }
        let input = blocking ? nil : CourseInputValues(
            name: trimmedName,
            externalName: trimmedExternal.isEmpty ? nil : trimmedExternal,
            courseRating: courseRating,
            slopeRating: slope,
            inUse: inUse,
            holes: noParAtAll ? [] : validHoles,
            kind: kind
        )
        return CourseValidation(issues: issues, values: input)
    }
}

/// Et hull klart til lagring.
nonisolated struct CourseHoleInput: Equatable, Sendable {
    var number: Int
    var par: Int
    var strokeIndex: Int?
    var lengthM: Int?

    func record(courseID: UUID) -> CourseHoleRecord {
        CourseHoleRecord(courseID: courseID, holeNumber: number, par: par, strokeIndex: strokeIndex, lengthM: lengthM)
    }
}

/// Banen klar til lagring. `holes` er tom når banen ikke er satt opp ennå.
nonisolated struct CourseInputValues: Equatable, Sendable {
    var name: String
    var externalName: String?
    var courseRating: Double?
    var slopeRating: Int?
    var inUse: Bool
    var holes: [CourseHoleInput]
    var kind: CourseKind = .simulator

    /// GolfgutuCore-banen, for `baneErKlar` og lengdesjekken.
    var coreCourse: Course {
        Course(
            name: name,
            par: CourseMath.par(holes.map(\.par)),
            courseRating: courseRating,
            slopeRating: slopeRating.map(Double.init),
            holes: holes.isEmpty ? nil : holes.map { CourseHole(par: $0.par, si: $0.strokeIndex, meters: $0.lengthM.map(Double.init)) }
        )
    }
}

nonisolated struct CourseValidation: Equatable, Sendable {
    var issues: [CourseIssue]
    /// nil når noe sperrer.
    var values: CourseInputValues?

    var errors: [CourseIssue] { issues.filter(\.isBlocking) }
    var warnings: [CourseIssue] { issues.filter { !$0.isBlocking } }
    var canSave: Bool { values != nil }
}

/// Det som er galt eller rart i skjemaet. Feil sperrer lagring, advarsler gjør ikke.
nonisolated enum CourseIssue: Equatable, Sendable {
    case nameMissing
    case nameTooLong
    case externalNameTooLong
    case courseRatingOutOfRange
    case slopeOutOfRange
    case holeCount(Int)
    case missingPar(holes: [Int])
    case invalidPar(hole: Int)
    case strokeIndexOutOfRange(hole: Int, max: Int)
    case duplicateStrokeIndex(Int, holes: [Int])
    case lengthOutOfRange(hole: Int)
    // Advarsler
    case notSetUp
    case missingStrokeIndex(holes: [Int])
    case oddLength(hole: Int, par: Int, meters: Int)

    var isBlocking: Bool {
        switch self {
        case .notSetUp, .missingStrokeIndex, .oddLength: false
        default: true
        }
    }

    var message: String {
        switch self {
        case .nameMissing: "Gi banen et navn."
        case .nameTooLong: "Navnet kan ha høyst \(CourseInput.maxNameLength) tegn."
        case .externalNameTooLong: "Navnet i simulatoren kan ha høyst \(CourseInput.maxNameLength) tegn."
        case .courseRatingOutOfRange:
            "Course Rating må være et tall mellom \(Int(CourseInput.courseRatingRange.lowerBound)) og \(Int(CourseInput.courseRatingRange.upperBound)), eller stå tom."
        case .slopeOutOfRange:
            "Slope må være et heltall mellom \(CourseInput.slopeRange.lowerBound) og \(CourseInput.slopeRange.upperBound), eller stå tom."
        case .holeCount(let count): "En bane har 9 eller 18 hull, ikke \(count)."
        case .missingPar(let holes): "Par mangler på \(CourseInput.holeList(holes)). Les det av skjermen."
        case .invalidPar(let hole): "Hull \(hole): par må være mellom 3 og 6."
        case .strokeIndexOutOfRange(let hole, let max): "Hull \(hole): indeks må være mellom 1 og \(max), eller stå tom."
        case .duplicateStrokeIndex(let index, let holes): "\(CourseInput.holeList(holes).capitalizedFirst) har samme indeks (\(index))."
        case .lengthOutOfRange(let hole):
            "Hull \(hole): lengden må være mellom \(CourseInput.lengthRange.lowerBound) og \(CourseInput.lengthRange.upperBound) meter, eller stå tom."
        case .notSetUp: "Ingen par er skrevet inn. Banen lagres, men står som ikke satt opp."
        case .missingStrokeIndex(let holes):
            "Indeks mangler på \(CourseInput.holeList(holes)). Den trengs bare når appen selv deler ut slagene."
        case .oddLength(let hole, let par, let meters): "Hull \(hole): \(meters) m er uvanlig for en par \(par). Stemmer det med skjermen?"
        }
    }
}

/// Tolking av tallfeltene og databasens grenser for banen.
nonisolated enum CourseInput {
    /// Valgene i par-feltet: det `Course.isValidPar` godtar (og `course_holes.par`).
    static let parChoices = Array(3...6)
    /// `courses.name` og `external_name`: høyst 80 tegn.
    static let maxNameLength = 80
    /// PWA-ens grense (`handleLagreBane`). Databasen tåler 20–90.
    static let courseRatingRange: ClosedRange<Double> = 50...90
    /// `courses.slope_rating`.
    static let slopeRange: ClosedRange<Int> = 55...155
    /// `course_holes.length_m`.
    static let lengthRange: ClosedRange<Int> = 50...700

    enum ParseError: Error { case notANumber }

    /// Desimaltall med komma eller punktum, rundet til én desimal. Tomt = nil.
    static func decimal(_ raw: String) -> Result<Double?, ParseError> {
        let text = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        if text.isEmpty { return .success(nil) }
        guard let value = Double(text), value.isFinite else { return .failure(.notANumber) }
        return .success((value * 10).rounded() / 10)
    }

    /// Heltall. Tomt = nil.
    static func integer(_ raw: String) -> Result<Int?, ParseError> {
        let text = raw.trimmingCharacters(in: .whitespaces)
        if text.isEmpty { return .success(nil) }
        guard let value = Int(text) else { return .failure(.notANumber) }
        return .success(value)
    }

    /// `72.0` → «72», `71.4` → «71,4».
    static func decimalText(_ value: Double) -> String {
        JS.norwegianString(value)
    }

    /// «hull 3», «hull 3 og 7», «hull 3, 7 og 12».
    static func holeList(_ holes: [Int]) -> String {
        let numbers = holes.map(String.init)
        guard let last = numbers.last else { return "" }
        if numbers.count == 1 { return "hull \(last)" }
        return "hull " + numbers.dropLast().joined(separator: ", ") + " og " + last
    }
}

/// Utregninger for banelista.
nonisolated enum CourseMath {
    /// Banens par regnet fra hullene (lagres ikke, se skjemaet). nil hvis et hull mangler par
    /// eller det ikke er noen hull.
    static func par(_ pars: [Int?]) -> Int? {
        guard !pars.isEmpty else { return nil }
        var sum = 0
        for par in pars {
            guard let par else { return nil }
            sum += par
        }
        return sum
    }
}

private extension String {
    nonisolated var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
