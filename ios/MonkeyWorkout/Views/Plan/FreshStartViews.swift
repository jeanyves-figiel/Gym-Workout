import SwiftUI
import WorkoutEngine

// MARK: - Start fresh (#492)
//
// Design A + B from `fresh-start/proposals.png`: a "Start fresh" card at the bottom of Training profile opens a
// sheet saying what goes and what stays. **Build my new plan** keeps the current answers (A); **Answer again**
// opens every plan question prefilled (B). Either way a gradient Undo bar follows.

private let freshColors = [Color(red: 1, green: 0.62, blue: 0.11), Color(red: 1, green: 0.24, blue: 0.35)]
private var freshGradient: LinearGradient { LinearGradient(colors: freshColors, startPoint: .topLeading, endPoint: .bottomTrailing) }

/// Training profile → last card: icon tile left, heavy title, chevron right.
struct FreshStartCard: View {
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 22, weight: .bold))
                    .frame(width: 52, height: 52)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.22)))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Start fresh").font(Theme.display(21)).lineLimit(1).minimumScaleFactor(0.6)
                    Text("New plan from scratch, history kept").font(.footnote.weight(.semibold)).opacity(0.88).lineLimit(2)
                }
                .layoutPriority(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.footnote.bold()).opacity(0.7)
            }
            .foregroundStyle(.white)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(freshGradient))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
        .accessibilityLabel("Start fresh: new plan from scratch, history kept")
        .sheet(isPresented: $open) { FreshStartSheet() }
    }
}

/// What goes and what stays, then a new plan with the same answers or with the plan questions answered again.
struct FreshStartSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var answering = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    HStack(alignment: .top, spacing: 10) {
                        list("GOES", goes, colors: [Color(red: 1, green: 0.24, blue: 0.55), Color(red: 1, green: 0.6, blue: 0.37)])
                        list("STAYS", ["History", "PRs & XP", "Profile & gyms", "What Monkey learned", "Your own workouts"],
                             colors: WorkoutEngine.Category.cardio.colors)
                    }
                    Button { build(nil) } label: { Label("Build my new plan", systemImage: "arrow.counterclockwise") }
                        .buttonStyle(LimeButtonStyle())
                        .accessibilityIdentifier("fresh.build")
                    Button { answering = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 18, weight: .bold))
                                .frame(width: 40, height: 40)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.22)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Answer again").font(Theme.display(18))
                                Text("Goal, week, time, style, gym: prefilled").font(.caption.weight(.semibold)).opacity(0.88)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right").font(.footnote.bold()).opacity(0.7)
                        }
                        .foregroundStyle(.white)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(WorkoutEngine.Category.strength.gradient))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("fresh.answer")
                    Text("Workouts already done this week stay done.").font(.footnote).foregroundStyle(Theme.muted)
                }
                .padding(16)
            }
            .readableWidth()
            .background(Theme.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $answering) {
                if let p = model.freshStartProfile {
                    ProfileFormView(initial: p) { build($0) }
                        .navigationTitle("Start from scratch")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Start fresh?").font(Theme.display(28))
                Text("Monkey builds a brand new plan").font(.subheadline.weight(.semibold)).opacity(0.9)
            }
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 14, weight: .heavy))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(.white.opacity(0.25)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(freshGradient))
    }

    /// What this plan has that a fresh start drops; the plan's own exercises when nothing was customised.
    private var goes: [String] {
        let clears = model.freshStartClears
        return clears.isEmpty ? ["This week's exercises"] : clears
    }

    private func list(_ title: String, _ items: [String], colors: [Color]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(Theme.label(11)).tracking(1.3).opacity(0.8)
            ForEach(items, id: \.self) { Text($0).font(.subheadline.weight(.bold)) }
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)))
        .accessibilityElement(children: .combine)
    }

    private func build(_ profile: Profile?) {
        guard let undo = model.startFresh(profile) else { return dismiss() }
        dismiss()
        let p = model.profile
        UndoCloseCenter.shared.show(UndoOffer(
            title: "Fresh plan ready", detail: p.map { "\($0.goal.config.label) · \($0.sessionsPerWeek) days" } ?? "New plan",
            symbol: "arrow.counterclockwise", colors: freshColors, reopen: { AnyView(EmptyView()) },
            revert: { [model] in model.undoFreshStart(undo) }))
    }
}
