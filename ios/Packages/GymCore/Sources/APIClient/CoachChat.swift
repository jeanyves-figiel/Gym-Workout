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
    /// Pronouns (#415), e.g. "she/her"; nil = neutral wording.
    public var pronouns: String?
    /// What the member likes to be called (#415).
    public var callName: String?
    /// What the coach remembers about the member (#495): goal, likes, the member's own notes.
    public var memory: [String]?
    /// Exercise names Coach may hand back (#856, freestyle screen).
    public var exercises: [String]?
    /// Today's workout exercises (#999), so Coach can swap one by name.
    public var todayExercises: [String]?
    /// Today, 1 = Monday … 7 = Sunday (#999), for "move it to Saturday".
    public var weekday: Int?

    public init(goal: String? = nil, level: String? = nil, sessionMinutes: Int? = nil, equipment: [String]? = nil,
                readiness: String? = nil, todayPlanned: String? = nil, method: String? = nil, screen: String? = nil, focus: String? = nil,
                pronouns: String? = nil, callName: String? = nil, memory: [String]? = nil, exercises: [String]? = nil,
                todayExercises: [String]? = nil, weekday: Int? = nil) {
        self.todayExercises = todayExercises
        self.weekday = weekday
        self.memory = memory
        self.exercises = exercises
        self.pronouns = pronouns
        self.callName = callName
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
    /// Exercises to add now (#856, freestyle): names from `CoachChatContext.exercises`, best first.
    public var exercises: [String]?
    /// Train around pain (#870): the spot to protect; the app's engine picks the swaps.
    public var protect: CoachChatProtect?
    /// Body measurements the member told Coach to log (#1000): kg, %, cm.
    public var measurement: CoachChatMeasurement?
    /// Things Coach does for the member (#999): water, food, mood, move, skip, swap.
    public var doActions: [CoachChatDo]?
}

/// One thing Coach does (#999). `kind` water / food / mood / move / skip / swap; only its own fields are set.
public struct CoachChatDo: Codable, Sendable, Equatable {
    public var kind: String
    public var glasses: Int?
    public var foods: String?
    /// breakfast / lunch / dinner / snack.
    public var meal: String?
    /// 1 drained … 5 amazing.
    public var mood: Int?
    /// 1 = Monday … 7 = Sunday.
    public var weekday: Int?
    public var from: String?
    public var to: String?

    public init(kind: String, glasses: Int? = nil, foods: String? = nil, meal: String? = nil, mood: Int? = nil,
                weekday: Int? = nil, from: String? = nil, to: String? = nil) {
        self.kind = kind
        self.glasses = glasses
        self.foods = foods
        self.meal = meal
        self.mood = mood
        self.weekday = weekday
        self.from = from
        self.to = to
    }
}

/// What Coach logs (#1000). `girths[].site` is a GirthSite raw value, `side` left / right / none.
public struct CoachChatMeasurement: Codable, Sendable, Equatable {
    public struct Girth: Codable, Sendable, Equatable {
        public var site: String
        public var side: String
        public var cm: Double

        public init(site: String, side: String = "none", cm: Double) {
            self.site = site
            self.side = side
            self.cm = cm
        }
    }

    public var weightKg: Double?
    public var bodyFatPct: Double?
    public var girths: [Girth]?

    public init(weightKg: Double? = nil, bodyFatPct: Double? = nil, girths: [Girth]? = nil) {
        self.weightKg = weightKg
        self.bodyFatPct = bodyFatPct
        self.girths = girths
    }
}

/// Coach's train-around-pain offer (#870): area neck … ankle, side left / right / both, level mild / loaded / sharp.
public struct CoachChatProtect: Codable, Sendable, Equatable {
    public var area: String
    public var side: String
    public var level: String
    /// Red flags were mentioned: see a doctor first.
    public var seeDoctor: Bool

    public init(area: String, side: String, level: String, seeDoctor: Bool = false) {
        self.area = area
        self.side = side
        self.level = level
        self.seeDoctor = seeDoctor
    }
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
        /// Base64 JPEG of the machine in front of the member (#856).
        var photo: String?
    }

    /// Whether the chat is on (server has its key) and messages left today.
    public func coachChatStatus() async throws -> CoachChatStatus {
        try await authorized("GET", "/v1/me/coach-chat", Empty?.none, as: CoachChatStatus.self)
    }

    /// Sends the conversation (last turn = the member's). Errors: `daily_limit` (429), `pro_required` (402),
    /// `coach_unavailable` (503), `coach_failed` (502), `bad_photo` (400). `photo`: a JPEG up to 1.5 MB sent with the
    /// last message (#856).
    public func coachChat<W: Decodable & Sendable>(_ turns: [CoachChatTurn], context: CoachChatContext, photo: Data? = nil,
                                                  as _: W.Type) async throws -> CoachChatAnswer<W> {
        try await requireAI(.coach)
        return try await authorized("POST", "/v1/me/coach-chat", CoachChatBody(turns: turns, context: context, photo: photo?.base64EncodedString()),
                             as: CoachChatAnswer<W>.self)
    }
}
