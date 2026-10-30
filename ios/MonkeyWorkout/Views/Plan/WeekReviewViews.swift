import SwiftUI
import WorkoutEngine

/// Weekly Coach review on Train (#867, design A + C from `ai-epic/a1.png`): Sunday and Monday, Coach's look at the week
/// just done on a gradient card (score right, facts line, a few sentences) and up to 3 changes for the coming week, each
/// with Apply; Apply all, Ask Coach about it (the chat opens on the review) and ✕.
struct WeekReviewCard: View {
    let saved: WeekReviewStore.Saved
    @Environment(AppModel.self) private var model

    private var review: WeekReview { saved.review }
    private var open: [WeekReviewChange] { review.changes.filter { !model.isApplied($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            hero
            if !review.changes.isEmpty {
                Text("Next week · \(review.changes.count) \(review.changes.count == 1 ? "change" : "changes")").eyebrow()
                VStack(spacing: 6) {
                    ForEach(review.changes) { c in row(c) }
                }
            }
            HStack(spacing: 8) {
                if open.count > 1 {
                    pill("Apply all", lime: true) { withAnimation(.snappy) { open.forEach(model.applyWeekReview) } }
                        .accessibilityIdentifier("weekReview.applyAll")
                }
                pill("Ask Coach about it", lime: false) { model.askCoachAboutWeekReview(review) }
                    .accessibilityIdentifier("weekReview.ask")
            }
        }
        .accessibilityIdentifier("weekReview")
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Text("🐵").font(.system(size: 20))
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black.opacity(0.18)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Coach's week review").font(Theme.label(16))
                    Text(review.headline).font(.caption.weight(.semibold)).opacity(0.85).lineLimit(1)
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(review.score)").font(Theme.display(30)).monospacedDigit()
                    Text("WEEK SCORE").font(.system(size: 9, weight: .heavy)).tracking(0.8).opacity(0.8)
                }
                Button { withAnimation(.snappy) { model.closeWeekReview() } } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .heavy))
                        .frame(width: 30, height: 30).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black.opacity(0.25)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close the week review")
            }
            if !review.summary.isEmpty {
                Text(review.summary).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.64, green: 0.24, blue: 1), Color(red: 1, green: 0.31, blue: 0.85)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing)))
        .accessibilityElement(children: .combine)
    }

    private func row(_ c: WeekReviewChange) -> some View {
        let done = model.isApplied(c)
        return HStack(spacing: 10) {
            Image(systemName: symbol(c.kind)).font(.system(size: 14, weight: .bold))
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.1)))
            Text(c.label).font(.subheadline.weight(.semibold)).lineLimit(2)
            Spacer(minLength: 6)
            Button { withAnimation(.snappy) { model.applyWeekReview(c) } } label: {
                Text(done ? "Applied ✓" : "Apply").font(Theme.label(13))
                    .foregroundStyle(done ? .white : Theme.ink)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(done ? Color.white.opacity(0.12) : Theme.lime))
            }
            .buttonStyle(.plain)
            .disabled(done)
            .accessibilityIdentifier("weekReview.apply.\(c.kind.rawValue)")
        }
        .foregroundStyle(.white)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    private func pill(_ title: String, lime: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Theme.label(14)).foregroundStyle(lime ? Theme.ink : .white)
                .frame(maxWidth: .infinity).padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(lime ? Theme.lime : Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }

    private func symbol(_ k: WeekReviewChange.Kind) -> String {
        switch k {
        case .move: "calendar.badge.clock"
        case .skip: "moon.zzz.fill"
        case .lighter: "arrow.down.circle.fill"
        case .addSet: "plus.square.fill"
        }
    }
}

#if DEBUG
extension Demo {
    /// Demo review (no network): the coming week's first workout moves, the second gets lighter, +1 set on a lift.
    static func weekReview(_ d: WeekReviewDigest) -> WeekReview {
        var changes: [WeekReviewChange] = []
        let taken = Set(d.next.map(\.weekday))
        if let s = d.next.last, let free = (1...7).first(where: { !taken.contains($0) && !d.offDays.contains($0) }) {
            changes.append(.init(kind: .move, sessionId: s.id, weekday: free, label: "\(s.title) to \(dayName(free)) (you skip \(dayName(s.weekday)))"))
        }
        if let s = d.next.first { changes.append(.init(kind: .lighter, sessionId: s.id, label: "Lighter \(dayName(s.weekday)): sleep is low")) }
        if let s = d.next.dropFirst().first ?? d.next.first, let lift = s.lifts.first {
            changes.append(.init(kind: .addSet, sessionId: s.id, uid: lift.uid, label: "+1 set \(lift.name.lowercased())"))
        }
        return WeekReview(weekOf: d.weekOf, score: 82, headline: "\(d.doneCount) of \(d.days.count) done · 2 PRs · sleep ↓",
                          summary: "Strong week: bench press up to 85 kg and a squat best. You missed Thursday again and slept about 6 hours. Here's how next week fits better.",
                          changes: changes)
    }

    static func dayName(_ wd: Int) -> String { ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][max(0, min(6, wd - 1))] }
}

/// Demo screen `week-review`: the card for this week, any day.
struct DemoWeekReview: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack {
            if let s = WeekReviewStore.shared.saved { WeekReviewCard(saved: s) }
        }
        .task {
            let monday = Progression.weekStart(Date(), model.planCalendar)
            WeekReviewStore.shared.load(ownerId: "demo")
            guard let built = model.weekReviewDigest(reviewed: monday) else { return }
            let (digest, next) = built
            WeekReviewStore.shared.set(.init(review: Demo.weekReview(digest).cleaned(for: digest), nextWeekOf: next))
        }
    }
}
#endif
