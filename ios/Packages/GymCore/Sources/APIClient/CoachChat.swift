import Foundation

// Workout chat (#381): the member chats with Coach Monkey; the server asks Claude for generator settings.

/// One chat line: `member` or `coach`.
public struct CoachChatTurn: Codable, Sendable, Equatable {
    public var role: String
    public var text: String

    public init(role: String, text: String) {
        self.role = role
        self.text = text
    }
}

/// What the app tells the coach about the member (no identifiers).
public struct CoachChatContext: Codable, Sendable, Equatable {
    public var goal: String?
    public var level: String?
    public var sessionMinutes: Int?
    public var equipment: [String]?
    public var readiness: String?
    public var todayPlanned: String?
    public var method: String?
    /// Where the member asks from (#412): "train", "exercise", "progress", "calendar", "player", …
    public var screen: String?
    /// What that screen shows: an exercise, a chart and its numbers, a calendar day.
    public var focus: String?

    public init(goal: String? = nil, level: String? = nil, sessionMinutes: Int? = nil, equipment: [String]? = nil,
                readiness: String? = nil, todayPlanned: String? = nil, method: String? = nil, screen: String? = nil, focus: String? = nil) {
        self.goal = goal
        self.level = level
        self.sessionMinutes = sessionMinutes
        self.equipment = equipment
        self.readiness = readiness
        self.todayPlanned = todayPlanned
        self.method = method
        self.screen = screen
        self.focus = focus
    }
}

/// The coach's answer; `workout` is app-defined generator settings, nil while the coach asks something.
public struct CoachChatAnswer<W: Decodable & Sendable>: Decodable, Sendable {
    public var reply: String
    public var workout: W?
    public var remainingToday: Int
    /// A button that opens a screen (#412).
    public var action: CoachChatAction?
    /// Follow-up questions to tap (#412).
    public var suggestions: [String]?
}

/// Coach's "open this" button (#412): target progress / calendar / explore / settings / exercise (+ name).
public struct CoachChatAction: Codable, Sendable, Equatable {
    public var target: String
    public var exercise: String?
    public var label: String

    public init(target: String, exercise: String? = nil, label: String) {
        self.target = target
        self.exercise = exercise
        self.label = label
    }
}

public struct CoachChatStatus: Decodable, Sendable, Equatable {
    public var available: Bool
    public var remainingToday: Int

    public init(available: Bool, remainingToday: Int) {
        self.available = available
        self.remainingToday = remainingToday
    }
}

extension APIClient {
    private struct CoachChatBody: Encodable, Sendable {
        var turns: [CoachChatTurn]
        var context: CoachChatContext
    }

    /// Whether the chat is on (server has its key) and messages left today.
    public func coachChatStatus() async throws -> CoachChatStatus {
        try await authorized("GET", "/v1/me/coach-chat", Empty?.none, as: CoachChatStatus.self)
    }

    /// Sends the conversation (last turn = the member's). Errors: `daily_limit` (429), `pro_required` (402),
    /// `coach_unavailable` (503), `coach_failed` (502).
    public func coachChat<W: Decodable & Sendable>(_ turns: [CoachChatTurn], context: CoachChatContext, as _: W.Type) async throws -> CoachChatAnswer<W> {
        try await authorized("POST", "/v1/me/coach-chat", CoachChatBody(turns: turns, context: context), as: CoachChatAnswer<W>.self)
    }
}
