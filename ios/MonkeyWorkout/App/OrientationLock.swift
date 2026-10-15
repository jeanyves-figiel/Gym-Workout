import UIKit

/// iPhone stays upright everywhere except the workout player (#362), where the phone may lie on its side on a
/// machine or rack. iPad keeps every orientation (#120).
@MainActor
enum OrientationLock {
    private(set) static var landscapeAllowed = false

    static var mask: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .pad { return .all }
        return landscapeAllowed ? .allButUpsideDown : .portrait
    }

    /// Lets the screen turn with the phone (player on screen) or puts it back upright (player closed).
    static func allowLandscape(_ on: Bool) {
        guard landscapeAllowed != on else { return }
        landscapeAllowed = on
        guard UIDevice.current.userInterfaceIdiom != .pad,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        var vc = scene.keyWindow?.rootViewController
        while let c = vc {
            c.setNeedsUpdateOfSupportedInterfaceOrientations()
            vc = c.presentedViewController
        }
        if !on { scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in } }
    }
}
