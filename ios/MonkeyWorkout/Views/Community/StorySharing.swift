import PhotosUI
import SwiftUI
import UIKit
import WorkoutEngine

// Story sharing (#777, designs B + C from `story-sharing/proposals.png`). B: a Share button on the thing itself
// (workout summary, PR, week chest, level, badge, programme, recipe) opens one "Share as a story" sheet with three
// looks and an optional own photo. C: when something share-worthy happens (PR, level up, badge, week goal, new
// programme, new recipe) a toast offers the story once; Settings → Your profile → Share prompts turns them off.

enum StoryLook: String, CaseIterable, Identifiable {
    case bold, detail, clean
    var id: String { rawValue }
    var title: String {
        switch self {
        case .bold: "Bold"
        case .detail: "Detail"
        case .clean: "Clean"
        }
    }
}

/// 1080 × 1920 story image for Instagram, TikTok, WhatsApp status… Fixed type sizes (no Dynamic Type): it's a picture.
struct StoryPoster: View {
    var eyebrow: String
    var title: String
    var big: String
    var unit: String
    var line: String
    var colors: [Color]
    /// Lines for the Detail look (sets, week days, macros…); falls back to `line`.
    var details: [String] = []
    /// Invite code under the logo, so every shared story can bring a friend in.
    var code: String?
    var look: StoryLook = .bold
    /// The member's own photo behind the Bold and Detail looks.
    var photo: UIImage?

    /// Stable key for re-rendering.
    var key: String { [eyebrow, title, big, unit, line, look.rawValue, photo.map { "\($0.hash)" } ?? ""].joined(separator: "|") }

