import UIKit

/// The app's few haptics (#541), one place so the same moment always feels the same.
@MainActor
enum Haptics {
    /// A workout starts.
    static func start() { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
    /// A change was saved.
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    /// The Undo bar appeared, or Undo was tapped.
    static func undo() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    /// Something was deleted, or a save failed.
    static func destructive() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}
