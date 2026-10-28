import APIClient
import PhotosUI
import SwiftUI
import UIKit
import WorkoutEngine

/// Report a problem (#467, design A + B + C from `report-problem/proposals.png`). A: the page in Settings → Help.
/// B: shake anywhere → screenshot of the screen, draw on it, send. C: Report next to errors, error prefilled.
/// Reports go to the team by email (with screenshots) and, when switched on, as a GitHub issue without the member's name.
enum ReportPref {
    static let shakeKey = "report.shake"
    static var shake: Bool { UserDefaults.standard.object(forKey: shakeKey) as? Bool ?? true }
}

enum ReportKind: String, CaseIterable, Identifiable {
    case bug, broken, idea
    var id: String { rawValue }
    var title: String {
        switch self {
        case .bug: "Bug"
        case .broken: "Not working right"
        case .idea: "Idea"
        }
    }
    var symbol: String {
        switch self {
        case .bug: "ladybug.fill"
        case .broken: "wrench.adjustable.fill"
        case .idea: "lightbulb.fill"
        }
    }
}

enum ReportVia: String { case settings, shake, error }

struct ReportDraft: Identifiable {
    let id = UUID()
    var via: ReportVia
    var kind: ReportKind = .bug
    var area: String
    var screen: String?
    var error: String?
    var shots: [UIImage] = []

    static let areas = ["Train", "Workout player", "Explore", "Progress", "History", "Fuel", "Social", "Apple Watch", "Sync & account", "Settings", howItWorks, "Other"]
    /// Area of a Feels off? report from How it works (#769).
    static let howItWorks = "How it works"

    static func areaName(for tab: MainTab) -> String {
        switch tab {
        case .train: "Train"
        case .explore: "Explore"
        case .progress: "Progress"
        case .fuel: "Fuel"
        case .community: "Social"
        }
    }
}

/// Opens the report screen from anywhere (shake, error buttons) over whatever is on top, sheets included.
@MainActor final class ProblemReporter {
    static let shared = ProblemReporter()
    weak var model: AppModel?
    private var showing = false

    /// What the member is looking at: the Ask Coach focus, else the tab.
    private var screen: String? { CoachAsk.shared.current?.title }

    func open(via: ReportVia, error: String? = nil, area: String? = nil, screenshot: Bool = false) {
        guard let model, model.phase == .signedIn, !showing, let top = Self.topController() else { return }
        let shot = screenshot ? Self.capture() : nil
        var draft = ReportDraft(via: via, kind: error == nil ? .bug : .broken,
                                area: area ?? (screen == nil ? ReportDraft.areaName(for: model.tab) : Self.guessArea(screen!, tab: model.tab)),
                                screen: screen ?? ReportDraft.areaName(for: model.tab), error: error)
        if let shot { draft.shots = [shot] }
        let host = UIHostingController(rootView: NavigationStack {
            ReportProblemView(draft: draft, modal: true, onClose: { [weak self] in
                self?.showing = false
                top.presentedViewController?.dismiss(animated: true)
            })
        }
        .environment(model)
        .preferredColorScheme(.dark)
        .tint(Theme.lime))
        host.isModalInPresentation = true
        showing = true
        top.present(host, animated: true)
    }

    private static func guessArea(_ screen: String, tab: MainTab) -> String {
        let s = screen.lowercased()
        if s.contains("set") || s.contains("player") || s.contains("rest") { return "Workout player" }
        return ReportDraft.areaName(for: tab)
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
    }

    private static func topController() -> UIViewController? {
        var c = keyWindow?.rootViewController
        while let next = c?.presentedViewController { c = next }
        return c
    }

    /// The screen as the member sees it, before the report sheet covers it.
    static func capture() -> UIImage? {
        guard let w = keyWindow else { return nil }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(bounds: w.bounds, format: format).image { _ in _ = w.drawHierarchy(in: w.bounds, afterScreenUpdates: false) }
    }

