import SwiftUI
import WorkoutEngine

// Calisthenics skill tree (#621, designs A + B + C from `apple-tech-radar/batch4.html`).

extension Skills.Branch {
    var gradient: LinearGradient {
        let c: [Color] = switch self {
        case .pull: [Color(hex: 0x00C6A7), Color(hex: 0x1E6BFF)]
        case .push: [Color(hex: 0xFF4D8D), Color(hex: 0xFF8A00)]
        case .legs: [Color(hex: 0xFF8A00), Color(hex: 0xFFD400)]
        case .balance: [Color(hex: 0x8A2BFF), Color(hex: 0xFF4D8D)]
        }
        return LinearGradient(colors: c, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Explore → Programmes: entry to the tree with each branch's level.
struct SkillTreeCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationLink { SkillTreeView() } label: {
            HStack(spacing: 14) {
                Image(systemName: "figure.gymnastics")
                    .font(.system(size: 24, weight: .bold))
                    .frame(width: 52, height: 52)
                    .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.2)))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Skill tree").font(Theme.display(20))
                    Text(Skills.Branch.allCases.map { "\($0.label.prefix(4)) L\(model.skills.unlocked($0))" }.joined(separator: " · "))
                        .font(Theme.label(12)).opacity(0.9).lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.subheadline.weight(.heavy))
            }
            .foregroundStyle(.white)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Skills.Branch.balance.gradient))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Bodyweight skills with levels: pull, push, legs, balance")
    }
}

/// A: four branches of square nodes; passed = lime, current = white, locked = dim. Tap a node for its test.
struct SkillTreeView: View {
    @Environment(AppModel.self) private var model
    @State private var open: Skills.Node?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Skill tree").font(Theme.display(34))
                Text("Home, park, travel · test to unlock").eyebrow()
                if let focus = model.skillOfMonth { monthBanner(focus) }
                ForEach(Skills.Branch.allCases) { b in branch(b) }
                Text("Each skill opens the next when you pass its test: max reps, or seconds for holds. Pick one skill of the month and Train adds a 10′ practice on Monday, Wednesday and Friday.")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            .padding(16)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $open) { SkillNodeSheet(node: $0) }
    }

    private func monthBanner(_ n: Skills.Node) -> some View {
        let p = model.skillPracticeDays
        return HStack(spacing: 12) {
            Image(systemName: p.done >= p.goal ? "gift.fill" : "calendar")
                .font(.system(size: 18, weight: .bold))
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.22)))
            VStack(alignment: .leading, spacing: 2) {
                Text("Skill of \(Date().formatted(.dateTime.month(.wide)))").font(Theme.label(10)).tracking(1.2).textCase(.uppercase).opacity(0.85)
                Text(n.exercise.name).font(Theme.display(18)).lineLimit(1).minimumScaleFactor(0.7)
                Text("10′ practice Mon/Wed/Fri").font(Theme.label(11)).opacity(0.85)
            }
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(p.done)").font(Theme.display(28)).monospacedDigit()
                Text("/\(p.goal)").font(Theme.label(13))
            }
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(n.branch.gradient))
        .accessibilityElement(children: .combine)
    }

    private func branch(_ b: Skills.Branch) -> some View {
        let level = model.skills.unlocked(b)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(b.label, systemImage: b.symbol).font(Theme.display(18))
                Spacer(minLength: 0)
                Text("L\(level)").font(Theme.display(22)).monospacedDigit()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Skills.nodes(b)) { n in
                        let passed = model.skills.passed(n)
                        let current = n.level == level && !passed
                        let locked = n.level > level
                        Button { open = n } label: {
                            VStack(spacing: 3) {
                                Image(systemName: passed ? "checkmark" : locked ? "lock.fill" : "flag.fill")
                                    .font(.system(size: 13, weight: .heavy))
                                Text(n.exercise.name).font(Theme.label(10)).multilineTextAlignment(.center)
                                    .lineLimit(2).minimumScaleFactor(0.7)
                            }
                            .foregroundStyle(passed || current ? Theme.ink : .white.opacity(0.75))
                            .padding(6)
                            .frame(width: 76, height: 76)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(passed ? AnyShapeStyle(Theme.lime) : current ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.white.opacity(0.14))))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(n.exercise.name), level \(n.level), \(passed ? "passed" : locked ? "locked" : "to test")")
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(b.gradient))
    }
}

/// B: a node's test (max reps or a hold timer), its best, and C: make it the skill of the month or practise now.
struct SkillNodeSheet: View {
    let node: Skills.Node
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var result = 0
    @State private var holdStart: Date?
    @State private var unlocked: Skills.Node?
    @State private var saved = false

