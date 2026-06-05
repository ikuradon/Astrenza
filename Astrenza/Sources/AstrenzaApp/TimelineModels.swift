import SwiftUI

struct TimelinePost: Identifiable {
    let id: String
    let author: TimelineAuthor
    let avatar: AvatarStyle
    let body: String
    let timestamp: String
    let replyCount: Int?
    let boostCount: Int?
    let favoriteCount: Int?
    let isLocked: Bool
    let media: TimelineMedia?
    let context: String?
    let repostedBy: TimelineRepostAttribution?
    let quotedPost: QuotedTimelinePost?
    let replyContext: TimelineReplyContext?
    let replyMention: TimelineReplyMention?
    let contentWarning: TimelineContentWarning?
    let bodyPresentation: TimelineBodyPresentation
    let linkSummary: TimelineLinkSummary?
    let actionState: TimelinePostActionState

    init(
        id: String? = nil,
        authorName: String,
        handle: String,
        avatar: AvatarStyle,
        body: String,
        timestamp: String,
        replyCount: Int?,
        boostCount: Int?,
        favoriteCount: Int?,
        isLocked: Bool,
        media: TimelineMedia?,
        context: String?,
        repostedBy: TimelineRepostAttribution? = nil,
        quotedPost: QuotedTimelinePost? = nil,
        replyContext: TimelineReplyContext? = nil,
        replyMention: TimelineReplyMention? = nil,
        contentWarning: TimelineContentWarning? = nil,
        bodyPresentation: TimelineBodyPresentation = .standard,
        linkSummary: TimelineLinkSummary? = nil,
        actionState: TimelinePostActionState = .none
    ) {
        let author = TimelineAuthor.resolved(
            displayName: authorName,
            nip05: handle.hasPrefix("@") ? String(handle.dropFirst()) : handle,
            nip05Status: .valid,
            pubkey: TimelineAuthor.mockPubkey(for: authorName)
        )
        self.id = id ?? Self.stableMockID(authorKey: author.pubkey, body: body, timestamp: timestamp)
        self.author = author
        self.avatar = avatar.withPlaceholderSeed(author.pubkey)
        self.body = body
        self.timestamp = timestamp
        self.replyCount = replyCount
        self.boostCount = boostCount
        self.favoriteCount = favoriteCount
        self.isLocked = isLocked
        self.media = media
        self.context = context
        self.repostedBy = repostedBy
        self.quotedPost = quotedPost
        self.replyContext = replyContext
        self.replyMention = replyMention
        self.contentWarning = contentWarning
        self.bodyPresentation = bodyPresentation
        self.linkSummary = linkSummary
        self.actionState = actionState
    }

    init(
        id: String? = nil,
        author: TimelineAuthor,
        avatar: AvatarStyle,
        body: String,
        timestamp: String,
        replyCount: Int?,
        boostCount: Int?,
        favoriteCount: Int?,
        isLocked: Bool,
        media: TimelineMedia?,
        context: String?,
        repostedBy: TimelineRepostAttribution? = nil,
        quotedPost: QuotedTimelinePost? = nil,
        replyContext: TimelineReplyContext? = nil,
        replyMention: TimelineReplyMention? = nil,
        contentWarning: TimelineContentWarning? = nil,
        bodyPresentation: TimelineBodyPresentation = .standard,
        linkSummary: TimelineLinkSummary? = nil,
        actionState: TimelinePostActionState = .none
    ) {
        self.id = id ?? Self.stableMockID(authorKey: author.pubkey, body: body, timestamp: timestamp)
        self.author = author
        self.avatar = avatar.withPlaceholderSeed(author.pubkey)
        self.body = body
        self.timestamp = timestamp
        self.replyCount = replyCount
        self.boostCount = boostCount
        self.favoriteCount = favoriteCount
        self.isLocked = isLocked
        self.media = media
        self.context = context
        self.repostedBy = repostedBy
        self.quotedPost = quotedPost
        self.replyContext = replyContext
        self.replyMention = replyMention
        self.contentWarning = contentWarning
        self.bodyPresentation = bodyPresentation
        self.linkSummary = linkSummary
        self.actionState = actionState
    }

