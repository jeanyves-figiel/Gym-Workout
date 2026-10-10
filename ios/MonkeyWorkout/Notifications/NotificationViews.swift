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
        return [plan, done, "\(model.state.history.count)", "\(notify.prefs.hashValue)", "\(notify.moves.count)", model.user?.id ?? ""]
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
                    NavigationStack { SessionView(sessionId: id) }
                case let .reschedule(id, day):
                    MissedSessionSheet(sessionId: id, day: day)
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

                if !(model.plan?.sessions.contains { $0.weekday != nil } ?? false) {
                    Label("Pick gym days in your training profile (Train → edit) so reminders know which day each session is.",
                          systemImage: "calendar.badge.exclamationmark")
                        .font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
                        .card()
                }

                NotifyCard(symbol: "alarm.fill", title: "Session reminder", detail: "Morning of each planned session",
                           gradient: NotifyStyle.reminder, trailing: notify.prefs.sessionReminders ? NotificationPrefs.clock(notify.prefs.reminderMinutes) : "Off",
                           isOn: $notify.prefs.sessionReminders) {
                    TimeRow(title: "Remind me at", minutes: $notify.prefs.reminderMinutes)
                }

                NotifyCard(symbol: "arrow.uturn.forward.circle.fill", title: "Missed session", detail: "Next-day check-in: train today or pick another day",
                           gradient: NotifyStyle.missed, trailing: notify.prefs.missedCheckIn ? NotificationPrefs.clock(notify.prefs.checkInMinutes) : "Off",
                           isOn: $notify.prefs.missedCheckIn) {
                    TimeRow(title: "Check in at", minutes: $notify.prefs.checkInMinutes)
                }

                NotifyCard(symbol: "medal.fill", title: "Your achievements", detail: "When you unlock a badge",
                           gradient: NotifyStyle.badge, trailing: notify.prefs.ownAchievements ? "On" : "Off",
                           isOn: $notify.prefs.ownAchievements) { EmptyView() }

                NotifyCard(symbol: "trophy.fill", title: "People you follow", detail: "When they set a PR or unlock a badge",
                           gradient: NotifyStyle.follow, trailing: notify.prefs.followAchievements ? "On" : "Off",
                           isOn: $notify.prefs.followAchievements) { EmptyView() }

                NotifyCard(symbol: "moon.stars.fill", title: "Quiet hours", detail: "Reminders move out; follow alerts arrive silently",
                           gradient: NotifyStyle.quiet,
                           trailing: notify.prefs.quietHours ? "\(NotificationPrefs.clock(notify.prefs.quietStart))–\(NotificationPrefs.clock(notify.prefs.quietEnd))" : "Off",
                           isOn: $notify.prefs.quietHours) {
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
    let trailing: String
    @Binding var isOn: Bool
    @ViewBuilder var options: () -> Options

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
                Text(trailing).font(Theme.display(20)).opacity(0.85).lineLimit(1).minimumScaleFactor(0.6)
            }
            Toggle(isOn: $isOn) { Text(isOn ? "On" : "Off").font(Theme.label(14)) }
                .tint(.white.opacity(0.9))
            if isOn { options() }
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(gradient))
        .animation(.snappy, value: isOn)
    }
}

/// Minute-of-day picker row.
private struct TimeRow: View {
    let title: String
    @Binding var minutes: Int

    private var date: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date() },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                minutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            })
    }

    var body: some View {
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

/// Opened from the missed-session notification: train now, or move the session to another day.
struct MissedSessionSheet: View {
    let sessionId: String
    let day: Date
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var training = false

    private var session: Session? { model.session(sessionId) }
    private var climbing: Set<Int> { Set(model.profile?.climbingDays ?? []) }

    private var options: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Missed \(day.formatted(.dateTime.weekday(.wide)))").font(Theme.label(12)).tracking(1.6)
                            .foregroundStyle(Theme.muted).textCase(.uppercase)
                        Text(session?.title ?? "Your session").font(Theme.display(34))
                        Text("No stress. Train today or pick a day that works.").font(.body.weight(.medium)).foregroundStyle(Theme.muted)
                    }
                    .padding(.bottom, 4)

                    Button { training = true } label: {
                        DayCard(symbol: "bolt.fill", title: "Train now", detail: session.map { "\($0.estMin) min" } ?? "",
                                big: "GO", gradient: NotifyStyle.today)
                    }
                    .buttonStyle(.plain)

                    Text("Move to").font(Theme.label(11)).tracking(1.6).foregroundStyle(Theme.muted).textCase(.uppercase)
                        .padding(.top, 6)
                    ForEach(options, id: \.self) { d in
                        Button {
                            NotificationManager.shared.move(sessionId: sessionId, from: day, to: d, model: model)
                            dismiss()
                        } label: {
                            DayCard(symbol: climbing.contains(weekday(d)) ? "figure.climbing" : "calendar",
                                    title: label(d), detail: note(d),
                                    big: d.formatted(.dateTime.day()), gradient: NotifyStyle.day)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Skip") { dismiss() } }
            }
            .fullScreenCover(isPresented: $training, onDismiss: { dismiss() }) {
                WorkoutPlayerView(sessionId: sessionId)
            }
        }
    }

    private func weekday(_ d: Date) -> Int { WeekSchedule.fromCalendar(Calendar.current.component(.weekday, from: d)) }

    private func label(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInTomorrow(d) { return "Tomorrow" }
        return d.formatted(.dateTime.weekday(.wide))
    }

    /// What else is on that day.
    private func note(_ d: Date) -> String {
        let cal = Calendar.current
        let planned = NotificationManager.shared.plannedDays(model).filter { cal.isDate($0.day, inSameDayAs: d) && $0.sessionId != sessionId }
        var parts: [String] = []
        if climbing.contains(weekday(d)) { parts.append("Climbing day") }
        parts += planned.map { "\($0.title) planned" }
        return parts.isEmpty ? "Free" : parts.joined(separator: " · ")
    }
}

private struct DayCard: View {
    let symbol: String
    let title: String
    let detail: String
    let big: String
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
            Text(big).font(Theme.display(30)).opacity(0.85)
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(gradient))
    }
}
