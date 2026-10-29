import APIClient
import PhotosUI
import SwiftUI
import WorkoutEngine

// Save a workout seen on TikTok / Instagram (#909, design A + B with C as fallback from `save-from-social/proposals.png`).
// In: the post's link and caption (shared from the app, or pasted), up to 4 screenshots, or the member's own words.
// Coach maps every move onto the catalog; the check screen shows matched moves and flags near ones to check.

/// What arrives from a share or a paste: the link, the caption and screenshots.
struct VideoImportDraft: Identifiable {
    var id = UUID()
    var link = ""
    var caption = ""
    var photos: [UIImage] = []

    /// Splits pasted or shared text into the first link and the rest (the caption).
    mutating func take(_ text: String) {
        let found = NSDataDetector.links(in: text)
        if link.isEmpty, let url = found.first { link = url.absoluteString }
        var rest = text
        for url in found { rest = rest.replacingOccurrences(of: url.absoluteString, with: "") }
        rest = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rest.isEmpty { caption = caption.isEmpty ? rest : caption + "\n" + rest }
    }
}

/// A share from TikTok / Instagram waiting in the App Group (#909 A), opened as *Save from a video* over the tabs.
@MainActor @Observable
final class VideoShareLaunch {
    static let shared = VideoShareLaunch()
    var draft: VideoImportDraft?

    /// Picks up what the share extension left (on open and on monkeyworkout://video-import).
    func check() {
        guard draft == nil, let taken = VideoInbox.take() else { return }
        var d = VideoImportDraft()
        if let link = taken.share.link { d.link = link }
        if let text = taken.share.text { d.take(text) }
        d.photos = taken.images.compactMap { UIImage(data: $0) }
        draft = d
    }
}

private extension NSDataDetector {
    static func links(in text: String) -> [URL] {
        guard let d = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        return d.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap(\.url)
            .filter { $0.scheme == "https" || $0.scheme == "http" }
    }
}

/// "From a video" (#909): input step (link, caption or words, screenshots) → Coach reads it → check and save.
struct VideoImportSheet: View {
    /// Set when opened from a day's Add sheet: the workout is also added to that day.
    var weekday: Int?
    var onDone: (() -> Void)?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: VideoImportDraft
    @State private var words = ""
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var reading = false
    @State private var notice: String?
    @State private var read: VideoImportRead?
    @State private var name = ""
    @State private var picking: ImportedMove?
    @State private var gate: ProGate?
    @FocusState private var typing: Bool

    /// `read`: opens on the check step (demo screen).
    init(draft: VideoImportDraft = VideoImportDraft(), weekday: Int? = nil, read: VideoImportRead? = nil, onDone: (() -> Void)? = nil) {
        _draft = State(initialValue: draft)
        _read = State(initialValue: read)
        _name = State(initialValue: read?.name ?? "")
        self.weekday = weekday
        self.onDone = onDone
    }

