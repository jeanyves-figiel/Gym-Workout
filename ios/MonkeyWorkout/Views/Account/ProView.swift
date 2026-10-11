import APIClient
import StoreKit
import SwiftUI

extension AccountTint {
    /// MonkeyWorkout Pro (#126): lime → gold, the app's accent turned premium.
    static let pro = LinearGradient(colors: [Color(red: 0.62, green: 0.92, blue: 0.12), Color(red: 1, green: 0.72, blue: 0.1)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// What Pro adds. Proposal only (#126): nothing is locked until the server mode is `enforced`.
enum ProFeature: CaseIterable {
    case variation, builder, prAttempts, progress, watch, climbing

    var symbol: String {
        switch self {
        case .variation: "shuffle"
        case .builder: "hammer.fill"
        case .prAttempts: "trophy.fill"
        case .progress: "chart.xyaxis.line"
        case .watch: "applewatch"
        case .climbing: "figure.climbing"
        }
    }

    var title: String {
        switch self {
        case .variation: "New variations and kept swaps"
        case .builder: "Custom exercises and workouts"
        case .prAttempts: "PR attempts and share cards"
        case .progress: "Full progress and muscle heat map"
        case .watch: "Apple Watch workouts"
        case .climbing: "Climbing days and MonkeyGrade"
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
            let unit = p.subscription?.subscriptionPeriod.unit
            let yearly = unit == .year
            var note: String?
            if yearly, let monthly, monthly > 0 {
                let save = Int((NSDecimalNumber(decimal: (1 - (p.price / 12) / monthly) * 100).doubleValue).rounded())
                note = "\((p.price / 12).formatted(p.priceFormatStyle))/mo" + (save > 0 ? " · save \(save) %" : "")
            }
            return ProPlan(id: p.id, title: yearly ? "Yearly" : unit == .month ? "Monthly" : "Weekly", price: p.displayPrice,
                           period: yearly ? "year" : unit == .month ? "month" : "week", note: note, product: p)
        }
    }

    static let fallback = [
        ProPlan(id: "monkeyworkout.pro.yearly", title: "Yearly", price: "CHF 60.00", period: "year", note: "CHF 5.00/mo · save 17 %", product: nil),
        ProPlan(id: "monkeyworkout.pro.monthly", title: "Monthly", price: "CHF 6.00", period: "month", note: nil, product: nil),
        ProPlan(id: "monkeyworkout.pro.weekly", title: "Weekly", price: "CHF 2.00", period: "week", note: nil, product: nil),
    ]
}

/// Account → MonkeyWorkout Pro: status when Pro, otherwise the paywall (plans, free week, restore, redeem code, legal links).
struct ProView: View {
    @State private var pro = ProStore.shared
    @State private var selected = "monkeyworkout.pro.yearly"
    @State private var busy = false
    @State private var manage = false
    @State private var redeem = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                hero
                if pro.entitlement.pro { status } else { paywall }
                if let error = pro.error { ErrorText(message: error) }
                footer
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .themedForm()
        .navigationTitle("MonkeyWorkout Pro")
        .toolbarTitleDisplayMode(.inline)
        .task { await pro.refresh() }
        .manageSubscriptionsSheet(isPresented: $manage)
        .offerCodeRedemption(isPresented: $redeem) { _ in Task { await pro.refresh() } }
    }

    private var plans: [ProPlan] { ProPlan.from(pro.products) }
    private var plan: ProPlan? { plans.first { $0.id == selected } ?? plans.first }

    private var hero: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "crown.fill")
                .font(.system(size: 26, weight: .bold))
                .frame(width: 56, height: 56)
                .background(RoundedRectangle(cornerRadius: 17, style: .continuous).fill(.white.opacity(0.25)))
            VStack(alignment: .leading, spacing: 4) {
                Text(pro.entitlement.pro ? "You're Pro" : "Go Pro").font(Theme.display(30))
                Text(pro.entitlement.pro ? heroSubtitle : pro.trialEligible ? "1 week free, then pick your plan." : "Train with everything MonkeyWorkout has.")
                    .font(.subheadline.weight(.semibold)).opacity(0.9)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.ink)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(AccountTint.pro))
    }

    private var heroSubtitle: String {
        let e = pro.entitlement
        if e.source == .grant { return e.grant?.until.map { "Free access until \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "Free access, on the house" }
        let name = ProPlan.fallback.first { $0.id == e.productId }?.title ?? "Pro"
        guard let end = e.expiresAt?.formatted(date: .abbreviated, time: .omitted) else { return name }
        if e.trial == true { return "Free week until \(end)" }
        return e.willRenew == false ? "\(name) · ends \(end)" : "\(name) · renews \(end)"
    }

    // MARK: Pro

    @ViewBuilder private var status: some View {
        Text("Included").eyebrow().padding(.leading, 4).padding(.top, 8)
        features
        if pro.entitlement.source == .subscription {
            LimeActionButton(title: "Manage subscription", symbol: "creditcard.fill") { manage = true }.padding(.top, 6)
        }
    }

    // MARK: Paywall

    @ViewBuilder private var paywall: some View {
        features
        Text("Choose your plan").eyebrow().padding(.leading, 4).padding(.top, 8)
        ForEach(plans) { p in
            Button { selected = p.id } label: { planCard(p) }.buttonStyle(.plain)
        }
        if let plan {
            Text(pro.trialEligible ? "Free for 1 week, then \(plan.price) per \(plan.period). Cancel anytime." : "\(plan.price) per \(plan.period). Cancel anytime.")
                .font(.footnote.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.top, 4)
            LimeActionButton(title: pro.trialEligible ? "Start free week" : "Subscribe", busy: busy, disabled: plan.product == nil) {
                guard let product = plan.product else { return }
                busy = true
                Task { await pro.purchase(product); busy = false }
            }
        }
        HStack(spacing: 10) {
            AccountPillButton(title: "Restore") { Task { busy = true; await pro.restore(); busy = false } }
            AccountPillButton(title: "Redeem code") { redeem = true }
        }
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
                Text("per \(p.period)").font(Theme.label(10)).opacity(0.8)
            }
        }
        .foregroundStyle(on ? Theme.ink : .white)
        .padding(16)
        .selectableGradient(AccountTint.pro, selected: on)
    }

    // MARK: Legal (App Store 3.1.2: length, price, renewal terms, Terms of Use + Privacy Policy links)

    private var footer: some View {
        VStack(spacing: 10) {
            Text("Payment is charged to your Apple ID when you confirm (after the free week, if you're eligible). The subscription renews automatically at the same price unless you cancel at least 24 hours before the end of the period. Manage or cancel in Settings → Apple ID → Subscriptions.")
                .font(.caption).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            HStack(spacing: 18) {
                Link("Terms of Use", destination: AppConfig.apiBaseURL.appendingPathComponent("terms"))
                Link("Privacy Policy", destination: AppConfig.apiBaseURL.appendingPathComponent("privacy"))
            }
            .font(.caption.weight(.bold)).tint(Theme.lime)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
    }
}
