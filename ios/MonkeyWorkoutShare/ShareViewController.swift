import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Share → MonkeyFit (#909 A): takes the post's link, caption and screenshots from TikTok, Instagram or any app, keeps
/// them for the app (`VideoInbox`); the next time MonkeyFit opens, *Save from a video* shows them and Coach reads them.
/// Nothing is sent from here. (Share extensions can't open their app, so the card says where it waits.)
final class ShareViewController: UIViewController {
    private let state = ShareState()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let host = UIHostingController(rootView: ShareCard(state: state, close: { [weak self] in self?.finish() }))
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        Task { await collect() }
    }

    /// Link, text and up to 4 images from the shared items.
    private func collect() async {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        var link: String?
        var texts: [String] = []
        var jpegs: [Data] = []
        for p in providers {
            if p.hasItemConformingToTypeIdentifier(UTType.url.identifier),
               let url = try? await p.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) as? URL,
               url.scheme == "https" || url.scheme == "http" {
                if link == nil { link = url.absoluteString }
            } else if p.hasItemConformingToTypeIdentifier(UTType.image.identifier), jpegs.count < 4 {
                let item = try? await p.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil)
                let image = (item as? UIImage) ?? (item as? Data).flatMap(UIImage.init(data:))
                    ?? (item as? URL).flatMap { try? Data(contentsOf: $0) }.flatMap(UIImage.init(data:))
                if let image, let jpeg = Self.jpeg(image) { jpegs.append(jpeg) }
            } else if p.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                      let text = try? await p.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) as? String {
                texts.append(text)
            }
        }
        let text = texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let saved = (link != nil || !text.isEmpty || !jpegs.isEmpty)
            && VideoInbox.put(link: link, text: text.isEmpty ? nil : text, jpegs: jpegs)
        await MainActor.run {
            state.platform = link.flatMap { URL(string: $0)?.host() }.map(Self.platform)
            state.hasCaption = !text.isEmpty
            state.shots = jpegs.count
            state.phase = saved ? .ready : .empty
        }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    private static func platform(_ host: String) -> String {
        if host.contains("tiktok") { return "TikTok" }
        if host.contains("instagram") || host == "instagr.am" { return "Instagram" }
        if host.contains("youtube") || host == "youtu.be" { return "YouTube" }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    /// Longest side 1280 px, JPEG under 1.4 MB (the server takes 1.5 MB).
    private static func jpeg(_ image: UIImage) -> Data? {
        let scale = min(1, 1280 / max(image.size.width, image.size.height, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        for q in [0.7, 0.5, 0.35] as [CGFloat] {
            if let d = small.jpegData(compressionQuality: q), d.count < 1_400_000 { return d }
        }
        return nil
    }
}

@MainActor @Observable
final class ShareState {
    enum Phase { case reading, ready, empty }
    var phase = Phase.reading
    var platform: String?
    var hasCaption = false
    var shots = 0
}

/// The card over the host app (design A): what was taken and where it waits.
private struct ShareCard: View {
    let state: ShareState
    let close: () -> Void

    var body: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("🐵 MONKEYFIT").font(.system(size: 11, weight: .heavy, design: .rounded)).tracking(1.4).opacity(0.85)
                    Spacer()
                    Button(action: close) {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .heavy))
                            .frame(width: 30, height: 30)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.black.opacity(0.25)))
                    }
                    .accessibilityLabel("Close")
                }
                switch state.phase {
                case .reading:
                    HStack(spacing: 8) { ProgressView().tint(.white); Text("Taking the post…") }
                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                case .empty:
                    Text("Nothing to save here").font(.system(size: 22, weight: .black, design: .rounded))
                    Text("Share a post's link, its caption or screenshots of the moves.")
                        .font(.footnote.weight(.semibold)).opacity(0.9)
                case .ready:
                    Text("Workout saved for Coach").font(.system(size: 22, weight: .black, design: .rounded))
                    HStack(spacing: 6) {
                        if let p = state.platform { chip("♪ \(p)") }
                        if state.hasCaption { chip("caption") }
                        if state.shots > 0 { chip(state.shots == 1 ? "1 screenshot" : "\(state.shots) screenshots") }
                    }
                    Text("Open MonkeyFit: it's waiting there, and Coach turns it into your own workout to check and save.")
                        .font(.footnote.weight(.semibold)).opacity(0.9)
                    Button(action: close) {
                        Text("Got it").font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color(red: 0.9, green: 0.26, blue: 0.37))
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Capsule().fill(.white))
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 1, green: 0.6, blue: 0.12), Color(red: 1, green: 0.31, blue: 0.48)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)))
            .padding(16)
        }
        .preferredColorScheme(.dark)
    }

    private func chip(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .heavy, design: .rounded))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white.opacity(0.22)))
    }
}
