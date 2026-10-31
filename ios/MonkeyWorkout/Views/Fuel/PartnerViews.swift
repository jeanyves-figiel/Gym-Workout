import APIClient
import SwiftUI
import WorkoutEngine

// Fuel with a partner (#1014, designs A + C from partner-share/proposals.png): a household shares one meal plan and
// one grocery list live (invite → yes, leave any time), and Send a copy hands a plan or list to a friend once.

private func rgb(_ v: UInt32) -> Color {
    Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
}

extension Theme {
    /// Household: teal to blue.
    static let partnerColors = [rgb(0x2BD9B1), rgb(0x2F8CFF)]
    /// Invites and copies: violet to pink.
    static let partnerInviteColors = [rgb(0x9B4DFF), rgb(0xE84A6F)]
}

/// Square initials tile (square shapes, not circles).
struct PartnerTile: View {
    let name: String
    var me = false
    var size: CGFloat = 30

    var body: some View {
        Text(me ? "You" : String(name.prefix(2)).uppercased())
            .font(.system(size: size * (me ? 0.32 : 0.4), weight: .black, design: .rounded))
            .foregroundStyle(Theme.ink)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(me ? Theme.lime : rgb(0xFF8AD8)))
            .accessibilityHidden(true)
    }
}

/// On Meal plan and Groceries: an invite to answer, who shares the plan, or the way in ("Cook together").
struct PartnerCard: View {
    /// Fuel home: only invites to answer, nothing when there are none.
    var invitesOnly = false
    @State private var home = HouseholdStore.shared
    @State private var sheet = false

    var body: some View {
        VStack(spacing: 10) {
            ForEach(home.incoming) { inv in inviteCard(inv) }
            if !invitesOnly {
                Button { sheet = true } label: { main }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("fuel.partner")
                if let n = home.notice {
                    Label(n, systemImage: "arrow.triangle.2.circlepath").font(.caption.weight(.heavy)).foregroundStyle(Theme.lime)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity)
                }
            }
        }
        .animation(.snappy, value: home.notice)
        .sheet(isPresented: $sheet) { PartnerSheet() }
    }

    @ViewBuilder private var main: some View {
        HStack(spacing: 12) {
            if home.isSharing, let h = home.household {
                HStack(spacing: -6) {
                    PartnerTile(name: "You", me: true, size: 40)
                    ForEach(h.others.prefix(3)) { PartnerTile(name: $0.nickname, size: 40) }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("SHARED PLAN").font(Theme.label(10)).tracking(1.2).opacity(0.85)
                    Text(home.membersLine).font(Theme.display(18)).lineLimit(1).minimumScaleFactor(0.7)
                    Text(updatedLine(h)).font(.caption.weight(.semibold)).opacity(0.85).lineLimit(1)
                }
            } else {
                Text("🍽️").font(.system(size: 22))
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.white.opacity(0.22)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cook together").font(Theme.display(18))
                    Text(home.outgoing.first.map { "Waiting for \($0.to?.nickname ?? "them")…" } ?? "Share this plan and the grocery list with your partner")
                        .font(.caption.weight(.semibold)).opacity(0.85).lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .heavy)).opacity(0.8)
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(LinearGradient(colors: Theme.partnerColors, startPoint: .topLeading, endPoint: .bottomTrailing)))
        .contentShape(Rectangle())
    }

    private func updatedLine(_ h: HouseholdStore.Home) -> String {
        guard let at = h.updatedAt.flatMap(PartnerTime.date) else { return "Live for both of you" }
        let who = h.updatedBy.map { $0.userId == home.meId ? "you" : $0.nickname } ?? "someone"
        return "Changed by \(who) \(at.formatted(.relative(presentation: .named)))"
    }

    private func inviteCard(_ inv: HouseholdInvite) -> some View {
        let name = inv.from?.nickname ?? "A member"
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                PartnerTile(name: name, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(name) wants to share meals").font(Theme.display(17)).lineLimit(2).minimumScaleFactor(0.8)
                    Text("One plan and one grocery list, live for both. Their plan replaces yours here. Logs, macros and weight stay private.")
                        .font(.caption.weight(.semibold)).opacity(0.9)
                }
            }
            if home.needsLeave == inv.id, let e = home.error {
                Text(e).font(.caption.weight(.bold))
            }
            HStack(spacing: 8) {
                Button {
                    Task { await home.accept(inv.id, leaveCurrent: home.needsLeave == inv.id) }
                } label: {
                    Text(home.needsLeave == inv.id ? "LEAVE MINE AND JOIN" : "YES, SHARE")
                        .font(Theme.label(13)).tracking(1).foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Capsule().fill(Theme.lime))
                }
                Button { Task { await home.drop(inv.id) } } label: {
                    Text("NOT NOW").font(Theme.label(13)).tracking(1).foregroundStyle(.white)
                        .padding(.vertical, 12).padding(.horizontal, 16)
                        .background(Capsule().fill(.white.opacity(0.22)))
                }
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(LinearGradient(colors: Theme.partnerInviteColors, startPoint: .topLeading, endPoint: .bottomTrailing)))
    }
}

