import APIClient
import AVFoundation
import Observation
import SwiftUI
import WorkoutEngine

/// Coach voice picks (#395): female / male, accent, and the studio voice ("" = the best iPhone voice).
enum CoachVoicePref {
    static let genderKey = "coach.voiceGender"
    static let accentKey = "coach.voiceAccent"
    static let studioKey = "coach.studioVoice"

    static var gender: String { UserDefaults.standard.string(forKey: genderKey) ?? "female" }
    static var accent: String { UserDefaults.standard.string(forKey: accentKey) ?? "us" }
    static var studio: String { UserDefaults.standard.string(forKey: studioKey) ?? "" }

    static let accents: [(id: String, flag: String, title: String, language: String)] = [
        ("us", "🇺🇸", "American", "en-US"), ("gb", "🇬🇧", "British", "en-GB"), ("au", "🇦🇺", "Australian", "en-AU"),
        ("ie", "🇮🇪", "Irish", "en-IE"), ("in", "🇮🇳", "Indian", "en-IN"), ("za", "🇿🇦", "South African", "en-ZA"),
        ("nz", "🇳🇿", "New Zealand", "en-NZ"),
    ]

    static func language(_ accent: String) -> String { accents.first { $0.id == accent }?.language ?? "en-US" }

    /// Fallback (A): the best installed English voice for the pick, never a novelty voice; premium > enhanced > basic.
    static func bestSystemVoice(gender: String = gender, accent: String = accent) -> AVSpeechSynthesisVoice? {
        let english = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.hasPrefix("en") && !$0.voiceTraits.contains(.isNoveltyVoice) && !$0.voiceTraits.contains(.isPersonalVoice)
        }
        let want: AVSpeechSynthesisVoiceGender = gender == "male" ? .male : .female
        func score(_ v: AVSpeechSynthesisVoice) -> Int {
            let quality = switch v.quality {
            case .premium: 300
            case .enhanced: 200
            default: 100
            }
            return quality + (v.language == language(accent) ? 50 : 0) + (v.gender == want ? 30 : 0)
        }
        return english.max { score($0) < score($1) }
    }

    static func qualityTitle(_ v: AVSpeechSynthesisVoice) -> String {
        switch v.quality {
        case .premium: "Premium"
        case .enhanced: "Enhanced"
        default: "Basic"
        }
    }
}

/// Studio voice packs (#395, design B from `workout-coach/voices.png`): the coach's lines recorded with Amazon Polly
/// neural voices on the server, downloaded once per voice into Application Support, then played offline.
@MainActor @Observable
final class CoachVoiceStore {
    static let shared = CoachVoiceStore()

    private(set) var catalog: CoachVoiceCatalog?
    /// Voices with every line on the device.
    private(set) var ready: Set<String> = []
    /// Download progress 0…1 per voice.
    private(set) var progress: [String: Double] = [:]
    private(set) var failed: String?

    private static let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("coach-voices", isDirectory: true)
    private static var catalogURL: URL { dir.appendingPathComponent("catalog.json") }

    private init() {
        if let data = try? Data(contentsOf: Self.catalogURL), let c = try? JSONDecoder().decode(CoachVoiceCatalog.self, from: data) {
            catalog = c
            ready = Set(c.voices.map(\.id).filter(isComplete))
        }
    }

    private func file(_ voice: String, _ line: CoachVoiceCatalog.Line) -> URL {
        Self.dir.appendingPathComponent(voice, isDirectory: true).appendingPathComponent("\(line.hash).mp3")
    }

    private func isComplete(_ voice: String) -> Bool {
        guard let lines = catalog?.lines, !lines.isEmpty else { return false }
        return lines.allSatisfy { FileManager.default.fileExists(atPath: file(voice, $0).path) }
    }

    func refresh(model: AppModel) async {
        #if DEBUG
        if model.demo {
            catalog = Demo.coachVoices
            ready = ["Arthur"]
            return
        }
        #endif
        guard let c = try? await model.api.coachVoices() else { return }
        catalog = c
        try? FileManager.default.createDirectory(at: Self.dir, withIntermediateDirectories: true)
        try? JSONEncoder().encode(c).write(to: Self.catalogURL)
        // Lines changed on the server: a pack missing new recordings is no longer ready until downloaded again.
        ready = Set(c.voices.map(\.id).filter(isComplete))
    }