    /// ≤ 1024 px per side, ≤ 500 KB: what the server accepts.
    static func jpeg(_ image: UIImage) -> Data? {
        let scale = min(1, 1024 / max(image.size.width, image.size.height))
        let size = CGSize(width: max(64, (image.size.width * scale).rounded()), height: max(64, (image.size.height * scale).rounded()))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        for q in stride(from: 0.8, through: 0.3, by: -0.1) {
            if let d = resized.jpegData(compressionQuality: q), d.count <= 500_000 { return d }
        }
        return nil
    }

    static var appInfo: ProblemReport.AppInfo {
        var sys = utsname()
        uname(&sys)
        let model = withUnsafeBytes(of: &sys.machine) { String(decoding: $0.prefix(while: { $0 != 0 }), as: UTF8.self) }
        return ProblemReport.AppInfo(
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?",
            os: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            device: model.isEmpty ? UIDevice.current.model : model,
            locale: Locale.current.identifier)
    }
}

extension UIWindow {
    /// Shake to report (#467 B). Settings → Help can turn it off.
    override open func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        guard motion == .motionShake, ReportPref.shake else { return }
        ProblemReporter.shared.open(via: .shake, screenshot: true)
    }
}

/// "Report" chip next to an error (#467 C).
struct ReportErrorButton: View {
    let error: String
    var area: String?

    var body: some View {
        Button { ProblemReporter.shared.open(via: .error, error: error, area: area, screenshot: true) } label: {
            Text("Report").font(Theme.label(12)).foregroundStyle(Color(hex: 0xFF3D81))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(.white))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Report this problem")
    }
}

struct ReportProblemView: View {
    @Environment(AppModel.self) private var model
    @State var draft: ReportDraft
    var modal = false
    var onClose: (() -> Void)?
    var demoSent = false

    @State private var text = ""
    @State private var pick: [PhotosPickerItem] = []
    @State private var marking: Int?
    @State private var sending = false
    @State private var sent: Int??
    @State private var failure: String?
    @FocusState private var typing: Bool

    init(draft: ReportDraft, modal: Bool = false, onClose: (() -> Void)? = nil, demoSent: Bool = false) {
        _draft = State(initialValue: draft)
        self.modal = modal
        self.onClose = onClose
        self.demoSent = demoSent
    }

    private static let hot = LinearGradient(colors: [Color(hex: 0xFF3D81), Color(hex: 0x7B2FF7)], startPoint: .topLeading, endPoint: .bottomTrailing)
    private static let send = LinearGradient(colors: [Color(hex: 0xFF3D81), Color(hex: 0xFFB100)], startPoint: .leading, endPoint: .trailing)

