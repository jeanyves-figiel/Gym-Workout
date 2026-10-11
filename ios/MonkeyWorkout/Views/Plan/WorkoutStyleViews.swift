import SwiftUI
import WorkoutEngine

/// Workout detail (#106): this workout's rest between sets and grouping, as one vivid card that opens the picker.
struct WorkoutStyleCard: View {
    let session: Session
    @Environment(AppModel.self) private var model
    @State private var editing = false

    var body: some View {
        if let profile = model.profile, model.canStyle(session) {
            let style = model.sessionStyle(session.id)
            let rest = style.rest ?? profile.rest
            let group = style.grouping ?? profile.group
            Button { editing = true } label: {
                HStack(spacing: 14) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 22, weight: .bold))
                        .frame(width: 52, height: 52)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.22)))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(style.isEmpty ? "PLAN DEFAULT" : "THIS WORKOUT ONLY").font(Theme.label(10)).tracking(1.2).opacity(0.85)
                        Text(rest.label).font(Theme.display(20)).lineLimit(1).minimumScaleFactor(0.7)
                        Text("\(group.label) · tap to change").font(.footnote.weight(.semibold)).opacity(0.85)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(rest.range.value).font(Theme.display(26)).lineLimit(1).minimumScaleFactor(0.6)
                        Text(rest.range.unit).font(Theme.label(9)).tracking(1.2).opacity(0.8)
                    }
                }
                .foregroundStyle(.white)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(rest.gradient))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.lime, lineWidth: style.isEmpty ? 0 : 3))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Rest and grouping: \(rest.label), \(group.label). \(style.isEmpty ? "Plan default" : "This workout only")")
            .sheet(isPresented: $editing) {
                WorkoutStyleSheet(session: session).presentationDetents([.large])
            }
        }
    }
}

/// Rest and grouping for one workout; the plan's choice carries a PLAN badge and picking it follows the plan again.
struct WorkoutStyleSheet: View {
    let session: Session
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            if let profile = model.profile {
                let style = model.sessionStyle(session.id)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(session.displayTitle).font(Theme.display(30))
                        Text("Only this workout changes; your plan keeps \(profile.rest.label.lowercased()) and \(profile.group.label.lowercased()). PLAN = your plan's setting.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)

                        Text("Rest between sets").eyebrow().padding(.top, 10)
                        ForEach(RestStyle.allCases) { r in
                            StyleCard(
                                title: r.label, subtitle: r.blurb, symbol: r.symbol, big: r.range, gradient: r.gradient,
                                selected: (style.rest ?? profile.rest) == r, recommended: profile.rest == r, badge: "PLAN"
                            ) { update { $0.rest = r == profile.rest ? nil : r } }
                        }

                        Text("Group exercises").eyebrow().padding(.top, 10)
                        ForEach(Grouping.allCases) { g in
                            StyleCard(
                                title: g.label, subtitle: g.blurb, symbol: g.symbol, big: g.size, gradient: g.gradient,
                                selected: (style.grouping ?? profile.group) == g, recommended: profile.group == g, badge: "PLAN"
                            ) { update { $0.grouping = g == profile.group ? nil : g } }
                        }

                        Text("Exercises and time are re-planned for the new rests; the main lift stays.")
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)

                        if !style.isEmpty {
                            Button { model.setSessionStyle(session.id, SessionStyle()) } label: {
                                Label("Back to plan default", systemImage: "arrow.uturn.backward")
                            }
                            .buttonStyle(LimeButtonStyle())
                            .padding(.top, 6)
                        }
                    }
                    .padding(16)
                    .animation(.spring(duration: 0.3), value: style)
                }
                .background(Theme.bg.ignoresSafeArea())
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func update(_ change: (inout SessionStyle) -> Void) {
        var s = model.sessionStyle(session.id)
        change(&s)
        model.setSessionStyle(session.id, s)
    }
}
