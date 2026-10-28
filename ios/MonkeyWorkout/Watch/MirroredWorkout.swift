import HealthKit
import SwiftUI
import UIKit
import WorkoutEngine

/// Workout mirroring (#603, designs A + C from `apple-tech-radar/t1.png`). A workout run on the Watch mirrors its
/// HealthKit session to the iPhone: heart rate and calories arrive natively, the Watch player's state comes as
/// `WMirrorState`, and the twin player sends `WCommand`s back. A mirrored session also keeps this app running with the
/// phone locked, so a workout run on the iPhone and tracked by the Watch keeps answering the Watch from the locker.
@MainActor @Observable
final class MirroredWorkout: NSObject {
    static let shared = MirroredWorkout()

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    /// What the Watch player shows; nil while the Watch tracks an iPhone workout (that player is the iPhone's own).
    private(set) var state: WMirrorState?
    private(set) var heartRate: Int?
    private(set) var kcal: Int?
    /// Twin player on screen; closing it leaves the Watch running and shows the banner on Train instead.
    var presented = false
    /// The Watch finished while the twin player was open (#822 A): it stays open on the finish screen.
    private(set) var finishedSessionId: String?
    /// What the iPhone saved from that finish, once `WatchEvent.finished` arrived.
    private(set) var finished: (record: WorkoutRecord, session: Session?, reward: GameReward?)?

    var live: Bool { session != nil && state?.finished != true }

    /// Must be set before launch ends: watchOS starts mirroring as soon as the Watch session begins.
    func listen() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        store.workoutSessionMirroringStartHandler = { [weak self] s in
            Task { @MainActor in self?.attach(s) }
        }
    }

    private func attach(_ s: HKWorkoutSession) {
        session = s
        state = nil
        heartRate = nil
        kcal = nil
        s.delegate = self
        // Heart rate and kcal from the mirrored builder need iOS 26; earlier the twin player shows the Watch's state only.
        if #available(iOS 26.0, *) { s.associatedWorkoutBuilder().delegate = self }
    }

    private func ended() {
        session = nil
        state = nil
        heartRate = nil
        kcal = nil
        // A finish screen on show stays until its DONE (#822 A).
        if finishedSessionId == nil { presented = false }
    }

    /// The iPhone saved the workout the Watch finished (#822 A). Shown when the twin player is open (or the finish
    /// state hasn't arrived yet); otherwise the Train screen already shows the new workout.
    func recorded(_ r: WorkoutRecord, session s: Session?, sessionId: String, reward: GameReward?) {
        guard finishedSessionId == sessionId || (presented && state?.sessionId == sessionId) else { return }
        finishedSessionId = sessionId
        finished = (r, s, reward)
    }

    /// DONE or ✕ on the finish screen.
    func closeFinish() {
        finishedSessionId = nil
        finished = nil
        presented = false
    }

    /// FINISH on the twin player (#822 +): the Watch ends the workout (summary and Health there), the iPhone shows the
    /// finish screen when the record arrives.
    func finishOnWatch() {
        finishedSessionId = state?.sessionId
        send(.finish)
    }

    /// A press on the twin player, done by the Watch player.
    func send(_ c: WCommand) {
        guard let session, let data = try? JSONEncoder.watch.encode(c) else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task { try? await session.sendToRemoteWorkoutSession(data: data) }
    }

    fileprivate func received(_ data: [Data]) {
        guard let last = data.compactMap({ try? JSONDecoder.watch.decode(WMirrorState.self, from: $0) }).last else { return }
        let first = state == nil
        state = last
        // Watch workout just showed up: open the twin player once (A); closing it keeps the Train banner.
        if first, !last.finished { presented = true }
        // Finished with the twin player open: it turns into the finish screen (#822 A) instead of vanishing.
        if last.finished { if presented { finishedSessionId = last.sessionId } else { presented = false } }
    }

    @available(iOS 26.0, *)
    fileprivate func collected(_ builder: HKLiveWorkoutBuilder, _ types: Set<HKSampleType>) {
        if types.contains(HKQuantityType(.heartRate)), let q = builder.statistics(for: HKQuantityType(.heartRate))?.mostRecentQuantity() {
            heartRate = Int(q.doubleValue(for: HKUnit.count().unitDivided(by: .minute())).rounded())
        }
        if types.contains(HKQuantityType(.activeEnergyBurned)),
           let q = builder.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity() {
            kcal = Int(q.doubleValue(for: .kilocalorie()).rounded())
        }
    }
}