enum PartnerTime {
    static func date(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}

/// Who shares the plan, invites waiting, people to invite (members you follow), Send a copy, Leave.
struct PartnerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var home = HouseholdStore.shared
    @State private var following: [CommunityMemberSummary]?
    @State private var sending = false
    @State private var busy: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if home.isSharing, let h = home.household { membersCard(h) }
                    if !home.outgoing.isEmpty { waitingCard }
                    inviteCard
                    if let e = home.error, home.needsLeave == nil {
                        Text(e).font(.footnote.weight(.semibold)).foregroundStyle(rgb(0xFF8A8A))
                    }
                    Button { sending = true } label: {
                        Label("SEND A COPY INSTEAD", systemImage: "paperplane.fill")
                    }
                    .buttonStyle(LimeButtonStyle(fill: Theme.cardStrong, text: .white))
                    Label("Only the plan, the recipes it uses and the grocery list are shared. Food logs, macros, weight and What I have stay on your phone. Anyone can leave at any time and keeps a copy.",
                          systemImage: "lock.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                    if home.household != nil {
                        Button {
                            Task {
                                await home.leave()
                                if home.error == nil { dismiss() }
                            }
                        } label: {
                            Text(home.isSharing ? "LEAVE SHARED PLAN" : "STOP SHARING").font(Theme.label(14)).tracking(1)
                                .foregroundStyle(rgb(0xFF8A8A)).frame(maxWidth: .infinity).padding(.vertical, 12)
                        }
                        .accessibilityIdentifier("fuel.partner.leave")
                    }
                }
                .padding(16)
            }
            .readableWidth()
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Cook together")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
            .task {
                home.error = nil
                await home.refresh(force: true)
                following = (try? await model.api.followingMembers()) ?? []
            }
            .sheet(isPresented: $sending) { SendCopySheet() }
        }
    }

    private func membersCard(_ h: HouseholdStore.Home) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SHARING WITH").font(Theme.label(10)).tracking(1.2).opacity(0.85)
            ForEach(h.members) { m in
                HStack(spacing: 10) {
                    PartnerTile(name: m.nickname, me: m.me, size: 34)
                    Text(m.me ? "You" : m.nickname).font(.body.weight(.heavy))
                    Spacer()
                    Text("since \(PartnerTime.date(m.joinedAt)?.formatted(.dateTime.day().month()) ?? "")")
                        .font(.caption.weight(.semibold)).opacity(0.85)
                }
            }
            Text("Servings follow the household: \(FuelStore.shared.saved.people) people.").font(.caption.weight(.semibold)).opacity(0.85)
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(LinearGradient(colors: Theme.partnerColors, startPoint: .topLeading, endPoint: .bottomTrailing)))
    }

    private var waitingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WAITING FOR A YES").font(Theme.label(10)).tracking(1.2).opacity(0.85)
            ForEach(home.outgoing) { inv in
                HStack(spacing: 10) {
                    PartnerTile(name: inv.to?.nickname ?? "?", size: 34)
                    Text(inv.to?.nickname ?? "Member").font(.body.weight(.heavy))
                    Spacer()
                    Button("Cancel") { Task { await home.drop(inv.id) } }
                        .font(.subheadline.weight(.heavy)).foregroundStyle(.white)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(LinearGradient(colors: Theme.partnerInviteColors, startPoint: .topLeading, endPoint: .bottomTrailing)))
    }

    @ViewBuilder private var inviteCard: some View {
        let inHousehold = Set(home.household?.members.map(\.userId) ?? [])
        let waiting = Set(home.outgoing.compactMap { $0.to?.userId })
        let people = (following ?? []).filter { !inHousehold.contains($0.userId) }
        VStack(alignment: .leading, spacing: 8) {
            Text("INVITE YOUR PARTNER").font(Theme.label(10)).tracking(1.2).foregroundStyle(Theme.muted)
            if following == nil {
                ProgressView().frame(maxWidth: .infinity).padding()
            } else if people.isEmpty {
                Text("Follow your partner in Social first (Social → Find a friend), then invite them here.")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
            } else {
                ForEach(people) { p in
                    HStack(spacing: 10) {
                        PartnerTile(name: p.nickname, size: 34)
                        Text(p.nickname).font(.body.weight(.heavy)).foregroundStyle(.white).lineLimit(1)
                        Spacer()
                        if waiting.contains(p.userId) {
                            Text("Invited").font(.caption.weight(.heavy)).foregroundStyle(Theme.muted)
                        } else {
                            Button {
                                busy = p.userId
                                Task {
                                    await home.invite(p.userId)
                                    busy = nil
                                }
                            } label: {
                                Text(busy == p.userId ? "…" : "INVITE").font(Theme.label(12)).tracking(1).foregroundStyle(Theme.ink)
                                    .padding(.vertical, 8).padding(.horizontal, 14).background(Capsule().fill(Theme.lime))
                            }
                            .buttonStyle(.plain)
                            .disabled(busy != nil)
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
                }
            }
        }
    }
}

/// Send a copy (#1014 C): pick a friend (they must follow you back), plan and/or groceries, send. Nothing stays linked.
struct SendCopySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var following: [CommunityMemberSummary]?
    @State private var to: String?
    @State private var plan = true
    @State private var list = true
    @State private var sending = false
    @State private var error: String?

    var body: some View {
        let groceries = model.groceries()
        let store = FuelStore.shared
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("SEND TO").font(Theme.label(10)).tracking(1.2).foregroundStyle(Theme.muted)
                    if following == nil {
                        ProgressView().frame(maxWidth: .infinity).padding()
                    } else if following!.isEmpty {
                        Text("Follow a friend in Social first. They need to follow you back to receive copies.")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                            ForEach(following!) { p in
                                Button { to = p.userId } label: {
                                    VStack(spacing: 6) {
                                        PartnerTile(name: p.nickname, size: 40)
                                        Text(p.nickname).font(.caption.weight(.heavy)).lineLimit(1)
                                    }
                                    .foregroundStyle(to == p.userId ? Theme.ink : .white)
                                    .frame(maxWidth: .infinity).padding(10)
                                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(to == p.userId ? Theme.lime : Theme.card))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    Text("WHAT").font(Theme.label(10)).tracking(1.2).foregroundStyle(Theme.muted)
                    HStack(spacing: 8) {
                        chip("📅 Plan · \(store.sharedPlan.summary)", on: $plan, enabled: !store.saved.plan.isEmpty)
                        chip("🛒 Groceries · \(groceries.count)", on: $list, enabled: !groceries.isEmpty)
                    }
                    if let error { Text(error).font(.footnote.weight(.semibold)).foregroundStyle(rgb(0xFF8A8A)) }
                    Button {
                        guard let to else { return }
                        sending = true
                        let kind: FuelShareKind = plan && list ? .both : plan ? .plan : .groceries
                        let lines = groceries.map { SharedGroceryLine(id: $0.id, name: $0.food.name, grams: $0.grams) }
                        Task {
                            error = await HouseholdStore.shared.send(to: to, kind: kind, groceries: lines)
                            sending = false
                            if error == nil {
                                Haptics.success()
                                dismiss()
                            }
                        }
                    } label: {
                        Label(sending ? "SENDING…" : "SEND", systemImage: "paperplane.fill")
                    }
                    .buttonStyle(LimeButtonStyle())
                    .disabled(to == nil || sending || !((plan && !store.saved.plan.isEmpty) || (list && !groceries.isEmpty)))
                    Text("A copy: they can use it as their plan or read the list. Later changes aren't sent.")
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                }
                .padding(16)
            }
            .readableWidth()
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Send a copy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
            .task {
                following = (try? await model.api.followingMembers()) ?? []
                if store.saved.plan.isEmpty { plan = false }
                if groceries.isEmpty { list = false }
            }
        }
    }

    private func chip(_ title: String, on: Binding<Bool>, enabled: Bool) -> some View {
        Button { on.wrappedValue.toggle() } label: {
            Text(title).font(.caption.weight(.heavy)).lineLimit(2).multilineTextAlignment(.leading)
                .foregroundStyle(on.wrappedValue && enabled ? Theme.ink : .white)
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(on.wrappedValue && enabled ? Theme.lime : Theme.card))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }
}

