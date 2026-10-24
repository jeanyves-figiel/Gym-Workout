import APIClient
import PhotosUI
import SwiftUI
import VisionKit
import WorkoutEngine

// What I have (#496): type it, pick it, scan labels / receipts / barcodes live, or snap the fridge (Pro). The app
// builds the meal closest to the targets from it and lists the recipes the member can make.

struct PantryView: View {
    @Environment(AppModel.self) private var model
    @State private var store = FuelStore.shared
    @State private var text = ""
    @State private var group: FoodGroup = .protein
    @State private var target = Target.next
    @State private var liveScan = false
    @State private var photoScan = false
    @State private var editingGrams: Food?
    @State private var gramsText = ""
    @State private var notice: String?
    @State private var gate: ProGate?
    @FocusState private var typing: Bool

    enum Target: Hashable { case next, rest }

    var body: some View {
        let plan = model.fuelPlan(on: Date())
        let haveFoods = store.saved.pantry.compactMap { FoodBook.food($0.foodId, own: store.saved.foods) }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                input
                matches
                HStack(spacing: 10) {
                    if LiveFoodScanner.available {
                        Button { liveScan = true } label: {
                            scanTile("barcode.viewfinder", "Scan live", "Labels, receipts, barcodes", FuelPalette.water)
                        }
                        .buttonStyle(.plain)
                    }
                    Button { ProStore.shared.run(.foodScan, $gate) { photoScan = true } } label: {
                        scanTile("refrigerator.fill", "Snap the fridge", ProStore.shared.locked ? "Photo · PRO" : "Photo, cupboard, shopping", FuelPalette.violet)
                    }
                    .buttonStyle(.plain)
                }
                if let notice {
                    Text(notice).font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
                }
                yourFoods(haveFoods)
                picker
                if !haveFoods.isEmpty {
                    GradientSegments(selection: $target, items: [
                        SegmentItem(value: Target.next, title: "Next meal", symbol: "fork.knife"),
                        SegmentItem(value: Target.rest, title: "Rest of today", symbol: "sun.max.fill"),
                    ], gradient: FuelPalette.mint)
                    mealCard(plan)
                    recipes(plan)
                }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("What I have")
        .toolbar {
            if !store.saved.pantry.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Clear all", systemImage: "trash", role: .destructive) { store.clearPantry() }
                    } label: { Image(systemName: "ellipsis") }
                    .accessibilityLabel("More")
                }
            }
        }
        .proPaywall($gate)
        .sheet(isPresented: $liveScan) { LiveScanSheet() }
        .sheet(isPresented: $photoScan) { FoodPhotoScanSheet().remotePaused(.foodScan) }
        .alert("How much \(editingGrams?.name.lowercased() ?? "")?", isPresented: Binding(get: { editingGrams != nil }, set: { if !$0 { editingGrams = nil } })) {
            TextField("Grams (empty = enough)", text: $gramsText).keyboardType(.numberPad)
            Button("Save") {
                if let f = editingGrams { store.setGrams(f.id, Double(gramsText)) }
                editingGrams = nil
            }
            Button("Remove", role: .destructive) {
                if let f = editingGrams { store.remove(f.id) }
                editingGrams = nil
            }
            Button("Cancel", role: .cancel) { editingGrams = nil }
        } message: {
            Text("Leave empty when you have plenty.")
        }
    }

    private var input: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SEARCH OR TYPE A LIST").font(Theme.label(10)).tracking(1.2).opacity(0.9)
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .bold)).opacity(0.8)
                    TextField("eggs, rice, spinach, skyr…", text: $text, axis: .vertical)
                        .lineLimit(1...3)
                        .focused($typing)
                        .submitLabel(.done)
                        .onSubmit(addTyped)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.black.opacity(0.25)))
                Button(action: addTyped) {
                    Image(systemName: "plus").font(.system(size: 18, weight: .heavy)).foregroundStyle(Theme.ink)
                        .frame(width: 44, height: 44).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.lime))
                }
                .buttonStyle(.plain)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Add")
            }
            Text(query.count < 2 ? "Type to search all \(FoodBook.catalog.count + store.saved.foods.count) foods, or a list and tap +."
                                : "Tap a match below, or + to add the whole list.")
                .font(.system(size: 11, weight: .bold, design: .rounded)).opacity(0.85)
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(FuelPalette.mint))
    }

    private func addTyped() {
        let found = FoodBook.find(in: text, own: store.saved.foods)
        if found.isEmpty {
            notice = "Didn't recognise that. Try a simpler name or pick below."
        } else {
            store.add(found)
            notice = "Added \(found.map(\.name).joined(separator: ", "))."
            text = ""
        }
    }

    private func scanTile(_ symbol: String, _ title: String, _ detail: String, _ g: LinearGradient) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            IconTile(symbol: symbol, size: 38)
            Text(title).font(Theme.display(16)).lineLimit(1).minimumScaleFactor(0.7)
            Text(detail).font(.system(size: 11, weight: .bold, design: .rounded)).opacity(0.85).lineLimit(2)
        }
        .foregroundStyle(.white)
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(g))
    }

    @ViewBuilder private func yourFoods(_ foods: [Food]) -> some View {
        if !foods.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("At home · \(foods.count)").eyebrow()
                FlowLayout(spacing: 6) {
                    ForEach(foods) { f in
                        let grams = store.saved.pantry.first { $0.foodId == f.id }?.grams
                        Button {
                            gramsText = grams.map { String(Int($0)) } ?? ""
                            editingGrams = f
                        } label: {
                            HStack(spacing: 4) {
                                Text("\(f.emoji) \(f.name)")
                                if let grams { Text("\(Int(grams)) g").opacity(0.7) }
                            }
                            .font(Theme.label(12)).foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(Capsule().fill(Theme.cardStrong))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("Tap a food to set how much you have or remove it.").font(.caption2.weight(.semibold)).foregroundStyle(Theme.muted)
            }
        }
    }

    /// The word being typed: the last item of a comma list.
    private var query: String {
        String(text.split(separator: ",", omittingEmptySubsequences: false).last ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// One box (#511): matches from the whole catalogue show right under the box as you type.
    @ViewBuilder private var matches: some View {
        let q = query
        if q.count >= 2 {
            let have = store.pantryIds
            let found = FoodBook.search(q, own: store.saved.foods)
            VStack(alignment: .leading, spacing: 8) {
                Text("Matches for “\(q)” · \(found.count)").eyebrow()
                if found.isEmpty {
                    Text("Nothing matches. Try a shorter word, or scan the label.")
                        .font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(found) { f in
                            foodChip(f, on: have.contains(f.id)) {
                                if !have.contains(f.id) { store.add([f]) }
                                dropQuery()
                            }
                        }
                    }
                }
            }
        }
    }

    /// Browse by group: the groups wrap with their counts so none hide off screen.
    private var picker: some View {
        let have = store.pantryIds
        return VStack(alignment: .leading, spacing: 8) {
            Text(query.count >= 2 ? "Or browse" : "Pick").eyebrow()
            FlowLayout(spacing: 6) {
                ForEach(FoodGroup.allCases) { g in
                    let count = FoodBook.catalog.filter { $0.group == g && $0.fits(store.prefs) }.count
                    Button { group = g } label: {
                        Text("\(g.emoji) \(g.label) \(count)").font(Theme.label(12))
                            .foregroundStyle(group == g ? Theme.ink : .white)
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(Capsule().fill(group == g ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(Theme.card)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(group == g ? .isSelected : [])
                }
            }
            FlowLayout(spacing: 6) {
                ForEach(FoodBook.catalog.filter { $0.group == group && $0.fits(store.prefs) }) { f in
                    let on = have.contains(f.id)
                    foodChip(f, on: on) { if on { store.remove(f.id) } else { store.add([f]) } }
                }
            }
        }
    }

    private func foodChip(_ f: Food, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("\(f.emoji) \(f.name)\(on ? " ✓" : "")").font(Theme.label(12))
                .foregroundStyle(on ? Theme.ink : .white)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Capsule().fill(on ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(Theme.card)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Picked from the matches: keep the rest of the typed list, drop the word being searched.
    private func dropQuery() {
        var parts = text.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        parts.removeLast()
        text = parts.isEmpty ? "" : parts.joined(separator: ",") + ", "
    }

    private func targetMacros(_ plan: FuelPlan) -> (Macros, String) {
        switch target {
        case .next:
            let cal = Calendar.current
            let now = cal.component(.hour, from: Date()) * 60 + cal.component(.minute, from: Date())
            let log = store.log(Date())
            let slot = plan.slots.first { $0.minute >= now - 30 && log.ticks[$0.id] == nil } ?? plan.slots.last
            guard let slot else { return (Macros(), "") }
            return (Macros(protein: Double(slot.protein), carbs: Double(slot.carbs), fat: Double(slot.fat)), "\(slot.title) · \(slot.time)")
        case .rest:
            let e = store.log(Date()).eaten
            let left = Macros(protein: Double(plan.protein) - Double(e.palms) * Portions.proteinPerPalm,
                              carbs: Double(plan.carbs) - Double(e.cups) * Portions.carbsPerCup,
                              fat: Double(plan.fat) - Double(e.thumbs) * Portions.fatPerThumb / 0.6)
            return (left, "Rest of today")
        }
    }

    private func mealCard(_ plan: FuelPlan) -> some View {
        let (t, title) = targetMacros(plan)
        let meal = Pantry.meal(target: t, have: store.saved.pantry, own: store.saved.foods, prefs: store.prefs)
        let noNumbers = store.prefs.noNumbers
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("BEST FROM WHAT YOU HAVE").font(Theme.label(10)).tracking(1.2).opacity(0.85)
                    Text(title).font(Theme.display(19))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(Int((meal.closeness * 100).rounded()))%").font(Theme.display(30)).monospacedDigit()
                    Text("OF TARGET").font(Theme.label(9)).opacity(0.85)
                }
            }
            if meal.items.isEmpty {
                Text("Add a protein food and a carb to build a meal.").font(.subheadline.weight(.bold))
            }
            ForEach(meal.items) { i in
                HStack {
                    Text("\(i.food.emoji) \(i.food.name)").font(.body.weight(.bold))
                    Spacer()
                    Text(noNumbers ? portionText(i) : "\(Int(i.grams)) g").font(Theme.label(14)).monospacedDigit()
                }
            }
            if !noNumbers && !meal.items.isEmpty {
                HStack(spacing: 8) {
                    FuelStat(value: "\(Int(meal.totals.protein))/\(Int(t.protein))", label: "Protein g", progress: meal.totals.protein / max(1, t.protein))
                    FuelStat(value: "\(Int(meal.totals.carbs))/\(Int(t.carbs))", label: "Carbs g", progress: meal.totals.carbs / max(1, t.carbs), bar: Color(hex: 0xFFD23D))
                    FuelStat(value: "\(Int(meal.totals.kcal))", label: "kcal")
                }
            }
            ForEach(meal.gaps, id: \.what) { g in
                Text(noNumbers ? "Short on \(g.what)\(g.add.map { ": add \($0.name.lowercased())" } ?? "")."
                     : "\(g.grams) g \(g.what) short\(g.add.map { ": add \($0.name.lowercased()) next time" } ?? "").")
                    .font(.footnote.weight(.bold))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.22)))
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(FuelPalette.hot))
    }

    private func portionText(_ i: PantryMeal.Item) -> String {
        let n = i.grams / max(1, i.food.portion.g)
        return n < 0.75 ? "a little" : "\(n < 1.25 ? "1" : String(format: "%.1f", n))× \(i.food.portion.label.replacingOccurrences(of: "1 ", with: ""))"
    }

    @ViewBuilder private func recipes(_ plan: FuelPlan) -> some View {
        let list = Array(Pantry.recipes(have: store.pantryIds, prefs: store.prefs, own: store.saved.recipes,
                                        protein: plan.slots.first?.protein).prefix(12))
        VStack(alignment: .leading, spacing: 8) {
            Text("Recipes you can make").eyebrow()
            if list.isEmpty {
                Text("Add a few more foods to see recipes.").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.muted)
            }
            ForEach(list) { p in
                NavigationLink(value: p.recipe) {
                    VStack(alignment: .leading, spacing: 6) {
                        RecipeRow(recipe: p.recipe)
                        Text(p.missing.isEmpty ? "✅ You have everything"
                             : "Missing: \(p.missing.compactMap { FoodBook.food($0)?.name.lowercased() }.joined(separator: ", "))")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(p.missing.isEmpty ? Theme.lime : Theme.muted)
                            .padding(.leading, 6)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Live scan (on device)

/// VisionKit live scanner: reads text (labels, receipts) and barcodes on the device; nothing is uploaded.
struct LiveFoodScanner: UIViewControllerRepresentable {
    let onText: (String) -> Void
    let onBarcode: (String) -> Void

    @MainActor static var available: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.text(), .barcode(symbologies: [.ean13, .ean8, .upce])],
                                           qualityLevel: .balanced, recognizesMultipleItems: true,
                                           isHighFrameRateTrackingEnabled: false, isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_: DataScannerViewController, context _: Context) {}

    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator _: Coordinator) { vc.stopScanning() }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let parent: LiveFoodScanner
        init(_ parent: LiveFoodScanner) { self.parent = parent }

        func dataScanner(_: DataScannerViewController, didAdd added: [RecognizedItem], allItems _: [RecognizedItem]) {
            for item in added {
                switch item {
                case .text(let t): parent.onText(t.transcript)
                case .barcode(let b): if let p = b.payloadStringValue { parent.onBarcode(p) }
                @unknown default: break
                }
            }
        }
    }
}

struct LiveScanSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var store = FuelStore.shared
    @State private var found: [ScanPick] = []
    @State private var codes: Set<String> = []
    @State private var looking = 0
    /// Barcode first (#573): words read off a package only count when no barcode product came within a few seconds of
    /// them, so the label of a scanned bottle can't add a second, wrong food.
    @State private var fromText: [String: Date] = [:]
    @State private var lastProduct = Date.distantPast

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                LiveFoodScanner(onText: { text in
                    guard Date().timeIntervalSince(lastProduct) > 4 else { return }
                    for f in FoodBook.find(in: text, own: store.saved.foods) where !found.contains(where: { $0.id == f.id }) {
                        found.append(ScanPick(f, sure: false, source: "Label", on: true))
                        fromText[f.id] = Date()
                    }
                }, onBarcode: { code in
                    guard codes.insert(code).inserted else { return }
                    looking += 1
                    let seen = Date()
                    Task {
                        defer { looking -= 1 }
                        guard let f = await model.lookUpBarcode(code) else { return }
                        lastProduct = Date()
                        found.removeAll { fromText[$0.id].map { seen.timeIntervalSince($0) < 4 } ?? false }
                        if !found.contains(where: { $0.id == f.id }) { found.append(ScanPick(f, sure: true, source: "Barcode")) }
                    }
                })
                .ignoresSafeArea()
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(found.isEmpty ? "Point at labels, a receipt or barcodes" : "Found \(found.count)").font(Theme.display(17))
                        if looking > 0 { ProgressView().tint(.white) }
                    }
                    if !found.isEmpty {
                        ScrollView { ScanCheckList(picks: $found) }
                            .frame(maxHeight: 250)
                            .scrollBounceBehavior(.basedOnSize)
                        let on = found.filter(\.on).map(\.food)
                        Button {
                            store.add(on)
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            dismiss()
                        } label: { Text("ADD \(on.count) TO WHAT I HAVE") }
                            .buttonStyle(LimeButtonStyle())
                            .disabled(on.isEmpty)
                    }
                    Text("Read on your iPhone. Barcodes are looked up on Open Food Facts (only the code is sent).")
                        .font(.caption2.weight(.semibold)).opacity(0.75)
                }
                .foregroundStyle(.white)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.black.opacity(0.7)))
                .padding(12)
            }
            .navigationTitle("Scan live")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
        }
    }
}

