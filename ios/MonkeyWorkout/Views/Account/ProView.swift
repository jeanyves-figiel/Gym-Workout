import APIClient
import StoreKit
import SwiftUI

extension AccountTint {
    /// MonkeyWorkout Pro (#126): lime → gold, the app's accent turned premium.
    static let pro = LinearGradient(colors: [Color(red: 0.62, green: 0.92, blue: 0.12), Color(red: 1, green: 0.72, blue: 0.1)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// What Pro adds (decided 2026-10-24): Ask Coach, Generate & do today and the two AI scans. Everything else is free.
/// Proposal only (#126): nothing is locked until the server mode is `enforced`.
enum ProFeature: CaseIterable {
    case askCoach, generateToday, gymScan, foodScan

    var symbol: String {
        switch self {
        case .askCoach: "bubble.left.and.text.bubble.right.fill"
        case .generateToday: "wand.and.stars"
        case .gymScan: "camera.viewfinder"
        case .foodScan: "refrigerator.fill"
        }
    }

    var title: String {
        switch self {
        case .askCoach: "Ask Coach anything, anywhere"
        case .generateToday: "Generate a workout and do it today"
        case .gymScan: "Gym scan: equipment sorts itself"
        case .foodScan: "Fridge and receipt scan for meals"
        }
    }
}

/// One plan on the paywall. Built from the App Store product; CHF fallbacks when products can't load (demo, no network).
struct ProPlan: Identifiable {
    let id: String
    let title: String
    let price: String
    let period: String
    let note: String?
    let product: Product?

    static func from(_ products: [Product]) -> [ProPlan] {
        guard !products.isEmpty else { return fallback }
        let monthly = products.first { $0.id.hasSuffix(".monthly") }?.price
        return products.map { p in
            if p.type == .nonConsumable {
                return ProPlan(id: p.id, title: "Lifetime", price: p.displayPrice, period: "lifetime", note: "Pay once · all future updates included", product: p)
            }
            let unit = p.subscription?.subscriptionPeriod.unit
            let yearly = unit == .year
            var note: String?
            if yearly, let monthly, monthly > 0 {
                let save = Int((NSDecimalNumber(decimal: (1 - (p.price / 12) / monthly) * 100).doubleValue).rounded())
                note = "\((p.price / 12).formatted(p.priceFormatStyle))/mo" + (save > 0 ? " · save \(save)%" : "") // no space: "%" never wraps alone (#823)
            }
            return ProPlan(id: p.id, title: yearly ? "Yearly" : unit == .month ? "Monthly" : "Weekly", price: p.displayPrice,
                           period: yearly ? "year" : unit == .month ? "month" : "week", note: note, product: p)
        }
    }

    static let fallback = [
        ProPlan(id: "monkeyworkout.pro.yearly", title: "Yearly", price: "CHF 60.00", period: "year", note: "CHF 5.00/mo · save 17%", product: nil),
        ProPlan(id: ProStore.lifetimeId, title: "Lifetime", price: "CHF 100.00", period: "lifetime", note: "Pay once · all future updates included", product: nil),
        ProPlan(id: "monkeyworkout.pro.monthly", title: "Monthly", price: "CHF 6.00", period: "month", note: nil, product: nil),
        ProPlan(id: "monkeyworkout.pro.weekly", title: "Weekly", price: "CHF 2.00", period: "week", note: nil, product: nil),
    ]
}

/// A Pro feature someone tapped (#126): heads the paywall sheet ("Ask Coach is Pro").
enum ProGate: String, Identifiable {
    case askCoach, generateWorkout, gymScan, foodScan

    var id: String { rawValue }

    var title: String {
        switch self {
        case .askCoach: "Ask Coach is Pro"
        case .generateWorkout: "Generate & do today is Pro"
        case .gymScan: "Gym scan is Pro"
        case .foodScan: "Fridge scan is Pro"
        }
    }

    var subtitle: String {
        switch self {
        case .askCoach: "Your coach answers about any screen, by text or voice."
        case .generateWorkout: "Pick muscles, get a workout and start it now. Adding it to a day stays free."
        case .gymScan: "Snap each area of your gym, the equipment sorts itself."
        case .foodScan: "Snap your fridge or a receipt, get meals that fit your day."
        }
    }

    var symbol: String {
        switch self {
        case .askCoach: "bubble.left.and.text.bubble.right.fill"
        case .generateWorkout: "wand.and.stars"
        case .gymScan: "camera.viewfinder"
        case .foodScan: "refrigerator.fill"
        }
    }
}

extension View {
    /// Shows the Pro paywall as a sheet for `gate` (set it to present).
    func proPaywall(_ gate: Binding<ProGate?>) -> some View {
        sheet(item: gate) { g in ProPaywallSheet(gate: g) }
    }
}

/// Paywall sheet from a PRO-badged feature: the feature on top, Yearly preselected, others one tap away.
struct ProPaywallSheet: View {
    let gate: ProGate
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ProView(context: .gate(gate))
                .toolbar { CloseToolbarItem { dismiss() } }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.bg)
    }
}

/// Small lime "PRO" mark on a Pro feature's button (only when Pro is switched on and the person isn't Pro).
struct ProBadge: View {
    var body: some View {
        if ProStore.shared.badged {
            Text("PRO").font(Theme.label(9.5)).tracking(1)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Capsule().fill(Theme.lime))
                .foregroundStyle(Theme.ink)
        }
    }
}

