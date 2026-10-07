import SwiftUI
import WorkoutEngine

/// Runs an async action with busy + error state for forms.
@MainActor @Observable
final class FormTask {
    var busy = false
    var error: String?

    func run(_ action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do { try await action() } catch { self.error = error.localizedDescription }
        }
    }
}

struct ErrorText: View {
    let message: String?
    var body: some View {
        if let message {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }
}

struct BusyButton: View {
    let title: String
    let busy: Bool
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Spacer()
                if busy { ProgressView() } else { Text(title).bold() }
                Spacer()
            }
        }
        .disabled(busy || disabled)
    }
}

extension BlockKind {
    var color: Color { category.color }

    var short: String {
        switch self {
        case .warmup: "Warm-up"
        case .power: "Power"
        case .strength: "Strength"
        case .mobility: "Mobility"
        case .cardio: "Cardio"
        case .cooldown: "Stretch"
        }
    }
}

enum Format {
    static func rest(_ sec: Int) -> String {
        sec >= 60 ? String(format: "%d:%02d", sec / 60, sec % 60) : "\(sec) s"
    }

    static func prescription(_ p: Prescription) -> String {
        var parts = [p.sets > 1 ? "\(p.sets) × \(p.reps)" : p.reps]
        if p.restSec > 0 { parts.append("rest \(rest(p.restSec))") }
        return parts.joined(separator: " · ")
    }

    static func elapsed(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    static func count(_ v: Double) -> String {
        v >= 10_000 ? String(format: "%.0fk", v / 1000) : String(Int(v.rounded()))
    }

    static func kg(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(format: "%.1f", v)
    }
}

/// Password rules mirrored from the API so users get instant feedback.
enum PasswordRules {
    static func problem(_ pw: String) -> String? {
        if pw.isEmpty { return nil }
        if pw.count < 10 { return "At least 10 characters." }
        if pw.count > 128 { return "At most 128 characters." }
        return nil
    }
}
