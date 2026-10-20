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
            do { try await action() } catch is CancellationError {
                // Closed the "Confirm it's you" sheet or a system prompt: nothing to report (#257).
            } catch { self.error = error.localizedDescription }
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

    /// Lifted volume, one style app-wide (History, Progress, shared cards): kilos below a tonne ("850 kg"),
    /// then tonnes with one decimal ("6.5 t"), whole grouped tonnes from 100 t ("1,240 t").
    static func volume(_ kg: Double) -> String {
        let p = volumeParts(kg)
        return "\(p.value) \(p.unit)"
    }

    static func volumeParts(_ kg: Double) -> (value: String, unit: String) {
        let number = FloatingPointFormatStyle<Double>(locale: Locale(identifier: "en_US"))
        let v = max(0, kg)
        if v < 1000 { return (v.rounded().formatted(number.precision(.fractionLength(0))), "kg") }
        let t = v / 1000
        return (t.formatted(number.precision(.fractionLength(t >= 100 ? 0 : 1))), "t")
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

/// X that closes a sheet (#149): top right, so it never covers the sheet's title.
/// Standard sheet chrome (#539): sheets that create something new put a lime `SaveToolbarItem` just before it;
/// sheets editing something that exists auto-save (`.autoSave`) and have the X only.
struct CloseToolbarItem: ToolbarContent {
    var placement: ToolbarItemPlacement = .topBarTrailing
    let action: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: placement) {
            Button(action: action) {
                Image(systemName: "xmark").font(.system(size: 15, weight: .bold))
            }
            .accessibilityLabel("Close")
        }
    }
}

/// Menu picker row with the label on top and the value large under it (#281): long values get the full width
/// instead of wrapping beside the label, so every row keeps the same height.
struct StackedMenuRow<Content: View>: View {
    let title: String
    let value: String
    @ViewBuilder let options: () -> Content

    var body: some View {
        Menu(content: options) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).eyebrow()
                HStack(spacing: 8) {
                    Text(value).font(Theme.display(18)).foregroundStyle(Theme.lime)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(Theme.lime.opacity(0.8))
                }
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

// MARK: - Standard sheet chrome (#539)

/// Lime Save beside the close X, only on sheets that create something new (existing records auto-save).
/// Declare it before `CloseToolbarItem` so the X stays in the corner.
struct SaveToolbarItem: ToolbarContent {
    var title = "Save"
    var disabled = false
    let action: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button(action: action) {
                Text(title).font(Theme.label(15)).foregroundStyle(disabled ? Theme.muted : Theme.ink)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.lime)
            .disabled(disabled)
        }
    }
}

/// Heavy screen title drawn in the content (#539), so it never sits under the toolbar's glass buttons.
struct ContentTitle: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Theme.display(30)).foregroundStyle(.white)
                .lineLimit(2).minimumScaleFactor(0.7)
            if let subtitle {
                Text(subtitle).font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    /// Pairs with a `ContentTitle` at the top of the content: keeps `title` for the back button and VoiceOver
    /// but draws nothing in the navigation bar.
    func titleInContent(_ title: String) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) }
            }
    }

    /// List row drawn as an Explore-style gradient card (#539) in place of the grey grouped row.
    func gradientRow(_ gradient: LinearGradient, ink: Color = .white) -> some View {
        foregroundStyle(ink)
            .padding(.vertical, 4)
            .listRowBackground(
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(gradient)
                    .padding(.vertical, 4).padding(.horizontal, 16)
            )
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: 28, bottom: 8, trailing: 28))
    }

    /// List row drawn as a dark card (#539), for rows that aren't a coloured item (presets, notes, actions).
    func darkCardRow() -> some View {
        padding(.vertical, 2)
            .listRowBackground(
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card)
                    .padding(.vertical, 4).padding(.horizontal, 16)
            )
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: 28, bottom: 8, trailing: 28))
    }
}

/// Square on/off mark (#539): the rounded-square toggle on gradient rows. Not a control by itself.
struct SquareToggle: View {
    let on: Bool
    var ink: Color = .white

    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(on ? ink : ink.opacity(0.22))
            .frame(width: 26, height: 26)
            .overlay {
                Image(systemName: on ? "checkmark" : "plus")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(on ? (ink == .white ? Theme.ink : Color.white) : ink)
            }
            .accessibilityHidden(true)
    }
}

/// Red gradient card with Retry (#539), in place of a value that didn't load or a request that failed.
struct InlineErrorCard: View {
    let title: String
    var message: String? = nil
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .bold))
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.2)))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Theme.label(14))
                if let message { Text(message).font(.caption.weight(.semibold)).opacity(0.85).lineLimit(2) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: retry) {
                Text("Retry").font(Theme.label(13)).foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(SavedPill.failure))
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Retry", retry)
    }
}