/// MonkeyWorkout Pro screen in three places: Account (status or paywall), the one-time offer after onboarding,
/// and the sheet from a PRO-badged feature. Plans, free week, Lifetime, restore, redeem code, legal links.
struct ProView: View {
    enum Context: Equatable { case account, onboarding, gate(ProGate) }

    var context: Context = .account
    /// Onboarding: "Not now" / done.
    var onFinish: (() -> Void)?
    @State private var pro = ProStore.shared
    @State private var selected = "monkeyworkout.pro.yearly"
    @State private var busy = false
    @State private var manage = false
    @State private var redeem = false
    @State private var wasSubscriber = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                hero
                if pro.testing && context == .account { testPanel }
                if pro.entitlement.pro && context == .account { status } else if pro.entitlement.pro { unlocked } else { paywall }
                if let error = pro.error { ErrorText(message: error) }
                footer
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .readableWidth()
        .themedForm()
        .navigationTitle(context == .account ? "MonkeyWorkout Pro" : "")
        .toolbarTitleDisplayMode(.inline)
        .task { await pro.refresh() }
        .manageSubscriptionsSheet(isPresented: $manage)
        .offerCodeRedemption(isPresented: $redeem) { _ in Task { await pro.refresh() } }
    }

    private var plans: [ProPlan] { ProPlan.from(pro.products) }
    private var plan: ProPlan? { plans.first { $0.id == selected } ?? plans.first }
    private var lifetimePlan: ProPlan? { plans.first { $0.period == "lifetime" } }

    private var hero: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: heroSymbol)
                .font(.system(size: 26, weight: .bold))
                .frame(width: 56, height: 56)
                .background(RoundedRectangle(cornerRadius: 17, style: .continuous).fill(.white.opacity(0.25)))
            VStack(alignment: .leading, spacing: 4) {
                Text(heroTitle).font(Theme.display(28)).fixedSize(horizontal: false, vertical: true)
                Text(heroLine).font(.subheadline.weight(.semibold)).opacity(0.9).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.ink)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(AccountTint.pro))
    }

    private var heroSymbol: String {
        if case .gate(let g) = context, !pro.entitlement.pro { return g.symbol }
        return "crown.fill"
    }

    private var heroTitle: String {
        if pro.entitlement.pro { return "You're Pro" }
        switch context {
        case .onboarding: return "Your week is ready"
        case .gate(let g): return g.title
        case .account: return "Go Pro"
        }
    }

    private var heroLine: String {
        if pro.entitlement.pro { return statusLine }
        if case .gate(let g) = context { return g.subtitle }
        return pro.trialEligible ? "Try everything free for 1 week." : "Train with everything MonkeyWorkout has."
    }

    private var statusLine: String {
        let e = pro.entitlement
        if e.lifetime == true { return "Lifetime · all updates included" }
        if e.source == .grant { return e.grant?.until.map { "Free access until \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "Free access, on the house" }
        let name = ProPlan.fallback.first { $0.id == e.productId }?.title ?? "Pro"
        guard let end = e.expiresAt?.formatted(date: .abbreviated, time: .omitted) else { return name }
        if e.trial == true { return "\(name) · free week until \(end)" }
        return e.willRenew == false ? "\(name) · ends \(end)" : "\(name) · renews \(end)"
    }

    // MARK: Pro

    @ViewBuilder private var status: some View {
        let e = pro.entitlement
        if e.source == .subscription && e.lifetime != true, let end = e.expiresAt {
            HStack(spacing: 10) {
                statTile(value: "\(max(0, Calendar.current.dateComponents([.day], from: .now, to: end).day ?? 0))",
                         unit: e.trial == true ? "days left in trial" : "days to renewal")
                statTile(value: e.willRenew == false ? "OFF" : "ON", unit: "auto-renew")
            }
        }
        Text("Included").eyebrow().padding(.leading, 4).padding(.top, 8)
        features
        if e.source == .subscription && e.lifetime != true {
            if e.environment == "Test" {
                LimeActionButton(title: "Cancel auto-renew (test)", symbol: "xmark.circle.fill", busy: busy, disabled: e.willRenew == false) {
                    busy = true
                    Task { await pro.testCancel(end: false); busy = false }
                }
                .padding(.top, 6)
            } else {
                LimeActionButton(title: "Manage subscription", symbol: "creditcard.fill") { manage = true }.padding(.top, 6)
            }
            if let life = lifetimePlan, life.product != nil || pro.testing {
                // Subscriber → Lifetime: buy once, then cancel the subscription so it doesn't renew.
                Button {
                    busy = true
                    wasSubscriber = e.environment != "Test"
                    Task { await pro.buy(life); busy = false }
                } label: {
                    AccountCard(symbol: "infinity", title: "Own it: \(life.price) once", subtitle: "Lifetime, all future updates included",
                                gradient: AccountTint.pro, ink: true) { AccountChevron() }
                }
                .buttonStyle(.plain)
                .disabled(busy)
            }
        }
        if e.lifetime == true && wasSubscriber {
            AccountNote(text: "Lifetime unlocked. Cancel your subscription in Manage subscription so it doesn't renew.")
            LimeActionButton(title: "Manage subscription", symbol: "creditcard.fill") { manage = true }
        }
        if e.environment == "Test" {
            AccountPillButton(title: "End test purchase now") { Task { busy = true; await pro.testCancel(end: true); busy = false } }
        } else {
            HStack(spacing: 10) {
                AccountPillButton(title: "Restore") { Task { busy = true; await pro.restore(); busy = false } }
                AccountPillButton(title: "Redeem code") { redeem = true }
            }
        }
    }

    /// Staging only: how this account sees Pro (Off / Preview / Enforced, or the server's setting).
    @ViewBuilder private var testPanel: some View {
        Text("Staging test").eyebrow().padding(.leading, 4).padding(.top, 8)
        VStack(alignment: .leading, spacing: 10) {
            Text("Pro for this account only").font(.body.weight(.bold))
            GradientSegments(selection: Binding(get: { pro.entitlement.test?.mode?.rawValue ?? "server" },
                                                set: { v in Task { await pro.setTestMode(Entitlement.Mode(rawValue: v)) } }), items: [
                SegmentItem(value: "server", title: "Server", symbol: "server.rack"),
                SegmentItem(value: Entitlement.Mode.off.rawValue, title: "Off", symbol: "lock.open.fill"),
                SegmentItem(value: Entitlement.Mode.preview.rawValue, title: "Preview", symbol: "eye.fill"),
                SegmentItem(value: Entitlement.Mode.enforced.rawValue, title: "Enforced", symbol: "lock.fill"),
            ])
            Text(pro.testEffect).font(.subheadline.weight(.bold)).foregroundStyle(pro.locked ? Theme.lime : .white)
            Text("Pick Enforced to start as Free: Pro features ask for Pro until you buy. Purchases here are fake: no Apple, no charge.")
                .font(.caption).foregroundStyle(Theme.muted)
        }
        .card(padding: 14)
    }

    /// Purchase done from onboarding or a feature sheet.
    @ViewBuilder private var unlocked: some View {
        features
        LimeActionButton(title: context == .onboarding ? "Start training" : "Continue", symbol: "checkmark") { close() }
            .padding(.top, 6)
    }

    private func statTile(value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(Theme.display(24))
            Text(unit).font(Theme.label(10)).tracking(1).textCase(.uppercase).opacity(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
    }

    // MARK: Paywall

    @ViewBuilder private var paywall: some View {
        if case .gate = context {} else { features }
        ForEach(context == .account || context == .onboarding ? plans : Array(plans.prefix(1))) { p in
            Button { selected = p.id } label: { planCard(p) }.buttonStyle(.plain)
        }
        if case .gate = context, plans.count > 1 {
            DisclosureGroup("Other plans") {
                ForEach(plans.dropFirst()) { p in
                    Button { selected = p.id } label: { planCard(p) }.buttonStyle(.plain)
                }
            }
            .font(.footnote.weight(.bold)).tint(.white)
        }
        if let plan {
            Text(planLine(plan))
                .font(.footnote.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.top, 4)
            LimeActionButton(title: buyTitle(plan), busy: busy, disabled: plan.product == nil && !pro.testing) {
                busy = true
                Task {
                    await pro.buy(plan)
                    busy = false
                }
            }
            if pro.testing { AccountNote(text: "Staging test: no Apple, no charge.") }
        }
        if context == .onboarding {
            Button("Not now, train on Free") { close() }
                .font(.subheadline.weight(.bold)).foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: .infinity).padding(.vertical, 6)
        } else {
            HStack(spacing: 10) {
                AccountPillButton(title: "Restore") { Task { busy = true; await pro.restore(); busy = false } }
                AccountPillButton(title: "Redeem code") { redeem = true }
            }
        }
    }

    private func planLine(_ p: ProPlan) -> String {
        if p.period == "lifetime" { return "One payment of \(p.price), no renewal. All future updates included." }
        return pro.trialEligible ? "Free for 1 week, then \(p.price) per \(p.period). Cancel anytime." : "\(p.price) per \(p.period). Cancel anytime."
    }

    private func buyTitle(_ p: ProPlan) -> String {
        if p.period == "lifetime" { return "Buy for \(p.price)" }
        return pro.trialEligible ? "Start free week" : "Subscribe"
    }

    private func close() {
        if let onFinish { onFinish() } else { dismiss() }
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(ProFeature.allCases, id: \.self) { f in
                HStack(spacing: 12) {
                    Image(systemName: f.symbol).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.lime).frame(width: 28)
                    Text(f.title).font(.subheadline.weight(.semibold))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func planCard(_ p: ProPlan) -> some View {
        let on = p.id == selected
        return HStack(spacing: 12) {
            Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 24, weight: .bold))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(p.title).font(Theme.display(20))
                    if p.period == "year" {
                        Text("BEST VALUE").font(Theme.label(10)).tracking(1).padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Capsule().fill(on ? Theme.ink.opacity(0.15) : Theme.lime.opacity(0.2)))
                    }
                }
                if let note = p.note { Text(note).font(.footnote.weight(.semibold)).opacity(0.8) }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 0) {
                Text(p.price).font(Theme.display(20))
                Text(p.period == "lifetime" ? "one time" : "per \(p.period)").font(Theme.label(10)).textCase(.uppercase).opacity(0.8)
            }
        }
        .foregroundStyle(on ? Theme.ink : .white)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .selectableGradient(AccountTint.pro, selected: on)
    }

    // MARK: Legal (App Store 3.1.2: length, price, renewal terms, Terms of Use + Privacy Policy links)

    private var footer: some View {
        VStack(spacing: 10) {
            Text("Subscriptions: payment is charged to your Apple ID when you confirm (after the free week, if you're eligible) and renews automatically at the same price unless you cancel at least 24 hours before the end of the period. Manage or cancel in Settings → Apple ID → Subscriptions. Lifetime is a one-time purchase.")
                .font(.caption).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            HStack(spacing: 18) {
                Link("Terms of Use", destination: AppConfig.termsURL)
                Link("Privacy Policy", destination: AppConfig.privacyURL)
            }
            .font(.caption.weight(.bold)).tint(Theme.lime)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
    }
}
