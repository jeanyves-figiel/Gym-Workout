import SwiftUI
import WorkoutEngine

// MARK: - Train around pain (#870)
//
// A: tap the sore spot on the body figure and pick how bad; Coach lists the swaps across the whole plan.
// B: say it in Ask Coach; Coach asks one question, then offers the plan with Apply (`PainPlanCard`).
// C: while on, a Protected badge on Train, swapped moves marked 🛡, "Feels better" ends it.

private let painColors = [Color(red: 0.13, green: 0.80, blue: 0.62), Color(red: 0.16, green: 0.55, blue: 0.95)]
private let coralColors = [Color(red: 1, green: 0.42, blue: 0.42), Color(red: 1, green: 0.62, blue: 0.27)]

/// Where each spot sits on the front figure, in design space (member's right = viewer's left).
private func painPoint(_ area: PainArea, _ side: PainSide) -> CGPoint {
    let right = side != .left
    func x(_ v: CGFloat) -> CGFloat { right ? v : CGFloat(BodyMapLayout.width) - v }
    switch area {
    case .neck: return CGPoint(x: 100, y: 60)
    case .shoulder: return CGPoint(x: x(52), y: 84)
    case .elbow: return CGPoint(x: x(42), y: 152)
    case .wrist: return CGPoint(x: x(28), y: 214)
    case .lowerBack: return CGPoint(x: 100, y: 182)
    case .hip: return CGPoint(x: x(74), y: 208)
    case .knee: return CGPoint(x: x(76), y: 308)
    case .ankle: return CGPoint(x: x(78), y: 378)
    }
}

/// Every tappable spot: sided areas twice.
private let painSpots: [(PainArea, PainSide)] = PainArea.allCases.flatMap { a in a.sided ? [(a, .right), (a, .left)] : [(a, .both)] }

/// A: "Where does it hurt?"
struct PainSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var area: PainArea?
    @State private var side: PainSide = .both
    @State private var level: PainLevel = .loaded
    @State private var since = Date()
    @State private var preview: PainProtect.Result?

    private var draft: PainProtect? { area.map { PainProtect(area: $0, side: side, level: level, since: since) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Pain & injury").eyebrow()
                    Text("Where does it hurt?").font(Theme.display(30))
                    figure
                    if let d = draft {
                        Text(d.spot.capitalized).font(Theme.display(18))
                        levelChips
                        Text("Coach changes · until better").eyebrow()
                        changes
                    } else {
                        Text("Tap the sore spot. Coach swaps the moves that load it across your whole plan, until it feels better.")
                            .font(.subheadline).foregroundStyle(Theme.muted)
                    }
                    Text(PainProtect.notAdvice).font(.caption).foregroundStyle(Theme.muted)
                }
                .padding(16)
                .padding(.bottom, 80)
            }
            .safeAreaInset(edge: .bottom) { if let d = draft { protectButton(d) } }
            .background(Theme.bg)
            .toolbar { CloseToolbarItem { dismiss() } }
        }
        .task(id: draft) { preview = draft.flatMap { model.painPreview($0) } }
        .onAppear {
            guard let p = model.painProtect else { return }
            area = p.area
            side = p.side
            level = p.level
            since = p.since
        }
    }

    private var figure: some View {
        BodyMapView(side: .front, showLabel: false)
            .overlay {
                GeometryReader { geo in
                    let s = min(geo.size.width / CGFloat(BodyMapLayout.width), geo.size.height / CGFloat(BodyMapLayout.height))
                    let dx = (geo.size.width - CGFloat(BodyMapLayout.width) * s) / 2
                    ForEach(Array(painSpots.enumerated()), id: \.offset) { _, spot in
                        let on = area == spot.0 && (side == spot.1 || !spot.0.sided)
                        let p = painPoint(spot.0, spot.1)
                        Button {
                            withAnimation(.snappy) {
                                area = spot.0
                                side = spot.1
                            }
                        } label: {
                            Circle()
                                .fill(on ? AnyShapeStyle(LinearGradient(colors: coralColors, startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Color.white.opacity(0.18)))
                                .frame(width: on ? 24 : 14, height: on ? 24 : 14)
                                .shadow(color: on ? coralColors[0].opacity(0.8) : .clear, radius: 8)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .position(x: dx + p.x * s, y: p.y * s)
                        .accessibilityLabel(PainProtect(area: spot.0, side: spot.1, level: level).spot.capitalized)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 300)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.card))
    }

    private var levelChips: some View {
        HStack(spacing: 8) {
            ForEach(PainLevel.allCases) { l in
                let on = level == l
                Button { withAnimation(.snappy) { level = l } } label: {
                    Text(l.label).font(Theme.label(13)).lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundStyle(on ? Theme.ink : .white)
                        .padding(.horizontal, 12).frame(minHeight: 40)
                        .background(Capsule().fill(on ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(Theme.card)))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    @ViewBuilder private var changes: some View {
        if let preview, !preview.changes.isEmpty {
            ForEach(preview.changes, id: \.self) { c in
                HStack {
                    Text(c.line).font(.subheadline.weight(.bold)).lineLimit(2)
                    Spacer(minLength: 8)
                    Image(systemName: "checkmark").font(.caption.weight(.heavy)).foregroundStyle(Theme.ink)
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.lime))
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
            }
        } else if preview != nil {
            Text("Nothing this week loads it. Coach keeps watching every new week.").font(.subheadline).foregroundStyle(Theme.muted)
        }
    }

    private func protectButton(_ d: PainProtect) -> some View {
        let n = preview?.changes.count ?? 0
        return Button {
            model.setPainProtect(d)
            dismiss()
        } label: {
            Text("Protect my \(d.spot)" + (n > 0 ? " · \(n) swap\(n == 1 ? "" : "s")" : ""))
                .font(Theme.display(17)).lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Capsule().fill(Theme.lime))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16).padding(.bottom, 8)
    }
}

/// B: Coach's offer in the chat, "Knee-friendly plan · 6 swaps · 3 workouts · until better · Apply".
struct PainPlanCard: View {
    let protect: PainProtect
    @Environment(AppModel.self) private var model
    @State private var preview: PainProtect.Result?

    private var applied: Bool {
        guard let p = model.painProtect else { return false }
        return p.area == protect.area && p.side == protect.side && p.level == protect.level
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { if !applied { model.setPainProtect(protect) } } label: {
                HStack(spacing: 12) {
                    Image(systemName: "shield.lefthalf.filled").font(.system(size: 18, weight: .bold))
                        .frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.22)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(protect.area.friendly).font(Theme.display(16)).lineLimit(1).minimumScaleFactor(0.7)
                        Text(detail).font(.caption.weight(.semibold)).opacity(0.9).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 6)
                    Text(applied ? "ON" : "APPLY").font(Theme.label(13))
                }
                .foregroundStyle(.white)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: coralColors, startPoint: .leading, endPoint: .trailing)))
            }
            .buttonStyle(.plain)
            .disabled(applied)
            .accessibilityLabel("\(protect.area.friendly), \(detail)")
            .accessibilityHint(applied ? "On" : "Applies it to your plan")
            Text(protect.seeDoctor ? "Please see a doctor or physio first. Not medical advice." : PainProtect.notAdvice)
                .font(.caption2.weight(protect.seeDoctor ? .bold : .regular))
                .foregroundStyle(protect.seeDoctor ? coralColors[0] : Theme.muted)
        }
        .padding(.leading, 42)
        .task { preview = model.painPreview(protect) }
    }

    private var detail: String {
        guard let preview else { return "Until better" }
        let n = preview.changes.count
        return "\(n) swap\(n == 1 ? "" : "s") · \(preview.workouts) workout\(preview.workouts == 1 ? "" : "s") · until better"
    }
}

