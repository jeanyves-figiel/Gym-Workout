import SwiftUI
import UIKit

// MARK: - Auto save (#437, design A + C from `auto-save/proposals.png`)
//
// Screens that edit something that already exists save on their own, no Save button. A: a lime pill in the
// navigation bar reads "Saving…" while a change waits (short debounce) and "Saved" once written. C: leaving
// the screen after a change shows the gradient Undo bar (#285) with what changed; Undo puts the values the
// screen opened with back. Screens opt in with `.autoSave(_:title:detail:save:)`.
// A save that throws turns the pill into a red "Couldn't save · Retry" (#539); the change stays on screen.

enum AutoSaveStatus: Equatable { case idle, saving, saved, failed }

extension View {
    /// Saves `value` a moment after each change, flushes on leave, shows the Saved pill and offers Undo on close.
    /// `value` is nil until the screen has loaded; the first non-nil value is what Undo goes back to.
    /// `save` gets the value only: it must not read the screen's `@State` (Undo calls it after the screen is gone).
    /// When it throws, the pill shows "Couldn't save · Retry".
    /// `committed` runs once when the screen closes after a change (e.g. writing to Apple Health).
    func autoSave<V: Equatable>(_ value: V?, title: String, symbol: String = "checkmark",
                                detail: @escaping (V) -> String = { _ in "" },
                                save: @escaping @MainActor (V) async throws -> Void,
                                committed: ((V) -> Void)? = nil) -> some View {
        modifier(AutoSaveModifier(value: value, title: title, symbol: symbol, detail: detail, save: save, committed: committed))
    }
}

private struct AutoSaveModifier<V: Equatable>: ViewModifier {
    let value: V?
    let title: String
    let symbol: String
    let detail: (V) -> String
    let save: @MainActor (V) async throws -> Void
    let committed: ((V) -> Void)?

    @State private var original: V?
    @State private var lastSaved: V?
    @State private var status: AutoSaveStatus = .idle
    @State private var pending: Task<Void, Never>?
    @State private var closeGuard = CloseGuard()

    static var delay: Duration { .milliseconds(700) }

    func body(content: Content) -> some View {
        content
            .toolbar {
                if status != .idle {
                    ToolbarItem(placement: .topBarTrailing) { SavedPill(status: status, retry: flush) }
                }
            }
            .onAppear {
                if original == nil, let value { original = value; lastSaved = value }
            }
            .onChange(of: value) { _, new in
                guard let new else { return }
                guard original != nil else { original = new; lastSaved = new; return }
                guard new != lastSaved else { return }
                withAnimation(.snappy) { status = .saving }
                pending?.cancel()
                pending = Task { @MainActor in
                    try? await Task.sleep(for: Self.delay)
                    guard !Task.isCancelled else { return }
                    flush()
                }
            }
            .onDisappear {
                pending?.cancel()
                flush()
            }
            .undoableClose(closeGuard, offer: offer)
            .background(CommitProbe(onClose: commit))
    }

    private func flush() {
        guard let value, value != lastSaved else { return }
        let previous = lastSaved
        lastSaved = value
        withAnimation(.snappy) { status = .saving }
        let save = save
        Task { @MainActor in
            do {
                try await save(value)
                withAnimation(.snappy) { status = .saved }
                Haptics.success()
                UIAccessibility.post(notification: .announcement, argument: "Saved")
            } catch {
                // Not written: the next change or Retry tries again.
                lastSaved = previous
                withAnimation(.snappy) { status = .failed }
                Haptics.destructive()
                UIAccessibility.post(notification: .announcement, argument: "Couldn't save. Retry available.")
            }
        }
    }

    private func commit() {
        guard let value, let original, value != original else { return }
        committed?(value)
    }

    /// Undo bar on leave, only when something changed since the screen opened.
    private var offer: UndoOffer? {
        guard let value, let original, value != original else { return nil }
        let save = save
        return UndoOffer(title: "\(title) saved", detail: detail(value), symbol: symbol,
                         reopen: { AnyView(EmptyView()) }, revert: { Task { @MainActor in try? await save(original) } })
    }
}

