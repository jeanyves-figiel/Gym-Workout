import PhotosUI
import SwiftUI
import UIKit
import WorkoutEngine

/// Builder for the user's own exercises (#52), e.g. a machine in their gym: name, category, machine,
/// muscles on the body map, reps or seconds, cues, and a picture (photo and/or pose drawing).
struct CustomExerciseBuilderView: View {
    var existing: CustomExercise?
    var onSave: (CustomExercise) -> Void = { _ in }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CustomExercise
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var designing = false
    @State private var confirmArchive = false

    init(existing: CustomExercise? = nil, onSave: @escaping (CustomExercise) -> Void = { _ in }) {
        self.existing = existing
        self.onSave = onSave
        _draft = State(initialValue: existing ?? CustomExercise())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    preview
                    nameSection
                    categorySection
                    machineSection
                    musclesSection
                    measureSection
                    pictureSection
                    cuesSection
                    if existing != nil { archiveButton }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(existing == nil ? "New exercise" : "Edit exercise")
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let saved = model.saveCustomExercise(draft)
                        onSave(saved)
                        dismiss()
                    }
                    .bold()
                    .disabled(!draft.isComplete)
                }
            }
            .navigationDestination(isPresented: $designing) {
                PoseDesignerView(
                    drawing: Binding(
                        get: { draft.drawing ?? ExerciseDrawing(template: .standing) },
                        set: { draft.drawing = $0 }),
                    category: draft.category, primary: draft.primary)
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    if let image { draft.photo = PhotoCompressor.jpeg(image) }
                }
                .ignoresSafeArea()
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        draft.photo = PhotoCompressor.jpeg(image)
                    }
                    photoItem = nil
                }
            }
            .confirmationDialog("Remove this exercise?", isPresented: $confirmArchive, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    model.archiveCustomExercise(draft.id)
                    dismiss()
                }
            } message: {
                Text("It disappears from the picker. Workouts and history that use it keep it.")
            }
        }
    }

    // MARK: Sections

    private var preview: some View {
        HStack(spacing: 14) {
            ZStack {
                Rectangle().fill(draft.category.gradient)
                if draft.photo == nil && draft.drawing == nil {
                    Image(systemName: draft.category.symbol).font(.system(size: 30, weight: .bold)).foregroundStyle(.white.opacity(0.9))
                }
                CustomExerciseArt(record: draft)
            }
            .frame(width: 120, height: 90)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                CategoryPill(category: draft.category, compact: true)
                Text(draft.name.isEmpty ? "Your exercise" : draft.name)
                    .font(Theme.display(20))
                    .foregroundStyle(draft.name.isEmpty ? Theme.muted : .white)
                    .lineLimit(2)
                if let m = draft.machine, !m.isEmpty {
                    Text(m).font(.caption.weight(.semibold)).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .card(padding: 12)
    }

    private var nameSection: some View {
        section("Name") {
            TextField("e.g. Hip abductor machine", text: $draft.name)
                .font(Theme.display(22))
                .textInputAutocapitalization(.sentences)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
        }
    }

    private var categorySection: some View {
        section("Category") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(WorkoutEngine.Category.allCases) { c in
                        Button { draft.category = c } label: {
                            CategoryTile(title: c.label, symbol: c.symbol, count: nil, fill: AnyShapeStyle(c.gradient),
                                         iconColor: .white, selected: draft.category == c, dimmed: draft.category != c)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var machineSection: some View {
        section("Machine or equipment") {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Machine name (optional), e.g. Technogym abductor", text: Binding(
                    get: { draft.machine ?? "" }, set: { draft.machine = $0 }))
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            FilterChip(title: "Bodyweight", on: draft.equipment.isEmpty) { draft.equipment = [] }
                            ForEach(Equipment.allCases) { eq in
                                FilterChip(title: eq.label, on: draft.equipment.contains(eq)) {
                                    if let i = draft.equipment.firstIndex(of: eq) { draft.equipment.remove(at: i) } else { draft.equipment.append(eq) }
                                }
                                .id(eq)
                            }
                        }
                    }
                    // Editing: bring the picked equipment into view instead of leaving it off-screen.
                    .onAppear { if let eq = draft.equipment.first { proxy.scrollTo(eq, anchor: .center) } }
                }
            }
        }
    }

    private var musclesSection: some View {
        section("Muscles · tap once main, twice assist") {
            VStack(alignment: .leading, spacing: 10) {
                BodyMapPair(heat: heat) { cycle($0) }
                    .frame(height: 240)
                if draft.primary.isEmpty && draft.secondary.isEmpty {
                    Text("Pick at least one main muscle.").font(.footnote).foregroundStyle(Theme.muted)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(draft.primary) { m in MuscleChip(muscle: m).onTapGesture { cycle(m) } }
                            ForEach(draft.secondary) { m in MuscleChip(muscle: m, primary: false).onTapGesture { cycle(m) } }
                        }
                    }
                }
            }
            .card()
        }
    }

    private var heat: [Muscle: Double] {
        var h: [Muscle: Double] = [:]
        for m in draft.secondary { h[m] = 0.35 }
        for m in draft.primary { h[m] = 1 }
        return h
    }

    /// none → main → assist → none.
    private func cycle(_ m: Muscle) {
        if let i = draft.primary.firstIndex(of: m) {
            draft.primary.remove(at: i)
            draft.secondary.append(m)
        } else if let i = draft.secondary.firstIndex(of: m) {
            draft.secondary.remove(at: i)
        } else {
            draft.primary.append(m)
        }
    }

    private var measureSection: some View {
        section("Counted in") {
            Picker("Counted in", selection: $draft.unit) {
                Text("Reps").tag(WorkoutEngine.Unit.reps)
                Text("Seconds").tag(WorkoutEngine.Unit.sec)
            }
            .pickerStyle(.segmented)
        }
    }

    private var pictureSection: some View {
        section("Picture") {
            HStack(spacing: 12) {
                pictureTile(title: "Photo", symbol: "camera.fill", filled: draft.photo != nil) {
                    if let data = draft.photo, let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFill()
                    }
                } menu: {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button { showCamera = true } label: { Label("Take photo", systemImage: "camera") }
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) { Label("Choose from library", systemImage: "photo.on.rectangle") }
                    if draft.photo != nil {
                        Button(role: .destructive) { draft.photo = nil } label: { Label("Remove photo", systemImage: "trash") }
                    }
                }
                pictureTile(title: "Pose", symbol: "figure.strengthtraining.traditional", filled: draft.drawing != nil) {
                    if let d = draft.drawing {
                        FigureDrawingView(drawing: d, lit: FigureHighlight.segments(for: draft.primary), accent: draft.category.figureAccent)
                    }
                } menu: {
                    Button { designing = true } label: { Label(draft.drawing == nil ? "Draw pose" : "Edit pose", systemImage: "hand.draw") }
                    if draft.drawing != nil {
                        Button(role: .destructive) { draft.drawing = nil } label: { Label("Remove pose", systemImage: "trash") }
                    }
                }
            }
        }
    }

    private func pictureTile<Content: View, Actions: View>(
        title: String, symbol: String, filled: Bool,
        @ViewBuilder content: () -> Content, @ViewBuilder menu: () -> Actions
    ) -> some View {
        let art = content()
        let actions = menu()
        return Menu {
            actions
        } label: {
            ZStack {
                Rectangle().fill(draft.category.gradient)
                art
                if !filled {
                    VStack(spacing: 6) {
                        Image(systemName: symbol).font(.system(size: 26, weight: .bold))
                        Text(title).font(Theme.display(17))
                    }
                    .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Image(systemName: filled ? "pencil.circle.fill" : "plus.circle.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.ink, Theme.lime)
                    .padding(8)
            }
        }
        .accessibilityLabel(filled ? "Change \(title.lowercased())" : "Add \(title.lowercased())")
    }

    private var cuesSection: some View {
        section("Cues (optional)") {
            VStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { i in
                    TextField(i == 0 ? "e.g. Slow return, 2 s" : "Another cue", text: Binding(
                        get: { draft.cues.indices.contains(i) ? draft.cues[i] : "" },
                        set: { v in
                            while draft.cues.count <= i { draft.cues.append("") }
                            draft.cues[i] = v
                        }))
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
                }
            }
        }
    }

    private var archiveButton: some View {
        Button(role: .destructive) { confirmArchive = true } label: {
            Text("Remove exercise").font(.body.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 12)
        }
        .buttonStyle(.bordered)
        .tint(.red)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).eyebrow()
            content()
        }
    }
}

/// Downscales and compresses photos to fit `CustomExercise.maxPhotoBytes`.
enum PhotoCompressor {
    static func jpeg(_ image: UIImage, maxSide: CGFloat = 900) -> Data? {
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        for q in stride(from: 0.75, through: 0.3, by: -0.15) {
            if let data = resized.jpegData(compressionQuality: q), data.count <= CustomExercise.maxPhotoBytes { return data }
        }
        return nil
    }
}

/// System camera.
struct CameraPicker: UIViewControllerRepresentable {
    let onPick: (UIImage?) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let c = UIImagePickerController()
        c.sourceType = .camera
        c.delegate = context.coordinator
        return c
    }

    func updateUIViewController(_: UIImagePickerController, context _: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.onPick(info[.originalImage] as? UIImage)
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_: UIImagePickerController) {
            parent.onPick(nil)
            parent.dismiss()
        }
    }
}