    private static let colors = [Color(hex: 0x7B4DFF), Color(hex: 0x3D7BFF)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let read { review(read) } else { input }
                    if let notice {
                        Label(notice, systemImage: "exclamationmark.circle.fill")
                            .font(.footnote.weight(.bold)).foregroundStyle(.yellow)
                    }
                }
                .padding(16)
                .padding(.bottom, 90)
            }
            .readableWidth()
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.bg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseToolbarItem { dismiss() } }
            .safeAreaInset(edge: .bottom) { bottomBar.padding(.horizontal, 16).padding(.bottom, 8).readableWidth() }
            .onChange(of: photoItems) { loadPhotos() }
            .sheet(item: $picking) { move in
                ExercisePickerView(limit: 1, selected: move.exerciseId.map { [$0] } ?? []) { list in
                    guard let e = list.first, let i = read?.moves.firstIndex(where: { $0.id == move.id }) else { return }
                    read?.moves[i].exerciseId = e.id
                    read?.moves[i].sure = true
                }
            }
            .proPaywall($gate)
        }
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
    }

    // MARK: Input (paste, words, screenshots)

    private var input: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("FROM A VIDEO").font(Theme.label(11)).tracking(1.4).opacity(0.85)
                    Spacer()
                    ProBadge()
                }
                Text("Saw a cool workout?").font(Theme.display(28))
                Text("Share it from TikTok or Instagram, paste the link, add screenshots or just say what you saw. Coach turns it into your own workout.")
                    .font(.footnote.weight(.semibold)).opacity(0.9)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .gradientCard(LinearGradient(colors: Self.colors, startPoint: .topLeading, endPoint: .bottomTrailing))

            HStack(spacing: 8) {
                PasteButton(payloadType: String.self) { texts in
                    for t in texts { draft.take(t) }
                }
                .buttonBorderShape(.capsule)
                .tint(Theme.lime)
                .labelStyle(.titleAndIcon)
                if !draft.link.isEmpty {
                    Label(WorkoutSource(platform: "", url: draft.link).link?.host() ?? draft.link, systemImage: "link")
                        .font(Theme.label(12)).lineLimit(1)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(Capsule().fill(Theme.cardStrong))
                    Button { draft.link = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .foregroundStyle(Theme.muted)
                        .accessibilityLabel("Remove link")
                }
            }

            field("Caption or link", text: $draft.caption, prompt: "Paste the post's text: \u{201C}Hip thrust 4x12, split squats 3x10…\u{201D}")
            field("Or tell Coach what you saw", text: $words, prompt: "\u{201C}Hip thrusts, then split squats on a bench, about 20 min\u{201D} (tap 🎙 on the keyboard to talk)")

            VStack(alignment: .leading, spacing: 8) {
                Text("SCREENSHOTS").font(Theme.label(11)).tracking(1.2).foregroundStyle(Theme.muted)
                HStack(spacing: 8) {
                    ForEach(Array(draft.photos.enumerated()), id: \.offset) { i, img in
                        Image(uiImage: img).resizable().scaledToFill()
                            .frame(width: 62, height: 100).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(alignment: .topTrailing) {
                                Button { draft.photos.remove(at: i) } label: {
                                    Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundStyle(.white, .black.opacity(0.6))
                                }
                                .padding(3)
                                .accessibilityLabel("Remove screenshot \(i + 1)")
                            }
                    }
                    if draft.photos.count < 4 {
                        PhotosPicker(selection: $photoItems, maxSelectionCount: 4 - draft.photos.count, matching: .screenshots) {
                            VStack(spacing: 4) {
                                Image(systemName: "plus").font(.system(size: 20, weight: .heavy))
                                Text("Add").font(Theme.label(10))
                            }
                            .foregroundStyle(.white)
                            .frame(width: 62, height: 100)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.cardStrong))
                        }
                        .accessibilityLabel("Add screenshots")
                    }
                }
                Text("Pause on the moves and take screenshots when the caption has no list. They are only read, never kept.")
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
            }
        }
    }

    private func field(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(Theme.label(11)).tracking(1.2).foregroundStyle(Theme.muted)
            TextField("", text: text, prompt: Text(prompt).foregroundStyle(Theme.muted), axis: .vertical)
                .lineLimit(3...8)
                .focused($typing)
                .font(.callout.weight(.semibold))
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
        }
    }

    private var hasInput: Bool {
        !draft.link.isEmpty || !draft.caption.trimmed.isEmpty || !words.trimmed.isEmpty || !draft.photos.isEmpty
    }

    // MARK: Review (design B)

    private func review(_ r: VideoImportRead) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                Text("FROM A VIDEO").font(Theme.label(11)).tracking(1.4).opacity(0.85)
                TextField("Name", text: $name).font(Theme.display(26)).textInputAutocapitalization(.words)
                if let s = r.source {
                    sourceChip(s)
                }
                if !draft.photos.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(draft.photos.enumerated()), id: \.offset) { _, img in
                            Image(uiImage: img).resizable().scaledToFill()
                                .frame(width: 44, height: 70).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                    .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .gradientCard(LinearGradient(colors: Self.colors, startPoint: .topLeading, endPoint: .bottomTrailing))

            let toCheck = r.moves.filter { !$0.sure }.count
            if r.moves.isEmpty {
                Text("No exercises found in that post. Add screenshots of the moves or tell Coach what you saw.")
                    .font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
            } else if toCheck > 0 {
                Text(toCheck == 1 ? "1 move to check: tap it to pick the exercise." : "\(toCheck) moves to check: tap one to pick the exercise.")
                    .font(.footnote.weight(.bold)).foregroundStyle(Color(hex: 0xFFE14D))
            }
            ForEach(r.moves) { m in
                Button { picking = m } label: { MoveRow(move: m) }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Remove", systemImage: "trash", role: .destructive) { read?.moves.removeAll { $0.id == m.id } }
                    }
            }
            Text("Long press a move to remove it. Sets, reps and rest can be changed after saving, in My workouts.")
                .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
        }
    }

    private func sourceChip(_ s: WorkoutSource) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "play.rectangle.fill")
            Text(s.label).lineLimit(1)
            Spacer(minLength: 4)
            if let url = s.link {
                Link(destination: url) { Label("Open", systemImage: "arrow.up.right").labelStyle(.titleAndIcon) }
            }
        }
        .font(Theme.label(12))
        .foregroundStyle(.white)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black.opacity(0.25)))
    }

    // MARK: Actions

    @ViewBuilder private var bottomBar: some View {
        if let r = read {
            let w = workout(r)
            HStack(spacing: 8) {
                if let weekday {
                    Button("Save only") { save(w, to: nil) }
                        .buttonStyle(LimeButtonStyle(fill: Theme.cardStrong, text: .white))
                    Button("Add to \(WeekSchedule.shortName(weekday))") { save(w, to: weekday) }
                        .buttonStyle(LimeButtonStyle())
                } else {
                    Button("Do it today") { save(w, to: model.todayWeekday) }
                        .buttonStyle(LimeButtonStyle(fill: Theme.cardStrong, text: .white))
                    Button("Save workout") { save(w, to: nil) }
                        .buttonStyle(LimeButtonStyle())
                }
            }
            .disabled(w.items.isEmpty)
        } else {
            Button {
                typing = false
                ProStore.shared.run(.videoImport, $gate) { readIt() }
            } label: {
                if reading {
                    HStack(spacing: 8) { ProgressView().tint(Theme.ink); Text("Coach is reading…") }
                } else {
                    Label("Read it", systemImage: "sparkles")
                }
            }
            .buttonStyle(LimeButtonStyle())
            .disabled(!hasInput || reading)
            .accessibilityIdentifier("videoImport.read")
        }
    }

    private func workout(_ r: VideoImportRead) -> CustomWorkout {
        CustomWorkout(importing: name.trimmed.isEmpty ? r.name : name, moves: r.moves, source: r.source)
    }

    private func readIt() {
        notice = nil
        reading = true
        let photos = draft.photos.compactMap(GymScanSheet.jpeg)
        let link = draft.link.trimmed, caption = draft.caption.trimmed, text = words.trimmed
        Task {
            defer { reading = false }
            do {
                let r = try await model.readVideoWorkout(link: link.isEmpty ? nil : link, caption: caption.isEmpty ? nil : caption,
                                                         text: text.isEmpty ? nil : text, photos: photos)
                name = r.name
                withAnimation(.snappy) { read = r }
            } catch APIError.server(_, _, let message) {
                notice = message
            } catch {
                notice = "Couldn't reach Coach. Check your connection and try again."
            }
        }
    }

    private func save(_ w: CustomWorkout, to day: Int?) {
        let saved = model.saveCustomWorkout(w)
        if let day { model.addExtra(saved, weekday: day) }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onDone?()
        dismiss()
    }

    private func loadPhotos() {
        let items = photoItems
        guard !items.isEmpty else { return }
        photoItems = []
        Task {
            for item in items {
                guard draft.photos.count < 4 else { break }
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) { draft.photos.append(img) }
            }
        }
    }
}