extension MirroredWorkout: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        guard toState == .ended || toState == .stopped else { return }
        Task { @MainActor in self.ended() }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in self.ended() }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        Task { @MainActor in self.received(data) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: Error?) {
        Task { @MainActor in self.ended() }
    }
}

@available(iOS 26.0, *)
extension MirroredWorkout: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        Task { @MainActor in self.collected(workoutBuilder, collectedTypes) }
    }
}

// MARK: - Twin player (A)

/// The Watch's workout on the iPhone (#603, design A): same set, log on either device, the other follows.
struct TwinPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    private var mirror: MirroredWorkout { .shared }

    var body: some View {
        if let f = mirror.finished, let session = f.session {
            // Finished on the Watch (#822 A): the phone's own finish screen, DONE closes with "Workout saved · Undo".
            SummaryView(session: session, elapsed: TimeInterval(f.record.durationSec), setsDone: f.record.totalSets,
                        kcal: f.record.kcal, healthSaved: true, reward: f.reward, wins: model.wins(for: f.record),
                        record: f.record, report: model.workoutReport(f.record)) {
                done(f.record)
            }
            .background(Theme.bg.ignoresSafeArea())
            .onAppear { if f.reward?.weekCleared == true { model.markChestSeen() } }
        } else if mirror.finishedSessionId != nil {
            finishing
        } else {
            livePlayer
        }
    }

    /// DONE: same close as a phone workout (#822).
    private func done(_ r: WorkoutRecord) {
        mirror.closeFinish()
        dismiss()
        UndoCloseCenter.shared.show(.workoutSaved(r, model: model))
    }

    /// Finished on the Watch, record not here yet (or the session left the plan): the finish card and DONE.
    private var finishing: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 4) {
                Text("FINISHED ON WATCH").font(Theme.label(12)).opacity(0.9)
                Text(mirror.finished?.record.title ?? mirror.state?.title ?? "Workout").font(Theme.display(28))
                    .lineLimit(2).minimumScaleFactor(0.7)
                if let r = mirror.finished?.record {
                    Text("\(r.totalSets) sets · \(max(1, r.durationSec / 60))′").font(Theme.label(15)).opacity(0.9)
                } else {
                    Text("Saving…").font(Theme.label(15)).opacity(0.9)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(LinearGradient(colors: [Color(hex: 0xFF2D55), Color(hex: 0xFF8A00)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Button {
                if let r = mirror.finished?.record { done(r) } else { mirror.closeFinish(); dismiss() }
            } label: {
                Text("DONE").font(Theme.label(18)).foregroundStyle(Theme.ink).frame(maxWidth: .infinity, minHeight: 60)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.lime))
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(Theme.bg.ignoresSafeArea())
    }

    private var livePlayer: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("LIVE FROM WATCH" + (mirror.heartRate.map { " · ♥ \($0)" } ?? ""), systemImage: "applewatch")
                    .font(Theme.label(12)).foregroundStyle(Theme.lime)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).frame(width: 36, height: 36)
                        .background(Circle().fill(Theme.cardStrong))
                }
                .accessibilityLabel("Close, the Watch keeps going")
            }
            if let s = mirror.state {
                Text(s.title).font(Theme.display(26)).lineLimit(1).minimumScaleFactor(0.7)
                card(s)
                if let end = s.restEnd, end > .now { rest(end) } else { controls(s) }
                upNext(s)
                stats(s)
                // Ends the workout on both (#822 +): the Watch saves it, the finish screen follows here.
                Button { mirror.finishOnWatch() } label: {
                    Text("Finish workout").font(Theme.label(15)).frame(maxWidth: .infinity, minHeight: 50)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.cardStrong))
                }
                .accessibilityHint("Ends the workout on the Watch and the iPhone")
            } else {
                Text("Waiting for the Watch…").font(Theme.label(15)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(Theme.bg.ignoresSafeArea())
        // A finish keeps the screen for the finish card (#822 A); anything else that ends the Watch session closes it.
        .onChange(of: mirror.live) { _, live in if !live, mirror.finishedSessionId == nil { dismiss() } }
    }

    private func card(_ s: WMirrorState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(s.setLabel.isEmpty ? "EXERCISE \(s.position) OF \(s.count)" : s.setLabel).font(Theme.label(12)).opacity(0.9)
            Text(s.exercise).font(Theme.display(24)).lineLimit(2).minimumScaleFactor(0.7)
            Text(s.detail).font(Theme.display(46)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(LinearGradient(colors: [Color(hex: s.tint), Color(hex: s.tint2)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder private func controls(_ s: WMirrorState) -> some View {
        HStack(spacing: 10) {
            if s.loggable { square("minus", "Less weight") { mirror.send(.kgDown) } }
            Button { mirror.send(.main) } label: {
                Text(s.action).font(Theme.label(18)).foregroundStyle(Theme.ink).frame(maxWidth: .infinity, minHeight: 60)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.lime))
            }
            if s.loggable { square("plus", "More weight") { mirror.send(.kgUp) } }
        }
    }

    private func rest(_ end: Date) -> some View {
        HStack(spacing: 10) {
            Text(timerInterval: Date.now...max(.now, end), countsDown: true)
                .font(Theme.display(40)).monospacedDigit().foregroundStyle(Theme.lime).frame(maxWidth: .infinity, alignment: .leading)
            Button { mirror.send(.addRest) } label: {
                Text("+15 s").font(Theme.label(15)).frame(width: 72, height: 60)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.cardStrong))
            }
            Button { mirror.send(.skipRest) } label: {
                Text("Skip").font(Theme.label(15)).foregroundStyle(Theme.ink).frame(width: 72, height: 60)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.lime))
            }
        }
    }

    private func upNext(_ s: WMirrorState) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("UP NEXT").font(Theme.label(11)).opacity(0.85)
            Text(s.next).font(Theme.label(15)).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(LinearGradient(colors: [Color(hex: 0xD1239A), Color(hex: 0xFF5A5A)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func stats(_ s: WMirrorState) -> some View {
        HStack(spacing: 10) {
            tile("HEART", mirror.heartRate.map(String.init) ?? "–", 0xFF3D7B, 0xFF8A00)
            tile("KCAL", mirror.kcal.map(String.init) ?? "–", 0x0F9D6A, 0x2F9BFF)
            tile("EXERCISE", "\(s.position)/\(s.count)", 0x2F6BFF, 0x8A4DFF)
        }
    }

    private func tile(_ label: String, _ value: String, _ a: UInt32, _ b: UInt32) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Theme.label(10)).opacity(0.9)
            Text(value).font(Theme.display(24)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(LinearGradient(colors: [Color(hex: a), Color(hex: b)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func square(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 20, weight: .black)).frame(width: 60, height: 60)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.cardStrong))
        }
        .accessibilityLabel(label)
    }
}

