import PhotosUI
import SwiftUI
import WorkoutEngine

// Machine setup notes (#355, design B + C): the member's settings for an exercise at a gym (Seat 4, Pad 2…),
// shown as a strip on the player's exercise card with a photo thumbnail; edited in a sheet; listed per machine.

/// Field tiles cycle through the category gradients.
private let tileGradients: [WorkoutEngine.Category] = [.power, .strength, .cardio, .warmup, .mobility, .stretch]

/// The note's photo, loaded from the device or the server.
struct MachineNotePhotoImage: View {
    let note: MachineNote
    var contentMode: ContentMode = .fill
    @Environment(AppModel.self) private var model
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else {
                Rectangle().fill(.white.opacity(0.12))
                Image(systemName: "camera.fill").font(.caption.bold()).opacity(0.7)
            }
        }
        .task(id: "\(note.id)-\(note.photoId ?? "local")") {
            image = await model.machineNotePhoto(note).flatMap(UIImage.init(data:))
        }
    }
}

/// Player strip (B + C): photo thumbnail (tap = full photo) and the member's values (tap = edit). One line; values
/// that don't fit are dropped rather than wrapping, so the set card never moves (#206).
struct MachineNoteStrip: View {
    let note: MachineNote
    let hasPhoto: Bool
    let onEdit: () -> Void
    let onPhoto: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if hasPhoto {
                Button(action: onPhoto) {
                    MachineNotePhotoImage(note: note)
                        .frame(width: 34, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(.white, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Setup photo")
            }
            Button(action: onEdit) {
                HStack(spacing: 5) {
                    Image(systemName: "gearshape.fill").font(.system(size: 12, weight: .bold))
                    ViewThatFits(in: .horizontal) {
                        values(8)
                        values(3)
                        values(2)
                        values(1)
                        values(0)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black.opacity(0.28)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("My setup: \(note.summary.isEmpty ? "photo" : note.summary)")
        }
    }

    @ViewBuilder
    private func values(_ n: Int) -> some View {
        let fields = note.filledFields
        if fields.isEmpty || n == 0 {
            Text(fields.isEmpty ? (note.trimmedText ?? "My setup") : note.summary)
                .font(Theme.label(12))
                .lineLimit(1)
        } else {
            HStack(spacing: 4) {
                ForEach(fields.prefix(n)) { f in
                    Text("\(f.label) \(f.value)")
                        .font(Theme.label(12))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white.opacity(0.2)))
                }
                if fields.count > n { Text("+\(fields.count - n)").font(Theme.label(11)).opacity(0.8).fixedSize() }
            }
        }
    }
}

/// "Setup" chip on the exercise card when there's no note yet at this gym.
struct MachineNoteAddChip: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Setup", systemImage: "gearshape.fill")
                .font(Theme.label(11))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().strokeBorder(.white.opacity(0.6), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add my machine setup")
    }
}

/// Opens the setup sheet for an exercise at a gym.
struct MachineNoteTarget: Identifiable, Hashable {
    let exerciseId: String
    let gym: GymRef
    var id: String { "\(gym.id)|\(exerciseId)" }
}

/// Edit sheet: photo, quick-field tiles, preset names, text, and setups from other gyms to copy.
struct MachineNoteSheet: View {
    let exerciseId: String
    let gym: GymRef
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: MachineNote
    /// nil = unchanged; .some(nil) = removed.
    @State private var newPhoto: Data??
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var loaded = false
    @FocusState private var focus: UUID?

    init(exerciseId: String, gym: GymRef) {
        self.exerciseId = exerciseId
        self.gym = gym
        _draft = State(initialValue: MachineNote(gymId: gym.id, gymName: gym.name, exerciseId: exerciseId,
                                                 equipment: Exercise.find(exerciseId)?.equipment.first?.rawValue))
    }

