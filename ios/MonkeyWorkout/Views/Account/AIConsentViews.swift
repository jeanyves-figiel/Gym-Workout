import APIClient
import SwiftUI

private let claudeGradient = LinearGradient(colors: [Color(red: 0.48, green: 0.18, blue: 0.97), Color(red: 0.95, green: 0.03, blue: 0.64)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing)
private let privacyGradient = LinearGradient(colors: [Color(red: 0.07, green: 0.60, blue: 0.56), Color(red: 0.22, green: 0.94, blue: 0.49)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)

/// A (#972): first AI use. What each feature sends to Anthropic, a switch each (all on), Allow or Not now.
struct AIConsentSheet: View {
    private let store = AIConsentStore.shared
    @State private var on = Set(AIFeature.allCases)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("COACH'S AI").font(Theme.label(11)).tracking(1.4).opacity(0.85)
                    Text("Coach thinks\nwith Claude").font(Theme.display(28)).fixedSize(horizontal: false, vertical: true)
                    Text("Smart answers come from Claude by Anthropic. Pick what it may get; change it any time in Settings → AI & privacy.")
                        .font(.subheadline.weight(.semibold)).opacity(0.9)
                }
                .foregroundStyle(.white)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(claudeGradient))
                ForEach(AIFeature.allCases) { f in
                    AIFeatureRow(feature: f, on: Binding(get: { on.contains(f) }, set: { if $0 { on.insert(f) } else { on.remove(f) } }))
                }
                AIPromiseRow()
                Button { store.answer(on) } label: {
                    Text(on.isEmpty ? "Save · on-device only" : "Allow Coach AI").font(Theme.label(15)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(AIFeature.coach.gradient))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("aiConsent.allow")
                Button { store.answer([]) } label: {
                    Text("Not now · on-device only").font(Theme.label(15)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.cardStrong))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("aiConsent.notNow")
                Link("Privacy policy · AI features", destination: AppConfig.privacyURL)
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.lime)
            }
            .padding(16)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .toolbar { CloseToolbarItem { store.dismissed() } }
    }
}

/// C (#972): Settings → AI & privacy, a switch per feature and the community check (always on when you post).
struct AIPrivacyView: View {
    private let store = AIConsentStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Claude by Anthropic").font(Theme.display(20))
                    Text("Only what each switch says is sent. Off: Coach answers on this iPhone only.")
                        .font(.subheadline.weight(.semibold)).opacity(0.9)
                }
                .foregroundStyle(Theme.ink)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(privacyGradient))
                ForEach(AIFeature.allCases) { f in
                    AIFeatureRow(feature: f, on: Binding(get: { store.allows(f) }, set: { store.set(f, $0) }))
                }
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.shield.fill").font(.system(size: 16, weight: .bold))
                        .frame(width: 36, height: 36)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(0.22)))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Community checks").font(Theme.display(17))
                        Text("Names, captions and photos you post are checked against the guidelines first").font(.caption.weight(.semibold)).opacity(0.85)
                    }
                }
                .foregroundStyle(.white)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
                AIPromiseRow()
                Link("Privacy policy · AI features", destination: AppConfig.privacyURL)
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.lime)
            }
            .padding(16)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("AI & privacy")
    }
}

/// Icon tile left, what it sends, switch right.
private struct AIFeatureRow: View {
    let feature: AIFeature
    @Binding var on: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: feature.symbol).font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(feature.gradient))
            VStack(alignment: .leading, spacing: 1) {
                Text(feature.title).font(Theme.display(16)).lineLimit(1).minimumScaleFactor(0.75)
                Text(feature.sends).font(.caption.weight(.semibold)).opacity(0.8).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            Toggle(feature.title, isOn: $on).labelsHidden().tint(Theme.lime)
                .accessibilityIdentifier("aiConsent.\(feature.rawValue)")
        }
        .foregroundStyle(.white)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
    }
}

private struct AIPromiseRow: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.ink)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(privacyGradient))
            Text("Never your name, email or account id. Not used to train models; Anthropic deletes it within 30 days.")
                .font(.caption.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
    }
}
