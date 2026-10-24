import Observation
import SwiftUI
import UIKit
import WorkoutEngine

/// Workout on the TV (#724): what the player shows, for a second screen. The player publishes it on every change;
/// the AirPlay / HDMI scene (and the Chromecast sender) draws it.
struct TVLive: Equatable {
    var title: String
    var startedAt: Date
    var exercise: Exercise
    var category: WorkoutEngine.Category
    /// "Strength", the block's title, …
    var label: String
    /// 1-based set on screen, of `sets`.
    var set: Int
    var sets: Int
    /// Coming set's kg; nil when not logged by load.
    var kg: Double?
    /// "10", "8-12", "30 s", …
    var reps: String
    var restEnd: Date?
    var workEnd: Date?
    /// "Seated Cable Row · 3 × 12" or "Finish".
    var next: String
    var position: Int
    var count: Int
    /// 0…1 of all sets.
    var progress: Double
    var heartRate: Int?
}

@MainActor @Observable
final class TVCast {
    static let shared = TVCast()
    /// nil when no workout is open.
    var live: TVLive?
    /// An AirPlay / HDMI screen shows the workout.
    var connected = false
}

/// AirPlay (Screen Mirroring to an Apple TV / AirPlay TV) or an HDMI adapter: the TV gets its own 16:9 workout layout
/// instead of the mirrored phone (design mix B + A). The phone stays the remote.
@MainActor
final class TVSceneDelegate: NSObject, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: TVScreen().preferredColorScheme(.dark))
        window.isHidden = false
        self.window = window
        TVCast.shared.connected = true
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        window = nil
        TVCast.shared.connected = false
    }
}

/// Root of the TV: the workout when one is open, otherwise a waiting card.
struct TVScreen: View {
    var body: some View {
        if let live = TVCast.shared.live {
            TVPlayerView(live: live)
        } else {
            TVIdleView()
        }
    }
}

struct TVIdleView: View {
    var body: some View {
        GeometryReader { geo in
            let u = geo.size.height / 100
            ZStack {
                WorkoutEngine.Category.strength.gradient.ignoresSafeArea()
                VStack(spacing: 2 * u) {
                    Image(systemName: "dumbbell.fill").font(.system(size: 14 * u, weight: .black))
                    Text("MonkeyFit").font(.system(size: 9 * u, weight: .black, design: .rounded))
                    Text("Start a workout on your iPhone: it shows here.")
                        .font(.system(size: 3.5 * u, weight: .heavy, design: .rounded)).opacity(0.85)
                }
                .foregroundStyle(.white)
            }
        }
        .ignoresSafeArea()
    }
}

/// Full-screen movement (B) with the set / kg / reps tiles (A), the big timer and one Up next bar. Everything sits in
/// fixed places: nothing moves between sets, rest and timed work.
struct TVPlayerView: View {
    let live: TVLive