    private var exercise: Exercise { Exercise.get(exerciseId) }
    private var existing: MachineNote? { model.machineNote(exerciseId: exerciseId, gymId: gym.id) }
    private var others: [MachineNote] { model.machineNotes(for: exercise).filter { $0.gymId != gym.id } }
    private var photoShown: Bool {
        switch newPhoto {
        case let .some(d): d != nil
        case .none: existing?.photoId != nil || MachineNotePhotos.load(draft.id) != nil
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("My setup · \(gym.name)").eyebrow()
                        Text(exercise.name).font(Theme.display(28)).fixedSize(horizontal: false, vertical: true)
                        Text("Only you see this.").font(.footnote).foregroundStyle(Theme.muted)
                    }
                    photoCard
                    fieldsSection
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Note").eyebrow()
                        TextField("Pad just above the heels, range limiter off…", text: Binding(
                            get: { draft.text ?? "" }, set: { draft.text = String($0.prefix(MachineNote.maxText)) }), axis: .vertical)
                            .lineLimit(2...6)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.cardStrong))
                    }
                    if !others.isEmpty { otherGyms }
                    if existing != nil {
                        Button(role: .destructive) {
                            if let id = existing?.id { model.deleteMachineNote(id) }
                            dismiss()
                        } label: {
                            Text("Delete setup").font(.body.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 12)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .readableWidth()
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Machine setup")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button {
                    model.saveMachineNote(draft, photo: newPhoto)
                    dismiss()
                } label: {
                    Text("Save setup").frame(maxWidth: .infinity)
                }
                .buttonStyle(LimeButtonStyle())
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .toolbar { CloseToolbarItem { dismiss() } }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    if let image, let jpeg = PhotoCompressor.jpeg(image) { newPhoto = .some(jpeg) }
                }
                .ignoresSafeArea()
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data),
                       let jpeg = PhotoCompressor.jpeg(image) { newPhoto = .some(jpeg) }
                    photoItem = nil
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let existing { draft = existing }
                if draft.fields.isEmpty { draft.fields = [.init(label: "Seat", value: "")] }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var photoCard: some View {
        Menu {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { showCamera = true } label: { Label("Take photo", systemImage: "camera") }
            }
            PhotosPicker(selection: $photoItem, matching: .images) { Label("Choose from library", systemImage: "photo.on.rectangle") }
            if photoShown {
                Button(role: .destructive) { newPhoto = .some(nil) } label: { Label("Remove photo", systemImage: "trash") }
            }
        } label: {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if case let .some(.some(data)) = newPhoto, let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else if photoShown {
                        MachineNotePhotoImage(note: existing ?? draft)
                    } else {
                        LinearGradient(colors: WorkoutEngine.Category.cardio.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                            .overlay(Image(systemName: "camera.fill").font(.system(size: 34, weight: .bold)))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 170)
                .clipped()
                Label(photoShown ? "Replace photo" : "Add a photo of your settings", systemImage: "camera.fill")
                    .font(Theme.label(12))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.black.opacity(0.55)))
                    .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .foregroundStyle(.white)
        }
    }

    private var fieldsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Settings").eyebrow()
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Array(draft.fields.enumerated()), id: \.element.id) { i, f in fieldTile(i, f) }
                if draft.fields.count < MachineNote.maxFields {
                    Button { addField("") } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("+ ADD").font(Theme.label(11)).tracking(1)
                            Text("…").font(Theme.display(26))
                        }
                        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.stroke, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                    }
                    .buttonStyle(.plain)
                }
            }
            let unused = MachineNote.presets.filter { p in !draft.fields.contains { $0.label.caseInsensitiveCompare(p) == .orderedSame } }
            if draft.fields.count < MachineNote.maxFields, !unused.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(unused, id: \.self) { p in FilterChip(title: p, on: false, small: true) { addField(p) } }
                }
            }
        }
    }

    private func fieldTile(_ i: Int, _ f: MachineNote.Field) -> some View {
        let cat = tileGradients[i % tileGradients.count]
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                TextField("NAME", text: Binding(get: { draft.fields[safe: i]?.label ?? "" },
                                                set: { if draft.fields.indices.contains(i) { draft.fields[i].label = String($0.prefix(MachineNote.maxLabel)) } }))
                    .font(Theme.label(11))
                    .textInputAutocapitalization(.words)
                Button { draft.fields.removeAll { $0.id == f.id } } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 16, weight: .bold)).opacity(0.8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(f.label)")
            }
            TextField("–", text: Binding(get: { draft.fields[safe: i]?.value ?? "" },
                                         set: { if draft.fields.indices.contains(i) { draft.fields[i].value = String($0.prefix(MachineNote.maxLabel)) } }))
                .font(Theme.display(26))
                .focused($focus, equals: f.id)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(cat.gradient))
        .foregroundStyle(cat == .warmup || cat == .stretch || cat == .cardio ? Theme.ink : .white)
    }

    private func addField(_ label: String) {
        guard draft.fields.count < MachineNote.maxFields else { return }
        let f = MachineNote.Field(label: label, value: "")
        draft.fields.append(f)
        focus = f.id
    }

    private var otherGyms: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("From your other gyms").eyebrow()
            ForEach(others) { n in
                HStack(spacing: 10) {
                    MachineNoteRowLabel(note: n, showsExercise: n.exerciseId != exerciseId)
                    Button("Use") {
                        draft.fields = n.fields.map { .init(label: $0.label, value: $0.value) }
                        draft.text = n.text
                        Task {
                            if let photo = await model.machineNotePhoto(n) { newPhoto = .some(photo) }
                        }
                    }
                    .font(Theme.label(12))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Theme.lime))
                    .foregroundStyle(Theme.ink)
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
            }
        }
    }
}

