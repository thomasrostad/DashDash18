import Supabase
import SwiftUI
import Vision
import VisionKit

/// «Min kode»: QR-koden andre skanner for å følge deg med en gang, koden i tekst, og «Ny kode».
struct FollowCodeView: View {
    let client: SupabaseClient
    @State private var link: FollowLink?
    @State private var isWorking = false
    @State private var confirmsRenew = false
    @State private var error: String?

    var body: some View {
        DDList {
            Section {
                VStack(spacing: DDSpacing.m) {
                    if let link, let image = QRCode.image(for: link.url.absoluteString) {
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 240)
                            .padding(DDSpacing.m)
                            .background(Color.white, in: .rect(cornerRadius: 16))
                            .accessibilityLabel("QR-kode for å følge deg")
                        Text(link.display)
                            .font(.ddTitle)
                            .monospaced()
                            .foregroundStyle(Color.ddInk)
                            .textSelection(.enabled)
                            .accessibilityLabel("Koden er \(link.display)")
                    } else if isWorking {
                        ProgressView().frame(height: 240)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DDSpacing.s)
                if let link {
                    ShareLink(item: link.url) {
                        Label("Del lenken", systemImage: "square.and.arrow.up").labelStyle(DDIconLabelStyle())
                    }
                }
                Button { confirmsRenew = true } label: {
                    Label("Ny kode", systemImage: "arrow.triangle.2.circlepath").labelStyle(DDIconLabelStyle())
                }
                .disabled(isWorking)
            } footer: {
                DDFooter("Den som skanner koden, følger deg med en gang, også når du godkjenner nye følgere. Lag en ny kode om den har kommet på avveie.")
            }
            if let error {
                Section { Label(error, systemImage: "exclamationmark.triangle").ddErrorStyle() }
            }
        }
        .navigationTitle("Min kode")
        .ddNavigationChrome()
        .task { await load(renew: false) }
        .confirmationDialog("Lage ny kode?", isPresented: $confirmsRenew, titleVisibility: .visible) {
            Button("Lag ny kode") { Task { await load(renew: true) } }
            Button("Avbryt", role: .cancel) {}
        } message: {
            Text("Den gamle koden slutter å virke.")
        }
    }

    private func load(renew: Bool) async {
        isWorking = true
        defer { isWorking = false }
        do {
            link = try await FollowService(client: client).code(renew: renew)
            error = link == nil ? "Fikk ikke laget koden." : nil
        } catch {
            self.error = FollowService.message(error)
        }
    }
}

/// «Skann kode»: kameraet leser QR-koden (VisionKit), eller du skriver koden. Følger med en gang
/// (`follow_by_code`).
struct FollowScanSheet: View {
    let client: SupabaseClient
    @Environment(\.dismiss) private var dismiss
    @State private var found: FollowLink?
    @State private var typed = ""

    var body: some View {
        NavigationStack {
            Group {
                if let found {
                    FollowByCodeView(client: client, link: found, source: .qr) { dismiss() }
                } else {
                    scanner
                }
            }
            .navigationTitle("Skann kode")
            .navigationBarTitleDisplayMode(.inline)
            .ddNavigationChrome()
            .toolbar {
                DDCancelToolbarItem {
                    Button("Lukk") { dismiss() }.tint(Color.ddOnDark)
                }
            }
        }
        .tint(Color.ddForestInk)
    }

    private var scanner: some View {
        DDList {
            if FollowQRScanner.isAvailable {
                Section {
                    FollowQRScanner { text in
                        if found == nil, let link = FollowLink(scanned: text) { found = link }
                    }
                    .frame(height: 320)
                    .clipShape(.rect(cornerRadius: 16))
                    .listRowInsets(EdgeInsets())
                    .accessibilityLabel("Kamera. Pek på QR-koden.")
                } footer: {
                    DDFooter("Pek kameraet på koden under Deg → Følger → Min kode på telefonen til den du vil følge.")
                }
            }
            Section {
                TextField("Koden, for eksempel ABCD-EFGH", text: $typed)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .ddField()
                Button("Følg") { found = FollowLink(scanned: typed) }
                    .buttonStyle(.dd(.primary, fullWidth: true))
                    .disabled(FollowLink(scanned: typed) == nil)
            } header: {
                DDHeader("Eller skriv koden")
            }
        }
    }
}

/// Følger eieren av koden og viser svaret. Brukes etter skanning og fra lenken.
struct FollowByCodeView: View {
    let client: SupabaseClient
    let link: FollowLink
    let source: FollowSource
    let done: () -> Void
    @State private var result: FollowByCodeResult?
    @State private var error: String?

    var body: some View {
        VStack(spacing: DDSpacing.l) {
            if let result {
                Image(systemName: result.isNotFound ? "questionmark.circle" : "person.crop.circle.badge.checkmark")
                    .font(.system(size: 48))
                    .foregroundStyle(result.isNotFound ? Color.ddInkSecondary : Color.ddForestInk)
                    .accessibilityHidden(true)
                Text(result.message)
                    .font(.ddBodyEmphasis)
                    .foregroundStyle(Color.ddInk)
                    .multilineTextAlignment(.center)
                if !result.isNotFound {
                    Text("Rundene deres kommer under «Følger» på Hjem.")
                        .font(.ddCallout)
                        .foregroundStyle(Color.ddInkSecondary)
                        .multilineTextAlignment(.center)
                }
                Button("Ferdig", action: done).buttonStyle(.dd(.primary))
            } else if let error {
                Label(error, systemImage: "exclamationmark.triangle").ddErrorStyle()
                Button("Lukk", action: done).buttonStyle(.dd(.secondary))
            } else {
                ProgressView("Følger …")
            }
        }
        .padding(DDSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ddScreenBackground()
        .task {
            do {
                result = try await FollowService(client: client).follow(link, source: source)
            } catch {
                self.error = FollowService.message(error)
            }
        }
    }
}

/// En følgelenke (`https://dashdash18.com/folg/KODE` eller `dashdash://folg/KODE`) åpnet utenfra.
struct FollowFromLinkView: View {
    let client: SupabaseClient
    let link: FollowLink
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            FollowByCodeView(client: client, link: link, source: .link) { dismiss() }
                .navigationTitle("Følg")
                .navigationBarTitleDisplayMode(.inline)
                .ddNavigationChrome()
        }
        .tint(Color.ddForestInk)
    }
}

/// Kameraet som leser QR-koder (VisionKit `DataScannerViewController`). Bruker kameratillatelsen
/// appen alt har (`NSCameraUsageDescription`).
struct FollowQRScanner: UIViewControllerRepresentable {
    let onFound: (String) -> Void

    /// Støtter telefonen skanning, og er kameraet tilgjengelig (ikke i simulatoren)?
    static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                                qualityLevel: .balanced, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onFound: (String) -> Void

        init(onFound: @escaping (String) -> Void) {
            self.onFound = onFound
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let code) = item, let text = code.payloadStringValue {
                    onFound(text)
                }
            }
        }
    }
}
