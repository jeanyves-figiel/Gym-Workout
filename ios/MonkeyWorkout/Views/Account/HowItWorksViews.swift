import SwiftUI
import WorkoutEngine

/// How it works (#769, design A from `methodology-page/proposals.png`): a Me-sheet tile opening a deck of every
/// calculation behind the member's numbers. Each card shows the member's live number; its page shows the rule,
/// what it gives for them, sources and **Feels off?** (a report prefilled with the topic).
struct HowItWorksView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ContentTitle(title: "How it works", subtitle: "Where every number comes from. Something feels off? Tell us from any page.")
                    .padding(.bottom, 4)
                ForEach(HowItWorks.topics) { topic in
                    NavigationLink { HowItWorksTopicView(topic: topic) } label: { card(topic) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("how.\(topic.id)")
                }
            }
            .padding(16)
            .readableWidth()
        }
        .background(Theme.bg.ignoresSafeArea())
        .titleInContent("How it works")
    }

    private func card(_ topic: HowItWorks.Topic) -> some View {
        HStack(spacing: 12) {
            IconTile(symbol: topic.symbol, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(topic.title).font(Theme.display(18)).lineLimit(1).minimumScaleFactor(0.8)
                Text(topic.summary).font(.caption.weight(.semibold)).opacity(0.85).lineLimit(2)
            }
            Spacer(minLength: 6)
            if let n = HowItWorksLive(model: model).headline(topic.id) {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(n.value).font(Theme.display(22)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    Text(n.unit).font(Theme.label(9)).tracking(0.8).textCase(.uppercase).opacity(0.85)
                }
                .fixedSize()
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(topic.gradient))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// One topic: where it shows, what it gives for the member, each calculation as a gradient card, sources, Feels off?.
struct HowItWorksTopicView: View {
    @Environment(AppModel.self) private var model
    let topic: HowItWorks.Topic

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ContentTitle(title: topic.title, subtitle: "Shows in: \(topic.shows)")
                    .padding(.bottom, 4)
                if let you = HowItWorksLive(model: model).yours(topic.id) {
                    Label(you, systemImage: "person.fill")
                        .font(.subheadline.weight(.bold)).foregroundStyle(Theme.ink)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.lime))
                        .accessibilityIdentifier("how.you")
                }
                ForEach(Array(topic.parts.enumerated()), id: \.offset) { i, part in
                    partCard(part, index: i)
                }
                sources
                NavigationLink {
                    ReportProblemView(draft: ReportDraft(via: .settings, kind: .broken, area: ReportDraft.howItWorks,
                                                         screen: "How it works · \(topic.title)"))
                } label: {
                    HStack(spacing: 12) {
                        IconTile(symbol: "exclamationmark.bubble.fill", size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Feels off?").font(Theme.display(18))
                            Text("Tell us which number and what you expected").font(.caption.weight(.semibold)).opacity(0.85)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(LinearGradient(colors: [Color(hex: 0xFF3D77), Color(hex: 0xFF8A00)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("how.feelsOff")
            }
            .padding(16)
            .readableWidth()
        }
        .background(Theme.bg.ignoresSafeArea())
        .titleInContent(topic.title)
    }

    /// Each calculation as a gradient tile (#823): number tile left, the plain-language title and text, the formula as
    /// small secondary lines under it.
    private func partCard(_ part: HowItWorks.Part, index i: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(i + 1)").font(Theme.display(20)).monospacedDigit()
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.white.opacity(0.22)))
            VStack(alignment: .leading, spacing: 6) {
                Text(part.title).font(Theme.display(17)).fixedSize(horizontal: false, vertical: true)
                Text(part.text).font(.subheadline.weight(.medium)).opacity(0.95).fixedSize(horizontal: false, vertical: true)
                if !part.rule.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(part.rule, id: \.self) { line in
                            Text(line).font(.system(.caption2, design: .monospaced).weight(.semibold)).opacity(0.8)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(i == 0 ? topic.gradient : Theme.routineGradient(i - 1)))
        .accessibilityElement(children: .combine)
    }

    private var sources: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sources").font(Theme.label(12)).tracking(1.2).textCase(.uppercase).foregroundStyle(Theme.muted)
            ForEach(topic.sources, id: \.self) { s in
                Text(s).font(.caption).foregroundStyle(.white.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.card))
    }
}

/// The member's own numbers for a topic, from the same model the rest of the app reads.
@MainActor struct HowItWorksLive {
    let model: AppModel

    /// Big number on the deck card.
    func headline(_ id: String) -> (value: String, unit: String)? {
        switch id {
        case "xp": return ("\(model.game.xpInLevel)", "of \(GameProgress.perLevel) XP")
        case "move": return (Self.k(MoveStore.shared.usual), "usual")
        case "plan": return model.profile.map { (value: "\(Generator.sessionMinutes($0))′", unit: "a session") }
        case "readiness": return ("\(model.tuneVerdict.score)", model.tuneVerdict.level.title)
        case "zones": return ("\(model.heartZones.starts[0])", "zone 2 bpm")
        case "fuel": return ("\(today.protein) g", "protein")
        case "water": return ("\(today.glasses)", "glasses")
        case "caffeine": return ("\(Supplements.caffeineGuideMg)", "mg max")
        default: return nil
        }
    }

    /// What the rule gives for the member, one line.
    func yours(_ id: String) -> String? {
        let g = model.game
        switch id {
        case "xp":
            return "You: \(g.xp) XP → level \(g.level) · \(model.rank.title), \(g.xpToNext) XP to level \(g.level + 1)"
        case "move":
            return "Your usual: \(MoveStore.shared.usual.formatted()) steps a day"
        case "plan":
            guard let p = model.profile else { return nil }
            return "You: \(p.sessionsPerWeek)× a week, \(Generator.sessionMinutes(p))′ a session, \(p.goal.config.label)"
        case "methods":
            return model.profile.map { "Your method: \($0.trainingMethod.label)" }
        case "readiness":
            let v = model.tuneVerdict
            return "Today: \(v.score) → \(v.level.title) · \(v.reason)"
        case "zones":
            let s = model.heartZones.starts
            return "Your zones start at " + s.enumerated().map { "Z\($0.offset + 2) \($0.element)" }.joined(separator: " · ") + " bpm"
        case "fuel":
            let f = today
            return "Today (\(f.load.label.lowercased())): \(f.protein) g protein · \(f.carbs) g carbs · \(f.fat) g fat · \(f.kcal.formatted()) kcal"
                + (f.estimated ? " · typical body, log your weight" : "")
        case "water":
            return "Today: \(today.glasses) glasses · \((Double(today.waterMl) / 1000).formatted(.number.precision(.fractionLength(1)))) L"
        default:
            return nil
        }
    }

    private var today: FuelPlan { model.fuelPlan(on: Date()) }

    static func k(_ n: Int) -> String {
        n >= 1000 ? (Double(n) / 1000).formatted(.number.precision(.fractionLength(1))) + "k" : "\(n)"
    }
}

extension HowItWorks.Topic {
    var gradient: LinearGradient {
        LinearGradient(colors: colors.map { Color(hex: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