/// On Train while a Watch workout runs and the twin player is closed (#603).
struct WatchLiveBanner: View {
    private var mirror: MirroredWorkout { .shared }

    var body: some View {
        if mirror.live, let s = mirror.state {
            Button { mirror.presented = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "applewatch").font(.system(size: 20, weight: .bold))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("LIVE ON WATCH" + (mirror.heartRate.map { " · ♥ \($0)" } ?? "")).font(Theme.label(11))
                        Text("\(s.exercise) · \(s.detail)").font(Theme.label(15)).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Text("Open").font(Theme.label(13)).foregroundStyle(Theme.ink).padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(Theme.lime))
                }
                .foregroundStyle(.white)
                .padding(12)
                .background(LinearGradient(colors: [Color(hex: s.tint), Color(hex: s.tint2)], startPoint: .leading, endPoint: .trailing),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}

extension UndoOffer {
    /// "Workout saved · Undo" after DONE on a finish screen (#822): Undo takes the workout back off the history.
    /// Shared by the phone player and the Watch's twin player.
    @MainActor static func workoutSaved(_ r: WorkoutRecord, model: AppModel) -> UndoOffer {
        UndoOffer(
            title: "Workout saved", detail: undoDetail(r.title, "\(max(1, r.durationSec / 60))′"), symbol: "checkmark.circle.fill",
            colors: [Color(hex: 0x2FD27A), Color(hex: 0x1E9E8F)], reopen: { AnyView(EmptyView()) },
            revert: { [model] in _ = model.undoWorkout(r.id) })
    }
}