/// C: the Protected badge on Train while a spot is protected.
struct PainProtectBar: View {
    @Environment(AppModel.self) private var model
    @State private var editing = false

    var body: some View {
        if let p = model.painProtect {
            let n = model.painSwapped.count
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Button { editing = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "shield.lefthalf.filled").font(.system(size: 18, weight: .bold))
                                .frame(width: 40, height: 40)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.22)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Protecting \(p.spot)").font(Theme.display(16)).lineLimit(1).minimumScaleFactor(0.7)
                                Text("day \(p.day()) · \(n) swap\(n == 1 ? "" : "s") · \(p.level.label.lowercased())")
                                    .font(.caption.weight(.semibold)).opacity(0.9).lineLimit(1).minimumScaleFactor(0.7)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Change the spot or how bad it is")
                    Button { withAnimation(.snappy) { model.endPainProtect() } } label: {
                        Text("FEELS\nBETTER").font(Theme.label(12)).multilineTextAlignment(.trailing)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Feels better")
                    .accessibilityHint("Brings every move back")
                }
                if p.seeDoctor || p.longRunning() {
                    Button { CoachAsk.shared.request = AskCoachRequest(focus: .tab(.train), question: "My \(p.spot) still hurts after \(p.day()) days. What should I do?") } label: {
                        HStack {
                            Text(p.seeDoctor ? "See a doctor or physio first" : "Still hurts after 2 weeks?").font(.subheadline.weight(.bold))
                            Spacer(minLength: 6)
                            Text("Get advice").font(Theme.label(12)).foregroundStyle(Theme.ink)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Capsule().fill(Theme.lime))
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.22)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .foregroundStyle(.white)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: painColors, startPoint: .topLeading, endPoint: .bottomTrailing)))
            .sheet(isPresented: $editing) { PainSheet() }
        }
    }
}

/// Entry to A from the sore-muscle grid and My plan.
struct PainEntryRow: View {
    @Environment(AppModel.self) private var model
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            SmartRow(symbol: "bandage.fill", title: model.painProtect.map { "Protecting \($0.spot)" } ?? "Pain or injury?",
                     detail: model.painProtect == nil ? "Tap where it hurts, Coach trains around it" : "Change it, or say it feels better on Train",
                     colors: coralColors, compact: true) {
                Image(systemName: "chevron.right").font(.caption.weight(.heavy))
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $open) { PainSheet() }
    }
}
