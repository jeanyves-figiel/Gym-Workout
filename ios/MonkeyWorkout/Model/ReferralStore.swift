import APIClient
import Foundation

/// Invite a friend (#745, design A + C from `referral-invites/proposals.png`): your code, friends who joined and
/// subscribed, and the reward ladder. Free rewards (XP, app icons) unlock on the device from the server counts;
/// Pro months go out as App Store offer codes once Pro launches, never as server-side Pro.
@MainActor @Observable
final class ReferralStore {
    static let shared = ReferralStore()

    private(set) var summary: ReferralSummary?
    var error: String?
    private var userId: String?

    private static let cacheName = "referrals.json"

    private init() {}

    var joined: Int { summary?.joined ?? 0 }
    var subscribed: Int { summary?.subscribed ?? 0 }
    var code: String? { summary?.code }

    /// XP from invites: ladder rewards, plus a welcome bonus for joining with a friend's code.
    var xp: Int {
        InviteReward.allCases.filter { $0.earned(self) }.reduce(0) { $0 + $1.xp } + (summary?.invitedBy != nil ? InviteReward.welcomeXP : 0)
    }

    func load(api: APIClient, userId: String?) async {
        if self.userId != userId {
            self.userId = userId
            summary = DeviceCache.load(ReferralSummary.self, Self.cacheName, userId: userId)
        }
        guard userId != nil else { return }
        do {
            let s = try await api.referrals()
            summary = s
            error = nil
            DeviceCache.save(s, Self.cacheName, userId: userId)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Enter a friend's code; true when it was taken.
    func redeem(_ code: String, api: APIClient) async -> Bool {
        do {
            let s = try await api.redeemReferral(code.trimmingCharacters(in: .whitespacesAndNewlines))
            summary = s
            error = nil
            DeviceCache.save(s, Self.cacheName, userId: userId)
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func signOut() {
        summary = nil
        userId = nil
        error = nil
    }

    #if DEBUG
    func loadDemo() {
        summary = ReferralSummary(code: "DJY7K2Q", path: "/i/DJY7K2Q", joined: 2, subscribed: 0, canRedeem: false)
    }
    #endif
}

/// Steps of the invite ladder (C).
enum InviteReward: String, CaseIterable, Identifiable {
    case recruiter, ironIcon, proMonth, titan, proYear

    static let welcomeXP = 200

    var id: String { rawValue }

    /// Friends who joined (or subscribed, for `proMonth`) to earn it.
    var need: Int {
        switch self {
        case .recruiter: 1
        case .ironIcon: 2
        case .proMonth: 1
        case .titan: 5
        case .proYear: 10
        }
    }

    var emoji: String {
        switch self {
        case .recruiter: "🏅"
        case .ironIcon: "🎨"
        case .proMonth: "⭐"
        case .titan: "🐵"
        case .proYear: "👑"
        }
    }

    var title: String {
        switch self {
        case .recruiter: "Recruiter · +200 XP"
        case .ironIcon: "Iron app icon, any level"
        case .proMonth: "Friend subscribes · 1 month Pro each"
        case .titan: "+1,000 XP · Titan app icon"
        case .proYear: "Pro for a year"
        }
    }

    var xp: Int {
        switch self {
        case .recruiter: 200
        case .titan: 1000
        default: 0
        }
    }

    /// Pro rewards arrive as App Store offer codes.
    var isPro: Bool { self == .proMonth || self == .proYear }

    /// App icon the step unlocks early (same icons as the level ladder).
    var appIconRank: GameRank? {
        switch self {
        case .ironIcon: .iron
        case .titan: .titan
        default: nil
        }
    }

    @MainActor func earned(_ s: ReferralStore) -> Bool {
        self == .proMonth ? s.subscribed >= need : s.joined >= need
    }
}
