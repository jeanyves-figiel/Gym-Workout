import SwiftUI
import WorkoutEngine

/// What the app learned about the member's exercise likes and dislikes (#299), design A + C from
/// `member-learning/proposals.png`: the What Monkey learned page (Settings → profile card since #305) and the coach's new-week card (Train).

private let likedColor = Theme.lime
private let avoidColor = Color(red: 1, green: 0.24, blue: 0.35)

/// Settings → profile card → What Monkey learned (#305, design B from `learned-settings/proposals.png`):
/// a strip inside the member's profile card with the top liked / avoided moves.
struct TasteProfileStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let t = model.memberTaste
        let now = Date()
        let liked = t.liked(at: now).compactMap { Exercise.find($0) }
        let avoided = t.disliked(at: now).compactMap { Exercise.find($0) }
        NavigationLink { TasteView() } label: {
            HStack(spacing: 10) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.white.opacity(0.22)))
                VStack(alignment: .leading, spacing: 5) {
                    Text("What Monkey learned").font(Theme.display(16)).lineLimit(1).minimumScaleFactor(0.7)
                    if !model.learningOn || liked.isEmpty && avoided.isEmpty {
                        Text(model.learningOn ? "Learning from your choices" : "Learning off")
                            .font(.caption.weight(.semibold)).opacity(0.88).lineLimit(1)
                    } else {
                        // Two liked and one avoided fit one row on the smallest iPhone.
                        HStack(spacing: 5) {
                            ForEach(liked.prefix(avoided.isEmpty ? 3 : 2), id: \.id) { chip("♥ \($0.name)", fill: likedColor, ink: true) }
                            ForEach(avoided.prefix(liked.isEmpty ? 3 : 1), id: \.id) { chip("✕ \($0.name)", fill: avoidColor, ink: false) }
                        }
                    }
                }
                .layoutPriority(1)
                Spacer(minLength: 4)
                Text("\(liked.count + avoided.count)").font(Theme.display(20)).fixedSize()
                Image(systemName: "chevron.right").font(.footnote.bold()).opacity(0.7)
            }
            .foregroundStyle(.white)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.black.opacity(0.25)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("What Monkey learned: \(liked.count) liked, \(avoided.count) avoided")
    }

    private func chip(_ text: String, fill: Color, ink: Bool) -> some View {
        Text(text)
            .font(Theme.label(10)).lineLimit(1).truncationMode(.tail)
            .foregroundStyle(ink ? Theme.ink : .white)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(fill))
    }
}

/// Liked and avoided exercises with the reason; tap one to forget it, never see it again or say you like it.
struct TasteView: View {
    @Environment(AppModel.self) private var model
    /// What Reset removed, for Undo.
    @State private var undo: MemberTaste?

    var body: some View {
        let t = model.memberTaste
        let now = Date()
        let liked = t.liked(at: now).compactMap { Exercise.find($0) }
        let avoided = t.disliked(at: now).compactMap { Exercise.find($0) }
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                hero(count: liked.count + avoided.count)
                if !liked.isEmpty {
                    Label("You like", systemImage: "heart.fill").font(Theme.label(12)).tracking(1.4).textCase(.uppercase)
                        .foregroundStyle(likedColor).padding(.top, 4)
                    ForEach(liked, id: \.id) { row($0, taste: t, now: now) }
                }
                if !avoided.isEmpty {
                    Label("You avoid", systemImage: "xmark").font(Theme.label(12)).tracking(1.4).textCase(.uppercase)
                        .foregroundStyle(avoidColor).padding(.top, 4)
                    ForEach(avoided, id: \.id) { row($0, taste: t, now: now) }
                }
                if liked.isEmpty && avoided.isEmpty {
                    Text("Nothing yet. Swap, remove or skip exercises and finish workouts: Monkey picks up what you like and shapes next week around it.")
                        .font(.callout).foregroundStyle(Theme.muted)
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
                }
                Toggle(isOn: Binding(get: { model.learningOn }, set: { model.setLearning($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Learn from my choices").font(Theme.label(15))
                        Text("Off: plans ignore what Monkey learned").font(.caption).foregroundStyle(Theme.muted)
                    }
                }
                .tint(Theme.lime)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
                .padding(.top, 6)
                if let undo {
                    HStack {
                        Text("Monkey forgot everything").font(Theme.label(14))
                        Spacer()
                        Button("Undo") { model.restoreTaste(undo); self.undo = nil }
                            .font(Theme.label(14)).foregroundStyle(Theme.ink)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Capsule().fill(Theme.lime))
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(LinearGradient(colors: UndoOffer.warm, startPoint: .leading, endPoint: .trailing)))
                } else if !t.isEmpty {
                    Button { withAnimation { undo = model.resetTaste() } } label: {
                        Text("Reset what Monkey learned").font(Theme.label(15)).frame(maxWidth: .infinity).padding(.vertical, 13)
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("What Monkey learned")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func hero(count: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 24, weight: .bold))
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.black.opacity(0.22)))
            VStack(alignment: .leading, spacing: 3) {
                Text(model.learningOn ? "Learning from you" : "Learning off").font(Theme.display(21)).lineLimit(1).minimumScaleFactor(0.6)
                Text("Swaps, edits and skipped moves shape next week").font(.footnote.weight(.semibold)).opacity(0.9)
            }
            Spacer(minLength: 4)
            Text("\(count)").font(Theme.display(34))
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(WorkoutEngine.Category.mobility.gradient))
    }

    private func row(_ e: Exercise, taste: MemberTaste, now: Date) -> some View {
        let a = taste.affinity(e.id, at: now)
        let mark = taste.mark(e.id)
        return Menu {
            Button("Forget this", systemImage: "arrow.uturn.backward") { withAnimation { model.forgetTaste(e.id) } }
            if mark != .never {
                Button("Never suggest again", systemImage: "nosign", role: .destructive) { withAnimation { model.markTaste(e.id, .never) } }
            }
            if a < 0 {
                Button("Actually, I like it", systemImage: "heart") { withAnimation { model.markTaste(e.id, .liked) } }
            }
        } label: {
            HStack(spacing: 10) {
                ExerciseThumbnail(exercise: e, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.name).font(Theme.display(16)).foregroundStyle(.white).lineLimit(2).minimumScaleFactor(0.7)
                        .multilineTextAlignment(.leading)
                    Text(taste.reason(e.id, at: now)).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.85)).lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 6)
                // On a dark chip so the lime / red bar reads on the gradient (#823).
                Group {
                    if mark == .never {
                        Image(systemName: "nosign").font(.footnote.bold()).foregroundStyle(avoidColor)
                    } else {
                        TasteBar(affinity: a)
                    }
                }
                .padding(.horizontal, 7).padding(.vertical, 7)
                .background(Capsule().fill(.black.opacity(0.3)))
            }
            .padding(10)
            // Gradient tiles (#823): liked on teal, avoided on violet, thumbnail as the tile on the left.
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(a > 0 && mark != .never ? WorkoutEngine.Category.cardio.gradient : WorkoutEngine.Category.strength.gradient))
            .contentShape(Rectangle())
        }
        .accessibilityLabel("\(e.name), \(a > 0 ? "liked" : "avoided"). \(taste.reason(e.id, at: now))")
    }
}

