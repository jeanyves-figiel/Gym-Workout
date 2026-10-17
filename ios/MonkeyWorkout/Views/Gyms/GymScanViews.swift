import APIClient
import PhotosUI
import SwiftUI
import WorkoutEngine
#if canImport(RoomPlan)
import RoomPlan
#endif

// Gym Map (#406): set up the gym by looking at it. Scan: pick a zone, take a photo of that area, the photo AI lists
// the equipment on it, one tap adds it all to the zone. Room scan (LiDAR iPhones): walk the walls once, the map
// gets the real room size and the entrance.

/// Photo scan of one area at a time.
struct GymScanSheet: View {
    @Binding var layout: GymLayout
    /// Items found that the gym list doesn't have yet.
    let onFound: ([Equipment]) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var zoneId: String?
    @State private var camera = false
    @State private var photoItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var scanning = false
    @State private var found: [Equipment] = []
    @State private var picked: Set<Equipment> = []
    @State private var notice: String?
    @State private var added = 0

    private var zone: GymLayout.Zone? { zoneId.flatMap { layout.zone(id: $0) } ?? layout.zones.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Pick the area, take a photo of it, and the equipment lands in that zone.")
                        .font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
                    FlowLayout(spacing: 6) {
                        ForEach(layout.zones) { z in
                            Button { zoneId = z.id; reset() } label: {
                                Text(z.name).font(Theme.label(12)).foregroundStyle(.white)
                                    .padding(.horizontal, 10).padding(.vertical, 7)
                                    .background(Capsule().fill(z.gradient))
                                    .overlay(Capsule().strokeBorder(.white, lineWidth: zone?.id == z.id ? 2.5 : 0))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    viewfinder
                    if !found.isEmpty, let zone { results(zone) }
                    if let notice {
                        Label(notice, systemImage: "exclamationmark.circle.fill").font(.footnote.weight(.bold)).foregroundStyle(.yellow)
                    }
                    if added > 0 {
                        Label("\(added) placed so far. Pick the next area.", systemImage: "checkmark.seal.fill")
                            .font(.footnote.weight(.bold)).foregroundStyle(Theme.lime)
                    }
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Scan your gym")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .fullScreenCover(isPresented: $camera) {
                CameraPicker { if let img = $0 { scan(img) } }.ignoresSafeArea()
            }
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

    /// Photo (or the prompt to take one), with boxes-style scanning overlay while the AI reads it.
    private var viewfinder: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                LinearGradient(colors: zone?.colors ?? [Theme.card, Theme.card], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "camera.viewfinder").font(.system(size: 44, weight: .bold))
                            Text("Photo of \(zone?.name ?? "this area")").font(Theme.display(18))
                        }
                        .foregroundStyle(.white)
                    )
            }
            if scanning {
                RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.lime, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .padding(20)
                ProgressView("Spotting equipment…").tint(.white).foregroundStyle(.white)
                    .padding(12).background(Capsule().fill(.black.opacity(0.6)))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(alignment: .bottom) {
            HStack(spacing: 8) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { camera = true } label: { Label("Take photo", systemImage: "camera.fill") }
                        .buttonStyle(LimeButtonStyle())
                }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Library", systemImage: "photo.on.rectangle")
                        .font(Theme.label(14)).padding(.horizontal, 14).padding(.vertical, 12)
                        .background(Capsule().fill(.black.opacity(0.55)))
                }
            }
            .padding(12)
            .disabled(scanning)
        }
    }

    private func results(_ zone: GymLayout.Zone) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Found \(found.count)").font(Theme.display(22))
            FlowLayout(spacing: 6) {
                ForEach(found) { e in
                    let on = picked.contains(e)
                    Button { if on { picked.remove(e) } else { picked.insert(e) } } label: {
                        Label(e.label, systemImage: on ? "checkmark.circle.fill" : e.symbol)
                            .font(Theme.label(12))
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(Capsule().fill(.black.opacity(on ? 0.35 : 0.15)))
                            .opacity(on ? 1 : 0.6)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button {
                let items = found.filter { picked.contains($0) }
                onFound(items)
                for e in items { layout.move(e, to: zone.id) }
                added += items.count
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                reset()
            } label: {
                Label("Put \(picked.count) in \(zone.name)", systemImage: "arrow.down.to.line")
            }
            .buttonStyle(LimeButtonStyle())
            .disabled(picked.isEmpty)
        }
        .gradientCard(zone.gradient, padding: 14)
    }

    private func reset() {
        image = nil
        found = []
        picked = []
        notice = nil
    }

    private func scan(_ photo: UIImage) {
        reset()
        image = photo
        guard let jpeg = Self.jpeg(photo) else { notice = "Couldn't read that photo."; return }
        scanning = true
        Task {
            defer { scanning = false }
            do {
                found = try await model.scanGym(jpeg: jpeg)
                picked = Set(found)
                if found.isEmpty { notice = "No equipment spotted. Try a wider shot of the area." }
            } catch APIError.server(_, _, let message) {
                notice = message
            } catch {
                notice = "Couldn't reach the server. Check your connection and try again."
            }
        }
    }

    /// Longest side 1280 px, JPEG under 1.4 MB.
    static func jpeg(_ image: UIImage) -> Data? {
        let side: CGFloat = 1280
        let scale = min(1, side / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        for q in [0.7, 0.5, 0.35] as [CGFloat] {
            if let d = small.jpegData(compressionQuality: q), d.count < 1_400_000 { return d }
        }
        return nil
    }
}

/// Room scan with LiDAR: real room size and the entrance for the map.
enum RoomScan {
    static var supported: Bool {
        #if canImport(RoomPlan) && !targetEnvironment(simulator)
        return RoomCaptureSession.isSupported
        #else
        return false
        #endif
    }

    /// Room size (metres) and the entrance (unit square, on a wall) measured by a scan.
    struct Result {
        var sizeM: GymLayout.Point
        var door: GymLayout.Point?
    }
}

#if canImport(RoomPlan) && !targetEnvironment(simulator)
/// Full-screen RoomPlan capture; Done finishes the scan and hands back the room's size and entrance.
struct RoomScanView: View {
    let onResult: (RoomScan.Result?) -> Void
    @State private var finish = false

    var body: some View {
        ZStack(alignment: .bottom) {
            RoomCaptureRepresentable(finish: $finish, onResult: onResult).ignoresSafeArea()
            VStack(spacing: 10) {
                Text("Walk slowly along the walls, phone up. Include the entrance.")
                    .font(Theme.label(13)).multilineTextAlignment(.center)
                    .padding(10).background(Capsule().fill(.black.opacity(0.6)))
                HStack {
                    Button("Cancel") { onResult(nil) }
                        .font(Theme.label(15)).padding(.horizontal, 18).padding(.vertical, 12)
                        .background(Capsule().fill(.black.opacity(0.6)))
                    Button("Done") { finish = true }.buttonStyle(LimeButtonStyle())
                }
            }
            .foregroundStyle(.white)
            .padding(20)
        }
    }
}

private struct RoomCaptureRepresentable: UIViewRepresentable {
    @Binding var finish: Bool
    let onResult: (RoomScan.Result?) -> Void

    func makeUIView(context: Context) -> RoomCaptureView {
        let v = RoomCaptureView(frame: .zero)
        v.delegate = context.coordinator
        v.captureSession.run(configuration: RoomCaptureSession.Configuration())
        return v
    }

    func updateUIView(_ v: RoomCaptureView, context: Context) {
        if finish, !context.coordinator.stopped {
            context.coordinator.stopped = true
            v.captureSession.stop()
        }
    }

    static func dismantleUIView(_ v: RoomCaptureView, coordinator: Coordinator) {
        if !coordinator.stopped { v.captureSession.stop() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onResult: onResult) }

    // RoomCaptureViewDelegate is NSCoding: a nested class needs a stable Objective-C name to archive.
    @objc(MWRoomCaptureCoordinator)
    final class Coordinator: NSObject, RoomCaptureViewDelegate {
        let onResult: (RoomScan.Result?) -> Void
        var stopped = false

        init(onResult: @escaping (RoomScan.Result?) -> Void) { self.onResult = onResult }

        // RoomCaptureViewDelegate inherits NSCoding; the coordinator is never archived.
        required init?(coder _: NSCoder) { nil }
        func encode(with _: NSCoder) {}

        func captureView(shouldPresent _: CapturedRoomData, error _: Error?) -> Bool { true }

        func captureView(didPresent room: CapturedRoom, error: Error?) {
            onResult(error == nil ? Self.measure(room) : nil)
        }

        /// Bounding box of the walls on the floor plane; the first door (or opening) as the entrance.
        static func measure(_ room: CapturedRoom) -> RoomScan.Result? {
            var xs: [Float] = [], zs: [Float] = []
            for w in room.walls {
                let c = w.transform.columns.3, d = w.transform.columns.0
                let half = w.dimensions.x / 2
                xs += [c.x - d.x * half, c.x + d.x * half]
                zs += [c.z - d.z * half, c.z + d.z * half]
            }
            guard let minX = xs.min(), let maxX = xs.max(), let minZ = zs.min(), let maxZ = zs.max(),
                  maxX - minX > 1, maxZ - minZ > 1 else { return nil }
            let size = GymLayout.Point(x: Double(maxX - minX), y: Double(maxZ - minZ))
            let entrance = (room.doors.first ?? room.openings.first).map { s -> GymLayout.Point in
                let c = s.transform.columns.3
                return GymLayout.Point(x: Double((c.x - minX) / (maxX - minX)), y: Double((c.z - minZ) / (maxZ - minZ))).onWall
            }
            return RoomScan.Result(sizeM: size, door: entrance)
        }
    }
}
#endif