    var body: some View {
        GeometryReader { geo in
            let u = geo.size.height / 100
            ZStack(alignment: .topLeading) {
                live.category.gradient
                HStack(spacing: 0) {
                    ExerciseMotionView(exercise: live.exercise, playTrigger: live.set)
                        .padding(.top, 20 * u)
                        .padding(.bottom, 16 * u)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Color.clear.frame(width: geo.size.width * 0.36)
                }
                header(u)
                    .padding(.leading, 5 * u)
                    .padding(.top, 5 * u)
                side(u)
                    .frame(width: geo.size.width * 0.36 - 5 * u)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 5 * u)
                    .padding(.top, 5 * u)
                VStack {
                    Spacer()
                    upNext(u)
                }
                .padding(.horizontal, 5 * u)
                .padding(.bottom, 4 * u)
            }
            .foregroundStyle(live.category.ink)
        }
        .ignoresSafeArea()
    }

    private func header(_ u: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 1.2 * u) {
            Label(live.label.uppercased(), systemImage: live.category.symbol)
                .font(.system(size: 2.6 * u, weight: .heavy, design: .rounded)).tracking(2).opacity(0.85)
            Text(live.exercise.name)
                .font(.system(size: 7 * u, weight: .black, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.5)
            Text("\(live.position) of \(live.count) · \(live.title)")
                .font(.system(size: 2.8 * u, weight: .heavy, design: .rounded)).opacity(0.8).lineLimit(1)
        }
        .frame(maxWidth: 0.6 * 16 / 9 * 100 * u, alignment: .leading)
    }

    /// Big timer above the three tiles, then heart rate and time.
    private func side(_ u: CGFloat) -> some View {
        VStack(spacing: 2.4 * u) {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let (value, caption) = timer(at: ctx.date)
                VStack(spacing: 0.4 * u) {
                    Text(value).font(.system(size: 15 * u, weight: .black, design: .rounded)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.5)
                    Text(caption).font(.system(size: 2.8 * u, weight: .heavy, design: .rounded)).tracking(2).opacity(0.85)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2.4 * u)
                .background(RoundedRectangle(cornerRadius: 3 * u, style: .continuous).fill(.black.opacity(0.22)))
            }
            HStack(spacing: 1.6 * u) {
                tile("SET", "\(live.set)", suffix: "/\(live.sets)", WorkoutEngine.Category.power.gradient, u)
                tile("KG", live.kg.map { LoadAdvisor.formatKg($0) } ?? "–", suffix: nil, WorkoutEngine.Category.mobility.gradient, u)
                tile("REPS", live.reps, suffix: nil, WorkoutEngine.Category.cardio.gradient, u)
            }
            HStack {
                Label(live.heartRate.map { "\($0)" } ?? "–", systemImage: "heart.fill")
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(Self.clock(ctx.date.timeIntervalSince(live.startedAt))).monospacedDigit()
                }
                Spacer()
                Text("\(Int((live.progress * 100).rounded())) %").monospacedDigit()
            }
            .font(.system(size: 3.4 * u, weight: .black, design: .rounded))
        }
    }

    private func tile(_ title: String, _ value: String, suffix: String?, _ gradient: LinearGradient, _ u: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0.4 * u) {
            Text(title).font(.system(size: 2.4 * u, weight: .heavy, design: .rounded)).opacity(0.85)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(value).font(.system(size: 8 * u, weight: .black, design: .rounded))
                if let suffix { Text(suffix).font(.system(size: 3.6 * u, weight: .black, design: .rounded)).opacity(0.75) }
            }
            .lineLimit(1).minimumScaleFactor(0.4)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(1.8 * u)
        .background(RoundedRectangle(cornerRadius: 2.4 * u, style: .continuous).fill(gradient)
            .overlay(RoundedRectangle(cornerRadius: 2.4 * u, style: .continuous).stroke(.white.opacity(0.35), lineWidth: 0.3 * u)))
    }

    private func upNext(_ u: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 2 * u) {
                Text("UP NEXT").font(.system(size: 3 * u, weight: .black, design: .rounded)).tracking(1.5)
                Text(live.next).font(.system(size: 3.4 * u, weight: .heavy, design: .rounded)).opacity(0.85).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 2.4 * u)
            .frame(height: 8 * u)
            GeometryReader { g in
                Rectangle().fill(.white).frame(width: g.size.width * min(1, max(0, live.progress)))
            }
            .frame(height: 0.6 * u)
            .background(.white.opacity(0.2))
        }
        .foregroundStyle(.white)
        .background(.black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 2.4 * u, style: .continuous))
    }

    /// Rest left, timed work left, otherwise the set count-up is shown by the tiles: workout time.
    private func timer(at now: Date) -> (String, String) {
        if let end = live.restEnd { return (Self.clock(max(0, end.timeIntervalSince(now))), "REST") }
        if let end = live.workEnd { return (Self.clock(max(0, end.timeIntervalSince(now))), "WORK") }
        return ("GO", "SET \(live.set) OF \(live.sets)")
    }

    static func clock(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.up))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}
