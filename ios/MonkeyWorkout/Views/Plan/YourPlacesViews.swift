import SwiftUI
import WorkoutEngine

// Your places (#960, design B): a gradient section per kind of place, ★ the home spot each sport's log opens on.
// "This gym also has" (design C): what makes a gym count for climbing, swimming, courts…

/// Account → Your places.
struct YourPlacesView: View {
    @Environment(AppModel.self) private var model
    @State private var adding: PlaceGroup?

    /// Places of each group: Your places first, then typed places from logs.
    private var byGroup: [PlaceGroup: [SessionPlace]] {
        var seen = Set<String>()
        var out: [PlaceGroup: [SessionPlace]] = [:]
        let used = model.placeUses.sorted { $0.start > $1.start }.map(\.place).filter { $0.gymId == nil }
        for p in model.placeBook.places + used {
            guard let k = p.kind, seen.insert(p.id).inserted else { continue }
            out[k.group, default: []].append(p)
        }
        return out
    }

    /// Places logged before types: set their type here.
    private var untyped: [SessionPlace] {
        var seen = Set(model.placeBook.places.map(\.id))
        return model.placeUses.map(\.place).filter { $0.kind == nil && $0.gymId == nil && seen.insert($0.id).inserted }
    }

    /// Groups the member does: gyms, their sports' groups and any with places; the rest under "Add another kind".
    private var shown: [PlaceGroup] {
        var groups: Set<PlaceGroup> = [.gym]
        if let p = model.profile {
            if Generator.isClimber(p) { groups.insert(.climbing) }
            p.otherSports.forEach { groups.insert($0.sport.placeGroup) }
        }
        byGroup.keys.forEach { groups.insert($0) }
        return PlaceGroup.allCases.filter { groups.contains($0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Each sport's log only lists places of its kind and opens on the ★ home spot.")
                    .font(.subheadline).foregroundStyle(Theme.muted)
                ForEach(shown) { g in
                    if g == .gym { gyms } else { section(g, places: byGroup[g] ?? []) }
                }
                if !untyped.isEmpty { untypedCard }
                let more = PlaceGroup.allCases.filter { !shown.contains($0) }
                if !more.isEmpty {
                    Text("Add another kind").eyebrow().padding(.top, 8)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(more) { g in
                            Button { adding = g } label: {
                                Label(g.label, systemImage: g.symbol)
                                    .font(Theme.label(14)).foregroundStyle(.white)
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(g.sport.gradient))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(16)
        }
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Your places")
        .sheet(item: $adding) { g in
            SessionPlaceSheet(sport: g.sport, kinds: g.kinds) { p in model.updatePlaceBook { $0.save(p) } }
        }
    }

    /// Gyms: the home gym is set on Your gym; what each also has decides which sports list it.
    private var gyms: some View {
        VStack(alignment: .leading, spacing: 6) {
            header(.gym, add: false)
            ForEach(model.placeGyms) { g in
                let extras = (g.extras ?? []).map(\.label)
                row(g.ref.name, detail: extras.isEmpty ? "Gym" : "Gym · " + extras.joined(separator: ", "),
                    home: g.id == model.homeGym.id)
            }
            Text("Boulder wall, pool, courts… are set under Your gym → This gym also has.")
                .font(.caption.weight(.semibold)).opacity(0.85)
        }
        .gradientCard(WorkoutEngine.Category.cardio.gradient, padding: 14)
    }

    private func section(_ g: PlaceGroup, places: [SessionPlace]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            header(g, add: true)
            if places.isEmpty {
                Text("No \(g.label.lowercased()) place yet. + adds one.").font(.caption.weight(.semibold)).opacity(0.85)
            }
            ForEach(places) { p in
                let home = model.placeBook.isHome(p)
                Menu {
                    Button(home ? "Not home spot" : "Make home spot", systemImage: home ? "star.slash" : "star.fill") {
                        model.updatePlaceBook { $0.toggleHome(p) }
                    }
                    typeMenu(p)
                    if model.placeBook.places.contains(where: { $0.id == p.id }) {
                        Button("Remove", systemImage: "trash", role: .destructive) { model.updatePlaceBook { $0.remove(p.id) } }
                    }
                } label: {
                    row(p.name, detail: p.kind?.label ?? "", home: home)
                } primaryAction: {
                    model.updatePlaceBook { $0.toggleHome(p) }
                }
                .accessibilityHint(home ? "Tap for not home spot" : "Tap to make it the home spot")
            }
        }
        .gradientCard(g.sport.gradient, padding: 14)
    }

    private var untypedCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Set a type").font(.system(size: 18, weight: .heavy, design: .rounded))
            Text("Logged before places had a type: they show for the sport they were logged for only.")
                .font(.caption.weight(.semibold)).opacity(0.85)
            ForEach(untyped) { p in
                Menu { typeMenu(p) } label: { row(p.name, detail: "Tap to set", home: false) }
            }
        }
        .foregroundStyle(.white)
        .card(padding: 14)
    }