// MARK: - Photo scan (Pro, server)

struct FoodPhotoScanSheet: View {
    /// Magic Snap (#733): the photo and the foods Monkey saw on it, already read.
    var preset: [ScanPick] = []
    var presetImage: UIImage?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var store = FuelStore.shared
    @State private var camera = false
    @State private var photoItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var scanning = false
    @State private var picks: [ScanPick] = []
    @State private var notice: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Snap your open fridge, a cupboard, your shopping or a receipt. Monkey lists the food it sees.")
                        .font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
                    ZStack {
                        if let image {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            FuelPalette.violet
                            VStack(spacing: 8) {
                                Image(systemName: "refrigerator.fill").font(.system(size: 44, weight: .bold))
                                Text("Fridge, cupboard or receipt").font(Theme.display(17))
                            }
                            .foregroundStyle(.white)
                        }
                        if scanning {
                            ProgressView("Looking for food…").tint(.white).foregroundStyle(.white)
                                .padding(12).background(Capsule().fill(.black.opacity(0.6)))
                        }
                    }
                    .frame(maxWidth: .infinity).frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    HStack(spacing: 8) {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button { camera = true } label: { Label("Take photo", systemImage: "camera.fill") }
                                .buttonStyle(LimeButtonStyle())
                        }
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label("Library", systemImage: "photo.on.rectangle")
                                .font(Theme.label(14)).foregroundStyle(.white)
                                .padding(.horizontal, 16).padding(.vertical, 18)
                                .background(Capsule().fill(Theme.cardStrong))
                        }
                    }
                    .disabled(scanning)
                    if let notice { Text(notice).font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted) }
                    if !picks.isEmpty {
                        Text("Found \(picks.count)").font(Theme.display(22))
                        ScanCheckList(picks: $picks)
                        let on = picks.filter(\.on).map(\.food)
                        Button {
                            store.add(on)
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            dismiss()
                        } label: { Text("ADD \(on.count) TO WHAT I HAVE") }
                            .buttonStyle(LimeButtonStyle())
                            .disabled(on.isEmpty)
                    }
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Snap the fridge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
            .fullScreenCover(isPresented: $camera) { CameraPicker { if let img = $0 { scan(img) } }.ignoresSafeArea() }
            .onChange(of: photoItem) {
                guard let item = photoItem else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) { scan(img) }
                    photoItem = nil
                }
            }
            .task {
                if !preset.isEmpty, picks.isEmpty, image == nil {
                    var seen: Set<String> = []
                    picks = preset.filter { seen.insert($0.food.id).inserted }
                    image = presetImage
                }
            }
        }
    }

    private func scan(_ photo: UIImage) {
        image = photo
        picks = []
        notice = nil
        guard let jpeg = GymScanSheet.jpeg(photo) else { notice = "Couldn't read that photo."; return }
        scanning = true
        Task {
            defer { scanning = false }
            do {
                // Unsure ones (#573) start unticked: FIX or tick them if Monkey got them right.
                var seen: Set<String> = []
                picks = try await model.scanFood(jpeg: jpeg).filter { seen.insert($0.food.id).inserted }
                    .map { ScanPick($0.food, sure: $0.sure, source: "Photo") }
                if picks.isEmpty { notice = "No food spotted. Open the fridge door wide and try again." }
            } catch APIError.server(_, _, let message) {
                notice = message
            } catch {
                notice = "Couldn't reach the server. Check your connection and try again."
            }
        }
    }
}