    var body: some View {
        let ink: Color = look == .clean ? Theme.ink : .white
        VStack(alignment: .leading, spacing: 0) {
            Text(eyebrow.uppercased()).font(.system(size: 15, weight: .heavy, design: .rounded)).tracking(3).opacity(0.85)
            Text(title).font(.system(size: 44, weight: .black, design: .rounded)).lineLimit(3).minimumScaleFactor(0.5).padding(.top, 6)
            Spacer()
            if look == .detail {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array((details.isEmpty ? [line] : details).prefix(7).enumerated()), id: \.offset) { _, d in
                        Text(d).font(.system(size: 22, weight: .heavy, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.18)))
                    }
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(big).font(.system(size: 132, weight: .black, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.4)
                    Text(unit.uppercased()).font(.system(size: 24, weight: .black, design: .rounded)).lineLimit(1).minimumScaleFactor(0.6)
                }
                .foregroundStyle(look == .clean ? AnyShapeStyle(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)) : AnyShapeStyle(ink))
                Text(line).font(.system(size: 19, weight: .bold, design: .rounded)).opacity(0.92).lineLimit(2)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 4) {
                Text("🐵 MonkeyWorkout").font(.system(size: 24, weight: .black, design: .rounded))
                if let code {
                    Text("Train with me · code \(code)").font(.system(size: 16, weight: .heavy, design: .rounded)).opacity(0.9)
                }
            }
        }
        .foregroundStyle(ink)
        .padding(34)
        .frame(width: 360, height: 640, alignment: .leading)
        .background(background)
        .clipped()
    }

    @ViewBuilder private var background: some View {
        if look == .clean {
            Color.white
        } else if let photo {
            ZStack {
                Image(uiImage: photo).resizable().scaledToFill().frame(width: 360, height: 640).clipped()
                LinearGradient(colors: colors.map { $0.opacity(0.55) } + [.black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
            }
        } else {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    @MainActor func render() -> UIImage? {
        let r = ImageRenderer(content: self)
        r.scale = 3
        return r.uiImage
    }
}

extension StoryPoster {
    @MainActor static func workout(title: String, minutes: Int, sets: Int, moves: Int, details: [String] = []) -> StoryPoster {
        StoryPoster(eyebrow: "Workout done", title: title, big: "\(minutes)", unit: "min", line: "\(sets) sets · \(moves) exercises",
                    colors: WorkoutEngine.Category.power.colors + [Color(hex: 0xFF9A3C)], details: details)
    }

    @MainActor static func record(exercise: String, value: String, unit: String, line: String, isRecord: Bool) -> StoryPoster {
        StoryPoster(eyebrow: isRecord ? "New personal record" : "Lifted", title: exercise, big: value, unit: unit, line: line,
                    colors: [Color(hex: 0xFFB800), Color(hex: 0xFF5C3C), Color(hex: 0xFF2D87)])
    }

    @MainActor static func chest(sessions: Int) -> StoryPoster {
        StoryPoster(eyebrow: "Week goal met", title: "Chest opened 🎁", big: "\(sessions)", unit: "sessions",
                    line: "+\(GameProgress.weekBonus) XP this week", colors: [Color(hex: 0x7B5CFF), Color(hex: 0x3C8DFF), Color(hex: 0x00C9A7)])
    }

    @MainActor static func level(_ level: Int, xp: Int) -> StoryPoster {
        let rank = GameRank.of(level: level)
        return StoryPoster(eyebrow: "Level up", title: rank.title, big: "\(level)", unit: "level", line: "\(xp.formatted()) XP",
                           colors: [Color(hex: 0x7B2CFF), Color(hex: 0xFF2D87)])
    }

    @MainActor static func badge(_ b: Badge) -> StoryPoster {
        StoryPoster(eyebrow: "Badge unlocked", title: b.title, big: "🏅", unit: "", line: b.detail,
                    colors: [Color(hex: 0xFF8A00), Color(hex: 0xFF3D77)])
    }

    @MainActor static func programme(_ p: Programme, days: [String] = []) -> StoryPoster {
        StoryPoster(eyebrow: "My programme", title: p.name, big: "\(p.weeks)", unit: "weeks",
                    line: "\(p.sessionsPerWeek) days a week · \(p.tagline)", colors: p.palette.colors, details: days)
    }

    @MainActor static func recipe(_ r: Recipe) -> StoryPoster {
        StoryPoster(eyebrow: "Cooked it", title: "\(r.emoji) \(r.name)", big: "\(r.protein)", unit: "g protein",
                    line: "\(r.kcal) kcal · \(r.minutes) min", colors: [Color(hex: 0x1ED98A), Color(hex: 0x00B8D4)],
                    details: ["\(r.protein) g protein", "\(r.carbs) g carbs", "\(r.fat) g fat", "\(r.kcal) kcal", "\(r.minutes) min"])
    }
}

/// Opens the "Share as a story" sheet (B).
struct StoryShareButton<Label: View>: View {
    let poster: StoryPoster
    @ViewBuilder var label: () -> Label
    @State private var open = false

    var body: some View {
        Button { open = true } label: { label() }
            .buttonStyle(.plain)
            .sheet(isPresented: $open) { StorySheet(poster: poster) }
    }
}

extension StoryShareButton where Label == AnyView {
    /// Instagram-gradient "Share to story" pill.
    init(poster: StoryPoster, title: String = "Share to story") {
        self.init(poster: poster) {
            AnyView(SwiftUI.Label(title, systemImage: "camera.fill")
                .font(Theme.label(15))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Capsule().fill(StorySheet.instagram)))
        }
    }
}

/// B: three looks side by side, an optional photo, then the share sheet (Instagram Stories, TikTok, WhatsApp…).
struct StorySheet: View {
    let poster: StoryPoster
    @Environment(\.dismiss) private var dismiss
    @State private var look: StoryLook = .bold
    @State private var photoItem: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var image: Image?

    static let instagram = LinearGradient(colors: [Color(hex: 0xFEDA75), Color(hex: 0xFA7E1E), Color(hex: 0xD62976), Color(hex: 0x962FBF)],
                                          startPoint: .bottomLeading, endPoint: .topTrailing)
    private static let scale: CGFloat = 0.28

    private func styled(_ l: StoryLook) -> StoryPoster {
        var p = poster
        p.code = p.code ?? ReferralStore.shared.code
        p.look = l
        p.photo = photo
        return p
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    HStack(spacing: 10) {
                        ForEach(StoryLook.allCases) { l in
                            Button { look = l } label: {
                                styled(l)
                                    .scaleEffect(Self.scale, anchor: .topLeading)
                                    .frame(width: 360 * Self.scale, height: 640 * Self.scale, alignment: .topLeading)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(look == l ? Theme.lime : .clear, lineWidth: 3))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(l.title) look")
                            .accessibilityAddTraits(look == l ? .isSelected : [])
                        }
                    }
                    HStack(spacing: 6) {
                        ForEach(StoryLook.allCases) { l in chip(l.title, on: look == l) { look = l } }
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Text(photo == nil ? "+ my photo" : "Photo ✓").font(Theme.label(12))
                                .foregroundStyle(photo == nil ? .white : Theme.ink)
                                .padding(.horizontal, 10).frame(minHeight: 32)
                                .background(Capsule().fill(photo == nil ? AnyShapeStyle(Theme.cardStrong) : AnyShapeStyle(Theme.lime)))
                        }
                        if photo != nil {
                            Button { photo = nil; photoItem = nil } label: { Image(systemName: "xmark").font(.caption.bold()).frame(width: 32, height: 32) }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove photo")
                        }
                    }
                    if let image {
                        ShareLink(item: image, preview: SharePreview(poster.title, image: image)) {
                            VStack(spacing: 2) {
                                Label("Share story", systemImage: "camera.fill").font(Theme.label(16))
                                Text("Instagram, TikTok, WhatsApp, Messages…").font(.caption.weight(.semibold)).opacity(0.9)
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 58)
                            .background(Capsule().fill(Self.instagram))
                        }
                    } else {
                        ProgressView().frame(minHeight: 58)
                    }
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Share as a story")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
        .task(id: styled(look).key) { image = styled(look).render().map { Image(uiImage: $0) } }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let ui = UIImage(data: data) { photo = ui }
            }
        }
    }

    private func chip(_ title: String, on: Bool, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(title).font(Theme.label(12))
                .foregroundStyle(on ? Theme.ink : .white)
                .padding(.horizontal, 10).frame(minHeight: 32)
                .background(Capsule().fill(on ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(Theme.cardStrong)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - C · moment nudges

/// One share-worthy moment, offered once.
struct ShareMoment: Identifiable {
    let id: String
    let title: String
    let poster: StoryPoster
}

@MainActor @Observable
final class ShareMoments {
    static let shared = ShareMoments()

    /// Settings → Your profile → Share prompts (#777): off = no toasts at all; Share buttons stay.
    var enabled: Bool = UserDefaults.standard.object(forKey: "shareMoments.enabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "shareMoments.enabled")
            if !enabled { pending = nil }
        }
    }
    private(set) var pending: ShareMoment? {
        didSet { if pending?.id != oldValue?.id { MomentToastCenter.shared.update(paused ? nil : pending) } }
    }
    var sharing: ShareMoment?
    /// The app tour is showing: the toast waits under it.
    var paused = false {
        didSet { if paused != oldValue { MomentToastCenter.shared.update(paused ? nil : pending) } }
    }

    private var seen: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "shareMoments.seen") ?? [])

    private init() {}

    /// Offers `moment` unless prompts are off or it was offered before.
    func offer(_ moment: ShareMoment) {
        guard !seen.contains(moment.id) else { return }
        remember(moment.id)
        guard enabled else { return }
        pending = moment
    }

    func dismiss() { pending = nil }

    func share() {
        sharing = pending
        pending = nil
    }

    private func remember(_ id: String) {
        seen.insert(id)
        UserDefaults.standard.set(Array(seen.suffix(400)), forKey: "shareMoments.seen")
    }

    /// Level, badges, personal records and the week goal, from the model. The first run only takes note of what is
    /// already there, so nothing old pops up.
    func check(_ model: AppModel) {
        #if DEBUG
        if model.demo { return }
        #endif
        guard model.user != nil else { return }
        let g = model.game
        var found: [ShareMoment] = []
        if g.level > 1 { found.append(ShareMoment(id: "level-\(g.level)", title: "Level \(g.level) · \(GameRank.of(level: g.level).title)", poster: .level(g.level, xp: g.xp))) }
        for b in model.badges where b.unlocked {
            found.append(ShareMoment(id: "badge-\(b.id)", title: "Badge: \(b.title)", poster: .badge(b)))
        }
        if let pr = model.personalRecords.first {
            let name = Exercise.get(pr.exerciseId).name
            let value = pr.kind == .maxReps ? "\(pr.reps)" : LoadAdvisor.formatKg(pr.kg)
            found.append(ShareMoment(id: "pr-\(pr.id.uuidString)", title: "\(name) \(value) \(pr.kind == .maxReps ? "reps" : "kg") 🏆",
                                     poster: .record(exercise: name, value: value, unit: pr.kind == .maxReps ? "reps" : "kg",
                                                     line: pr.date.formatted(.dateTime.day().month(.abbreviated)), isRecord: true)))
        }
        if model.weekChestOpen {
            let week = Int(Progression.weekStart(.now, Progression.calendar()).timeIntervalSince1970)
            let done = Progression.stats(records: model.state.history, weights: [], targetPerWeek: model.gameTarget).thisWeek
            found.append(ShareMoment(id: "week-\(week)", title: "Week goal met · \(done) sessions", poster: .chest(sessions: done)))
        }
        let baseline = "shareMoments.baseline"
        if !UserDefaults.standard.bool(forKey: baseline) {
            found.forEach { remember($0.id) }
            UserDefaults.standard.set(true, forKey: baseline)
            return
        }
        if let m = found.last(where: { !seen.contains($0.id) }) {
            found.filter { !seen.contains($0.id) }.forEach { remember($0.id) }
            if enabled { pending = m }
        }
    }
}

