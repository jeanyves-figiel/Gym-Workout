import SwiftUI

/// Account → MonkeyGrade (#48): connect with MonkeyGrade email + password, read-only import of climbing sessions.
struct MonkeyGradeView: View {
    @Environment(AppModel.self) private var model
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var needsCode = false
    @FocusState private var codeFocused: Bool

    private var link: MonkeyGradeLink { .shared }
    private var connected: Bool { link.isConnected(for: model.user?.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if connected { connectedCard } else { signInForm }
                if let e = link.error {
                    Label(e, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange)
                }
                Text("Read-only. MonkeyWorkout reads your MonkeyGrade climbing sessions (duration, sends, grades, effort) from your home gym to show them with your climbs and plan around hard sessions. Your MonkeyGrade sign-in stays on this iPhone and is never sent to the MonkeyWorkout server.")
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("MonkeyGrade")
        .toolbarTitleDisplayMode(.inline)
        .task { if connected { await link.refresh() } }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(systemName: "figure.climbing")
                .font(.system(size: 30, weight: .bold))
                .frame(width: 60, height: 60)
                .background(RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.2)))
            VStack(alignment: .leading, spacing: 4) {
                Text("MonkeyGrade").font(Theme.display(24))
                Text(connected ? "Connected · \(link.stored?.email ?? "")" : "Bring your climbing sessions and grades in.")
                    .font(.footnote.weight(.medium)).opacity(0.85).lineLimit(2)
            }
            Spacer()
            if connected {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(link.sessions.count)").font(Theme.display(30)).monospacedDigit()
                    Text("sessions").font(Theme.label(10)).opacity(0.8)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(ClimbKind.lead.gradient))
    }

    private var connectedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let last = link.lastFetch {
                Text("Synced \(last.formatted(.relative(presentation: .named)))").font(.footnote).foregroundStyle(Theme.muted)
            }
            ForEach(link.sessions.prefix(5)) { s in
                HStack {
                    Image(systemName: (s.kind ?? .boulder).symbol).foregroundStyle(Theme.lime)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))).font(.subheadline.weight(.bold))
                        Text([s.detail, s.topGrade.map { "Top \($0)" }, s.effort.map { "RPE \($0)" }].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Text(Climbs.duration(s.minutes)).font(Theme.label(13))
                }
            }
            HStack(spacing: 10) {
                Button {
                    Task { await link.refresh(force: true) }
                } label: {
                    Label(link.busy ? "Syncing…" : "Sync now", systemImage: "arrow.clockwise")
                }
                .buttonStyle(LimeButtonStyle())
                Button(role: .destructive) { link.disconnect() } label: {
                    Text("Disconnect").font(Theme.label(15)).frame(maxWidth: .infinity).padding(.vertical, 18)
                        .background(Capsule().fill(Theme.cardStrong))
                }
                .buttonStyle(.plain)
            }
        }
        .card()
    }

    private var signInForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MonkeyGrade account").eyebrow()
            TextField("Email", text: $email)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .card(padding: 14)
            SecureField("Password", text: $password)
                .textContentType(.password)
                .card(padding: 14)
            if needsCode {
                TextField("2FA code", text: $code)
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
                    .focused($codeFocused)
                    .card(padding: 14)
            }
            Button {
                connect()
            } label: {
                if link.busy { ProgressView().tint(Theme.ink) } else { Label("Connect MonkeyGrade", systemImage: "link") }
            }
            .buttonStyle(LimeButtonStyle())
            .disabled(link.busy || email.isEmpty || password.isEmpty || (needsCode && code.isEmpty))
            Text("Signed up to MonkeyGrade with Apple? Set a password in MonkeyGrade (Account → Security) first; Apple sign-in can't be shared between apps.")
                .font(.footnote).foregroundStyle(Theme.muted)
        }
    }

    private func connect() {
        guard let owner = model.user?.id else { return }
        Task {
            switch await link.signIn(email: email, password: password, code: needsCode ? code : nil, ownerId: owner) {
            case .connected:
                password = ""
                code = ""
                needsCode = false
            case .needsCode:
                needsCode = true
                codeFocused = true
            case .failed:
                break
            }
        }
    }
}
