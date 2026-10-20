import APIClient
import SwiftUI

/// Settings → Watches → Garmin watch (#550): pair a Garmin watch with the code it shows, see and remove paired ones.
struct GarminView: View {
    private var sync: GarminSync { .shared }
    @State private var code = ""
    @State private var pairing = false
    @State private var error: String?
    @FocusState private var codeFocused: Bool

    static let gradient = LinearGradient(colors: [Color(hex: 0x1E8BFF), Color(hex: 0x00C2B8)], startPoint: .topLeading, endPoint: .bottomTrailing)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                AccountHeader(symbol: "watch.analog", title: "Garmin watch",
                              subtitle: "Today's workout, sets, rest and water on your Garmin.", gradient: Self.gradient)
                ForEach(sync.devices) { device in deviceRow(device) }
                pairCard
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.semibold)).foregroundStyle(Color(hex: 0xFF6A7A))
                }
                Text("Your Garmin saves each workout to Garmin Connect, which adds it to Apple Health. MonkeyWorkout logs it once.")
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
            .padding(16)
            .readableWidth()
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Garmin watch")
        .navigationBarTitleDisplayMode(.inline)
        .task { await sync.refreshDevices() }
    }

    private var pairCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(sync.devices.isEmpty ? "Pair your watch" : "Pair another watch").font(Theme.display(20))
            step(1, "Install **MonkeyWorkout** from the Connect IQ Store on your watch.")
            step(2, "Open it on the watch: it shows a 6-letter code.")
            step(3, "Type the code here.")
            HStack(spacing: 8) {
                TextField("CODE", text: $code)
                    .font(Theme.display(22)).monospaced()
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($codeFocused)
                    .submitLabel(.go)
                    .onSubmit(pair)
                    .onChange(of: code) { _, v in code = String(v.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6)) }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.ink.opacity(0.35)))
                    .accessibilityLabel("Pairing code")
                Button(action: pair) {
                    Group {
                        if pairing { ProgressView().tint(Theme.ink) } else { Text("Pair") }
                    }
                    .frame(width: 70)
                }
                .buttonStyle(LimeButtonStyle())
                .fixedSize()
                .disabled(code.count < 6 || pairing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gradientCard(Self.gradient)
    }

    private func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)").font(Theme.label(13)).frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white.opacity(0.22)))
            Text(text).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func deviceRow(_ d: GarminDevice) -> some View {
        HStack(spacing: 12) {
            IconTile(symbol: "watch.analog", size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(d.model.map { "Garmin \($0)" } ?? "Garmin watch").font(Theme.label(16)).lineLimit(1).minimumScaleFactor(0.7)
                Text(lastSeen(d)).font(.caption.weight(.semibold)).opacity(0.85)
            }
            Spacer(minLength: 8)
            Button {
                Task {
                    do { try await sync.remove(d) } catch { self.error = error.localizedDescription }
                }
            } label: {
                Text("Remove").font(Theme.label(13)).padding(.horizontal, 12).frame(minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black.opacity(0.25)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(d.model ?? "Garmin watch")")
        }
        .gradientCard(Self.gradient, padding: 12)
    }

    private func lastSeen(_ d: GarminDevice) -> String {
        guard let s = d.lastSeen, let date = ISO8601DateFormatter.withFraction.date(from: s) else { return "Paired" }
        return "Synced \(date.formatted(.relative(presentation: .named)))"
    }

    private func pair() {
        guard code.count == 6, !pairing else { return }
        pairing = true
        error = nil
        Task {
            defer { pairing = false }
            do {
                try await sync.claim(code)
                code = ""
                codeFocused = false
                Haptics.success()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

private extension ISO8601DateFormatter {
    static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
