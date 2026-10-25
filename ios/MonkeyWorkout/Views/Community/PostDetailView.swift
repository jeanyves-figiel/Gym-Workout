import APIClient
import SwiftUI
import WorkoutEngine

/// A Social post opened (#779, design "Poster"): the post's colours full page, then what it was made of. A shared
/// workout lists every exercise and can be copied: today, a day this week or My workouts (sets and reps; weights
/// stay the member's own). Level ups open the ladder, streaks the weeks, bests and recipes keep their action.
struct PostDetailView: View {
    let post: CommunityPost
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var added: String?
    @State private var error: String?
    @State private var ladder = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    hero
                    switch CommunityMoment(post) {
                    case .level: level
                    case .streak: streak
                    default: content
                    }
                }
                .padding(16)
            }
            .readableWidth()
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(post.author.nickname)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
            .sheet(isPresented: $ladder) { LevelLadderSheet() }
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                AvatarView(url: model.api.resolve(post.author.avatarUrl), nickname: post.author.nickname, size: 28)
                Text(post.author.nickname).font(Theme.label(13)).lineLimit(1)
                Text(post.createdAt.formatted(.relative(presentation: .named))).font(.caption.weight(.semibold)).opacity(0.8)
            }
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    if let m = CommunityMoment(post) { Text(m.label).font(Theme.label(11)).tracking(1.5).opacity(0.85) }
                    Text(post.payload.title).font(Theme.display(30)).lineLimit(2).minimumScaleFactor(0.7)
                    if let s = post.payload.subtitle { Text(s).font(.subheadline.weight(.semibold)).opacity(0.85) }
                }
                Spacer(minLength: 8)
                if let m = post.payload.metric {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(m.value).font(Theme.display(44)).monospacedDigit()
                        Text(m.unit.uppercased()).font(Theme.label(10)).tracking(1).opacity(0.85)
                    }
                }
            }
            if let stats = post.payload.stats, !stats.isEmpty {
                HStack(spacing: 6) {
                    ForEach(stats, id: \.self) { s in
                        Text("\(s.value) \(s.label)")
                            .font(Theme.label(11))
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(Capsule().fill(.white.opacity(0.18)))
                    }
                }
            }
            if let c = post.caption { Text(c).font(.subheadline.weight(.medium)) }
        }
        .foregroundStyle(post.ink)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(post.gradient))
        .accessibilityElement(children: .combine)
    }

    // MARK: Workout

    @ViewBuilder private var content: some View {
        if let list = post.payload.exercises, !list.isEmpty {
            ForEach(Array(list.enumerated()), id: \.offset) { _, e in exerciseTile(e) }
            if !post.mine { copy(list) }
        } else if post.kind == "workout", (post.payload.style ?? "strength") == "strength" {
            note("Shared before posts carried their exercises: only the totals are known.")
        }
        if !post.mine, PostAction.exercise(post) != nil || PostAction.recipe(post) != nil {
            HStack {
                Text(PostAction.exercise(post) != nil ? "Can you beat it?" : "Like it?").font(Theme.label(15))
                Spacer()
                PostAction(post: post)
            }
            .foregroundStyle(post.ink)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(post.gradient))
        }
    }

    private func exerciseTile(_ e: CommunityCard.Exercise) -> some View {
        let known = Exercise.find(e.id)
        let category = known?.category ?? .strength
        return HStack(spacing: 12) {
            Image(systemName: category.symbol)
                .font(.system(size: 17, weight: .bold))
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(0.25)))
            VStack(alignment: .leading, spacing: 5) {
                Text(known?.name ?? e.name).font(Theme.label(15)).lineLimit(2)
                HStack(spacing: 4) {
                    Text(Self.sets(e, unit: known?.unit))
                        .font(Theme.label(11)).monospacedDigit()
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.black.opacity(0.22)))
                    if !post.mine, e.kg != nil, let mine = model.lastWeight(e.id) {
                        Text("you \(Format.kg(mine)) kg")
                            .font(Theme.label(11)).monospacedDigit()
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(0.28)))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(category.gradient))
        .accessibilityElement(children: .combine)
    }

    /// "5 × 5 × 100 kg", "3 × 45 s", "3 sets".
    static func sets(_ e: CommunityCard.Exercise, unit: WorkoutEngine.Unit?) -> String {
        var s = "\(e.sets) × "
        if let r = e.reps, r > 0 { s += "\(Int(r.rounded()))\(unit == .sec ? " s" : "")" } else { return "\(e.sets) sets" }
        if let kg = e.kg, kg > 0 { s += " × \(Format.kg(kg)) kg" }
        return s
    }

    // MARK: Make it yours (design C destinations)

    private func copy(_ list: [CommunityCard.Exercise]) -> some View {
        let today = model.todayWeekday
        return VStack(alignment: .leading, spacing: 10) {
            Text("Make it yours").font(Theme.display(22))
            Text("Copies the exercises, sets and reps. Weights come from your own history.")
                .font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
            if let added {
                HStack {
                    Label(added, systemImage: "checkmark.circle.fill").font(Theme.label(15))
                    Spacer()
                    Button("Open Train") {
                        model.tab = .train
                        dismiss()
                    }
                    .font(Theme.label(13))
                    .buttonStyle(.borderedProminent).tint(Theme.lime).foregroundStyle(Theme.ink)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.lime.opacity(0.18)))
            }
            destination("play.fill", "Do it today", "Added to today's plan", colors: [Color(hex: 0xFF7A2F), Color(hex: 0xE8455E)]) {
                plan(list, weekday: today)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    tileIcon("calendar")
                    Text("Add to a day").font(Theme.label(16))
                }
                HStack(spacing: 5) {
                    ForEach(today...7, id: \.self) { wd in
                        Button { plan(list, weekday: wd) } label: {
                            VStack(spacing: 1) {
                                Text(WeekSchedule.shortName(wd)).font(Theme.label(11))
                                Text(wd == today ? "Today" : "").font(.system(size: 8, weight: .bold))
                            }
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.black.opacity(0.22)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add to \(WeekSchedule.name(wd))")
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0xC64DFF), Color(hex: 0xFF4FA3)], startPoint: .topLeading, endPoint: .bottomTrailing)))
            destination("books.vertical.fill", "Save to My workouts", "Reuse it whenever", colors: [Color(hex: 0x00C9A7), Color(hex: 0x2F8CFF)]) {
                model.saveCustomWorkout(workout(list))
                added = "Saved to My workouts"
            }
            ErrorText(message: error)
        }
        .padding(.top, 6)
    }

    private func destination(_ symbol: String, _ title: String, _ detail: String, colors: [Color], tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 10) {
                tileIcon(symbol)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.label(16))
                    Text(detail).font(.caption.weight(.semibold)).opacity(0.85)
                }
                Spacer(minLength: 0)
                Image(systemName: "plus").font(.body.bold())
            }
            .foregroundStyle(.white)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
        }
        .buttonStyle(.plain)
    }

    private func tileIcon(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 15, weight: .bold))
            .frame(width: 34, height: 34)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.28)))
    }

    private func plan(_ list: [CommunityCard.Exercise], weekday: Int) {
        guard model.addExtra(workout(list), weekday: weekday) != nil else {
            error = "Set up your week in Train first."
            return
        }
        error = nil
        added = weekday == model.todayWeekday ? "Added to today" : "Added to \(WeekSchedule.name(weekday))"
    }

    /// The member's copy: catalog exercises only, their sets and reps, rest by category.
    func workout(_ list: [CommunityCard.Exercise]) -> CustomWorkout {
        CustomWorkout.copying(list, title: post.payload.title, from: post.author.nickname)
    }

    // MARK: Level and streak

    private var level: some View {
        let theirs = Int(post.payload.metric?.value ?? "") ?? post.author.level ?? 1
        let rank = GameRank.of(level: theirs)
        let mine = model.game.level
        return VStack(alignment: .leading, spacing: 10) {
            Text("The ladder").font(Theme.display(22))
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(GameRank.allCases) { r in
                    VStack(spacing: 4) {
                        if r == model.rank { Text("you").font(.system(size: 9, weight: .heavy)).foregroundStyle(Theme.lime) }
                        Text(r.title).font(.system(size: 9, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.6)
                            .frame(maxWidth: .infinity, minHeight: CGFloat(28 + r.rawValue * 12), alignment: .top)
                            .padding(.top, 6)
                            .foregroundStyle(r == rank ? Color(hex: 0x2F6BFF) : Color.white)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(r == rank ? Color.white : Color.white.opacity(0.22)))
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(CommunityMoment.level.gradient))
            Text("\(post.author.nickname) is \(rank.title), level \(theirs). You're level \(mine).")
                .font(.subheadline.weight(.semibold))
            bigButton("See my level") { ladder = true }
        }
    }

    private var streak: some View {
        let theirs = Int(post.payload.metric?.value ?? "") ?? 0
        let mine = Progression.stats(records: model.state.history, weights: model.weightEntries, targetPerWeek: model.gameTarget).currentStreakWeeks
        let shown = min(max(theirs, 1), 12)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Weeks in a row").font(Theme.display(22))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                ForEach(0..<shown, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white)
                        .frame(height: 30)
                        .overlay(Text("🔥").font(.caption))
                        .accessibilityHidden(true)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(CommunityMoment.streak.gradient))
            Text(mine >= theirs ? "You're on \(mine) weeks: already level with \(post.author.nickname)."
                 : "You're on \(mine) week\(mine == 1 ? "" : "s"). \(theirs - mine) more to catch up.")
                .font(.subheadline.weight(.semibold))
            bigButton("🔥 Beat it: open my week") {
                model.tab = .train
                dismiss()
            }
        }
    }

    private func bigButton(_ title: String, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Text(title).font(Theme.label(16)).frame(maxWidth: .infinity, minHeight: 50)
                .foregroundStyle(Theme.ink)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.lime))
        }
        .buttonStyle(.plain)
    }

    private func note(_ text: String) -> some View {
        Label(text, systemImage: "info.circle.fill")
            .font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
    }
}

extension CommunityMoment {
    var gradient: LinearGradient { LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing) }
}

extension CustomWorkout {
    /// A member's shared workout as the viewer's own (#779): known exercises only, their sets and reps
    /// (seconds for holds), rest by category. Weights are never copied: the player uses the viewer's own.
    static func copying(_ list: [CommunityCard.Exercise], title: String, from nickname: String) -> CustomWorkout {
        let items = list.compactMap { e -> Item? in
            guard let ex = Exercise.find(e.id) else { return nil }
            var item = Item(adding: ex)
            item.sets = max(1, min(e.sets, 10))
            if let r = e.reps, r > 0 { item.reps = Int(r.rounded()) }
            return item
        }
        return CustomWorkout(name: String("\(title) · \(nickname)".prefix(60)), items: items)
    }
}
