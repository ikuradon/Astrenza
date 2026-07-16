enum ComposeSheetMode: Equatable {
    case post
    case reply

    var title: String {
        switch self {
        case .post: "Compose"
        case .reply: "Reply"
        }
    }

    var placeholder: String {
        switch self {
        case .post: "Say something..."
        case .reply: "Write a reply..."
        }
    }

    var actionTitle: String {
        switch self {
        case .post: "Post"
        case .reply: "Reply"
        }
    }
}

struct ComposeSubmitRequest: Equatable {
    let mode: ComposeSheetMode
    let text: String
    let isSensitive: Bool
    let sensitiveReason: String
}
