import Foundation

// Mirrors server/src/types.ts. Field names match the server's JSON exactly.

enum Tier: String, Codable, CaseIterable, Identifiable, Hashable {
    case friend, close, closest

    var id: String { rawValue }

    var label: String {
        switch self {
        case .friend: return "Friend"
        case .close: return "Close friend"
        case .closest: return "Closest friend"
        }
    }
}

enum SupportLevel: String, Codable, Hashable {
    case doingFine = "doing_fine"
    case couldUseSupport = "could_use_support"
    case struggling

    var label: String {
        switch self {
        case .doingFine: return "Doing fine"
        case .couldUseSupport: return "Could use some support"
        case .struggling: return "Having a hard time"
        }
    }

    var symbol: String {
        switch self {
        case .doingFine: return "sun.max.fill"
        case .couldUseSupport: return "cloud.sun.fill"
        case .struggling: return "cloud.rain.fill"
        }
    }
}

enum GestureType: String, Codable, Hashable {
    case dropOff = "drop_off"
    case hangout
    case message

    var symbol: String {
        switch self {
        case .dropOff: return "cup.and.saucer.fill"
        case .hangout: return "figure.2"
        case .message: return "bubble.left.and.bubble.right.fill"
        }
    }
}

struct Preferences: Codable, Hashable {
    var coffeeOrder: String?
    var likes: String // "company" or "space"
}

struct User: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var email: String
    var homeLocation: String
    var preferences: Preferences
    /// "Open to support": the twin may tell friends when your week gets heavy.
    var surpriseOptIn: Bool
    var paused: Bool
    /// Profile photo on the server, if the person uploaded one. A path, resolved against the server URL.
    var photoUrl: String?
    /// Surprises on: a friend's gesture stays hidden until it happens. Missing means on.
    var surprisesOn: Bool?
    /// How friends with you in their contacts find you.
    var phone: String?
}

extension User {
    var surprisesEnabled: Bool { surprisesOn ?? true }
}

/// Only the fields being changed are sent.
struct SettingsPatch: Encodable {
    var openToSupport: Bool?
    var surprisesOn: Bool?
    var phone: String?
}

/// A pending or just-accepted request. `user` is always the other person.
struct FriendRequest: Codable, Identifiable, Hashable {
    var id: String
    var user: User
    var createdAt: String
}

struct FriendRequests: Codable {
    var incoming: [FriendRequest]
    var outgoing: [FriendRequest]
    /// Requests you sent that were accepted in the last day.
    var accepted: [FriendRequest]

    static let empty = FriendRequests(incoming: [], outgoing: [], accepted: [])
}

/// "pending" carries the request; "accepted" means they had already asked you, so you're now friends.
struct SendRequestResult: Decodable {
    var status: String
    var request: FriendRequest?
    var friend: FriendEntry?
}

enum InviteChannel: String, Encodable { case sms, email, link }

struct Invite: Decodable {
    var code: String
    var url: String
    /// Ready-to-send text that includes the link.
    var message: String
}

/// "pending": a request from the inviter is waiting for you. "friends": you already were.
struct RedeemResult: Decodable {
    var status: String
    var inviter: User
    var request: FriendRequest?
}

struct SignInResult: Decodable {
    let token: String
    let user: User
    /// True the first time this Google account signs in.
    let created: Bool
    let googleConnected: Bool
}

struct FriendEntry: Codable, Identifiable, Hashable {
    var friend: User
    var tier: Tier
    var id: String { friend.id }
}

struct Stressor: Codable, Hashable {
    var what: String
    var when: String
}

struct Signals: Codable, Hashable {
    var supportLevel: SupportLevel
    var stressors: [Stressor]
    var busyHoursNext3Days: Double
    var likelyLocation: String?
    var summaryForClosest: String
    var summaryForClose: String
    /// A light, low-detail line for the outer Friends circle, like "Busy week".
    var summaryForFriend: String?

    var friendLine: String { summaryForFriend ?? "Busy week" }
}

struct Place: Codable, Hashable {
    var name: String
    var address: String
    var rating: Double?
    var openNow: Bool?
    var mapsUrl: String?

    var mapsLink: URL? {
        if let mapsUrl, let url = URL(string: mapsUrl) {
            return url
        }
        let query = "\(name) \(address)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://maps.apple.com/?q=\(query)")
    }
}

struct Suggestion: Codable, Hashable {
    var gestureType: GestureType
    var title: String
    var detail: String
    var place: Place?
    /// What a drop-off brings, like "matcha".
    var item: String?
}

struct Nudge: Codable, Identifiable, Hashable {
    var id: String
    var fromUser: User
    var toFriendId: String
    var message: String
    var contextLevel: String // "closest", "close" or "friend"
    var status: String // "sent", "seen" or "acted"
    var createdAt: String
    /// Muse's starter note, which the friend edits before sending.
    var draftNote: String?
    /// When and where the friend's own twin found they can show up. Arrives a few seconds after the nudge.
    var moment: String?
    /// Why the twin nudged; only in the sender's privacy log.
    var reason: String?
    /// What you did for them, so you can mark a surprise delivered.
    var gesture: NudgeGesture?
}

struct NudgeGesture: Codable, Hashable {
    var id: String
    var surprise: Bool
    var revealed: Bool
}

struct Gesture: Codable, Identifiable, Hashable {
    var id: String
    var nudgeId: String
    var fromFriend: User
    var type: GestureType
    var place: Place?
    var note: String
    var deliveredAt: String
    /// "helped" or "space": how the person said it landed. Their twin reads it next time.
    var reaction: String?
    /// The person had surprises on, so this only showed up once the friend marked it delivered.
    var surprise: Bool?
}

// Response wrappers

struct TwinRefreshResult: Codable {
    var signals: Signals
    var nudgesSent: Int
    /// Every friend already heard about everything this refresh read, so no one was nudged again.
    var nothingNew: Bool?
}

/// Something you told your twin directly. It's read on every refresh until you delete it.
struct TwinEntry: Codable, Identifiable, Hashable {
    var id: String
    var text: String
    var createdAt: String
}

struct TwinState: Codable {
    var signals: Signals?
}

struct IngestResult: Codable {
    var events: Int
    var emails: Int?
}

struct PrivacyInfo: Codable {
    struct Sources: Codable {
        var google: Bool
        var ics: Bool
    }
    var sources: Sources
    var friends: [FriendEntry]
    var nudgeLog: [Nudge]
}

// Date helpers

enum DateText {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain = ISO8601DateFormatter()
    private static let relative = RelativeDateTimeFormatter()

    static func parse(_ text: String) -> Date? {
        iso.date(from: text) ?? isoPlain.date(from: text)
    }

    static func ago(_ text: String) -> String {
        guard let date = parse(text) else { return "" }
        return relative.localizedString(for: date, relativeTo: Date())
    }

    static func now() -> String {
        isoPlain.string(from: Date())
    }
}
