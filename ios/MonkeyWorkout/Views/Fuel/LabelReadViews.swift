import SwiftUI
import VisionKit
import WorkoutEngine

// Read a nutrition label (#872, epic #865, design C + A + B from `ai-epic/d2.png`): Label is the fourth Snap it chip,
// free for everyone. The camera reads the label's text on the iPhone (Vision, offline, nothing sent) and fills
// kcal / protein / carbs / fat live inside a lime frame; Use opens the new food form with the read values in lime.

/// Text-only VisionKit scanner: every frame's text, as rows top to bottom (blocks on one row joined left to right).
struct LabelTextScanner: UIViewControllerRepresentable {
    let onLines: ([String]) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.text(languages: ["en", "de", "fr", "it"])], qualityLevel: .accurate,
                                           recognizesMultipleItems: true, isHighFrameRateTrackingEnabled: false, isHighlightingEnabled: false)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_: DataScannerViewController, context _: Context) {}

    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator _: Coordinator) { vc.stopScanning() }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let parent: LabelTextScanner
        init(_ parent: LabelTextScanner) { self.parent = parent }

        func dataScanner(_: DataScannerViewController, didAdd _: [RecognizedItem], allItems: [RecognizedItem]) { read(allItems) }
        func dataScanner(_: DataScannerViewController, didUpdate _: [RecognizedItem], allItems: [RecognizedItem]) { read(allItems) }

        private func read(_ items: [RecognizedItem]) {
            var blocks: [(y: CGFloat, x: CGFloat, h: CGFloat, text: String)] = []
            for case .text(let t) in items {
                let b = t.bounds
                let top = min(b.topLeft.y, b.topRight.y), bottom = max(b.bottomLeft.y, b.bottomRight.y)
                let lines = t.transcript.split(separator: "\n").map(String.init)
                let step = (bottom - top) / CGFloat(max(1, lines.count))
                for (i, line) in lines.enumerated() {
                    blocks.append((top + step * (CGFloat(i) + 0.5), min(b.topLeft.x, b.bottomLeft.x), step, line))
                }
            }
            // A table row read as "Protein" and "13 g" side by side: same height on screen → one row.
            var rows: [[(x: CGFloat, text: String)]] = []
            var lastY = -CGFloat.infinity, lastH: CGFloat = 0
            for b in blocks.sorted(by: { $0.y < $1.y }) {
                if b.y - lastY < max(lastH, b.h) * 0.5, !rows.isEmpty {
                    rows[rows.count - 1].append((b.x, b.text))
                } else {
                    rows.append([(b.x, b.text)])
                    lastY = b.y
                    lastH = b.h
                }
            }
            parent.onLines(rows.map { $0.sorted { $0.x < $1.x }.map(\.text).joined(separator: " ") })
        }
    }
}

struct LabelReadSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var label = NutritionLabel()
    @State private var form = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("READ A LABEL · ⚡ ON DEVICE").font(Theme.label(10)).tracking(1.2).foregroundStyle(Theme.muted)
                Text("Nutrition label").font(Theme.display(26))
                ZStack {
                    if LiveFoodScanner.available {
                        LabelTextScanner { lines in
                            let read = NutritionLabel.read(lines)
                            guard !read.isEmpty else { return }
                            let was = label.usable
                            label = label.merged(read)
                            if !was, label.usable { UINotificationFeedbackGenerator().notificationOccurred(.success) }
                        }
                    } else {
                        Theme.card
                        Text("The camera can't read text on this device. Type the values in.")
                            .font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted).multilineTextAlignment(.center).padding(24)
                    }
                    RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.lime, lineWidth: 3)
                        .padding(.horizontal, 28).padding(.vertical, 20)
                        .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity).frame(height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                LabelTiles(label: label)
                Spacer(minLength: 0)
                Text("Point the frame at the nutrition table. Read on your iPhone; nothing is sent.")
                    .font(.caption2.weight(.semibold)).foregroundStyle(Theme.muted)
                Button { form = true } label: { Text(label.isEmpty ? "TYPE IT IN" : "USE · PER 100 \(label.perMl ? "ML" : "G")") }
                    .buttonStyle(LimeButtonStyle())
                    .accessibilityIdentifier("fuel.label.use")
            }
            .foregroundStyle(.white)
            .padding(16)
            .background(Theme.bg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
            .navigationDestination(isPresented: $form) { LabelFoodForm(label: label) { dismiss() } }
        }
        .preferredColorScheme(.dark)
    }
}

/// kcal, protein, carbs, fat: the four big gradient squares under the camera, filling as the label is read.
private struct LabelTiles: View {
    let label: NutritionLabel

