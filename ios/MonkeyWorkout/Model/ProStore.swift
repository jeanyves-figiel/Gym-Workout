import APIClient
import Foundation
import StoreKit

/// MonkeyWorkout Pro (#126): StoreKit 2 products and purchases. The server decides access (`Entitlement`):
/// every verified transaction is sent there (Apple-signed JWS, checked against Apple's root certificate),
/// and free access the owner gives an account comes back as `pro` too.
@MainActor @Observable
final class ProStore {
    static let shared = ProStore()
    /// One subscription group "MonkeyWorkout Pro": CHF 2 / week, CHF 6 / month, CHF 60 / year, 1-week free trial.
    static let productIds = ["monkeyworkout.pro.yearly", "monkeyworkout.pro.monthly", "monkeyworkout.pro.weekly"]

    private(set) var entitlement: Entitlement = .free
    private(set) var products: [Product] = []
    /// Free week still available on this Apple ID (introductory offer).
    private(set) var trialEligible = true
    var error: String?

    /// Pro is shown (Account row, paywall) once the server turns it on; nothing is locked before `enforced`.
    var visible: Bool { entitlement.mode != .off || demo }
    /// For a future gate: true when a Pro feature must show the paywall instead.
    var locked: Bool { !entitlement.access }

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

    func reset() {
        entitlement = .free
        userId = nil
    }

    func refresh() async {
        guard let api, !demo else { return }
        if let e = try? await api.entitlement() { entitlement = e }
        guard entitlement.mode != .off else { return }
        if products.isEmpty, let p = try? await Product.products(for: Self.productIds) {
            products = p.sorted { (Self.productIds.firstIndex(of: $0.id) ?? 9) < (Self.productIds.firstIndex(of: $1.id) ?? 9) }
        }
        if let sub = products.first?.subscription { trialEligible = await sub.isEligibleForIntroOffer }
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
            } catch APIError.server(_, let code, let message) where code == "subscription_other_account" {
                error = message
            } catch {
                // Offline: resent from currentEntitlements on next launch.
            }
        }
        if finish { await t.finish() }
    }

    #if DEBUG
    func loadDemo(pro: Bool) {
        demo = true
        entitlement = pro
            ? Entitlement(mode: .preview, pro: true, access: true, source: .subscription, productId: "monkeyworkout.pro.yearly",
                          expiresAt: Date().addingTimeInterval(6 * 86_400), trial: true, willRenew: true)
            : Entitlement(mode: .preview, pro: false, access: true, source: .none)
    }
    #endif
}