    private var locked: Bool { node.level > model.skills.unlocked(node.branch) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Level \(node.level) · \(node.branch.label)").eyebrow()
                    Text(node.exercise.name).font(Theme.display(30))
                    Text("Unlock the next level: \(node.targetText)" + ((model.skills.best?[node.exerciseId]).map { " · best \(node.seconds ? "\($0) s" : "\($0)")" } ?? ""))
                        .font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
                    if locked {
                        Label("Pass level \(node.level - 1) first", systemImage: "lock.fill").font(Theme.label(15))
                    } else {
                        testCard
                    }
                    if let unlocked {
                        Label("Unlocked L\(unlocked.level) · \(unlocked.exercise.name) 🎉", systemImage: "lock.open.fill")
                            .font(Theme.display(16)).foregroundStyle(Theme.lime)
                    } else if saved {
                        Label("Saved", systemImage: "checkmark").font(Theme.label(14)).foregroundStyle(Theme.lime)
                    }
                    if !locked {
                        let isFocus = model.skillOfMonth == node
                        Button {
                            model.setSkillOfMonth(isFocus ? nil : node)
                        } label: {
                            Label(isFocus ? "Stop skill of the month" : "Make it skill of the month", systemImage: isFocus ? "xmark" : "calendar.badge.plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(LimeButtonStyle())
                        NavigationLink(value: Skills.practice(node).sessionId) {
                            Label("Practise now · 10′", systemImage: "play.fill").font(Theme.label(15))
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .foregroundStyle(.white)
                                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.14)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationDestination(for: String.self) { SessionView(sessionId: $0) }
            .toolbar { CloseToolbarItem { dismiss() } }
        }
        .presentationDetents([.large])
    }

    /// Reps: a big count with − / +. Holds: Start / Stop timer.
    private var testCard: some View {
        VStack(spacing: 12) {
            Text("Test your max").font(Theme.label(12)).tracking(1.2).textCase(.uppercase).opacity(0.85)
            if node.seconds {
                TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                    let s = holdStart.map { Int(ctx.date.timeIntervalSince($0)) } ?? result
                    Text("\(s) s").font(Theme.display(64)).monospacedDigit()
                }
                Button(holdStart == nil ? "Start hold" : "Stop") {
                    if let start = holdStart {
                        result = Int(Date().timeIntervalSince(start))
                        holdStart = nil
                        Haptics.success()
                    } else {
                        holdStart = Date()
                        Haptics.start()
                    }
                }
                .font(Theme.display(18))
            } else {
                HStack(spacing: 24) {
                    Button { result = max(0, result - 1) } label: { Image(systemName: "minus").font(.title2.weight(.heavy)).frame(width: 56, height: 56) }
                    VStack(spacing: 0) {
                        Text("\(result)").font(Theme.display(64)).monospacedDigit()
                        Text("/ \(node.target)").font(Theme.label(13)).opacity(0.85)
                    }
                    Button { result += 1; Haptics.undo() } label: { Image(systemName: "plus").font(.title2.weight(.heavy)).frame(width: 56, height: 56) }
                }
                .buttonStyle(.plain)
            }
            if result > 0, result < node.target {
                Text("\(node.target - result) more to unlock L\(min(node.level + 1, Skills.nodes(node.branch).count))")
                    .font(Theme.label(13)).opacity(0.9)
            }
            Button("Save test") {
                unlocked = model.recordSkillTest(node, result: result)
                saved = true
                Haptics.success()
            }
            .buttonStyle(LimeButtonStyle())
            .disabled(result == 0 || holdStart != nil)
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(node.branch.gradient))
    }
}

/// C on Train: on a practice day (Mon/Wed/Fri) of the skill of the month, a bar to its 10′ practice.
struct SkillPracticeBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let node = model.skillOfMonth, Skills.practiceDays.contains(model.todayWeekday) {
            let p = model.skillPracticeDays
            NavigationLink(value: Skills.practice(node).sessionId) {
                HStack(spacing: 8) {
                    Image(systemName: node.branch.symbol)
                        .font(.system(size: 17, weight: .bold))
                        .frame(width: 38, height: 38)
                        .background(RoundedRectangle(cornerRadius: 11).fill(.white.opacity(0.22)))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Skill practice · \(node.exercise.name)").font(Theme.display(16)).lineLimit(1).minimumScaleFactor(0.7)
                        Text(p.done >= p.goal ? "Month done · chest earned 🎁" : "\(p.done)/\(p.goal) days this month · 10′")
                            .font(Theme.label(11)).opacity(0.85).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.subheadline.weight(.heavy))
                }
                .foregroundStyle(.white)
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(node.branch.gradient))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