    var body: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                tile("kcal", label.kcal, FuelPalette.hot)
                tile("Protein", label.protein, FuelPalette.mint)
            }
            GridRow {
                tile("Carbs", label.carbs, FuelPalette.violet)
                tile("Fat", label.fat, FuelPalette.gradient(0xFF3D7F, 0xFF9A3C))
            }
        }
    }

    private func tile(_ title: String, _ value: Double?, _ fill: LinearGradient) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(Theme.label(13))
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Text(value.map(LabelFoodForm.format) ?? "–").font(Theme.display(30)).contentTransition(.numericText())
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 84)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(fill))
        .opacity(value == nil ? 0.55 : 1)
        .animation(.snappy, value: value)
    }
}

/// New food · from label: a name, the values per 100 g (lime = read off the label, white once changed), a usual
/// serving, Save to What I have.
struct LabelFoodForm: View {
    let label: NutritionLabel
    var done: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var store = FuelStore.shared
    @State private var name = ""
    @State private var values: [NutritionLabel.Field: String] = [:]
    @State private var serving: Double = 0
    @FocusState private var naming: Bool

    private var servings: [Double] { label.perMl ? [200, 250, 330] : [30, 45, 60] }
    private var unit: String { label.perMl ? "ml" : "g" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("NEW FOOD · FROM LABEL").font(Theme.label(10)).tracking(1.2).foregroundStyle(Theme.muted)
                Text(name.isEmpty ? "New food" : name).font(Theme.display(26)).lineLimit(2)
                TextField("Name (e.g. Oat granola)", text: $name)
                    .focused($naming)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
                    .accessibilityIdentifier("fuel.label.name")
                Text("PER 100 \(unit.uppercased()) · READ FROM LABEL").font(Theme.label(10)).tracking(1.2).foregroundStyle(Theme.muted)
                VStack(spacing: 0) {
                    ForEach(NutritionLabel.Field.allCases, id: \.self) { f in
                        row(f)
                        if f != .salt { Divider().overlay(Color.white.opacity(0.08)) }
                    }
                }
                .padding(.horizontal, 12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
                Text("USUAL SERVING").font(Theme.label(10)).tracking(1.2).foregroundStyle(Theme.muted)
                HStack(spacing: 8) {
                    ForEach(servings, id: \.self) { g in
                        Button { serving = g } label: {
                            Text("\(Int(g)) \(unit)").font(Theme.label(14))
                                .foregroundStyle(serving == g ? Theme.ink : .white)
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(serving == g ? Theme.lime : Theme.cardStrong))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("Nothing uploaded. Lime = read from the label, check it against the pack.")
                    .font(.caption2.weight(.semibold)).foregroundStyle(Theme.muted)
                Button(action: save) { Text("SAVE TO WHAT I HAVE") }
                    .buttonStyle(LimeButtonStyle())
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || reading.protein == nil || reading.carbs == nil || reading.fat == nil)
                    .accessibilityIdentifier("fuel.label.save")
            }
            .foregroundStyle(.white)
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .readableWidth()
        .background(Theme.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { CloseToolbarItem { done(); dismiss() } }
        .onAppear {
            guard values.isEmpty else { return }
            for f in NutritionLabel.Field.allCases { values[f] = label[f].map(Self.format) ?? "" }
            serving = servings[1]
            naming = true
        }
    }

    private func row(_ f: NutritionLabel.Field) -> some View {
        let text = Binding(get: { values[f] ?? "" }, set: { values[f] = $0 })
        let read = label[f].map(Self.format) == values[f] && label[f] != nil
        return HStack {
            Text(title(f)).font(.subheadline.weight(.semibold))
            Spacer()
            TextField("–", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(read ? Theme.lime : .white)
                .frame(width: 80)
            Text(f == .kcal ? "kcal" : unit).font(.caption.weight(.bold)).foregroundStyle(Theme.muted).frame(width: 30, alignment: .leading)
        }
        .padding(.vertical, 10)
    }

    private func title(_ f: NutritionLabel.Field) -> String {
        switch f {
        case .kcal: "Energy"
        case .protein: "Protein"
        case .carbs: "Carbs"
        case .fat: "Fat"
        case .fibre: "Fibre"
        case .salt: "Salt"
        }
    }

    /// The form's values (the member's edits over what was read).
    private var reading: NutritionLabel {
        var out = NutritionLabel(perMl: label.perMl)
        for f in NutritionLabel.Field.allCases {
            out[f] = Double((values[f] ?? "").replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
        }
        return out
    }

    private func save() {
        store.add([reading.food(name: name, serving: serving, own: store.saved.foods)])
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        done()
        dismiss()
    }

    static func format(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%g", (v * 100).rounded() / 100)
    }
}