    private static func stableMockID(authorKey: String, body: String, timestamp: String) -> String {
        let seed = "\(authorKey)|\(timestamp)|\(body)"
        return "mock-\(TimelineAuthor.mockPubkey(for: seed).prefix(24))"
    }
}

extension TimelinePost {
    var shouldObscureExternalAttachments: Bool {
        !author.isFollowed && (repostedBy != nil || replyContext != nil)
    }
}

struct TimelineContentWarning {
    let reason: String?

    var displayReason: String {
        guard let reason, !reason.isEmpty else {
            return "The author marked this post as sensitive."
        }

        return reason
    }
}

struct TimelineRepostAttribution {
    let author: TimelineAuthor
    let avatar: AvatarStyle
    let timestamp: String
}

struct TimelineReplyContext {
    let author: TimelineAuthor
    let avatar: AvatarStyle
    let timestamp: String
    let bodyPreview: String
    let isSelfReply: Bool
}

struct TimelineReplyMention {
    let text: String
    let isExternal: Bool
}

enum TimelineBodyPresentation {
    case standard
    case collapsed(lineLimit: Int, reason: TimelineBodyCollapseReason)

    var timelineLineLimit: Int? {
        switch self {
        case .standard:
            nil
        case .collapsed(let lineLimit, _):
            lineLimit
        }
    }

    var collapseReason: TimelineBodyCollapseReason? {
        switch self {
        case .standard:
            nil
        case .collapsed(_, let reason):
            reason
        }
    }
}

enum TimelineBodyCollapseReason: Equatable {
    case longText
    case linkHeavy
    case lowTrustLinks

    var label: String {
        switch self {
        case .longText:
            "Show more"
        case .linkHeavy:
            "Link-heavy post"
        case .lowTrustLinks:
            "Tap to inspect"
        }
    }

    var systemName: String {
        switch self {
        case .longText:
            "text.alignleft"
        case .linkHeavy:
            "link"
        case .lowTrustLinks:
            "eye.slash"
        }
    }
}

struct TimelineLinkSummary {
    let totalCount: Int
    let visibleHosts: [String]
    let unresolvedCount: Int

    var compactText: String {
        if totalCount == 1 {
            return visibleHosts.first ?? "1 link"
        }

        return "\(totalCount) links"
    }

    var detailText: String {
        let hosts = visibleHosts.prefix(3).joined(separator: " / ")
        guard !hosts.isEmpty else { return compactText }

        let suffix = totalCount > visibleHosts.count ? " +\(totalCount - visibleHosts.count)" : ""
        return "\(hosts)\(suffix)"
    }
}

struct MockNostrEvent {
    let id: String
    let author: TimelineAuthor
    let avatar: AvatarStyle
    let content: String
    let timestamp: String
    let replyTo: TimelinePost?
    let replyMention: TimelineReplyMention?
    let reposts: Int?
    let reactions: Int?
    let actionState: TimelinePostActionState

    func timelinePost() -> TimelinePost {
        TimelinePost(
            id: id,
            author: author,
            avatar: avatar,
            body: content,
            timestamp: timestamp,
            replyCount: nil,
            boostCount: reposts,
            favoriteCount: reactions,
            isLocked: false,
            media: nil,
            context: nil,
            replyContext: replyTo.map(replyContext(for:)),
            replyMention: replyMention,
            actionState: actionState
        )
    }

    private func replyContext(for parent: TimelinePost) -> TimelineReplyContext {
        TimelineReplyContext(
            author: parent.author,
            avatar: parent.avatar,
            timestamp: parent.timestamp,
            bodyPreview: parent.body,
            isSelfReply: author.pubkey == parent.author.pubkey
        )
    }
}