/// One move read from the video: matched (exercise colours, lime tick), near (dashed yellow, "check") or unknown.
private struct MoveRow: View {
    let move: ImportedMove

    var body: some View {
        let e = move.exercise
        let measure = e.map(CustomWorkout.Measure.init)
        let item = move.item
        HStack(spacing: 10) {
            IconTile(symbol: e?.category.symbol ?? "questionmark", size: 38, ink: move.sure && e?.category.isLight == true)
            VStack(alignment: .leading, spacing: 2) {
                Text(move.sure ? (e?.name ?? move.said) : "\u{201C}\(move.said)\u{201D}").font(Theme.label(15)).lineLimit(2)
                if let item, let measure {
                    Text((item.sets > 1 ? "\(item.sets) × " : "") + measure.text(item.reps) + (move.sure || e == nil ? "" : " · closest: \(e!.name)"))
                        .font(.caption.weight(.bold)).opacity(0.85).lineLimit(2)
                } else {
                    Text("Not in the app yet · tap to pick an exercise").font(.caption.weight(.bold)).opacity(0.85)
                }
            }
            Spacer(minLength: 4)
            Text(move.sure ? "✓ matched" : "check")
                .font(Theme.label(10))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Capsule().fill(move.sure ? Theme.lime : Color(hex: 0xFFE14D)))
        }
        .padding(10)
        .foregroundStyle(move.sure ? (e?.category.ink ?? .white) : .white)
        .background {
            if move.sure, let e {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(e.category.gradient)
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color(hex: 0xFFE14D), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint(move.sure ? "Change the exercise" : "Pick the exercise")
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
