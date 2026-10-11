import SafariServices
import SwiftUI

/// In-app browser for web pages (privacy policy, terms, support) without leaving the app.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let vc = SFSafariViewController(url: url)
        vc.preferredControlTintColor = UIColor(Theme.lime)
        vc.dismissButtonStyle = .close
        return vc
    }

    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}

/// `sheet(item:)` value for a web page.
struct WebPage: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
