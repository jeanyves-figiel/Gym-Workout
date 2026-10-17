import SwiftUI
import WorkoutEngine

/// Settings chapters (#394, design B + C): grouped gradient cards, a search field and a sticky chapter bar.
enum SettingsChapter: String, CaseIterable, Identifiable {
    case you, training, watch, look, account, help

    var id: String { rawValue }

    var title: String {
        switch self {
        case .you: "You"
        case .training: "Training"
        case .watch: "Apple Watch"
        case .look: "Look & apps"
        case .account: "Account"
        case .help: "Help"
        }
    }

    var symbol: String {
        switch self {
        case .you: "person.fill"
        case .training: "dumbbell.fill"
        case .watch: "applewatch"
        case .look: "paintpalette.fill"
        case .account: "lock.fill"
        case .help: "questionmark.circle.fill"
        }
    }

    var gradient: LinearGradient {
        switch self {
        case .you: AccountTint.publicProfile
        case .training: LinearGradient(colors: [Color(hex: 0x8A3DF0), Color(hex: 0xFF4D8A)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .watch: LinearGradient(colors: [Color(hex: 0x3D6BFF), Color(hex: 0x22D3EE)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .look: LinearGradient(colors: [Color(hex: 0xFF8A00), Color(hex: 0xFF3D77)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .account: LinearGradient(colors: [Color(hex: 0x10B981), Color(hex: 0x3D6BFF)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .help: LinearGradient(colors: [Color(hex: 0x475569), Color(hex: 0x1E293B)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

/// Search over Settings rows: every word of the query must appear in the row's title or keywords.
struct SettingsSearch {
    var query: String

    var active: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    func matches(_ text: String) -> Bool {
        guard active else { return true }
        let hay = text.lowercased()
        return query.lowercased().split(separator: " ").allSatisfy { hay.contains($0) }
    }

    func any(_ texts: [String]) -> Bool { texts.contains(where: matches) }
}

/// One chapter: eyebrow title, then one gradient card holding its rows.
struct SettingsGroup<Content: View>: View {
    let chapter: SettingsChapter
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(chapter.title, systemImage: chapter.symbol)
                .font(Theme.label(11)).tracking(1.6).textCase(.uppercase).foregroundStyle(Theme.muted)
                .padding(.leading, 4)
            VStack(spacing: 6) { content() }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(chapter.gradient))
        }
        .padding(.top, 10)
        // Jump target sits above the card so the chapter title clears the sticky search + chapter bar.
        .background(alignment: .top) {
            Color.clear.frame(height: 1).alignmentGuide(.top) { $0[.top] + 110 }.id(chapter)
        }
        .background(GeometryReader { g in
            Color.clear.preference(key: ChapterTopKey.self, value: [chapter: g.frame(in: .named("settings")).minY])
        })
    }
}

/// A row inside a SettingsGroup: icon tile, title, plain current value right, chevron.
struct SettingsRow<Trailing: View>: View {
    let symbol: String
    let title: String
    var value: String?
    var ink = false
    var tint: Color?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(0.22)))
            Text(title).font(Theme.display(17)).lineLimit(1).minimumScaleFactor(0.75)
            Spacer(minLength: 6)
            if let value {
                Text(value).font(.subheadline.weight(.semibold)).opacity(0.9).lineLimit(1).minimumScaleFactor(0.75)
            }
            trailing()
        }
        .foregroundStyle(tint ?? (ink ? Theme.ink : .white))
        .padding(.horizontal, 10).padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.black.opacity(0.14)))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

extension SettingsRow where Trailing == AccountChevron {
    init(symbol: String, title: String, value: String? = nil, ink: Bool = false, tint: Color? = nil) {
        self.init(symbol: symbol, title: title, value: value, ink: ink, tint: tint) { AccountChevron() }
    }
}

/// Sticky chapter bar: tap a chapter to jump to it; the one on screen is lime.
struct SettingsChapterBar: View {
    let chapters: [SettingsChapter]
    let current: SettingsChapter?
    let jump: (SettingsChapter) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(chapters) { c in
                        Button { jump(c) } label: {
                            Label(c.title, systemImage: c.symbol)
                                .font(Theme.label(13)).lineLimit(1)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .foregroundStyle(current == c ? Theme.ink : .white)
                                .background(Capsule().fill(current == c ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(.white.opacity(0.14))))
                        }
                        .buttonStyle(.plain)
                        .id(c)
                        .accessibilityAddTraits(current == c ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 16)
            }
            .onChange(of: current) { _, c in
                if let c { withAnimation { proxy.scrollTo(c, anchor: .center) } }
            }
        }
        .padding(.vertical, 8)
        .background(Theme.bg.opacity(0.96))
    }
}

/// One choice inside a ChoiceCard.
struct SettingsChoice<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    let symbol: String
    let hint: String
    var id: Value { value }
}

/// Enhanced chip picker (#394, option 2): every option visible with its icon, one tap to pick,
/// and a hint saying what the picked option does.
struct ChoiceCard<Value: Hashable>: View {
    let symbol: String
    let title: String
    var note: String?
    let choices: [SettingsChoice<Value>]
    let selection: Value
    let gradient: LinearGradient
    var columns = 3
    let pick: (Value) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.22)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(Theme.display(20)).lineLimit(1).minimumScaleFactor(0.8)
                    if let note { Text(note).font(.caption.weight(.medium)).opacity(0.85) }
                }
                Spacer(minLength: 0)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns), spacing: 6) {
                ForEach(choices) { c in
                    let on = c.value == selection
                    Button { withAnimation(.snappy) { pick(c.value) } } label: {
                        VStack(spacing: 4) {
                            Image(systemName: on ? "checkmark.circle.fill" : c.symbol).font(.system(size: 17, weight: .bold))
                            Text(c.title).font(Theme.label(12)).lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .padding(.horizontal, 4)
                        .foregroundStyle(on ? Theme.ink : .white)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(on ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(.white.opacity(0.18))))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(c.title)
                    .accessibilityHint(c.hint)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            if let picked = choices.first(where: { $0.value == selection }) {
                Label(picked.hint, systemImage: "info.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.black.opacity(0.18)))
                    .contentTransition(.opacity)
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(gradient))
    }
}

// MARK: - Option texts

extension WatchStartMode {
    var short: String {
        switch self {
        case .ask: "Ask"
        case .always: "Auto"
        case .never: "Never"
        }
    }

    static var choices: [SettingsChoice<WatchStartMode>] {
        allCases.map { m in
            switch m {
            case .ask: SettingsChoice(value: m, title: "Ask", symbol: "questionmark.bubble.fill",
                                      hint: "A prompt on your wrist asks to track heart rate and energy.")
            case .always: SettingsChoice(value: m, title: "Auto", symbol: "play.fill",
                                         hint: "The Watch starts tracking as soon as the iPhone workout starts.")
            case .never: SettingsChoice(value: m, title: "Never", symbol: "xmark",
                                        hint: "The Watch stays quiet. Open its app to follow along.")
            }
        }
    }
}

extension WatchActionMode {
    static var choices: [SettingsChoice<WatchActionMode>] {
        allCases.map { m in
            switch m {
            case .smart: SettingsChoice(value: m, title: "Smart next", symbol: "forward.end.fill",
                                        hint: "The obvious next step: log the set, skip rest, start a timed set, next exercise, finish.")
            case .set: SettingsChoice(value: m, title: "Log set", symbol: "checkmark",
                                      hint: "Always logs the set you're on. During rest it skips the rest.")
            case .rest: SettingsChoice(value: m, title: "Rest timer", symbol: "timer",
                                       hint: "Starts or ends the rest countdown. Log sets on screen.")
            }
        }
    }
}

extension AutoNextPref {
    static func short(_ sec: Int) -> String {
        switch sec {
        case 0: "Straight on"
        case -1: "Wait for me"
        default: "\(sec) s"
        }
    }

    static var settingsChoices: [SettingsChoice<Int>] {
        choices.map { sec in
            switch sec {
            case 0: SettingsChoice(value: sec, title: "Straight on", symbol: "forward.fill",
                                   hint: "The next exercise opens right after the last set.")
            case -1: SettingsChoice(value: sec, title: "Wait for me", symbol: "hand.raised.fill",
                                    hint: "Stays on the exercise until you tap Next.")
            default: SettingsChoice(value: sec, title: "\(sec) s", symbol: "timer",
                                    hint: "A \(sec) s countdown bar, then the next exercise. Tap to go now or hold.")
            }
        }
    }
}

// MARK: - Option pages

/// Settings → Apple Watch (#394): what the Watch does in a workout, every option on one page.
struct WatchOptionsView: View {
    var focus: Focus?

    enum Focus: Hashable { case start, action, lift }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    AccountHeader(symbol: "applewatch", title: "Apple Watch",
                                  subtitle: "What the Watch does during a workout.", gradient: SettingsChapter.watch.gradient)
                    ChoiceCard(symbol: "applewatch.radiowaves.left.and.right", title: "Start from iPhone",
                               note: "When a workout starts on the iPhone",
                               choices: WatchStartMode.choices, selection: WatchStartPref.shared.mode,
                               gradient: LinearGradient(colors: [Color(hex: 0xFF3FA4), Color(hex: 0x8A3DFF)], startPoint: .topLeading, endPoint: .bottomTrailing)) {
                        WatchStartPref.shared.set($0)
                    }
                    .id(Focus.start)
                    ChoiceCard(symbol: "button.horizontal.top.press.fill", title: "Action button",
                               note: "Apple Watch Ultra, during a workout",
                               choices: WatchActionMode.choices, selection: WatchActionPref.shared.mode,
                               gradient: LinearGradient(colors: [Color(hex: 0xFF6A00), Color(hex: 0xFF3D6E)], startPoint: .topLeading, endPoint: .bottomTrailing)) {
                        WatchActionPref.shared.set($0)
                    }
                    .id(Focus.action)
                    LiftSensorCard()
                        .id(Focus.lift)
                }
                .padding(16)
                .readableWidth()
            }
            .onAppear { if let focus { proxy.scrollTo(focus, anchor: .top) } }
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Apple Watch")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Settings → Training → After the last set (#357, #394).
struct WorkoutFlowView: View {
    @AppStorage(AutoNextPref.key) private var autoNextSec = AutoNextPref.fallback

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                AccountHeader(symbol: "forward.fill", title: "Workout flow",
                              subtitle: "What the player does after an exercise's last set.", gradient: WorkoutEngine.Category.cardio.gradient)
                ChoiceCard(symbol: "arrow.right.circle.fill", title: "After the last set",
                           choices: AutoNextPref.settingsChoices, selection: autoNextSec,
                           gradient: SettingsChapter.training.gradient, columns: 3) { autoNextSec = $0 }
            }
            .padding(16)
            .readableWidth()
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Workout flow")
        .navigationBarTitleDisplayMode(.inline)
    }
}
