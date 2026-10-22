import APIClient
import Foundation
import StoreKit
import SwiftUI
import UserNotifications

/// MonkeyWorkout Pro (#126): StoreKit 2 products and purchases. The server decides access (`Entitlement`):
/// every verified transaction is sent there (Apple-signed JWS, checked against Apple's root certificate),
/// and free access the owner gives an account comes back as `pro` too.
@MainActor @Observable
final class ProStore {
    static let shared = ProStore()
    /// One subscription group "MonkeyWorkout Pro": CHF 2 / week, CHF 6 / month, CHF 60 / year, 1-week free trial,
    /// plus Lifetime: CHF 100 once (non-consumable), all future updates included.
    static let productIds = ["monkeyworkout.pro.yearly", "monkeyworkout.pro.lifetime", "monkeyworkout.pro.monthly", "monkeyworkout.pro.weekly"]
    static let lifetimeId = "monkeyworkout.pro.lifetime"

    private(set) var entitlement: Entitlement = .free
    private(set) var products: [Product] = []
    /// Free week still available on this Apple ID (introductory offer).
    private(set) var trialEligible = true
    var error: String?

    /// Pro is shown (Account row, paywall) once the server turns it on (or in staging test mode); nothing is locked before `enforced`.
    var visible: Bool { entitlement.mode != .off || demo || testing }
    /// Staging test mode: purchases go to the server as fakes, no Apple, no charge.
    var testing: Bool { entitlement.test != nil }
    /// Staging test: what the current mode does to this account, in one line.
    var testEffect: String {
        if entitlement.pro { return "Pro: everything unlocked" }
        switch entitlement.mode {
        case .enforced: return "Free: Pro features locked"
        case .preview: return "Preview: PRO badges, nothing locked"
        case .off: return "Pro off: nothing locked, no badges"
        }
    }
    /// A Pro feature must show the paywall instead (server mode `enforced` and no Pro).
    var locked: Bool { !entitlement.access }
    /// PRO badges on Pro features: Pro switched on (preview or enforced) and this account isn't Pro.
    var badged: Bool { entitlement.mode != .off && !entitlement.pro }

    /// Runs `action`, or presents the paywall for `g` when locked.
    func run(_ g: ProGate, _ gate: Binding<ProGate?>, _ action: () -> Void) {
        if locked { gate.wrappedValue = g } else { action() }
    }

    @ObservationIgnored private var api: APIClient?
    @ObservationIgnored private var userId: String?
    @ObservationIgnored private var updates: Task<Void, Never>?
    @ObservationIgnored private var demo = false

    /// After sign-in / launch: listen for transactions, load products and the server entitlement.
    func start(api: APIClient, userId: String?) async {
        self.api = api
        self.userId = userId
        if updates == nil {
            updates = Task { [weak self] in
                for await result in Transaction.updates { await self?.handle(result) }
            }
        }
        await refresh()
        // Purchases made while offline or on another device reach the server here.
        for await result in Transaction.currentEntitlements { await handle(result, finish: false) }
    }

    /// Last entitlement seen for this account (#641), so Pro isn't locked at launch or offline.
    func restore(userId: String?) {
        guard !demo, let e = DeviceCache.load(Entitlement.self, "entitlement.json", userId: userId) else { return }
        entitlement = e
    }