/// Gradient toast above the tab bar: "Your story is ready" (C). Grabber on top like the Undo bar (#811): it hides by
/// itself after `MomentToastCenter.seconds`, and ✕, a tap on the bar (outside its buttons) or a swipe down hides it.
struct MomentToast: View {
    let moment: ShareMoment
    @State private var moments = ShareMoments.shared

    var body: some View {
        HStack(spacing: 10) {
            moment.poster
                .scaleEffect(0.12, anchor: .topLeading)
                .frame(width: 43, height: 77, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.white, lineWidth: 2))
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 2) {
                Text(moment.title).font(Theme.label(14)).lineLimit(2).minimumScaleFactor(0.8)
                Text("Your story is ready").font(.caption.weight(.semibold)).opacity(0.9)
                Button("Don't suggest again") { moments.enabled = false }
                    .font(.caption2.weight(.bold)).opacity(0.75)
                    .buttonStyle(.plain)
            }
            Spacer(minLength: 4)
            Button("Share") { moments.share() }
                .font(Theme.label(14)).foregroundStyle(Theme.ink)
                .padding(.horizontal, 14).frame(minHeight: 40)
                .background(Capsule().fill(Theme.lime))
                .buttonStyle(.plain)
            Button { moments.dismiss() } label: {
                Image(systemName: "xmark").font(.footnote.bold()).frame(width: 36, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hide")
        }
        .foregroundStyle(.white)
        .padding(10)
        .padding(.top, 6)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(LinearGradient(colors: moment.poster.colors, startPoint: .leading, endPoint: .trailing)))
        .overlay(alignment: .top) {
            Capsule().fill(.white.opacity(0.6)).frame(width: 36, height: 4).padding(.top, 5)
        }
        .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture { moments.dismiss() }
        .gesture(DragGesture(minimumDistance: 10).onEnded { if $0.translation.height > 20 { moments.dismiss() } })
        .accessibilityAction(named: "Dismiss") { moments.dismiss() }
        .accessibilityAction(.escape) { moments.dismiss() }
    }
}