struct QuotedTimelinePost {
    let author: TimelineAuthor
    let avatar: AvatarStyle
    let body: String
    let timestamp: String
    let isAvailable: Bool

    func timelinePost() -> TimelinePost {
        TimelinePost(
            id: "quoted-\(author.pubkey)-\(timestamp)",
            author: author,
            avatar: avatar,
            body: body,
            timestamp: timestamp,
            replyCount: nil,
            boostCount: nil,
            favoriteCount: nil,
            isLocked: false,
            media: nil,
            context: nil
        )
    }
}

struct TimelineAuthor {
    let displayName: String?
    let nip05: String?
    let nip05Status: NIP05Status
    let pubkey: String
    let isMetadataResolved: Bool
    let isFollowed: Bool

    var primaryText: String {
        guard let displayName, !displayName.isEmpty else {
            return abbreviatedPubkey
        }

        return displayName
    }

    var secondaryText: String {
        guard isMetadataResolved else {
            return "kind:0 pending"
        }

        guard let nip05, !nip05.isEmpty else {
            return abbreviatedPubkey
        }

        return displayableNIP05(nip05)
    }

    var secondarySystemName: String {
        if !isMetadataResolved {
            return "clock"
        }

        switch nip05Status {
        case .valid:
            return "checkmark.seal.fill"
        case .invalid:
            return "exclamationmark.triangle.fill"
        case .unchecked:
            return "questionmark.circle"
        case .absent:
            return "person.crop.circle"
        }
    }

    static func resolved(
        displayName: String,
        nip05: String?,
        nip05Status: NIP05Status = .valid,
        pubkey: String,
        isFollowed: Bool = true
    ) -> TimelineAuthor {
        TimelineAuthor(
            displayName: displayName,
            nip05: nip05,
            nip05Status: nip05 == nil ? .absent : nip05Status,
            pubkey: pubkey,
            isMetadataResolved: true,
            isFollowed: isFollowed
        )
    }

    static func unresolved(pubkey: String) -> TimelineAuthor {
        TimelineAuthor(displayName: nil, nip05: nil, nip05Status: .absent, pubkey: pubkey, isMetadataResolved: false, isFollowed: false)
    }

    static func mockPubkey(for seed: String) -> String {
        let bytes = seed.utf8.reduce(into: [UInt8](repeating: 0, count: 32)) { result, byte in
            let index = Int(byte) % result.count
            result[index] = result[index] &+ byte &+ UInt8(index)
        }

        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func displayableNIP05(_ identifier: String) -> String {
        guard identifier.hasPrefix("_@") else {
            return identifier
        }

        return String(identifier.dropFirst(2))
    }

    private var abbreviatedPubkey: String {
        let displayPubkey = NIP19Display.npub(fromHexPubkey: pubkey) ?? pubkey
        guard displayPubkey.count > 16 else { return displayPubkey }

        return "\(displayPubkey.prefix(10))...\(displayPubkey.suffix(6))"
    }
}

private enum NIP19Display {
    private static let charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
    private static let generator: [Int] = [
        0x3b6a57b2,
        0x26508e6d,
        0x1ea119fa,
        0x3d4233dd,
        0x2a1462b3
    ]

    static func npub(fromHexPubkey hexPubkey: String) -> String? {
        guard let bytes = bytes(fromHex: hexPubkey), bytes.count == 32 else {
            return nil
        }

        let data = convertBits(bytes, fromBits: 8, toBits: 5, pad: true)
        return bech32Encode(hrp: "npub", data: data)
    }

    private static func bytes(fromHex hex: String) -> [UInt8]? {
        guard hex.count % 2 == 0 else { return nil }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(hex.count / 2)

        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else {
                return nil
            }

            bytes.append(byte)
            index = nextIndex
        }

        return bytes
    }

