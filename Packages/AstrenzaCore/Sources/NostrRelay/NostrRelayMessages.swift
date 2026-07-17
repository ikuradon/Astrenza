import Foundation
import NostrProtocol

public enum NostrRelayClientError: Error {
    case invalidRelayURL(String)
    case authRequired(challenge: String)
    case paymentRequired(String)
    case relayClosed(String)
    case negentropyRelayError(String)
    case timeout
}

public enum NostrRelayMessage: Equatable {
    case event(subscriptionID: String, event: NostrEvent)
    case eose(subscriptionID: String)
    case ok(eventID: String, accepted: Bool, message: String)
    case closed(subscriptionID: String, message: String)
    case notice(String)
    case auth(String)

    public static func parse(_ raw: String) -> NostrRelayMessage? {
        guard let data = raw.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let type = array.first as? String
        else { return nil }

        switch type {
        case "EVENT":
            guard array.count == 3,
                  let subscriptionID = array[1] as? String,
                  let object = array[2] as? [String: Any],
                  let event = decodeEvent(object)
            else { return nil }
            return .event(subscriptionID: subscriptionID, event: event)
        case "EOSE":
            guard array.count == 2, let subscriptionID = array[1] as? String else { return nil }
            return .eose(subscriptionID: subscriptionID)
        case "OK":
            guard array.count == 4,
                  let eventID = array[1] as? String,
                  let accepted = array[2] as? Bool,
                  let message = array[3] as? String
            else { return nil }
            return .ok(eventID: eventID, accepted: accepted, message: message)
        case "CLOSED":
            guard array.count == 3,
                  let subscriptionID = array[1] as? String,
                  let message = array[2] as? String
            else { return nil }
            return .closed(subscriptionID: subscriptionID, message: message)
        case "NOTICE":
            guard array.count == 2, let message = array[1] as? String else { return nil }
            return .notice(message)
        case "AUTH":
            guard array.count == 2, let challenge = array[1] as? String else { return nil }
            return .auth(challenge)
        default:
            return nil
        }
    }

    private static func decodeEvent(_ object: [String: Any]) -> NostrEvent? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let event = try? JSONDecoder().decode(NostrEvent.self, from: data)
        else { return nil }
        return event
    }
}
