import DashImportKit
import Foundation

let usage = """
Bruk:
  dashimport <snapshot-mappe> <ut.sql> [--club-id <uuid>] [--club-name <navn>] [--force]
      Leser <snapshot-mappe>/snapshot.json (fra sql/import/export_pwa.sql) og skriver én
      idempotent SQL-fil for appens database. Kjører ingenting mot noen database.
  dashimport parity <snapshot-mappe> [--club-id <uuid>]
      Regner jakketabellen og stablefordsummen med GolfgutuCore fra de importerte dataene og
      sammenligner rundepoengene med PWA-ens round_points. Avslutter med kode 1 ved avvik.

Snapshot- og utmappene skal ligge utenfor git (import-snapshot/ og import-out/ er ignorert).
"""

func fail(_ message: String, code: Int32 = 2) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

var args = Array(CommandLine.arguments.dropFirst())
var options = ImportOptions()
var force = false

@MainActor func takeValue(_ flag: String) -> String? {
    guard let i = args.firstIndex(of: flag) else { return nil }
    guard i + 1 < args.count else { fail("\(flag) mangler verdi.\n\n\(usage)") }
    let value = args[i + 1]
    args.removeSubrange(i...(i + 1))
    return value
}

if let raw = takeValue("--club-id") {
    guard let id = UUID(uuidString: raw) else { fail("--club-id er ikke en UUID: \(raw)") }
    options.clubID = id
}
options.clubName = takeValue("--club-name")
if let i = args.firstIndex(of: "--force") { force = true; args.remove(at: i) }
if args.contains("-h") || args.contains("--help") || args.isEmpty { print(usage); exit(args.isEmpty ? 2 : 0) }

func printWarnings(_ plan: ImportPlan) {
    guard !plan.warnings.isEmpty else { return }
    FileHandle.standardError.write(Data("Merknader (\(plan.warnings.count)):\n".utf8))
    for w in plan.warnings { FileHandle.standardError.write(Data("  - \(w)\n".utf8)) }
}

do {
    if args.first == "parity" {
        guard args.count == 2 else { fail(usage) }
        let (plan, _) = try ImportRun.plan(snapshotDirectory: URL(fileURLWithPath: args[1]), options: options)
        printWarnings(plan)
        let report = Parity.check(plan)
        print(Parity.render(report), terminator: "")
        exit(report.isOK ? 0 : 1)
    }

    guard args.count == 2 else { fail(usage) }
    let out = URL(fileURLWithPath: args[1])
    if ImportRun.isRiskyOutput(out) && !force {
        fail("Utfila havner i et git-arbeidstre. Bruk import-out/ (ignorert) eller en mappe utenfor repoet, eller --force.")
    }
    let (sql, plan) = try ImportRun.sql(snapshotDirectory: URL(fileURLWithPath: args[0]), options: options)
    printWarnings(plan)
    try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(sql.utf8).write(to: out)
    print("Skrev \(out.path): \(plan.members.count) spillere, \(plan.events.count) kvelder, \(plan.rounds.count) runder, "
          + "\(plan.scores.count) scorer. Ingenting er kjørt mot noen database.")
} catch {
    fail("Feil: \(error)", code: 1)
}