/// Shows the moment toast in its own window above the tab bar, like the Undo bar (#811, #857): as an overlay on the
/// TabView it took no taps on device, so ✕ did nothing and it stayed. Hides by itself after `seconds`.
@MainActor
final class MomentToastCenter {
    static let shared = MomentToastCenter()
    static let seconds: Double = 8

    private var window: MomentToastWindow?
    private let state = MomentToastState()
    private var timer: Task<Void, Never>?

    func update(_ moment: ShareMoment?) {
        timer?.cancel()
        guard let moment else {
            withAnimation(.easeOut(duration: 0.25)) { state.moment = nil }
            state.frame = .zero
            return
        }
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) ?? UIApplication.shared.connectedScenes.first as? UIWindowScene
        else { return }
        if window == nil || window?.windowScene !== scene {
            let w = MomentToastWindow(windowScene: scene)
            w.state = state
            // Under the Undo bar's window (.alert + 1).
            w.windowLevel = .normal + 1
            let host = UIHostingController(rootView: MomentToastHost(state: state))
            host.view.backgroundColor = .clear
            w.rootViewController = host
            w.isHidden = false
            window = w
        }
        state.lift = UndoCloseCenter.tabBarLift()
        withAnimation(.snappy) { state.moment = moment }
        UIAccessibility.post(notification: .announcement, argument: "\(moment.title). Your story is ready.")
        timer = Task { [id = moment.id] in
            try? await Task.sleep(for: .seconds(Self.seconds))
            guard !Task.isCancelled, ShareMoments.shared.pending?.id == id else { return }
            ShareMoments.shared.dismiss()
        }
    }
}

@MainActor @Observable
private final class MomentToastState {
    var moment: ShareMoment?
    var lift: CGFloat = 0
    /// Where the toast is, in window points: only touches there are taken.
    var frame: CGRect = .zero
}

/// Touches go through except on the toast itself.
private final class MomentToastWindow: UIWindow {
    fileprivate weak var state: MomentToastState?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let state, state.moment != nil, state.frame.insetBy(dx: -4, dy: -4).contains(point) else { return nil }
        return super.hitTest(point, with: event) ?? rootViewController?.view
    }
}

private struct MomentToastHost: View {
    let state: MomentToastState

    var body: some View {
        VStack {
            Spacer()
            if let m = state.moment {
                MomentToast(moment: m)
                    .id(m.id)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { state.frame = $0 }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8 + state.lift)
        .frame(maxWidth: Theme.readableWidth)
        .frame(maxWidth: .infinity)
    }
}

/// Holds the story sheet, keeps the toast under the app tour and checks for new moments as history changes.
struct ShareMomentsHost: ViewModifier {
    @Environment(AppModel.self) private var model
    @State private var moments = ShareMoments.shared

    func body(content: Content) -> some View {
        content
            .onChange(of: model.tourStep == nil, initial: true) { _, free in moments.paused = !free }
            .sheet(item: $moments.sharing) { m in StorySheet(poster: m.poster) }
            .task(id: model.observedStateVersion) { moments.check(model) }
    }
}