    func reset() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["pro-trial-ending"])
        entitlement = .free
        userId = nil
    }

    func refresh() async {
        guard let api, !demo else { return }
        if let e = try? await api.entitlement() {
            entitlement = e
            DeviceCache.save(e, "entitlement.json", userId: userId)
        }
        await scheduleTrialReminder()
        guard entitlement.mode != .off else { return }
        if products.isEmpty, let p = try? await Product.products(for: Self.productIds) {
            products = p.sorted { (Self.productIds.firstIndex(of: $0.id) ?? 9) < (Self.productIds.firstIndex(of: $1.id) ?? 9) }
        }
        if let sub = products.first(where: { $0.subscription != nil })?.subscription { trialEligible = await sub.isEligibleForIntroOffer }
    }

    /// Buys `product` for the signed-in account (its id rides along as appAccountToken so the server can link it).
    func purchase(_ product: Product) async {
        error = nil
        var options: Set<Product.PurchaseOption> = []
        if let id = userId.flatMap(UUID.init(uuidString:)) { options.insert(.appAccountToken(id)) }
        do {
            switch try await product.purchase(options: options) {
            case .success(let result): await handle(result)
            case .pending: error = "Purchase pending approval (Ask to Buy)."
            case .userCancelled: break
            @unknown default: break
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Buys a paywall plan: StoreKit, or a fake purchase in staging test mode.
    func buy(_ plan: ProPlan) async {
        if testing { await test { try await $0.testPurchase(plan.id) } } else if let p = plan.product { await purchase(p) }
    }

    func testCancel(end: Bool) async { await test { try await $0.testCancel(end: end) } }
    func setTestMode(_ mode: Entitlement.Mode?) async { await test { try await $0.setTestMode(mode) } }

    private func test(_ call: (APIClient) async throws -> Entitlement) async {
        guard let api else { return }
        error = nil
        do {
            entitlement = try await call(api)
            await scheduleTrialReminder()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Restore: sync with the App Store, then resend this Apple ID's active subscription.
    func restore() async {
        error = nil
        do { try await AppStore.sync() } catch { self.error = error.localizedDescription; return }
        var found = false
        for await result in Transaction.currentEntitlements {
            found = true
            await handle(result, finish: false)
        }
        await refresh()
        if !found && !entitlement.pro { error = "No active subscription on this Apple ID." }
    }

    private func handle(_ result: VerificationResult<StoreKit.Transaction>, finish: Bool = true) async {
        guard case .verified(let t) = result, Self.productIds.contains(t.productID) else { return }
        var renewal: String?
        if #available(iOS 17.2, *) { renewal = await t.subscriptionStatus?.renewalInfo.jwsRepresentation }
        if let api {
            do {
                entitlement = try await api.submitTransaction(result.jwsRepresentation, renewalInfo: renewal)
                await scheduleTrialReminder()
            } catch APIError.server(_, let code, let message) where code == "subscription_other_account" {
                error = message
            } catch {
                // Offline: resent from currentEntitlements on next launch.
            }
        }
        if finish { await t.finish() }
    }

    /// Apple sends no reminder before a free trial converts: one local notification 2 days before it ends.
    private func scheduleTrialReminder() async {
        let center = UNUserNotificationCenter.current()
        let id = "pro-trial-ending"
        center.removePendingNotificationRequests(withIdentifiers: [id])
        let e = entitlement
        guard e.trial == true, e.willRenew != false, let end = e.expiresAt,
              let fire = Calendar.current.date(byAdding: .day, value: -2, to: end), fire > .now,
              [.authorized, .provisional, .ephemeral].contains(await center.notificationSettings().authorizationStatus) else { return }
        let plan = ProPlan.fallback.first { $0.id == e.productId }
        let content = UNMutableNotificationContent()
        content.title = "Your free Pro week ends in 2 days"
        content.body = plan.map { "Then \($0.price) per \($0.period). Keep it, or cancel in Settings → Apple ID → Subscriptions." }
            ?? "Keep it, or cancel in Settings → Apple ID → Subscriptions."
        content.sound = .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
    }

    #if DEBUG
    func loadDemo(pro: Bool) {
        demo = true
        entitlement = pro
            ? Entitlement(mode: .preview, pro: true, access: true, source: .subscription, productId: "monkeyworkout.pro.yearly",
                          expiresAt: Date().addingTimeInterval(7 * 86_400), trial: true, willRenew: true)
            : Entitlement(mode: .preview, pro: false, access: true, source: .none)
    }
    #endif
}