/// Gym, exercise (when it's another one on the machine), values and photo of a note.
struct MachineNoteRowLabel: View {
    let note: MachineNote
    var showsExercise = false
    var isHere = false

    var body: some View {
        HStack(spacing: 10) {
            if note.photoId != nil || MachineNotePhotos.load(note.id) != nil {
                MachineNotePhotoImage(note: note)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Image(systemName: isHere ? "mappin.circle.fill" : "building.2.fill")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isHere ? WorkoutEngine.Category.power.gradient : WorkoutEngine.Category.strength.gradient))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(note.gymName).font(.subheadline.weight(.bold)).lineLimit(1)
                Text(([isHere ? "This gym" : nil, showsExercise ? Exercise.find(note.exerciseId)?.name : nil, note.summary.isEmpty ? nil : note.summary]
                        as [String?]).compactMap { $0 }.joined(separator: " · "))
                    .font(.caption.weight(.medium))
                    .opacity(0.85)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Full-screen photo with the note over it (C).
struct MachineNotePhotoViewer: View {
    let note: MachineNote
    let onEdit: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()
            MachineNotePhotoImage(note: note, contentMode: .fit).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 8) {
                Text("My setup · \(note.gymName)").eyebrow()
                Text(Exercise.find(note.exerciseId)?.name ?? "").font(Theme.display(22))
                if !note.filledFields.isEmpty { Text(note.summary).font(.headline.weight(.heavy)) }
                if let t = note.trimmedText { Text(t).font(.subheadline.weight(.medium)) }
                HStack {
                    Button { dismiss(); onEdit() } label: { Label("Edit", systemImage: "pencil") }
                        .font(Theme.label(13))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(.white.opacity(0.18)))
                    Spacer()
                    Button("Done") { dismiss() }
                        .font(Theme.label(13))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Theme.lime))
                        .foregroundStyle(Theme.ink)
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.white)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.black.opacity(0.65))
        }
        .preferredColorScheme(.dark)
    }
}

/// Exercise page and Form sheet: setups for this exercise and its machine at every gym, so one can be reused
/// where the same machine stands. Add / edit for the current gym.
struct MySetupsSection: View {
    let exercise: Exercise
    var plannedUid: String?
    @Environment(AppModel.self) private var model
    @State private var editing: MachineNoteTarget?

    var body: some View {
        let notes = model.machineNotes(for: exercise)
        let here = model.gymRef(forItem: plannedUid)
        if !exercise.equipment.isEmpty, model.profile != nil {
            GradientSection(symbol: "gearshape.2.fill", title: "My setups", gradient: WorkoutEngine.Category.power.gradient) {
                ForEach(notes) { n in
                    Button { editing = MachineNoteTarget(exerciseId: n.exerciseId, gym: GymRef(id: n.gymId, name: n.gymName, address: "")) } label: {
                        HStack(spacing: 8) {
                            MachineNoteRowLabel(note: n, showsExercise: n.exerciseId != exercise.id, isHere: n.gymId == here.id)
                            if n.gymId != here.id, model.machineNote(exerciseId: exercise.id, gymId: here.id) == nil {
                                Button("Copy here") { Task { await model.copyMachineNote(n, to: here, exerciseId: exercise.id) } }
                                    .font(Theme.label(11))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(Theme.lime))
                                    .foregroundStyle(Theme.ink)
                                    .buttonStyle(.plain)
                            } else {
                                Image(systemName: "chevron.right").font(.body.weight(.bold)).opacity(0.85)
                            }
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.16)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if model.machineNote(exerciseId: exercise.id, gymId: here.id) == nil {
                    Button { editing = MachineNoteTarget(exerciseId: exercise.id, gym: here) } label: {
                        Label("Add my setup at \(here.name)", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.black.opacity(0.25)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .sheet(item: $editing) { t in MachineNoteSheet(exerciseId: t.exerciseId, gym: t.gym) }
        }
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