    /// Downloads the lines of `voice` not on the device yet, 4 at a time.
    func download(_ voice: String, model: AppModel) async -> Bool {
        guard let lines = catalog?.lines, progress[voice] == nil else { return false }
        failed = nil
        let folder = Self.dir.appendingPathComponent(voice, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let missing = lines.filter { !FileManager.default.fileExists(atPath: file(voice, $0).path) }
        var done = lines.count - missing.count
        progress[voice] = Double(done) / Double(max(1, lines.count))
        let api = model.api
        var ok = true
        // Four at a time; stop at the first failure (offline, server error).
        var index = 0
        while ok, index < missing.count {
            let chunk = Array(missing[index..<min(missing.count, index + 4)])
            index += chunk.count
            let results = await withTaskGroup(of: (CoachVoiceCatalog.Line, Data?).self) { group in
                for line in chunk {
                    group.addTask { (line, try? await api.coachVoiceLine(voice: voice, line: line.id)) }
                }
                var out: [(CoachVoiceCatalog.Line, Data?)] = []
                for await r in group { out.append(r) }
                return out
            }
            for (line, data) in results {
                if let data, !data.isEmpty {
                    try? data.write(to: file(voice, line), options: .atomic)
                } else {
                    ok = false
                }
            }
            done += chunk.count
            progress[voice] = Double(done) / Double(max(1, lines.count))
        }
        progress[voice] = nil
        if ok, isComplete(voice) {
            ready.insert(voice)
            return true
        }
        failed = voice
        return false
    }

    func remove(_ voice: String) {
        try? FileManager.default.removeItem(at: Self.dir.appendingPathComponent(voice, isDirectory: true))
        ready.remove(voice)
        if CoachVoicePref.studio == voice { UserDefaults.standard.set("", forKey: CoachVoicePref.studioKey) }
    }

    /// A recorded line for the moment in the picked studio voice, if its pack is on the device.
    func clip(style: CoachStyle, kind: String, seed: Int, voice: String = CoachVoicePref.studio) -> (text: String, url: URL)? {
        guard !voice.isEmpty, ready.contains(voice), let lines = catalog?.lines else { return nil }
        let prefix = "\(style.rawValue)-\(kind)-"
        let options = lines.filter { $0.id.hasPrefix(prefix) }
        guard !options.isEmpty else { return nil }
        let line = options[abs(seed) % options.count]
        let url = file(voice, line)
        return FileManager.default.fileExists(atPath: url.path) ? (line.text, url) : nil
    }
}

// MARK: - Settings section

/// Coach voice picker (#395): Female / Male, accent flags, the studio voices for that pick (Get / ▶ / ✓) and the best
/// iPhone voice as the fallback.
struct CoachVoicePicker: View {
    let style: CoachStyle
    let sample: CoachVoice
    @Environment(AppModel.self) private var model
    @AppStorage(CoachVoicePref.genderKey) private var gender = "female"
    @AppStorage(CoachVoicePref.accentKey) private var accent = "us"
    @AppStorage(CoachVoicePref.studioKey) private var studio = ""
    @State private var tries = 0
    private var store: CoachVoiceStore { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Coach voice").eyebrow()
            HStack(spacing: 6) {
                pill("Female", picked: gender == "female") { gender = "female" }
                pill("Male", picked: gender == "male") { gender = "male" }
            }
            HStack(spacing: 4) {
                ForEach(CoachVoicePref.accents, id: \.id) { a in
                    Button { accent = a.id } label: {
                        Text(a.flag).font(.system(size: 18))
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(Capsule().fill(accent == a.id ? Theme.lime : .white.opacity(0.2)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(a.title)
                    .accessibilityAddTraits(accent == a.id ? .isSelected : [])
                }
            }
            let voices = (store.catalog?.available ?? false)
                ? (store.catalog?.voices ?? []).filter { $0.gender == gender && $0.accent == accent } : []
            ForEach(voices) { v in studioRow(v) }
            iPhoneRow
            if store.catalog?.available != true {
                Text("Studio voices load when you're online.").font(.caption).opacity(0.85)
            } else if voices.isEmpty {
                Text("No studio voice for this pick yet: the iPhone voice speaks.").font(.caption).opacity(0.85)
            }
            if let f = store.failed {
                Text("\(f) didn't finish downloading. Tap Get to try again.").font(.caption).foregroundStyle(.yellow)
            }
        }
        .task { await store.refresh(model: model) }
    }

    private func studioRow(_ v: CoachVoiceCatalog.Voice) -> some View {
        let isReady = store.ready.contains(v.id)
        let picked = studio == v.id && isReady
        return HStack(spacing: 10) {
            Image(systemName: "waveform").font(.system(size: 15, weight: .heavy))
                .frame(width: 34, height: 34).background(Circle().fill(.white.opacity(0.25)))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(v.name).font(Theme.label(15))
                    Text("STUDIO").font(Theme.label(9)).padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().fill(Theme.lime)).foregroundStyle(Theme.ink)
                }
                Text(v.label + (isReady ? " · on this iPhone" : "")).font(.caption).opacity(0.85)
            }
            Spacer(minLength: 0)
            if let p = store.progress[v.id] {
                ProgressView(value: p).progressViewStyle(.circular).tint(Theme.lime).frame(width: 34, height: 34)
            } else if isReady {
                Button { preview(studio: v.id) } label: { playIcon }
                    .buttonStyle(.plain).accessibilityLabel("Hear \(v.name)")
            } else {
                Button {
                    Task { if await store.download(v.id, model: model) { studio = v.id } }
                } label: {
                    Label("Get", systemImage: "arrow.down").font(Theme.label(12))
                        .padding(.horizontal, 10).frame(height: 30)
                        .overlay(Capsule().strokeBorder(Theme.lime, lineWidth: 1.5)).foregroundStyle(Theme.lime)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Download \(v.name)")
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.ink.opacity(0.35)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(picked ? Theme.lime : .clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture { if isReady { studio = v.id } }
        .contextMenu { if isReady { Button("Remove download", role: .destructive) { store.remove(v.id) } } }
        .accessibilityIdentifier("coach.voice.\(v.id)")
    }

    private var iPhoneRow: some View {
        let best = CoachVoicePref.bestSystemVoice(gender: gender, accent: accent)
        let picked = studio.isEmpty || !store.ready.contains(studio)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "iphone").font(.system(size: 15, weight: .heavy))
                    .frame(width: 34, height: 34).background(Circle().fill(.white.opacity(0.25)))
                VStack(alignment: .leading, spacing: 1) {
                    Text("iPhone voice · \(best?.name ?? "System")").font(Theme.label(15)).lineLimit(1)
                    Text(best.map(CoachVoicePref.qualityTitle) ?? "Basic").font(.caption).opacity(0.85)
                }
                Spacer(minLength: 0)
                Button { preview(studio: "") } label: { playIcon }
                    .buttonStyle(.plain).accessibilityLabel("Hear the iPhone voice")
            }
            if best?.quality != .premium {
                Text("Sounds better with a free premium voice: iOS Settings → Accessibility → Spoken Content → Voices → English.")
                    .font(.caption2).opacity(0.85)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.ink.opacity(0.35)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(picked ? Theme.lime : .clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture { studio = "" }
        .accessibilityIdentifier("coach.voice.iphone")
    }

    private var playIcon: some View {
        Image(systemName: "play.fill").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.ink)
            .frame(width: 34, height: 34).background(Circle().fill(Theme.lime))
    }

    private func preview(studio voice: String) {
        tries += 1
        let moment = CoachMoment.finalSet(exercise: "Bench press")
        if let clip = store.clip(style: style, kind: moment.studioKind, seed: tries, voice: voice) {
            sample.play(clip.url)
        } else {
            sample.speak(CoachLines.line(moment, style: style, seed: tries), style: style, voice: CoachVoicePref.bestSystemVoice(gender: gender, accent: accent))
        }
    }

    private func pill(_ title: String, picked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Theme.label(14))
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(Capsule().fill(picked ? Theme.lime : .white.opacity(0.2)))
                .foregroundStyle(picked ? Theme.ink : .white)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }
}
