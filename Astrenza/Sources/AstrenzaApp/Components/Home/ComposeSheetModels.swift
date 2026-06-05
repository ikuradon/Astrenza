enum ComposeSheetMode {
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