    var body: some View {
        ScrollView {
            if sent != nil { thanks } else { form }
        }
        .scrollDismissesKeyboard(.interactively)
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Report a problem")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if modal { CloseToolbarItem { onClose?() } } // the standard ✕ (#823)
        }
        .sheet(item: Binding(get: { marking.map { ReportMarkIndex(i: $0) } }, set: { marking = $0?.i })) { m in
            ScreenshotMarkupView(image: draft.shots[m.i]) { draft.shots[m.i] = $0 }
        }
        .onChange(of: pick) { _, items in
            Task {
                for item in items.prefix(3 - draft.shots.count) {
                    if let d = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: d) { draft.shots.append(img) }
                }
                pick = []
            }
        }
        #if DEBUG
        .onAppear {
            if demoSent { sent = .some(468) }
            if model.demo, text.isEmpty { text = draft.via == .shake ? "Rest timer froze after set 2" : "" }
        }
        #endif
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "ladybug.fill").font(.system(size: 22, weight: .bold))
                    .frame(width: 46, height: 46).background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.22)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.via == .shake ? "Something wrong here?" : "Report a problem").font(Theme.display(22))
                    Text("We read every report").font(.footnote.weight(.semibold)).opacity(0.85)
                }
                Spacer()
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Self.hot))

            section("What's wrong?") {
                ReportChips(items: ReportKind.allCases.map { ReportChip(id: $0.id, title: $0.title, symbol: $0.symbol) }, selected: draft.kind.id) { draft.kind = ReportKind(rawValue: $0) ?? .bug }
            }
            section("Where?") {
                ReportChips(items: ReportDraft.areas.map { ReportChip(id: $0, title: $0) }, selected: draft.area) { draft.area = $0 }
            }
            if let e = draft.error {
                Label(e, systemImage: "exclamationmark.triangle.fill").font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(hex: 0xFFB100))
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
            }
            section(draft.kind == .idea ? "Your idea" : "What happened?") {
                TextField(draft.kind == .idea ? "What would make it better?" : "What did you do, what did you expect?", text: $text, axis: .vertical)
                    .lineLimit(4...8)
                    .focused($typing)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
            }
            section("Screenshots") { shots }
            Label("App \(ProblemReporter.appInfo.version) (\(ProblemReporter.appInfo.build)) · \(ProblemReporter.appInfo.os) · \(draft.screen ?? draft.area) attached",
                  systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
            Text("Screenshots and your email stay with our team. Your words and the app facts may be shared in our issue tracker without your name.")
                .font(.caption).foregroundStyle(Theme.muted)
            if let failure { Text(failure).font(.footnote.weight(.semibold)).foregroundStyle(.red) }
            Button { Task { await sendReport() } } label: {
                HStack {
                    if sending { ProgressView().tint(Theme.ink) }
                    Text(sending ? "Sending…" : "Send report").font(Theme.display(17))
                }
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Self.send))
                .opacity(canSend ? 1 : 0.5)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(16)
    }

    private var shots: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(draft.shots.enumerated()), id: \.offset) { i, img in
                    ZStack(alignment: .topTrailing) {
                        Button { marking = i } label: {
                            Image(uiImage: img).resizable().scaledToFill().frame(width: 84, height: 150).clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(alignment: .bottom) {
                                    Label("Draw", systemImage: "pencil.tip").font(Theme.label(11))
                                        .padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(.black.opacity(0.6))).padding(6)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Screenshot \(i + 1), draw to highlight")
                        Button { draft.shots.remove(at: i) } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 20)).symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.7))
                        }
                        .padding(4)
                        .accessibilityLabel("Remove screenshot \(i + 1)")
                    }
                }
                if draft.shots.count < 3 {
                    PhotosPicker(selection: $pick, maxSelectionCount: 3 - draft.shots.count, matching: .screenshots) {
                        VStack(spacing: 6) {
                            Image(systemName: "photo.badge.plus").font(.system(size: 22, weight: .bold))
                            Text("Add").font(Theme.label(12))
                        }
                        .foregroundStyle(Theme.lime)
                        .frame(width: 84, height: 150)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.lime.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])))
                    }
                }
            }
        }
    }

    private var thanks: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 56, weight: .bold)).foregroundStyle(Theme.ink)
                .frame(width: 96, height: 96).background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Self.send))
            Text("Thanks, we got it").font(Theme.display(26))
            Text(draft.kind == .idea ? "We look at every idea when we plan the next updates." : "We look into it and ship the fix in a coming update. What's new tells you when.")
                .font(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            if case let .some(.some(n)) = sent {
                Text("Report #\(n)").font(Theme.label(13)).foregroundStyle(Theme.lime)
            }
            Button { if modal { onClose?() } else { reset() } } label: {
                Text(modal ? "Back to the app" : "Report something else").font(Theme.display(16)).foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.lime))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24).padding(.top, 60)
    }

    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Theme.label(11)).tracking(1.4).textCase(.uppercase).foregroundStyle(Theme.muted)
            content()
        }
    }

    private var canSend: Bool { !sending && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func reset() {
        draft = ReportDraft(via: .settings, area: draft.area)
        text = ""
        sent = nil
    }

    private func sendReport() async {
        sending = true
        failure = nil
        defer { sending = false }
        let report = ProblemReport(kind: draft.kind.rawValue, area: draft.area, text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                                   screen: draft.screen, error: draft.error, via: draft.via.rawValue, app: ProblemReporter.appInfo,
                                   screenshots: draft.shots.compactMap(ProblemReporter.jpeg))
        do {
            let issue = try await model.api.sendProblemReport(report)
            sent = .some(issue)
            typing = false
        } catch {
            failure = (error as? APIError).map { $0.localizedDescription } ?? "Couldn't send. Check your connection and try again."
        }
    }
}

