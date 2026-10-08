import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// Delingskortet: grønn topp med overskrift, hvite rader med plass, navn og verdi.
/// Tegnes alltid i lys modus, så bildet ser likt ut hos mottakeren.
struct ResultShareCard: View {
    let share: ResultShare

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(share.eyebrow)
                    .ddEyebrow(color: .ddGold)
                Text(share.title)
                    .font(.ddTitle)
                    .foregroundStyle(Color.ddOnDark)
                if let subtitle = share.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.ddCallout)
                        .foregroundStyle(Color.ddOnDark.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DDSpacing.xl)
            .background(Color.ddHeroCard)

            VStack(spacing: 0) {
                ForEach(Array(share.lines.enumerated()), id: \.offset) { i, line in
                    row(line)
                    if i < share.lines.count - 1 { DDDivider() }
                }
            }
            .padding(.horizontal, DDSpacing.xl)
            .padding(.vertical, DDSpacing.s)
            .background(Color.ddCard)

            Text("Atten")
                .ddEyebrow()
                .frame(maxWidth: .infinity)
                .padding(.vertical, DDSpacing.m)
                .background(Color.ddCard)
        }
        .clipShape(.rect(cornerRadius: DDRadius.cardLarge, style: .continuous))
        .padding(DDSpacing.l)
        .frame(width: 390)
        .background(Color.ddBackground)
        .environment(\.colorScheme, .light)
        // Bildet er det samme for alle: fast tekststørrelse, ikke avsenderens.
        .environment(\.dynamicTypeSize, .large)
    }

    private func row(_ line: ResultShare.Line) -> some View {
        HStack(spacing: DDSpacing.m) {
            Text(line.place.map { "\($0)." } ?? "")
                .font(.ddMonoSmall)
                .monospacedDigit()
                .foregroundStyle(Color.ddInkSecondary)
                .frame(minWidth: 26, alignment: .leading)
            Text(line.name)
                .font(line.isMe ? .ddNameSmall : .ddBody)
                .foregroundStyle(Color.ddForestInk)
                .lineLimit(1)
            Spacer(minLength: DDSpacing.s)
            // Et langt navn kortes av; verdien skal alltid stå helt.
            Text(line.value)
                .font(.ddNumber)
                .monospacedDigit()
                .foregroundStyle(Color.ddInk)
                .fixedSize()
                .layoutPriority(1)
        }
        .padding(.vertical, 10)
    }
}

/// Tegner delingskortet til et bilde.
enum ResultShareRenderer {
    static func image(_ share: ResultShare) -> UIImage? {
        let renderer = ImageRenderer(content: ResultShareCard(share: share))
        renderer.scale = 3
        return renderer.uiImage
    }

    static func png(_ share: ResultShare) -> Data? {
        image(share)?.pngData()
    }
}

/// Det som går i delingsarket: bildet først, teksten som fallback for mål som ikke tar bilder.
nonisolated struct ResultShareItem: Transferable {
    let share: ResultShare

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            guard let data = await ResultShareRenderer.png(item.share) else {
                throw CocoaError(.fileWriteUnknown)
            }
            return data
        }
        .suggestedFileName { $0.share.fileName }
        ProxyRepresentation { item in item.share.text }
    }
}

/// Delingsknappen i verktøylinja.
struct ResultShareButton: View {
    let share: ResultShare
    @State private var preview: UIImage?

    var body: some View {
        ShareLink(item: ResultShareItem(share: share), subject: Text(share.heading),
                  preview: SharePreview(share.heading, image: previewImage)) {
            Label("Del", systemImage: "square.and.arrow.up")
        }
        .task(id: share) { preview = ResultShareRenderer.image(share) }
    }

    private var previewImage: Image {
        preview.map(Image.init(uiImage:)) ?? Image(systemName: "trophy")
    }
}

#Preview {
    ScrollView {
        ResultShareCard(share: ResultShare(
            eyebrow: "Jakkeracet", title: "Sesong 2026", subtitle: "3 av 7 kvelder spilt",
            lines: [
                .init(place: 1, name: "Anders", value: "12,5 p", isMe: false),
                .init(place: 2, name: "Bjørn", value: "10 p", isMe: true),
                .init(place: 3, name: "Åse", value: "7 p", isMe: false),
            ]))
    }
}
