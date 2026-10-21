import SwiftUI
import WorkoutEngine

// Scan check list (#573, design A with B's guesses from `food-scan/proposals.png`): what a scan found, one gradient card
// each. Sure (teal), check (pink: Monkey wasn't sure, tap FIX), new (violet: not on the list, kept as a new food). Tap
// a card to leave it out; FIX opens "Or it's…" with three guesses and a search.

struct ScanPick: Identifiable, Equatable {
    enum Kind { case sure, check, new }

    var food: Food
    var kind: Kind
    var on: Bool
    /// Where it came from, shown under the name ("Barcode", "Label", "Photo").
    var source: String
    var id: String { food.id }

    /// A photo or label item: known and sure, known but unsure, or a food that isn't on the list.
    /// Unsure ones start left out unless `on` says otherwise (words read off a label: in, but worth a check).
    init(_ food: Food, sure: Bool, source: String, on: Bool? = nil) {
        self.food = food
        kind = FoodBook.food(food.id) == nil && food.barcode == nil ? .new : sure ? .sure : .check
        self.on = on ?? sure
        self.source = source
    }
}

struct ScanCheckList: View {
    @Binding var picks: [ScanPick]
    @State private var fixing: ScanPick?

    var body: some View {
        VStack(spacing: 8) {
            ForEach($picks) { $pick in
                card(pick)
                    .contentShape(Rectangle())
                    .onTapGesture { pick.on.toggle() }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityValue(pick.on ? "Added" : "Left out")
                    .accessibilityHint("Tap to add or leave out")
            }
        }
        .sheet(item: $fixing) { pick in
            ScanFixSheet(pick: pick) { food in
                guard let i = picks.firstIndex(where: { $0.id == pick.id }) else { return }
                if let dup = picks.firstIndex(where: { $0.id == food.id }), dup != i {
                    picks[dup].on = true
                    picks.remove(at: i)
                } else {
                    picks[i] = ScanPick(food, sure: true, source: "Fixed")
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func card(_ p: ScanPick) -> some View {
        HStack(spacing: 10) {
            Text(p.food.emoji).font(.system(size: 22))
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.22)))
            VStack(alignment: .leading, spacing: 2) {
                Text(p.kind == .check ? "\(p.food.name)?" : p.food.name).font(Theme.display(15)).lineLimit(1)
                Text(subtitle(p)).font(.system(size: 11, weight: .bold, design: .rounded)).opacity(0.85).lineLimit(1)
            }
            Spacer(minLength: 4)
            if p.kind == .check {
                Button { fixing = p } label: {
                    Text("FIX").font(Theme.label(11)).foregroundStyle(.white)
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.bg))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Fix \(p.food.name)")
            } else if p.kind == .new {
                Text("NEW").font(Theme.display(14))
            }
            Image(systemName: p.on ? "checkmark.square.fill" : "square").font(.system(size: 20, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(gradient(p.kind)))
        .opacity(p.on ? 1 : 0.45)
    }

    private func subtitle(_ p: ScanPick) -> String {
        switch p.kind {
        case .sure: p.source
        case .check: p.source == "Label" ? "Read on a label · FIX if wrong" : "Not sure · tap FIX"
        case .new: "New food · \(Int(p.food.per100.kcal.rounded())) kcal/100 \(p.food.group == .drink ? "ml" : "g")"
        }
    }

    private func gradient(_ k: ScanPick.Kind) -> LinearGradient {
        switch k {
        case .sure: FuelPalette.gradient(0x22C1A1, 0x2F7CF6)
        case .check: FuelPalette.gradient(0xFF9A3C, 0xFF3D7F)
        case .new: FuelPalette.gradient(0x8B5CF6, 0xD946EF)
        }
    }
}

/// "Or it's…": three guesses big, then a search over every food.
struct ScanFixSheet: View {
    let pick: ScanPick
    let onPick: (Food) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var store = FuelStore.shared
    @State private var query = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("OR IT'S…").font(Theme.label(12)).foregroundStyle(Theme.muted)
                    HStack(spacing: 8) {
                        ForEach(FoodBook.guesses(for: pick.food, own: store.saved.foods)) { f in
                            Button { choose(f) } label: {
                                VStack(spacing: 4) {
                                    Text(f.emoji).font(.system(size: 26))
                                    Text(f.name).font(Theme.label(11)).multilineTextAlignment(.center).lineLimit(2)
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 84)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    TextField("Search all foods", text: $query)
                        .textInputAutocapitalization(.never)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
                    ForEach(FoodBook.search(query, own: store.saved.foods).prefix(12)) { f in
                        Button { choose(f) } label: {
                            HStack {
                                Text("\(f.emoji) \(f.name)").font(Theme.label(14))
                                Spacer()
                                Image(systemName: "arrow.left.arrow.right")
                            }
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
                        }
                        .buttonStyle(.plain)
                    }
                    Button { choose(pick.food) } label: { Text("YES, IT'S \(pick.food.name.uppercased())") }
                        .buttonStyle(LimeButtonStyle())
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("\(pick.food.emoji) \(pick.food.name)?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
        }
    }

    private func choose(_ f: Food) {
        onPick(f)
        dismiss()
    }
}