private struct ReportMarkIndex: Identifiable {
    let i: Int
    var id: Int { i }
}

/// Wrapping chips; one selected.
private struct ReportChip: Identifiable {
    let id: String
    let title: String
    var symbol: String?
}

private struct ReportChips: View {
    let items: [ReportChip]
    let selected: String
    let pick: (String) -> Void

    var body: some View {
        ReportWrapLayout(spacing: 8) {
            ForEach(items) { item in
                let on = item.id == selected
                Button { pick(item.id) } label: {
                    Label { Text(item.title) } icon: { if let s = item.symbol { Image(systemName: s) } }
                        .font(Theme.label(14))
                        .foregroundStyle(on ? .white : .white.opacity(0.85))
                        .padding(.horizontal, 13).padding(.vertical, 9)
                        .background(Capsule().fill(on ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xFF3D81), Color(hex: 0x7B2FF7)], startPoint: .leading, endPoint: .trailing)) : AnyShapeStyle(Theme.card)))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selected)
    }
}

private struct ReportWrapLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        for row in arrange(width: bounds.width, subviews) {
            for (i, x) in zip(row.items, row.xs) {
                subviews[i].place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + row.y), proposal: .unspecified)
            }
        }
    }

    private struct Row { var items: [Int] = []; var xs: [CGFloat] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, _ subviews: Subviews) -> [Row] {
        var rows = [Row()]
        for (i, v) in subviews.enumerated() {
            let s = v.sizeThatFits(.unspecified)
            if !rows[rows.count - 1].items.isEmpty, rows[rows.count - 1].width + spacing + s.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var r = rows[rows.count - 1]
            let x = r.items.isEmpty ? 0 : r.width + spacing
            r.items.append(i)
            r.xs.append(x)
            r.width = x + s.width
            r.height = max(r.height, s.height)
            rows[rows.count - 1] = r
        }
        return rows
    }
}

/// Draw on a screenshot to show where the problem is (#467 B).
struct ScreenshotMarkupView: View {
    let image: UIImage
    let done: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var strokes: [[CGPoint]] = []
    @State private var size: CGSize = .zero

    private let ink = Color(hex: 0xFF3D81)

    var body: some View {
        NavigationStack {
            Image(uiImage: image).resizable().scaledToFit()
                .overlay {
                    GeometryReader { g in
                        Canvas { ctx, _ in
                            for s in strokes where s.count > 1 {
                                var p = Path()
                                p.addLines(s)
                                ctx.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                            }
                        }
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                            if v.translation == .zero || strokes.isEmpty { strokes.append([v.location]) } else { strokes[strokes.count - 1].append(v.location) }
                        })
                        .onAppear { size = g.size }
                        .onChange(of: g.size) { _, s in size = s }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.bg.ignoresSafeArea())
                .navigationTitle("Draw to highlight")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Undo") { _ = strokes.popLast() }.disabled(strokes.isEmpty)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { done(baked()); dismiss() }.fontWeight(.bold)
                    }
                }
        }
        .preferredColorScheme(.dark)
    }

    /// Strokes drawn into the screenshot's pixels.
    private func baked() -> UIImage {
        guard !strokes.isEmpty, size.width > 0 else { return image }
        let k = image.size.width / size.width
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format).image { c in
            image.draw(at: .zero)
            let g = c.cgContext
            g.setStrokeColor(UIColor(ink).cgColor)
            g.setLineWidth(5 * k)
            g.setLineCap(.round)
            g.setLineJoin(.round)
            for s in strokes where s.count > 1 {
                g.addLines(between: s.map { CGPoint(x: $0.x * k, y: $0.y * k) })
            }
            g.strokePath()
        }
    }
}
