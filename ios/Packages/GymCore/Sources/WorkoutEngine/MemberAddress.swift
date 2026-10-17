import Foundation

/// How the app talks about and to the member (#415, design C "How we talk to you"): pronouns, and what the coach calls
/// them. Both optional; with nothing set the app stays neutral ("you", "they").
public enum Pronouns: String, Codable, CaseIterable, Sendable, Identifiable {
    case she, he, they, custom
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .she: "she/her"
        case .he: "he/him"
        case .they: "they/them"
        case .custom: "Custom…"
        }
    }

    /// Prefill from the gender picked in About you (raw values of the app's `BodyMetrics.Gender`): woman → she,
    /// man → he, any other identity → they; not set or "prefer not to say" → nil (neutral, nothing assumed).
    public static func suggested(gender: String?) -> Pronouns? {
        switch gender ?? "" {
        case "", "preferNotToSay": nil
        case "woman": .she
        case "man": .he
        default: .they
        }
    }

    /// The text other people and the coach see: "she/her", or the member's own words for custom.
    public static func text(_ p: Pronouns?, custom: String?) -> String? {
        guard let p else { return nil }
        guard p == .custom else { return p.label }
        let t = (custom ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : String(t.prefix(24))
    }
}

/// What the coach calls the member before key lines ("Alex! Halfway!").
public enum CoachCall: String, Codable, CaseIterable, Sendable, Identifiable {
    case name, champ, legend, queen, king, none
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .name: "Your name"
        case .champ: "Champ"
        case .legend: "Legend"
        case .queen: "Queen"
        case .king: "King"
        case .none: "Nothing"
        }
    }

    /// Choices for the pronouns: Queen with she, King with he, both with custom; never a gendered term with they.
    public static func options(for p: Pronouns?) -> [CoachCall] {
        switch p {
        case .she: [.name, .champ, .legend, .queen, .none]
        case .he: [.name, .champ, .legend, .king, .none]
        case .custom: [.name, .champ, .legend, .queen, .king, .none]
        case .they, nil: [.name, .champ, .legend, .none]
        }
    }

    /// Default: the member's name when there is one, else nothing.
    public static func suggested(hasName: Bool) -> CoachCall { hasName ? .name : .none }

    /// The word the coach says; nil = no call. `name`: first name or nickname. A gendered term the pronouns no longer
    /// allow (e.g. Queen after switching to they/them) falls back to no call.
    public static func text(_ c: CoachCall?, name: String?, pronouns: Pronouns?) -> String? {
        guard let c, c != .none, options(for: pronouns).contains(c) else { return nil }
        guard c == .name else { return c.label }
        let first = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").first.map(String.init) ?? ""
        let clean = first.filter { $0.isLetter || $0 == "-" || $0 == "'" }
        return clean.isEmpty ? nil : String(clean.prefix(24))
    }
}

extension CoachMoment {
    /// Moments where the coach calls the member (#415): the big ones, not every set or rest.
    public var isCalled: Bool {
        switch self {
        case .start, .halfway, .record, .finish: true
        default: false
        }
    }
}

extension CoachLines {
    /// The call said before a line: "Alex!" in Hype, "Alex." otherwise (matches the studio recording).
    public static func call(_ name: String, style: CoachStyle) -> String { name + (style == .hype ? "!" : ".") }

    /// `line` with the call in front when the moment takes one.
    public static func called(_ line: String, moment: CoachMoment, style: CoachStyle, call name: String?) -> String {
        guard let name, !name.isEmpty, moment.isCalled else { return line }
        return call(name, style: style) + " " + line
    }
}