/// Copies friends sent (#1014 C), on Fuel: use the plan, read the list, or dismiss.
struct FuelCopiesInbox: View {
    @State private var home = HouseholdStore.shared
    @State private var reading: HouseholdStore.Copy?

    var body: some View {
        if !home.copies.isEmpty {
            VStack(spacing: 10) {
                ForEach(home.copies) { c in card(c) }
            }
            .sheet(item: $reading) { CopyListSheet(copy: $0) }
        }
    }

    private func card(_ c: HouseholdStore.Copy) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("FROM \(c.from.nickname.uppercased())").font(Theme.label(10)).tracking(1.2).opacity(0.9)
                Spacer()
                Button { Task { await home.dismiss(c) } } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .heavy)).padding(6)
                }
                .accessibilityLabel("Dismiss")
            }
            HStack(spacing: 12) {
                Text(c.kind == .groceries ? "🛒" : "📅").font(.system(size: 22))
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.white.opacity(0.22)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(c)).font(Theme.display(17)).lineLimit(1).minimumScaleFactor(0.8)
                    Text(detail(c)).font(.caption.weight(.semibold)).opacity(0.9)
                }
            }
            HStack(spacing: 8) {
                if c.payload.plan != nil {
                    Button { home.use(c) } label: {
                        Text("USE AS MY PLAN").font(Theme.label(12)).tracking(1).foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity).padding(.vertical, 11).background(Capsule().fill(Theme.lime))
                    }
                }
                if !(c.payload.groceries ?? []).isEmpty {
                    Button { reading = c } label: {
                        Text("SEE LIST").font(Theme.label(12)).tracking(1).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 11).background(Capsule().fill(.white.opacity(0.22)))
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(LinearGradient(colors: Theme.partnerInviteColors, startPoint: .topLeading, endPoint: .bottomTrailing)))
    }

    private func title(_ c: HouseholdStore.Copy) -> String {
        switch c.kind {
        case .plan: "Meal plan"
        case .groceries: "Grocery list"
        case .both: "Meal plan + list"
        }
    }

    private func detail(_ c: HouseholdStore.Copy) -> String {
        [c.payload.plan?.summary, c.payload.groceries.map { "\($0.count) items" }].compactMap { $0 }.joined(separator: " · ")
    }
}