    @ViewBuilder private func typeMenu(_ p: SessionPlace) -> some View {
        Menu("Type", systemImage: "tag") {
            ForEach(PlaceKind.allCases) { k in
                Button(k.label, systemImage: p.kind == k ? "checkmark" : k.symbol) {
                    var typed = p
                    typed.kind = k
                    model.updatePlaceBook { $0.save(typed) }
                }
            }
        }
    }

    private func header(_ g: PlaceGroup, add: Bool) -> some View {
        HStack {
            Text(g.label).font(.system(size: 20, weight: .heavy, design: .rounded))
            Spacer()
            Image(systemName: g.symbol).font(.system(size: 20, weight: .bold))
            if add {
                Button { adding = g } label: {
                    Image(systemName: "plus").font(.system(size: 14, weight: .heavy)).foregroundStyle(Theme.ink)
                        .frame(width: 32, height: 32)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add a \(g.label.lowercased()) place")
            }
        }
        .foregroundStyle(.white)
    }

    private func row(_ name: String, detail: String, home: Bool) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(Theme.label(14)).lineLimit(1)
                if !detail.isEmpty { Text(detail).font(Theme.label(10)).opacity(0.75).lineLimit(1) }
            }
            Spacer(minLength: 4)
            if home {
                Text("★ HOME").font(Theme.label(10)).foregroundStyle(Theme.ink)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10).frame(minHeight: 44)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black.opacity(0.2)))
    }
}

/// Your gym → This gym also has (design C): tiles that make a gym count for those sports' logs.
struct GymExtrasGrid: View {
    @Environment(AppModel.self) private var model
    let gym: SavedGym

    var body: some View {
        let on = Set(model.placeGyms.first { $0.id == gym.id }?.extras ?? gym.extras ?? [])
        VStack(alignment: .leading, spacing: 8) {
            Text("THIS GYM ALSO HAS").font(Theme.label(12)).tracking(1).foregroundStyle(Theme.muted)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(GymExtra.allCases) { x in
                    let has = on.contains(x)
                    Button {
                        var next = on
                        if has { next.remove(x) } else { next.insert(x) }
                        model.setGymExtras(GymExtra.allCases.filter { next.contains($0) }, for: gym)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Image(systemName: x.symbol).font(.system(size: 15, weight: .bold))
                                Text(x.label).font(.system(size: 15, weight: .heavy, design: .rounded)).lineLimit(1)
                                Spacer(minLength: 2)
                                if has { Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)) }
                            }
                            Text(has ? "Offered for " + x.blurb : x.blurb).font(.caption2.weight(.semibold)).opacity(0.8).lineLimit(1)
                        }
                        .foregroundStyle(.white)
                        .padding(10)
                        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(has ? AnyShapeStyle(x.sports[0].gradient) : AnyShapeStyle(Theme.card)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(has ? .isSelected : [])
                    .accessibilityIdentifier("gym.extra.\(x.rawValue)")
                }
            }
        }
    }
}
