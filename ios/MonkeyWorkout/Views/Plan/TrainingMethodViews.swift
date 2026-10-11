import SwiftUI
import WorkoutEngine

/// Training method (#156) in the training profile: how the plan progresses, as Explore-style cards with the
/// evidence behind the chosen one. Block periodization carries a DEFAULT badge; picking it stores nil.
struct TrainingMethodSection: View {
    @Binding var profile: Profile
    @State private var showingSources = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How your plan progresses. Your goal still picks what you train.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
            ForEach(TrainingMethod.allCases) { m in
                StyleCard(
                    title: m.label, subtitle: m.blurb, symbol: m.symbol, big: m.big,
                    gradient: m.gradient, selected: profile.trainingMethod == m, recommended: m == .block, badge: "DEFAULT"
                ) { profile.method = m == .block ? nil : m }
            }
            Text(profile.trainingMethod.detail)
                .font(.footnote)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button { showingSources = true } label: {
                Label("Sources for each method", systemImage: "book.closed.fill")
                    .font(.footnote.weight(.semibold))
            }
            .accessibilityHint("Lists the studies behind every training method")
            Text("Every method keeps ramp-up sets, a deload week, level-appropriate exercises and climbing-day rules, and eases loads back in after 2 weeks off.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .animation(.spring(duration: 0.3), value: profile.trainingMethod)
        .sheet(isPresented: $showingSources) { MethodSourcesSheet(selected: profile.trainingMethod) }
    }
}

/// The studies behind every training method (#156), grouped by method; each opens on PubMed.
struct MethodSourcesSheet: View {
    let selected: TrainingMethod
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(TrainingMethod.allCases) { m in
                    Section {
                        ForEach(m.sources) { s in
                            if let url = s.url {
                                Link(destination: url) { row(s) }
                            } else {
                                row(s)
                            }
                        }
                    } header: {
                        Label(m.label + (m == selected ? " · yours" : ""), systemImage: m.symbol)
                    }
                }
                Section {
                    Text("Peer-reviewed studies and reviews. Links open a PubMed search for the title.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
            }
            .navigationTitle("Sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func row(_ s: MethodSource) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(s.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
            Text("\(s.short) · \(s.journal)").font(.caption).foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 2)
    }
}

extension TrainingMethod {
    var symbol: String {
        switch self {
        case .block: "square.stack.3d.up.fill"
        case .undulating: "waveform.path"
        case .autoregulated: "gauge.with.dots.needle.67percent"
        case .volume: "chart.line.uptrend.xyaxis"
        case .minimal: "stopwatch.fill"
        }
    }

    /// Big number + caption on the card.
    var big: (value: String, unit: String) {
        switch self {
        case .block: ("\(Generator.mesocycleWeeks)", "WEEK BLOCK")
        case .undulating: ("3", "DAY TYPES")
        case .autoregulated: ("RIR", "EVERY SET")
        case .volume: ("10→16", "SETS / MUSCLE")
        case .minimal: ("\(Generator.minimalSessionMinutes)′", "MAX")
        }
    }

    var gradient: LinearGradient {
        let c: WorkoutEngine.Category = switch self {
        case .block: .strength
        case .undulating: .power
        case .autoregulated: .cardio
        case .volume: .warmup
        case .minimal: .mobility
        }
        return c.gradient
    }
}
