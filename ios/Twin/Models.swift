import Foundation

// Mirrors server/src/types.ts. Field names match the server's JSON exactly.

enum Tier: String, Codable, CaseIterable, Identifiable, Hashable {
    case friend, close, closest

    var id: String { rawValue }

    var label: String {
        switch self {
        case .friend: return "Friend"
        case .close: return "Close"
        case .closest: return "Closest"
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
    var surpriseOptIn: Bool
    var paused: Bool
    /// Profile photo on the server, if the person uploaded one.
    var photoUrl: String?
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
}

struct Nudge: Codable, Identifiable, Hashable {
    var id: String
    var fromUser: User
    var toFriendId: String
    var message: String
    var contextLevel: String // "closest" or "close"
    var status: String // "sent", "seen" or "acted"
    var createdAt: String
}

struct Gesture: Codable, Identifiable, Hashable {
    var id: String
    var nudgeId: String
    var fromFriend: User
    var type: GestureType
    var place: Place?
    var note: String
    var deliveredAt: String
}

// Response wrappers

struct TwinRefreshResult: Codable {
    var signals: Signals
    var nudgesSent: Int
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