/// Runs `onClose` when the screen holding it is really closed (not just covered).
private struct CommitProbe: UIViewControllerRepresentable {
    let onClose: () -> Void
    func makeUIViewController(context: Context) -> Probe { Probe() }
    func updateUIViewController(_ vc: Probe, context: Context) { vc.onClose = onClose }

    final class Probe: UIViewController {
        var onClose: (() -> Void)?
        override func loadView() { view = UIView(); view.isUserInteractionEnabled = false }
        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            var vc: UIViewController? = self
            while let current = vc {
                if current.isBeingDismissed || current.isMovingFromParent { onClose?(); return }
                vc = current.parent
            }
        }
    }
}

/// Design A: lime pill, "Saving…" with a spinner, then "Saved" with a tick. A failed save (#539): red gradient
/// "Couldn't save · Retry" that saves again when tapped.
struct SavedPill: View {
    let status: AutoSaveStatus
    var retry: () -> Void = {}

    static let failure = LinearGradient(colors: [Color(red: 1, green: 0.23, blue: 0.19), Color(red: 1, green: 0.18, blue: 0.43)],
                                        startPoint: .leading, endPoint: .trailing)

    var body: some View {
        if status == .failed {
            Button(action: retry) {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10, weight: .black))
                    Text("Couldn't save · ").font(Theme.label(12)) + Text("Retry").font(Theme.label(12)).underline()
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Self.failure))
                .fixedSize()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Couldn't save")
            .accessibilityHint("Tries saving again")
        } else {
            HStack(spacing: 5) {
                if status == .saving {
                    ProgressView().controlSize(.mini).tint(Theme.lime)
                } else {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .black))
                }
                Text(status == .saving ? "Saving…" : "Saved").font(Theme.label(12))
            }
            .foregroundStyle(Theme.lime)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(Theme.lime.opacity(0.15)))
            .fixedSize()
            .contentTransition(.opacity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(status == .saving ? "Saving" : "All changes saved")
        }
    }
}

// MARK: - Drafts that survive closing (#437)
//
// Screens that create something new keep their Save / Add button, but what's typed is kept on the device
// while the screen is open: closing it, or the app being killed, keeps the draft. Opening the screen again
// brings it back with a "Draft restored · Start fresh" strip. Saving clears it.

enum DraftStore {
    private static let prefix = "draft."

    static func load<D: Decodable>(_ key: String, as: D.Type = D.self) -> D? {
        guard let data = UserDefaults.standard.data(forKey: prefix + key) else { return nil }
        return try? JSONDecoder().decode(D.self, from: data)
    }

    static func save<D: Encodable>(_ key: String, _ draft: D) {
        guard let data = try? JSONEncoder().encode(draft) else { return }
        UserDefaults.standard.set(data, forKey: prefix + key)
    }

    static func clear(_ key: String) { UserDefaults.standard.removeObject(forKey: prefix + key) }
}

extension View {
    /// Keeps `value` on the device under `key` while it differs from `blank` (nil key: not kept).
    func keepsDraft<D: Codable & Equatable>(_ key: String?, _ value: D, blank: D) -> some View {
        onChange(of: value) { _, v in
            guard let key else { return }
            if v == blank { DraftStore.clear(key) } else { DraftStore.save(key, v) }
        }
    }
}

/// "Draft restored" strip with Start fresh, shown at the top of a screen that brought a draft back.
struct DraftRestoredStrip: View {
    let startFresh: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.badge.clock.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.ink)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.ink.opacity(0.12)))
            VStack(alignment: .leading, spacing: 1) {
                Text("Draft restored").font(Theme.label(14))
                Text("Picked up where you left off.").font(.caption.weight(.semibold)).opacity(0.75)
            }
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Start fresh", action: startFresh)
                .font(Theme.label(13))
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Capsule().fill(Theme.ink))
                .buttonStyle(.plain)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.lime))
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Start fresh", startFresh)
    }
}
