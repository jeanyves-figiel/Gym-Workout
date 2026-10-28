import SwiftUI
import UIKit
import WorkoutEngine

// Climbing live (#829, design B + A from `climb-track-live/proposals.png`): one tap per problem, the grade chips above,
// counts and the grade pyramid live. Mirrored on the Watch when one tracks it; closing keeps the session running.

struct ClimbLiveView: View {
    @Environment(AppModel.self) private var model
    @Environment(HealthManager.self) private var health
    @Environment(\.dismiss) private var dismiss
    @State private var live = ClimbLive.shared
    @State private var link = WatchLink.shared

    var body: some View {
        NavigationStack {
            Group {
                if let s = live.session {
                    content(s)
                } else {
                    Color.clear
                }
            }
            .readableWidth()
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Climbing live")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Discard session", systemImage: "trash", role: .destructive) {
                            live.discard()
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold))
                    }
                    .accessibilityLabel("More")
                }
                // Closing keeps it running: Track live on today's card opens it again.
                CloseToolbarItem { dismiss() }
            }
        }
        .onAppear { live.start(watch: link.ready) }
    }

    private func content(_ s: ClimbLiveSession) -> some View {
        let t = s.tally
        return VStack(alignment: .leading, spacing: 14) {
            header(s)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(t.tops)").font(Theme.display(54)).monospacedDigit()
                VStack(alignment: .leading, spacing: 0) {
                    Text(t.tops == 1 ? "send" : "sends").font(Theme.label(15))
                    Text([t.falls > 0 ? "\(t.falls) fall\(t.falls == 1 ? "" : "s")" : nil, t.top.map { "top \($0)" }]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(Theme.label(13)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
                scalePicker(s)
            }
            gradeChips(s)
            actions(s)
            pyramid(t)
            Spacer(minLength: 0)
            Button {
                live.finish(model: model, health: health)
                dismiss()
            } label: {
                Label(t.attempts == 0 ? "Finish climb" : "Finish · log \(t.attempts) go\(t.attempts == 1 ? "" : "s")",
                      systemImage: "checkmark")
            }
            .buttonStyle(LimeButtonStyle())
        }
        .padding(16)
    }

    /// Time on the wall, rest since the last go, kind chips; heart rate while the Watch tracks it.
    private func header(_ s: ClimbLiveSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TimelineView(.periodic(from: s.start, by: 1)) { ctx in
                HStack(spacing: 10) {
                    Text(Self.clock(Int(ctx.date.timeIntervalSince(s.start)))).font(Theme.display(22)).monospacedDigit()
                    if let rest = ClimbTally.rest(s.attempts, now: ctx.date) {
                        Label("Rest \(Self.clock(rest))", systemImage: "hourglass")
                            .font(Theme.label(13)).monospacedDigit()
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Capsule().fill(.white.opacity(0.12)))
                    }
                    Spacer(minLength: 0)
                    if s.watch {
                        Label(WatchSync.shared.liveHeartRate.map { "\($0)" } ?? "Watch", systemImage: WatchSync.shared.liveHeartRate == nil ? "applewatch" : "heart.fill")
                            .font(Theme.label(13)).monospacedDigit()
                            .foregroundStyle(Color(hex: 0xFF5F6D))
                    }
                }
            }
            HStack(spacing: 6) {
                ForEach(ClimbKind.allCases) { k in
                    Button { live.setKind(k) } label: {
                        Text(k.label).font(Theme.label(12)).lineLimit(1).minimumScaleFactor(0.7)
                            .foregroundStyle(k == s.kind ? Theme.ink : .white)
                            .frame(maxWidth: .infinity, minHeight: 32)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(k == s.kind ? AnyShapeStyle(Color.white) : AnyShapeStyle(.white.opacity(0.1))))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(k == s.kind ? .isSelected : [])
                }
            }
        }
    }

    private func scalePicker(_ s: ClimbLiveSession) -> some View {
        HStack(spacing: 2) {
            ForEach(ClimbScale.allCases) { sc in
                Button { live.setScale(sc) } label: {
                    Text(sc.label).font(Theme.label(12))
                        .foregroundStyle(sc == s.scale ? Theme.ink : .white)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(sc == s.scale ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(Color.clear)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(.white.opacity(0.1)))
        .accessibilityLabel("Grade scale")
    }

    private func gradeChips(_ s: ClimbLiveSession) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(s.scale.grades.enumerated()), id: \.element) { i, g in
                        Button { live.setGrade(g) } label: {
                            Text(g).font(Theme.display(17))
                                .foregroundStyle(.white)
                                .frame(minWidth: 48, minHeight: 48)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Self.gradeColor(i, of: s.scale.grades.count)))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(g == s.grade ? Color.white : .clear, lineWidth: 3))
                        }
                        .buttonStyle(.plain)
                        .id(g)
                        .accessibilityAddTraits(g == s.grade ? .isSelected : [])
                    }
                }
                .padding(.vertical, 2)
            }
            .onAppear { proxy.scrollTo(s.grade, anchor: .center) }
            .onChange(of: s.scale) { proxy.scrollTo(s.grade, anchor: .center) }
        }
    }

    private func actions(_ s: ClimbLiveSession) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                action("Flash", symbol: "bolt.fill", fill: Color(hex: 0xFFC93A), ink: Theme.ink) { live.log(.flash) }
                action("Sent", symbol: "checkmark", fill: Theme.lime, ink: Theme.ink) { live.log(.send) }
                action("Fell", symbol: "xmark", fill: .white.opacity(0.16), ink: .white) { live.log(.fall) }
            }
            if let last = s.attempts.last {
                Button { live.undo() } label: {
                    Label("Undo \(last.result == .fall ? "fall" : last.result == .flash ? "flash" : "send") · \(last.grade)",
                          systemImage: "arrow.uturn.backward")
                        .font(Theme.label(13)).foregroundStyle(Theme.muted)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func action(_ title: String, symbol: String, fill: Color, ink: Color, tap: @escaping () -> Void) -> some View {
        Button {
            tap()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } label: {
            Label(title, systemImage: symbol)
                .font(Theme.label(17))
                .foregroundStyle(ink)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(fill))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Today's grade pyramid, hardest first: tops in lime, falls dimmed; the five hardest grades fit without scrolling.
    @ViewBuilder private func pyramid(_ t: ClimbTally) -> some View {
        if !t.pyramid.isEmpty {
            let rows = Array(t.pyramid.prefix(5))
            let most = max(1, rows.map { $0.tops + $0.falls }.max() ?? 1)
            VStack(alignment: .leading, spacing: 5) {
                Text("Grade pyramid today").eyebrow()
                ForEach(rows, id: \.grade) { r in
                    HStack(spacing: 8) {
                        Text(r.grade).font(Theme.label(13)).frame(width: 36, alignment: .leading)
                        GeometryReader { geo in
                            HStack(spacing: 2) {
                                if r.tops > 0 {
                                    RoundedRectangle(cornerRadius: 4).fill(Theme.lime)
                                        .frame(width: geo.size.width * CGFloat(r.tops) / CGFloat(most))
                                }
                                if r.falls > 0 {
                                    RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.25))
                                        .frame(width: geo.size.width * CGFloat(r.falls) / CGFloat(most))
                                }
                            }
                        }
                        .frame(height: 14)
                        Text("\(r.tops)/\(r.tops + r.falls)").font(Theme.label(12)).foregroundStyle(Theme.muted).monospacedDigit()
                    }
                }
            }
        }
    }

    static func clock(_ seconds: Int) -> String {
        let h = seconds / 3600, m = seconds / 60 % 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// Easy green → blue → purple → red → hardest near black, like gym hold tags.
    static func gradeColor(_ index: Int, of count: Int) -> Color {
        let stops: [UInt32] = [0x2BB673, 0x2A8FE0, 0x7C4DFF, 0xB23BD8, 0xE8574A, 0x3A3A48]
        let i = count > 1 ? Int((Double(index) / Double(count - 1) * Double(stops.count - 1)).rounded()) : 0
        return Color(hex: stops[min(max(i, 0), stops.count - 1)])
    }
}
