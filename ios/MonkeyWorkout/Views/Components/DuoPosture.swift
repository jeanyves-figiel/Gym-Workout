import CoreMotion
import SwiftUI
import UIKit

/// How an iPhone Duo is held (#598): flat (open or folded, held normally), Flex (half open on a table, landscape:
/// top half to watch, bottom half to tap), Book (half open, portrait: left and right pages) or Tent (half open,
/// stood on the floor, read from a distance). Other iPhones are always `.flat`.
enum DuoPosture: String {
    case flat, flex, book, tent

    /// DEBUG `-duoPosture flex|book|tent`: the simulator has no hinge, so CI screenshots force one.
    static var forced: DuoPosture? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-duoPosture"), args.indices.contains(i + 1) { return DuoPosture(rawValue: args[i + 1]) }
        #endif
        return nil
    }
}

extension View {
    /// Keeps `posture` in step with the hinge (iOS 27.1 `UIHingeInteraction`). Half open + landscape is Flex; half open
    /// + portrait is Book, or Tent once the phone has been still for a few seconds (stood up, not held). iOS has no tent
    /// status, so stillness is the tell. A forced DEBUG posture wins.
    func duoPosture(_ posture: Binding<DuoPosture>) -> some View {
        modifier(DuoPostureReader(posture: posture))
    }
}

private struct DuoPostureReader: ViewModifier {
    @Binding var posture: DuoPosture
    @State private var halfOpen = false
    @State private var landscape = false
    @State private var still = StillDetector()

    func body(content: Content) -> some View {
        content
            .background { if DuoPosture.forced == nil { HingeView { halfOpen = $0 }.allowsHitTesting(false) } }
            .onGeometryChange(for: Bool.self) { $0.size.width > $0.size.height } action: {
                landscape = $0
                update()
            }
            .onChange(of: halfOpen) { _, open in
                if open { still.start { _ in update() } } else { still.stop() }
                update()
            }
            .onDisappear { still.stop() }
    }

    private func update() {
        if let forced = DuoPosture.forced { return posture = forced }
        guard halfOpen else { return posture = .flat }
        posture = landscape ? .flex : (still.isStill ? .tent : .book)
    }
}

/// Hosts the `UIHingeInteraction`; reports whether the hinge is partially open. Before iOS 27.1, never.
private struct HingeView: UIViewRepresentable {
    let onChange: (Bool) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        if #available(iOS 27.1, *) {
            view.addInteraction(UIHingeInteraction { _, update in
                onChange(update.hinge?.status == .partiallyOpen)
            })
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// Device motion at 5 Hz while the hinge is half open: still for 3 s → tent; a nudge → held again.
@Observable
private final class StillDetector {
    private(set) var isStill = false
    /// Made on the first start (#720): `@State` builds a detector on every view init, most never start.
    @ObservationIgnored private var motion: CMMotionManager?
    @ObservationIgnored private var quietSince: Date?

    func start(_ changed: @escaping (Bool) -> Void) {
        let motion = self.motion ?? CMMotionManager()
        self.motion = motion
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 0.2
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let a = data?.userAcceleration else { return }
            let moving = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot() > 0.03
            let now = Date()
            if moving { quietSince = nil } else if quietSince == nil { quietSince = now }
            let still = quietSince.map { now.timeIntervalSince($0) >= 3 } ?? false
            if still != isStill {
                isStill = still
                changed(still)
            }
        }
    }

    func stop() {
        motion?.stopDeviceMotionUpdates()
        quietSince = nil
        isStill = false
    }
}
