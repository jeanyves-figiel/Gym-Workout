import APIClient
import LiftSensor
import SwiftUI
import WorkoutEngine

// Live group sessions (#626, designs B + C from `apple-tech-radar/batch4.html`; no SharePlay).

/// B: gym buddies in Community. Paired buddies training now show their set, with cheers to send; invites to answer.
struct BuddiesCard: View {
    @Environment(AppModel.self) private var model
    private var live: LiveRoom { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "figure.2").font(.system(size: 22, weight: .bold))
                    .frame(width: 48, height: 48)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.22)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Gym buddies").font(Theme.display(21))
                    Text("Live sets and cheers on your Watch").font(.footnote.weight(.semibold)).opacity(0.88)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(live.paired.filter { $0.live != nil }.count)").font(Theme.display(26)).monospacedDigit()
                    Text("LIVE").font(Theme.label(9)).tracking(1.2).opacity(0.8)
                }
            }
            ForEach(live.invites) { b in
                HStack(spacing: 10) {
                    AvatarView(url: model.api.resolve(b.avatarUrl), nickname: b.nickname, size: 32)
                    Text("\(b.nickname) wants to train with you").font(Theme.label(13)).lineLimit(2)
                    Spacer(minLength: 4)
                    Button("PAIR") { Task { await live.add(b.userId, api: model.api) } }
                        .font(Theme.label(13)).foregroundStyle(Theme.ink)
                        .padding(.horizontal, 12).frame(minHeight: 36)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.lime))
                    Button { Task { await live.remove(b.userId, api: model.api) } } label: {
                        Image(systemName: "xmark").font(.footnote.bold()).frame(width: 36, height: 36)
                    }
                    .accessibilityLabel("Decline \(b.nickname)")
                }
                .buttonStyle(.plain)
            }
            ForEach(live.paired) { BuddyRow(buddy: $0) }
            if live.paired.isEmpty && live.invites.isEmpty {
                Text("Open a member's profile and tap Gym buddy. Once you both pair, you see each other's sets while you train.")
                    .font(.caption.weight(.semibold)).opacity(0.9)
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(LinearGradient.buddies))
    }
}

private struct BuddyRow: View {
    let buddy: GymBuddy
    @Environment(AppModel.self) private var model
    @State private var sent: LiveCheer?

    var body: some View {
        HStack(spacing: 10) {
            NavigationLink(value: buddy.author) {
                HStack(spacing: 10) {
                    AvatarView(url: model.api.resolve(buddy.avatarUrl), nickname: buddy.nickname, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(buddy.nickname.uppercased() + (buddy.live == nil ? "" : " · LIVE")).font(Theme.label(11)).tracking(1)
                        Text(buddy.live.map { "\($0.exercise)\($0.detail.map { " \($0)" } ?? "")\($0.state == .rest ? " ✓" : "")" } ?? "Not training now")
                            .font(Theme.label(14)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer(minLength: 4)
            if buddy.live != nil {
                ForEach(LiveCheer.allCases) { c in
                    Button {
                        LiveRoom.shared.cheer(buddy.userId, c, api: model.api)
                        sent = c
                    } label: {
                        Text(c.emoji).font(.system(size: 20)).frame(width: 38, height: 38)
                            .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(sent == c ? 0.4 : 0.18)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cheer \(buddy.nickname) \(c.rawValue)")
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.14)))
        .sensoryFeedback(.success, trigger: sent)
    }
}

/// On a member's page: invite, accept, or unpair.
struct BuddyButton: View {
    let userId: String
    @Environment(AppModel.self) private var model
    @State private var busy = false
    private var live: LiveRoom { .shared }

    private func title(_ status: GymBuddy.Status?) -> String {
        switch status {
        case .paired: "GYM BUDDY ✓"
        case .invited: "INVITED · CANCEL"
        case .invitesYou: "ACCEPT GYM BUDDY"
        case nil: "GYM BUDDY"
        }
    }

    var body: some View {
        let status = live.status(userId)
        Button {
            busy = true
            Task {
                defer { busy = false }
                if status == .paired || status == .invited { await live.remove(userId, api: model.api) } else { await live.add(userId, api: model.api) }
            }
        } label: {
            Label(title(status), systemImage: "figure.2")
        }
        .buttonStyle(LimeButtonStyle(fill: status == nil || status == .invitesYou ? Theme.lime : Theme.cardStrong,
                                     text: status == nil || status == .invitesYou ? Theme.ink : .white))
        .disabled(busy)
        .task { if live.buddies.isEmpty { await live.load(api: model.api) } }
    }
}

/// A buddy's set or cheer, over the player for a few seconds.
struct BuddyToast: View {
    private var live: LiveRoom { .shared }

    var body: some View {
        if let p = live.toast {
            HStack(spacing: 8) {
                Text(p.cheer ?? "💪").font(.system(size: 22))
                Text(p.cheer == nil ? "\(p.name) · \(p.text ?? "")" : "\(p.name) cheered you").font(Theme.label(14)).lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Capsule().fill(LinearGradient.buddies))
            .padding(.top, 6)
            .transition(.move(edge: .top).combined(with: .opacity))
            .id(p.id)
            .accessibilityElement(children: .combine)
        }
    }
}

/// Player top bar (#675 C): green LIVE while buddies see your sets, grey PRIVATE while they only see "Training".
struct LiveShareTile: View {
    private var live: LiveRoom { .shared }

    var body: some View {
        let on = live.sharing
        Button { live.toggleSharing() } label: {
            Image(systemName: on ? "dot.radiowaves.left.and.right" : "eye.slash.fill").font(.system(size: 15, weight: .heavy))
                .foregroundStyle(on ? Theme.ink : .white)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(on ? AnyShapeStyle(LinearGradient.buddies)
                             : AnyShapeStyle(Theme.cardStrong)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(on ? "Live" : "Private")
        .accessibilityHint(on ? "Go private: buddies only see that you train" : "Go live: buddies see your sets")
        .accessibilityIdentifier("player.liveShare")
    }
}

/// Your profile › Community (#675 B): the live sharing default and who sees it.
struct LiveSharingView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(LiveSharePref.key) private var pref = LiveSharePref.always.rawValue
    private var live: LiveRoom { .shared }

    var body: some View {
        let current = LiveSharePref(rawValue: pref) ?? .always
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Live").font(Theme.display(22))
                    Picker("Live", selection: $pref) {
                        ForEach(LiveSharePref.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    Text(current.note).font(Theme.label(13)).opacity(0.92)
                }
                .foregroundStyle(.white)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient.buddies))
                if current != .never {
                    Text("Who sees it").font(Theme.label(13)).tracking(1.2).textCase(.uppercase).foregroundStyle(Theme.muted).padding(.top, 8)
                    if live.paired.isEmpty {
                        AccountNote(text: "No gym buddies yet. Pair from a member's page in Social.")
                    }
                    ForEach(live.paired) { b in
                        Toggle(isOn: Binding(get: { b.sharesLive }, set: { on in Task { await live.setShare(b.userId, on, api: model.api) } })) {
                            Text(b.nickname).font(.system(.body, design: .rounded).weight(.heavy))
                        }
                        .tint(Theme.lime)
                        .card(padding: 14)
                    }
                    AccountNote(text: "Off: that buddy doesn't see you training. Cheers still come through from buddies who see you.")
                }
                ErrorText(message: live.error)
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Live")
        .navigationBarTitleDisplayMode(.inline)
        .task { await live.load(api: model.api) }
    }
}
