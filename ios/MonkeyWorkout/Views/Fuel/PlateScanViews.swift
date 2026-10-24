import APIClient
import PhotosUI
import SwiftUI
import WorkoutEngine

// Snap my plate (#723, mix of C + A + B from `scan-plate/proposals.png`): the dish and how much was eaten on top (C),
// the foods Monkey saw with their grams, unsure ones dashed and off (A), S–XL per food instead of typing grams (B).

/// Photo of a cooked meal → foods and grams → totals → logged on a meal, optionally saved as a dish (a usual).
struct PlateScanSheet: View {
    let plan: FuelPlan
    let day: Date
    let slot: FuelSlot
    /// Called once logged, so Just ate closes too.
    var logged: () -> Void = {}
    /// Magic Snap (#733): the photo and Monkey's answer, already read.
    var preset: PlateScan?
    var presetImage: UIImage?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var store = FuelStore.shared
    @State private var camera = false
    @State private var photoItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var scanning = false
    @State private var plate: PlateScan?
    @State private var saveDish = true
    @State private var notice: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    photo
                    HStack(spacing: 8) {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button { camera = true } label: { Label(plate == nil ? "Take photo" : "Again", systemImage: "camera.fill") }
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
                    if let plate { result(plate) }
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Snap my plate")
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
                if let preset, plate == nil {
                    plate = preset
                    image = presetImage
                }
                #if DEBUG
                if model.demo, plate == nil { plate = try? await model.scanPlate(jpeg: Data()) }
                #endif
            }
        }
        .preferredColorScheme(.dark)
    }

    private var photo: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                FuelPalette.hot
                VStack(spacing: 6) {
                    Image(systemName: "fork.knife.circle.fill").font(.system(size: 40, weight: .bold))
                    Text("Your plate, bowl or lunch box").font(Theme.display(17))
                    Text("Monkey names the food, guesses the grams and counts it.").font(.caption.weight(.bold)).opacity(0.9)
                }
                .multilineTextAlignment(.center).padding(.horizontal, 16)
                .foregroundStyle(.white)
            }
            if scanning {
                ProgressView("Reading your plate…").tint(.white).foregroundStyle(.white)
                    .padding(12).background(Capsule().fill(.black.opacity(0.6)))
            }
        }
        .frame(maxWidth: .infinity).frame(height: plate == nil ? 220 : 130)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder private func result(_ p: PlateScan) -> some View {
        let t = p.totals
        // C · the dish and how much was eaten.
        VStack(alignment: .leading, spacing: 2) {
            Text(p.dish.isEmpty ? "ON YOUR PLATE" : "LOOKS LIKE").font(Theme.label(10)).tracking(1.2).opacity(0.8)
            Text(p.dish.isEmpty ? p.name : p.dish).font(Theme.display(22)).lineLimit(2).minimumScaleFactor(0.7)
        }
        .foregroundStyle(Theme.ink)
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(FuelPalette.carbs))
        label("HOW MUCH DID YOU EAT?")
        segments(PlateScan.Share.allCases, on: p.share, label: \.label) { s in plate?.share = s }
        // A · the foods, unsure ones dashed and off.
        label("FOUND · TAP TO TICK")
        ForEach(Array(p.items.enumerated()), id: \.element.id) { i, item in row(item, index: i, in: p) }
        // Totals and log.
        if !store.prefs.noNumbers {
            HStack(spacing: 5) {
                number("\(Int(t.macros.protein.rounded()))", "G PROTEIN")
                number("\(Int(t.macros.carbs.rounded()))", "G CARBS")
                number("\(Int(t.macros.fat.rounded()))", "G FAT")
                number("\(Int(t.macros.kcal.rounded()))", "KCAL")
                if t.caffeineMg > 0 { number("\(t.caffeineMg)", "MG ☕") }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(FuelPalette.violet))
        }
        Button { withAnimation(.snappy) { saveDish.toggle() } } label: {
            HStack {
                Text("⭐ Save as my dish").font(Theme.display(14))
                Spacer()
                Image(systemName: saveDish ? "checkmark.square.fill" : "square").font(.system(size: 20, weight: .bold))
                    .foregroundStyle(saveDish ? Theme.lime : Theme.muted)
            }
            .foregroundStyle(.white)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(saveDish ? .isSelected : [])
        Button { log(p) } label: { Text("Log \(slot.title.lowercased())") }
            .buttonStyle(LimeButtonStyle())
            .disabled(p.servings.isEmpty)
            .accessibilityIdentifier("fuel.plateScan.log")
    }

    private func row(_ item: PlateScan.Item, index: Int, in p: PlateScan) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Button {
                Haptics.undo()
                withAnimation(.snappy) { plate?.items[index].on.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Text(item.food.emoji).font(.system(size: 20)).frame(width: 36, height: 36)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black.opacity(0.25)))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.sure ? item.food.name : "\(item.food.name)?").font(Theme.display(14)).lineLimit(1).minimumScaleFactor(0.75)
                        Text("≈ \(Int(p.grams(item).rounded())) g").font(.system(size: 11, weight: .bold, design: .rounded)).opacity(0.8)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: item.on ? "checkmark.square.fill" : "square").font(.system(size: 22, weight: .bold))
                        .foregroundStyle(item.on ? Theme.lime : Theme.muted)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(item.food.name), about \(Int(p.grams(item).rounded())) grams")
            .accessibilityAddTraits(item.on ? .isSelected : [])
            if item.on {
                // B · size against Monkey's guess.
                segments(PlateScan.Size.allCases, on: item.size, label: \.label) { s in plate?.items[index].size = s }
            }
        }
        .foregroundStyle(.white)
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Theme.card))
        .overlay {
            if !item.sure {
                RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Color.yellow, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            }
        }
    }

    private func segments<T: Hashable>(_ all: [T], on: T, label: KeyPath<T, String>, pick: @escaping (T) -> Void) -> some View {
        HStack(spacing: 5) {
            ForEach(all, id: \.self) { v in
                let sel = v == on
                Button {
                    Haptics.undo()
                    withAnimation(.snappy) { pick(v) }
                } label: {
                    Text(v[keyPath: label]).font(Theme.label(13))
                        .foregroundStyle(sel ? Theme.ink : .white)
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(sel ? Theme.lime : Theme.cardStrong))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(sel ? .isSelected : [])
            }
        }
    }

    private func number(_ v: String, _ unit: String) -> some View {
        VStack(spacing: 1) {
            Text(v).font(Theme.display(18)).monospacedDigit()
            Text(unit).font(Theme.label(8)).opacity(0.85).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black.opacity(0.22)))
    }

    private func label(_ t: String) -> some View {
        Text(t).font(Theme.label(10)).tracking(1.2).foregroundStyle(Theme.muted).padding(.top, 4)
    }

    private func log(_ p: PlateScan) {
        let items = p.servings
        guard !items.isEmpty else { return }
        Haptics.success()
        store.keep(p.items.filter(\.on).map(\.food))
        store.update(day, plan: plan) { $0.log(items, at: slot, own: store.saved.foods) }
        if saveDish { store.saveUsual(FoodUsual(name: String(p.name.prefix(40)), items: items, kind: slot.kind)) }
        dismiss()
        logged()
    }

    private func scan(_ photo: UIImage) {
        image = photo
        plate = nil
        notice = nil
        guard let jpeg = GymScanSheet.jpeg(photo) else { notice = "Couldn't read that photo."; return }
        scanning = true
        Task {
            defer { scanning = false }
            do {
                let p = try await model.scanPlate(jpeg: jpeg)
                if p.items.isEmpty { notice = "No food spotted. Take the photo from above, plate filling the frame." } else { plate = p }
            } catch APIError.server(_, _, let message) {
                notice = message
            } catch {
                notice = "Couldn't reach the server. Check your connection and try again."
            }
        }
    }
}
