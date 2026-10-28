import APIClient
import SwiftUI
import WorkoutEngine

private func rgb(_ v: UInt32) -> Color {
    Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
}

/// Gradients for notification cards, in the Explore category style.
enum NotifyStyle {
    static let reminder = LinearGradient(colors: [rgb(0x2F6BFF), rgb(0x8A4DFF)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let missed = LinearGradient(colors: [rgb(0xFF8A00), rgb(0xFFC93D)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let follow = LinearGradient(colors: [rgb(0xFF2D55), rgb(0xFF6FB5)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let badge = LinearGradient(colors: [rgb(0xFFB800), rgb(0xFF5E3A)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let move = LinearGradient(colors: [rgb(0xFF7A3D), rgb(0xFF3D8A)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let alarm = LinearGradient(colors: [rgb(0xFF8A00), rgb(0xFF3D7B)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let quiet = LinearGradient(colors: [rgb(0x3A2D7A), rgb(0x1E1650)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let today = LinearGradient(colors: [rgb(0x00C9A7), rgb(0x2EC5FF)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let day = LinearGradient(colors: [Color.white.opacity(0.10), Color.white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// Attach once to the signed-in root: keeps local reminders in sync with the plan, registers for push,
/// announces new badges, and presents the screen a tapped notification asks for.
struct NotificationsHost: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var notify = NotificationManager.shared

    /// Changes whenever something that affects reminders changes.
    private var key: String {
        let plan = model.plan?.sessions.map { "\($0.id)@\($0.weekday ?? 0)" }.joined(separator: ",") ?? ""
        let done = model.state.done.filter(\.value).keys.sorted().joined(separator: ",")
        // A skip or removal (this week or ahead) takes its reminders off (#818).
        let skipped = model.skippedIds.sorted().joined(separator: ",")
        let ahead = (model.state.skippedAhead ?? [:]).map { "\($0.key):\($0.value.sorted().joined(separator: "+"))" }.sorted().joined(separator: ",")
        return [plan, done, skipped, ahead, "\(model.state.history.count)", "\(notify.prefs.hashValue)", "\(model.away.count)", model.user?.id ?? ""]
            .joined(separator: "|")
    }

    func body(content: Content) -> some View {
        @Bindable var notify = notify
        content
            .task(id: key) {
                guard !model.demo else { return }
                if notify.authorization == .notDetermined, model.plan != nil { await notify.requestAuthorization() }
                await notify.reschedule(model)
                notify.registerRemoteIfNeeded()
                await notify.syncRemote(model)
                await notify.announceNewBadges(model)
                // Daily Move (#454): no slow-day nudge after a workout in this app, even one not saved to Health.
                if let last = model.state.history.map(\.startedAt).max(), Calendar.current.isDateInToday(last) {
                    MoveStore.shared.markBusy(last)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, !model.demo else { return }
                Task {
                    await notify.reschedule(model)
                    notify.registerRemoteIfNeeded()
                    await notify.syncRemote(model)
                }
            }
            .sheet(item: $notify.route) { route in
                switch route {
                case let .session(id):
                    // Standard chrome (#539): the X closes the session opened from a notification.
                    NavigationStack { SessionView(sessionId: id).toolbar { CloseToolbarItem { notify.route = nil } } }
                case let .reschedule(id, day):
                    MissedSessionSheet(sessionId: id, day: day)
                case let .move(id):
                    RescheduleSheet(sessionId: id)
                case let .member(userId, nickname):
                    NavigationStack {
                        MemberView(author: CommunityAuthor(userId: userId, nickname: nickname))
                            .toolbar { CloseToolbarItem { notify.route = nil } }
                    }
                case let .badge(id):
                    if let b = Achievements.evaluate(records: model.state.history, weights: model.weightEntries,
                                                     targetPerWeek: model.profile?.sessionsPerWeek ?? 3).first(where: { $0.id == id }) {
                        BadgeSheet(badge: b).presentationDetents([.medium])
                    }
                }
            }
    }
}

// MARK: - Settings

struct NotificationSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var notify = NotificationManager.shared
    @State private var testResult: String?
    @State private var testing = false
    @State private var alarms = TimerAlarms.shared

    /// Ring through Silent (#613 C): turning it on asks iOS for alarms; refused → stays off.
    private var ringBinding: Binding<Bool> {
        Binding(get: { alarms.enabled }, set: { on in
            if on { Task { await alarms.enable() } } else { alarms.disable() }
        })
    }

    var body: some View {
        @Bindable var notify = notify
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notifications").font(Theme.display(40))
                    Text("Session reminders, missed-session check-ins, your badges and wins from people you follow.")
                        .font(.body.weight(.medium)).foregroundStyle(Theme.muted)
                }
                .padding(.bottom, 6)

                if notify.authorization == .denied {
                    PermissionCard()
                } else if notify.authorization == .notDetermined {
                    Button { Task { await notify.requestAuthorization() } } label: {
                        Text("Turn on notifications").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(LimeButtonStyle())
                }

                if !(model.plan?.sessions.contains(where: { $0.weekday != nil }) ?? false) {
                    Label("Pick gym days in your training profile (Train → edit) so reminders know which day each session is.",
                          systemImage: "calendar.badge.exclamationmark")
                        .font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
                        .card()
                }

                // Cards show the real state (#822, design A from `full-app-audit-3/mockups/proposals-4.png`): dimmed with
                // "Off · iPhone notifications are off" until iPhone allows them; a time shows once, its number opens the picker.
                let blocked = !notify.allowed
                NotifyCard(symbol: "alarm.fill", title: "Session reminder", detail: "Morning of each planned session",
                           gradient: NotifyStyle.reminder, trailing: notify.prefs.sessionReminders ? NotificationPrefs.clock(notify.prefs.reminderMinutes) : "Off",
                           isOn: $notify.prefs.sessionReminders, blocked: blocked, time: $notify.prefs.reminderMinutes) { EmptyView() }

                NotifyCard(symbol: "arrow.uturn.forward.circle.fill", title: "Missed session", detail: "Next-day check-in: train today or pick another day",
                           gradient: NotifyStyle.missed, trailing: notify.prefs.missedCheckIn ? NotificationPrefs.clock(notify.prefs.checkInMinutes) : "Off",
                           isOn: $notify.prefs.missedCheckIn, blocked: blocked, time: $notify.prefs.checkInMinutes) { EmptyView() }

                // No big "On" (#822): the switch says it.
                NotifyCard(symbol: "medal.fill", title: "Your achievements", detail: "When you unlock a badge",
                           gradient: NotifyStyle.badge, trailing: nil,
                           isOn: $notify.prefs.ownAchievements, blocked: blocked) { EmptyView() }

                NotifyCard(symbol: "trophy.fill", title: "People you follow", detail: "When they set a PR or unlock a badge",
                           gradient: NotifyStyle.follow, trailing: nil,
                           isOn: $notify.prefs.followAchievements, blocked: blocked) { EmptyView() }

                NotifyCard(symbol: "figure.walk", title: "Daily Move nudge",
                           detail: "One nudge on a day well below your usual steps, at the hour you usually walk",
                           gradient: NotifyStyle.move, trailing: notify.prefs.moveNudges ? NotificationPrefs.clock(MoveStore.shared.hour * 60) : "Off",
                           isOn: $notify.prefs.moveNudges, blocked: blocked) {
                    Text("Skipped when you trained or logged a sport, hit your usual, or tapped Rest day. Steps never leave your iPhone.")
                        .font(.footnote.weight(.semibold)).opacity(0.9)
                }

                if alarms.available {
                    NotifyCard(symbol: "alarm.waves.left.and.right.fill", title: "Ring through Silent",
                               detail: "Rest and interval timers sound like an alarm on iPhone and Watch, even with Focus on",
                               gradient: NotifyStyle.alarm, trailing: alarms.enabled ? "On" : "Off", isOn: ringBinding) {
                        Text("End of rest: Start set or +30 s on the alarm. Tabata, EMOM and rounds ring at each block.")
                            .font(.footnote.weight(.semibold)).opacity(0.9)
                    }
                }

                NotifyCard(symbol: "moon.stars.fill", title: "Quiet hours", detail: "Reminders move out; follow alerts arrive silently",
                           gradient: NotifyStyle.quiet,
                           trailing: notify.prefs.quietHours ? "\(NotificationPrefs.clock(notify.prefs.quietStart))–\(NotificationPrefs.clock(notify.prefs.quietEnd))" : "Off",
                           isOn: $notify.prefs.quietHours, blocked: blocked) {
                    TimeRow(title: "From", minutes: $notify.prefs.quietStart)
                    TimeRow(title: "Until", minutes: $notify.prefs.quietEnd)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(notify.pendingCount)").font(Theme.display(28))
                        Text("Scheduled").font(Theme.label(11)).foregroundStyle(Theme.muted).textCase(.uppercase)
                    }
                    Spacer()
                    Button {
                        testing = true
                        Task {
                            await notify.sendLocalTest()
                            if let r = try? await model.api.sendTestPush() {
                                testResult = !r.pushConfigured ? "Reminder test sent. Server push not set up yet."
                                    : r.sent > 0 ? "Reminder and push test sent." : "Reminder test sent. No push device registered yet."
                            } else {
                                testResult = "Reminder test sent. Server unreachable."
                            }
                            testing = false
                        }
                    } label: {
                        Label(testing ? "Sending…" : "Send test", systemImage: "paperplane.fill").font(Theme.label(15))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(testing || !notify.allowed)
                }
                .card()
                if let testResult {
                    Text(testResult).font(.footnote).foregroundStyle(Theme.muted)
                }
            }
            .padding(16)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .task { await notify.refreshAuthorization() }
        .onChange(of: notify.prefs) { _, _ in
            Task {
                await notify.reschedule(model)
                notify.registerRemoteIfNeeded()
                await notify.syncRemote(model)
            }
        }
    }
}

/// Explore-style gradient card: icon tile, heavy title, big value right, toggle; options under it when on.
private struct NotifyCard<Options: View>: View {
    let symbol: String
    let title: String
    let detail: String
    let gradient: LinearGradient
    /// Big value on the right; nil = none (the switch says it, #822).
    let trailing: String?
    @Binding var isOn: Bool
    /// iPhone notifications not allowed (#822): dimmed, and the switch line says so.
    var blocked = false
    /// The card's time (#822): its big number opens the time picker, so the time shows once.
    var time: Binding<Int>? = nil
    @ViewBuilder var options: () -> Options
    @State private var picking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .bold))
                    .frame(width: 56, height: 56)
                    .background(RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.2)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(Theme.display(22))
                    Text(detail).font(.footnote.weight(.medium)).opacity(0.85)
                }
                Spacer(minLength: 4)
                if let trailing {
                    if time != nil, isOn {
                        Button { picking.toggle() } label: {
                            Text(trailing).font(Theme.display(20)).opacity(0.85).lineLimit(1).minimumScaleFactor(0.6)
                                .underline(picking)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(title) at \(trailing)")
                        .accessibilityHint("Changes the time")
                    } else {
                        Text(trailing).font(Theme.display(20)).opacity(0.85).lineLimit(1).minimumScaleFactor(0.6)
                    }
                }
            }
            Toggle(isOn: $isOn) {
                Text(blocked ? "Off · iPhone notifications are off" : isOn ? "On" : "Off").font(Theme.label(14))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
                .tint(.white.opacity(0.9))
            if isOn {
                if let time, picking { TimeRow(title: "Time", minutes: time, wheel: true) }
                options()
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(gradient))
        .opacity(blocked ? 0.55 : 1)
        .animation(.snappy, value: isOn)
        .animation(.snappy, value: picking)
    }
}

/// Minute-of-day picker row.
private struct TimeRow: View {
    let title: String
    @Binding var minutes: Int
    /// The picker opened from a card's big time (#822): a wheel, no label (the number above is the time).
    var wheel = false

    private var date: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date() },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                minutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            })
    }

    var body: some View {
        if wheel {
            DatePicker(title, selection: date, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .colorScheme(.dark)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 14).fill(.black.opacity(0.18)))
        } else {
            row
        }
    }

    private var row: some View {
        HStack {
            Text(title).font(Theme.label(14))
            Spacer()
            DatePicker(title, selection: date, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .colorScheme(.dark)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 14).fill(.black.opacity(0.18)))
    }
}

private struct PermissionCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Notifications are off for MonkeyWorkout", systemImage: "bell.slash.fill").font(Theme.label(16))
            Text("Turn them on in iOS Settings to get reminders and check-ins.").font(.footnote).foregroundStyle(Theme.muted)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

// MARK: - Missed-session check-in

/// Opened from the missed-session notification: train now, or move the session with the training calendar (#68).
struct MissedSessionSheet: View {
    let sessionId: String
    let day: Date
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var training = false
    @State private var calendar = false
    /// Move it found no free day left this week (#822).
    @State private var noFreeDay = false
    /// Log it from the catch-up row (#822).
    @State private var logging: Session?

    /// This week's session, still missed and not let go: the same catch-up row as Train and Calendar (#822).
    private var stillMissed: Session? { model.missedSessions.first { $0.id == sessionId } }

    private var session: Session? { model.session(sessionId) }

    private func moveNow() {
        let before = Set(model.away.map(\.id))
        let title = session?.displayTitle ?? ""
        let from = session?.weekday
        let moved = model.reschedule(sessionId: sessionId)
        let added = model.away.filter { !before.contains($0.id) }.map(\.id)
        // Nothing changed (#822): say so here, never a toast claiming a move or a skip.
        guard moved != nil || !added.isEmpty else {
            withAnimation { noFreeDay = true }
            return
        }
        dismiss()
        let toast = moved.map { "Moved to \($0.formatted(.dateTime.weekday(.wide)))" } ?? "No free day left: skipped"
        UndoCloseCenter.shared.deleted(toast, detail: title, symbol: "arrow.uturn.forward") { [model, sessionId] in
            for id in added { model.deleteAway(id) }
            // A missed day moves without a day off (#822): Undo puts it back on its day.
            if added.isEmpty, let from { model.moveSession(sessionId, to: from, swap: false) }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Missed \(day.formatted(.dateTime.weekday(.wide)))").font(Theme.label(12)).tracking(1.6)
                            .foregroundStyle(Theme.muted).textCase(.uppercase)
                        // Same name as Train and the missed card, "Lower body", not "Day 2 · Lower body" (#823).
                        Text(session?.displayTitle ?? "Your session").font(Theme.display(34))
                        // A week that has rolled on (#822): the session left the plan, so no dead Train / Move buttons.
                        Text(session == nil ? "That week is over and your plan has moved on. See what's coming in the calendar."
                             : "No stress. Train today or move it to a free day.")
                            .font(.body.weight(.medium)).foregroundStyle(Theme.muted)
                    }
                    .padding(.bottom, 4)

                    // Log it · Mark done · Do today · Skip (#822), each with its Undo bar, as on Train's missed card.
                    if let missed = stillMissed {
                        MissedActionsRow(session: missed) { logging = missed }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(MissedStyle.gradient))
                    }

                    if session != nil {
                        Button { training = true } label: {
                            DayCard(symbol: "bolt.fill", title: "Train now", detail: session.map { "\($0.estMin) min" } ?? "",
                                    big: "GO", gradient: NotifyStyle.today)
                        }
                        .buttonStyle(.plain)
                        // Done meanwhile (an old notification, #817): training it again would record a second workout.
                        .disabled(session == nil || model.doneIds.contains(sessionId))

                        // One tap moves it, as the card says; the Undo bar puts it back (#285).
                        Button(action: moveNow) {
                            DayCard(symbol: "arrow.uturn.forward", title: "Move it", detail: "Next free day this week",
                                    big: "→", gradient: NotifyStyle.missed)
                        }
                        .buttonStyle(.plain)
                        .disabled(noFreeDay)
                        if noFreeDay {
                            Text("No free day left this week, so it stays where it was. Pick a day in the calendar, or let it go.")
                                .font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
                        }
                    }

                    Button { calendar = true } label: {
                        DayCard(symbol: "calendar", title: "Open calendar", detail: "See the coming weeks, mark days off",
                                big: Date().formatted(.dateTime.day()), caption: Date().formatted(.dateTime.month(.abbreviated)),
                                gradient: NotifyStyle.reminder)
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
            }
            .readableWidth()
            .background(Theme.bg.ignoresSafeArea())
            // X top right as everywhere (#822): "Skip" read as skipping the session, but only closed.
            .toolbar { CloseToolbarItem { dismiss() } }
            .fullScreenCover(isPresented: $training, onDismiss: { dismiss() }) {
                WorkoutPlayerView(sessionId: sessionId)
            }
            .sheet(isPresented: $calendar) {
                NavigationStack { CalendarView() }
            }
            .sheet(item: $logging, onDismiss: { if stillMissed == nil { dismiss() } }) { MissedLogSheet(session: $0) }
            // Handled from the row (#822): done, moved to today or let go, so nothing is left to ask.
            .onChange(of: stillMissed == nil) { _, gone in if gone && logging == nil { dismiss() } }
        }
    }
}

private struct DayCard: View {
    let symbol: String
    let title: String
    let detail: String
    let big: String
    /// Small label under `big` (e.g. the month under today's date).
    var caption: String? = nil
    let gradient: LinearGradient

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .bold))
                .frame(width: 56, height: 56)
                .background(RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.2)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.display(22))
                Text(detail).font(.footnote.weight(.medium)).opacity(0.85)
            }
            Spacer()
            VStack(spacing: 0) {
                Text(big).font(Theme.display(30)).monospacedDigit()
                if let caption { Text(caption.uppercased()).font(Theme.label(10)).tracking(1.2) }
            }
            .opacity(0.85)
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(gradient))
    }
}