/// A sent grocery list: tick while shopping (on this screen only), or share it as text.
struct CopyListSheet: View {
    let copy: HouseholdStore.Copy
    @Environment(\.dismiss) private var dismiss
    @State private var ticked: Set<String> = []

    var body: some View {
        let lines = copy.payload.groceries ?? []
        NavigationStack {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(lines) { l in
                        let on = ticked.contains(l.id)
                        Button { if on { ticked.remove(l.id) } else { ticked.insert(l.id) } } label: {
                            HStack(spacing: 12) {
                                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22, weight: .bold)).foregroundStyle(on ? Theme.lime : Theme.muted)
                                Text(l.name).font(.body.weight(.bold)).strikethrough(on)
                                Spacer()
                                Text(Self.amount(l.grams)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.muted)
                            }
                            .foregroundStyle(.white).padding(12)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
                            .opacity(on ? 0.6 : 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .readableWidth()
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("From \(copy.from.nickname)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ShareLink(item: lines.map { "• \($0.name) \(Self.amount($0.grams))" }.joined(separator: "\n")) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share the list")
                }
                CloseToolbarItem { dismiss() }
            }
        }
    }

    static func amount(_ g: Double) -> String { g >= 1000 ? String(format: "%.1f kg", g / 1000) : "\(Int(g.rounded())) g" }
}
