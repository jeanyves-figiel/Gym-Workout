import AlarmKit
import AppIntents
import Foundation
import Observation
import SwiftUI

// MARK: - AlarmKit timers (#613, designs A + B + C from `apple-tech-radar/batch3.html`)
//
// Rest and timed blocks (Tabata, EMOM, rounds) ring like a real alarm on iPhone and Watch, through Silent and Focus.
// A: end of rest rings with Start set / +30 s. B: each timed block's end rings its bell. C: off by default, one ask
// the first time a timer runs; Settings → Reminders & alerts → Ring through Silent. iOS 26+; iOS 18 keeps the
// rest-over notification.

@available(iOS 26, *)
struct TimerAlarmData: AlarmMetadata {}

extension Notification.Name {
    /// "+30 s" on the rest alarm.
    static let workoutRestAdd30 = Notification.Name("workoutRestAdd30")
}

/// "+30 s" on the rest alarm: the player adds 30 s of rest and the alarm rings again then.
struct AddRest30Intent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Add 30 seconds of rest"

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            TimerAlarms.shared.snooze(30)
            NotificationCenter.default.post(name: .workoutRestAdd30, object: nil)
        }
        return .result()
    }
}

@MainActor @Observable
final class TimerAlarms {
    static let shared = TimerAlarms()

    enum Kind { case rest, bell }

    private static let enabledKey = "timerAlarms.enabled"
    private static let askedKey = "timerAlarms.asked"

    /// Ring through Silent (C): off until the member allows it.
    private(set) var enabled = UserDefaults.standard.bool(forKey: TimerAlarms.enabledKey)
    private var scheduled: UUID?
    private var scheduledFor: Date?
    private var last: (title: String, kind: Kind)?

    var available: Bool {
        if #available(iOS 26, *) { return true }
        return false
    }

    /// Rings instead of the rest-over notification.
    var ringing: Bool { available && enabled }

    /// The one-time ask (C), the first time a timer runs.
    var shouldAsk: Bool { available && !enabled && !UserDefaults.standard.bool(forKey: Self.askedKey) }

    func markAsked() { UserDefaults.standard.set(true, forKey: Self.askedKey) }

    /// Asks iOS for alarms; on only when allowed.
    @discardableResult
    func enable() async -> Bool {
        markAsked()
        guard #available(iOS 26, *) else { return false }
        var state = AlarmManager.shared.authorizationState
        if state == .notDetermined { state = (try? await AlarmManager.shared.requestAuthorization()) ?? .denied }
        set(state == .authorized)
        return enabled
    }

    func disable() {
        markAsked()
        set(false)
        cancel()
    }

    private func set(_ on: Bool) {
        enabled = on
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
    }

    /// Rings at `date` (A: rest over, B: end of a timed block); replaces the alarm set before.
    func ring(at date: Date, title: String, kind: Kind) {
        guard ringing, date.timeIntervalSinceNow > 1 else { return cancel() }
        guard scheduledFor != date else { return }
        cancel()
        let id = UUID()
        scheduled = id
        scheduledFor = date
        last = (title, kind)
        guard #available(iOS 26, *) else { return }
        Task { try? await Self.schedule(id: id, at: date, title: title, kind: kind) }
    }

    /// "+30 s" after the alarm rang: once more in `seconds`, even if the player already moved on.
    func snooze(_ seconds: TimeInterval) {
        guard let last else { return }
        let base = max(scheduledFor ?? Date(), Date())
        scheduledFor = nil
        ring(at: base.addingTimeInterval(seconds), title: last.title, kind: last.kind)
    }

    func cancel() {
        defer { scheduled = nil; scheduledFor = nil }
        guard let id = scheduled else { return }
        if #available(iOS 26, *) { try? AlarmManager.shared.cancel(id: id) }
    }

    @available(iOS 26, *)
    private static func schedule(id: UUID, at date: Date, title: String, kind: Kind) async throws {
        let rest = kind == .rest
        let heading = LocalizedStringResource(stringLiteral: title)
        let alert: AlarmPresentation.Alert
        if rest {
            alert = AlarmPresentation.Alert(title: heading,
                                            stopButton: AlarmButton(text: "Start set", textColor: .black, systemImageName: "play.fill"),
                                            secondaryButton: AlarmButton(text: "+30 s", textColor: .white, systemImageName: "plus"),
                                            secondaryButtonBehavior: .custom)
        } else {
            alert = AlarmPresentation.Alert(title: heading,
                                            stopButton: AlarmButton(text: "OK", textColor: .black, systemImageName: "checkmark"))
        }
        let attributes = AlarmAttributes<TimerAlarmData>(presentation: AlarmPresentation(alert: alert), metadata: TimerAlarmData(),
                                                         tintColor: Theme.lime)
        let secondary: (any LiveActivityIntent)? = rest ? AddRest30Intent() : nil
        let config = AlarmManager.AlarmConfiguration<TimerAlarmData>(
            countdownDuration: nil, schedule: .fixed(date), attributes: attributes,
            stopIntent: nil, secondaryIntent: secondary, sound: .default)
        _ = try await AlarmManager.shared.schedule(id: id, configuration: config)
    }
}

/// One-time ask (#613 C), the first time a rest or timed block runs.
struct RingThroughSilentAsk: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "alarm.waves.left.and.right.fill")
                    .font(.system(size: 24, weight: .bold))
                    .frame(width: 52, height: 52)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.2)))
                Text("Ring through Silent?").font(Theme.display(26)).lineLimit(2).minimumScaleFactor(0.8)
            }
            Text("Rest and interval timers sound like an alarm, even with Focus on. Change it any time in Settings → Reminders & alerts.")
                .font(.subheadline.weight(.semibold)).opacity(0.9)
            HStack(spacing: 10) {
                Button {
                    TimerAlarms.shared.disable()
                    dismiss()
                } label: {
                    Text("Not now").font(Theme.label(16)).frame(maxWidth: .infinity, minHeight: 50)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.2)))
                }
                .buttonStyle(.plain)
                Button {
                    Task {
                        await TimerAlarms.shared.enable()
                        dismiss()
                    }
                } label: {
                    Text("Allow").font(Theme.label(16)).foregroundStyle(Theme.ink).frame(maxWidth: .infinity, minHeight: 50)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.lime))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ring.allow")
            }
        }
        .foregroundStyle(.white)
        .padding(22)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(LinearGradient(colors: [Color(red: 1, green: 0.54, blue: 0), Color(red: 1, green: 0.24, blue: 0.48)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea())
        .presentationDetents([.height(280)])
        .interactiveDismissDisabled()
        .preferredColorScheme(.dark)
    }
}