/// Centre-zero bar: lime to the right for liked, red to the left for avoided.
private struct TasteBar: View {
    let affinity: Double

    var body: some View {
        let w: CGFloat = 46
        let share = affinity > 0 ? min(1, affinity / 0.9) : min(1, -affinity / 3)
        ZStack(alignment: .leading) {
            Capsule().fill(Theme.cardStrong).frame(width: w, height: 6)
            Capsule().fill(affinity > 0 ? likedColor : avoidColor)
                .frame(width: max(4, w / 2 * share), height: 6)
                .offset(x: affinity > 0 ? w / 2 : w / 2 - max(4, w / 2 * share))
        }
        .frame(width: w)
    }
}

/// Train: the coach says what a new week's plan changed because of what it learned, each change with Undo.
struct TasteRecapCard: View {
    let recap: TasteRecap
    @Environment(AppModel.self) private var model

    var body: some View {
        let out = recap.changes.filter { $0.kind == .out }.count
        let more = recap.changes.count - out
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                MonkeyFace(mood: .happy, scale: 0.75, gear: model.rank.gear)
                Text(headline(out: out, more: more)).font(Theme.label(15)).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(recap.changes) { c in change(c) }
            HStack(spacing: 10) {
                Button { withAnimation { model.dismissTasteRecap() } } label: {
                    Text("Got it").font(Theme.label(15)).foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.lime))
                }
                .buttonStyle(.plain)
                NavigationLink { TasteView() } label: {
                    Text("What Monkey learned ›").font(Theme.label(14)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.black.opacity(0.25)))
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(LinearGradient(colors: UndoOffer.warm, startPoint: .topLeading, endPoint: .bottomTrailing)))
    }

    private func headline(out: Int, more: Int) -> String {
        var parts: [String] = []
        if out > 0 { parts.append("I left out \(out == 1 ? "a move" : "\(out) moves") you keep swapping") }
        if more > 0 { parts.append("added more of what you like") }
        return "New week, made for you! " + parts.joined(separator: " and ") + "."
    }

    private func change(_ c: TasteChange) -> some View {
        let from = Exercise.find(c.from)?.name ?? c.from
        let to = Exercise.find(c.to)?.name ?? c.to
        return HStack(spacing: 8) {
            Text(c.kind == .out ? "OUT" : "MORE").font(Theme.label(10)).tracking(0.8)
                .foregroundStyle(c.kind == .out ? .white : Theme.ink)
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(Capsule().fill(c.kind == .out ? avoidColor : likedColor))
            VStack(alignment: .leading, spacing: 1) {
                Group {
                    if c.kind == .out {
                        Text("\(Text(from).strikethrough()) → \(to)")
                    } else {
                        Text(c.workouts > 1 ? "\(to), \(c.workouts) workouts" : to)
                    }
                }
                .font(Theme.label(13)).lineLimit(2)
                Text(model.memberTaste.reason(c.subject, at: Date())).font(.caption2.weight(.semibold)).opacity(0.75).lineLimit(1)
            }
            Spacer(minLength: 4)
            Button("Undo") { withAnimation { model.undoTasteChange(c) } }
                .font(Theme.label(12)).foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Capsule().fill(.black.opacity(0.3)))
                .buttonStyle(.plain)
                .accessibilityLabel("Undo: put \(c.kind == .out ? from : "the planned exercise") back")
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.black.opacity(0.22)))
    }
}
