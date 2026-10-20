import SwiftUI
import WorkoutEngine

/// How we talk to you (#415, design C from `pronouns/proposals.png`): one card with Gender → Pronouns → Coach calls you,
/// and live previews of every place it shows (coach voice, Ask Coach, Community). Everything optional.
struct TalkToYouCard: View {
    @Binding var gender: BodyMetrics.Gender?
    @Binding var pronouns: Pronouns?
    @Binding var pronounsCustom: String
    @Binding var call: CoachCall?
    @Binding var showPronouns: Bool
    /// First name or nickname the coach can call you; nil hides "Your name".
    let name: String?
    let nickname: String
    let avatar: URL?

    static let gradient = LinearGradient(colors: [Color(red: 0.55, green: 0.24, blue: 0.94), Color(red: 1, green: 0.30, blue: 0.54)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)

    private var effective: Pronouns? { pronouns ?? Pronouns.suggested(gender: gender?.rawValue) }
    private var callOptions: [CoachCall] { CoachCall.options(for: effective).filter { $0 != .name || name != nil } }
    private var pickedCall: CoachCall { call ?? CoachCall.suggested(hasName: name != nil) }
    private var callText: String? { CoachCall.text(pickedCall, name: name, pronouns: effective) }
    private var pronounsText: String? { Pronouns.text(effective, custom: pronounsCustom) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("How we talk to you").font(Theme.display(22))
                    Text("Optional · only what you pick is used").font(.caption.weight(.semibold)).opacity(0.9)
                }
                step(1, "Gender")
                Menu {
                    Picker("Gender", selection: $gender) {
                        Text("Not set").tag(BodyMetrics.Gender?.none)
                        ForEach(BodyMetrics.Gender.allCases) { Text($0.label).tag(BodyMetrics.Gender?.some($0)) }
                    }
                } label: {
                    HStack {
                        Text(gender?.label ?? "Not set").font(Theme.label(15))
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 13, weight: .heavy)).opacity(0.8)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.2)))
                }
                .accessibilityLabel("Gender, \(gender?.label ?? "not set")")

                step(2, "Pronouns", hint: pronouns == nil && effective != nil ? "from gender" : nil)
                Chips(items: Pronouns.allCases, label: { $0.label }, picked: effective) { pronouns = $0 }
                if effective == .custom {
                    TextField("", text: $pronounsCustom, prompt: Text("e.g. xe/xem").foregroundStyle(.white.opacity(0.6)))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(Theme.label(15))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.2)))
                        .onChange(of: pronounsCustom) { _, v in if v.count > 24 { pronounsCustom = String(v.prefix(24)) } }
                }

                step(3, "Coach calls you")
                Chips(items: callOptions, label: { $0 == .name ? (name ?? $0.label) : $0.label },
                      picked: callOptions.contains(pickedCall) ? pickedCall : .none) { call = $0 }

                Toggle(isOn: $showPronouns) {
                    Text("Show pronouns on my Community profile").font(Theme.label(14))
                }
                .tint(Theme.lime)
                .disabled(pronounsText == nil)
            }
            .foregroundStyle(.white)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 24).fill(Self.gradient))

            Text("Preview").eyebrow().padding(.leading, 4).padding(.top, 6)
            preview
        }
    }

    private func step(_ n: Int, _ title: String, hint: String? = nil) -> some View {
        HStack(spacing: 8) {
            Text("\(n)").font(.system(size: 12, weight: .black)).foregroundStyle(Color(red: 0.55, green: 0.24, blue: 0.94))
                .frame(width: 22, height: 22).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white))
            Text(title).font(Theme.label(14))
            if let hint { Text(hint).font(.caption.weight(.semibold)).opacity(0.75) }
        }
        .padding(.top, 4)
    }

    @ViewBuilder private var preview: some View {
        let style = CoachPref.style
        let line = CoachLines.called(CoachLines.line(.halfway(left: 3), style: style, seed: 0), moment: .halfway(left: 3), style: style, call: callText)
        VStack(alignment: .leading, spacing: 8) {
            previewBubble("speaker.wave.2.fill", "Coach voice · \(style.title)", "“\(line)”",
                          fill: AnyShapeStyle(WorkoutEngine.Category.cardio.gradient))
            previewBubble("bubble.left.fill", "Ask Coach",
                          callText.map { "Nice streak, \($0). Rest day tomorrow." } ?? "Nice streak. Rest day tomorrow.",
                          fill: AnyShapeStyle(Theme.card))
            HStack(spacing: 10) {
                AvatarView(url: avatar, nickname: nickname, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(nickname).font(Theme.label(15)).lineLimit(1)
                        PronounsChip(pronouns: showPronouns ? pronounsText : nil)
                    }
                    Text(showPronouns && pronounsText != nil ? "Community · on your posts and profile" : "Community · pronouns hidden")
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
        }
    }

    private func previewBubble(_ symbol: String, _ tag: String, _ text: String, fill: AnyShapeStyle) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(tag, systemImage: symbol).font(.caption2.weight(.bold)).opacity(0.85)
            Text(text).font(Theme.label(14)).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(fill))
        .accessibilityElement(children: .combine)
    }
}

/// Wrapping chip row: lime when picked.
private struct Chips<Item: Hashable>: View {
    let items: [Item]
    let label: (Item) -> String
    let picked: Item?
    let pick: (Item) -> Void

    init(items: [Item], label: @escaping (Item) -> String, picked: Item?, pick: @escaping (Item) -> Void) {
        self.items = items
        self.label = label
        self.picked = picked
        self.pick = pick
    }

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { item in
                let on = item == picked
                Button { pick(item) } label: {
                    Text(label(item))
                        .font(Theme.label(13))
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(on ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(Color.white.opacity(0.2))))
                        .foregroundStyle(on ? Theme.ink : .white)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}
