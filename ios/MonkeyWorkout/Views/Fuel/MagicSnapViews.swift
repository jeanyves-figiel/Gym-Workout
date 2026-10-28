import APIClient
import PhotosUI
import SwiftUI
import WorkoutEngine

// Magic Snap (#733, design C from `fuel-redesign/c.png`): one camera for Fuel. Point it at anything; Monkey sorts it:
// a meal or drink is logged (Snap my plate), food at home, shopping or a receipt goes to What I have. Plate, Fridge and
// Barcode chips go straight to one kind. Label (#872, free) reads a nutrition table on the iPhone into a new food.

/// What one Magic Snap photo turned out to be.
enum FuelSnap {
    case meal(PlateScan)
    case stock([(food: Food, sure: Bool)])
}

/// Top of the Log sheet: the big Snap card and its Plate / Fridge / Barcode chips.
struct MagicSnapCard: View {
    let plan: FuelPlan
    let day: Date
    let slot: FuelSlot
    /// Called once a meal is logged, so the Log sheet closes too.
    var logged: () -> Void = {}
    @State private var magic = false
    @State private var plate = false
    @State private var fridge = false
    @State private var barcode = false
    @State private var label = false
    @State private var gate: ProGate?

    var body: some View {
        let locked = ProStore.shared.locked
        VStack(alignment: .leading, spacing: 10) {
            Button { ProStore.shared.run(.foodScan, $gate) { magic = true } } label: {
                HStack(spacing: 12) {
                    Image(systemName: "camera.fill").font(.system(size: 22, weight: .black))
                        .frame(width: 50, height: 50)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.22)))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Snap it").font(Theme.display(20))
                        Text("Plate, fridge or receipt. Monkey sorts it.").font(.system(size: 11, weight: .bold, design: .rounded))
                            .opacity(0.9).lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    if locked {
                        Text("PRO").font(Theme.label(10)).padding(.horizontal, 7).padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.black.opacity(0.3)))
                    } else {
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .black))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("fuel.snap")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip("🍽️ Plate", lime: true) { ProStore.shared.run(.foodScan, $gate) { plate = true } }
                        .accessibilityIdentifier("fuel.justAte.snapPlate")
                    chip("🧊 Fridge") { ProStore.shared.run(.foodScan, $gate) { fridge = true } }
                    if LiveFoodScanner.available { chip("▥ Barcode") { barcode = true } }
                    chip("🏷️ Label") { label = true }
                        .accessibilityIdentifier("fuel.snap.label")
                }
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }
        .foregroundStyle(.white)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(FuelPalette.hot))
        .sheet(isPresented: $magic) { MagicSnapSheet(plan: plan, day: day, slot: slot, logged: logged).remotePaused(.foodScan) }
        .sheet(isPresented: $plate) { PlateScanSheet(plan: plan, day: day, slot: slot, logged: logged).remotePaused(.foodScan) }
        .sheet(isPresented: $fridge) { FoodPhotoScanSheet().remotePaused(.foodScan) }
        .sheet(isPresented: $barcode) { LiveScanSheet() }
        .sheet(isPresented: $label) { LabelReadSheet() }
        .proPaywall($gate)
    }

    private func chip(_ text: String, lime: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(Theme.label(12)).lineLimit(1)
                .foregroundStyle(lime ? Theme.ink : .white)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(lime ? AnyShapeStyle(Theme.lime) : AnyShapeStyle(Color.black.opacity(0.28))))
        }
        .buttonStyle(.plain)
    }
}

/// Take or pick one photo; once Monkey has sorted it, the sheet becomes Snap my plate or Snap the fridge with the answer.
struct MagicSnapSheet: View {
    let plan: FuelPlan
    let day: Date
    let slot: FuelSlot
    var logged: () -> Void = {}
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var camera = false
    @State private var photoItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var scanning = false
    @State private var notice: String?
    @State private var result: FuelSnap?

    var body: some View {
        switch result {
        case .meal(let p):
            PlateScanSheet(plan: plan, day: day, slot: slot, logged: logged, preset: p, presetImage: image)
        case .stock(let found):
            FoodPhotoScanSheet(preset: found.map { ScanPick($0.food, sure: $0.sure, source: "Photo") }, presetImage: image)
        case nil:
            capture
        }
    }

    private var capture: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ZStack {
                        if let image {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            FuelPalette.hot
                            VStack(spacing: 8) {
                                Image(systemName: "sparkles").font(.system(size: 40, weight: .bold))
                                Text("Snap anything").font(Theme.display(20))
                                Text("A plate or a drink is logged on \(slot.title.lowercased()). A fridge, shopping or a receipt goes to What I have.")
                                    .font(.caption.weight(.bold)).opacity(0.9)
                            }
                            .multilineTextAlignment(.center).padding(.horizontal, 18)
                            .foregroundStyle(.white)
                        }
                        if scanning {
                            ProgressView("Monkey is looking…").tint(.white).foregroundStyle(.white)
                                .padding(12).background(Capsule().fill(.black.opacity(0.6)))
                        }
                    }
                    .frame(maxWidth: .infinity).frame(height: 260)
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
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Snap it")
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
        }
        .preferredColorScheme(.dark)
    }

    private func scan(_ photo: UIImage) {
        image = photo
        notice = nil
        guard let jpeg = GymScanSheet.jpeg(photo) else { notice = "Couldn't read that photo."; return }
        scanning = true
        Task {
            defer { scanning = false }
            do {
                let snap = try await model.snapFood(jpeg: jpeg)
                let empty: Bool
                switch snap {
                case .meal(let p): empty = p.items.isEmpty
                case .stock(let found): empty = found.isEmpty
                }
                if empty {
                    notice = "No food spotted. Fill the frame with the plate, the open fridge or the receipt."
                } else {
                    withAnimation(.snappy) { result = snap }
                }
            } catch APIError.server(_, _, let message) {
                notice = message
            } catch {
                notice = "Couldn't reach the server. Check your connection and try again."
            }
        }
    }
}