    private static func convertBits(_ data: [UInt8], fromBits: Int, toBits: Int, pad: Bool) -> [Int] {
        var accumulator = 0
        var bitCount = 0
        let maxValue = (1 << toBits) - 1
        var output: [Int] = []

        for value in data {
            accumulator = (accumulator << fromBits) | Int(value)
            bitCount += fromBits

            while bitCount >= toBits {
                bitCount -= toBits
                output.append((accumulator >> bitCount) & maxValue)
            }
        }

        if pad, bitCount > 0 {
            output.append((accumulator << (toBits - bitCount)) & maxValue)
        }

        return output
    }

    private static func bech32Encode(hrp: String, data: [Int]) -> String {
        let checksum = createChecksum(hrp: hrp, data: data)
        let encodedData = (data + checksum).map { String(charset[$0]) }.joined()
        return "\(hrp)1\(encodedData)"
    }

    private static func createChecksum(hrp: String, data: [Int]) -> [Int] {
        let values = hrpExpand(hrp) + data + [0, 0, 0, 0, 0, 0]
        let polymodValue = polymod(values) ^ 1

        return (0..<6).map { index in
            (polymodValue >> (5 * (5 - index))) & 31
        }
    }

    private static func hrpExpand(_ hrp: String) -> [Int] {
        hrp.utf8.map { Int($0) >> 5 } + [0] + hrp.utf8.map { Int($0) & 31 }
    }

    private static func polymod(_ values: [Int]) -> Int {
        var checksum = 1

        for value in values {
            let top = checksum >> 25
            checksum = ((checksum & 0x1ffffff) << 5) ^ value

            for index in 0..<5 where ((top >> index) & 1) == 1 {
                checksum ^= generator[index]
            }
        }

        return checksum
    }
}

enum NIP05Status {
    case absent
    case unchecked
    case invalid
    case valid
}

struct TimelinePostActionState {
    let didReply: Bool
    let didRepost: Bool
    let didFavorite: Bool
    let didZap: Bool

    static let none = TimelinePostActionState(
        didReply: false,
        didRepost: false,
        didFavorite: false,
        didZap: false
    )
}

struct AvatarStyle {
    let primary: Color
    let secondary: Color
    let symbolName: String
    let pictureState: AvatarPictureState
    let placeholderSeed: String

    init(
        primary: Color,
        secondary: Color,
        symbolName: String,
        pictureState: AvatarPictureState = .resolved,
        placeholderSeed: String = ""
    ) {
        self.primary = primary
        self.secondary = secondary
        self.symbolName = symbolName
        self.pictureState = pictureState
        self.placeholderSeed = placeholderSeed
    }

    func withPlaceholderSeed(_ seed: String) -> AvatarStyle {
        AvatarStyle(
            primary: primary,
            secondary: secondary,
            symbolName: symbolName,
            pictureState: pictureState,
            placeholderSeed: seed
        )
    }
}

enum AvatarPictureState {
    case resolved
    case missing
    case metadataPending
    case failed

    var usesPlaceholder: Bool {
        switch self {
        case .resolved:
            false
        case .missing, .metadataPending, .failed:
            true
        }
    }

    var markerSystemName: String? {
        switch self {
        case .resolved:
            nil
        case .missing:
            "person.crop.circle"
        case .metadataPending:
            "clock"
        case .failed:
            "exclamationmark"
        }
    }
}

enum TimelineMedia {
    case gallery([MediaTile])
    case linkPreview(LinkPreview)
    case unresolvedLink(UnresolvedLinkPreview)
}

struct MediaTile: Identifiable {
    let id = UUID()
    let title: String
    let colors: [Color]
    let symbolName: String
}

struct LinkPreview {
    let title: String
    let subtitle: String
    let host: String
    let url: String
}

struct UnresolvedLinkPreview {
    let host: String
    let url: String
}

extension TimelineMedia {
    var browserURL: URL? {
        switch self {
        case .linkPreview(let preview):
            URL(string: preview.url)
        case .unresolvedLink(let preview):
            URL(string: preview.url)
        case .gallery:
            nil
        }
    }

    var isFullscreenMedia: Bool {
        if case .gallery = self {
            return true
        }

        return false
    }
}
