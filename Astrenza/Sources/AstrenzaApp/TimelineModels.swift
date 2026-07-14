import AstrenzaCore
import Foundation
import SwiftUI

struct TimelinePost: Identifiable {
    let id: String
    let author: TimelineAuthor
    let avatar: AvatarStyle
    let body: String
    let richBody: NostrRichContent?
    let createdAt: Int
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
        richBody: NostrRichContent? = nil,
        createdAt: Int,
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
        self.id = id ?? Self.stableMockID(authorKey: author.pubkey, body: body, createdAt: createdAt)
        self.author = author
        self.avatar = avatar.withPlaceholderSeed(author.pubkey)
        self.body = body
        self.richBody = richBody
        self.createdAt = createdAt
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
        richBody: NostrRichContent? = nil,
        createdAt: Int,
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
        self.id = id ?? Self.stableMockID(authorKey: author.pubkey, body: body, createdAt: createdAt)
        self.author = author
        self.avatar = avatar.withPlaceholderSeed(author.pubkey)
        self.body = body
        self.richBody = richBody
        self.createdAt = createdAt
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

    private static func stableMockID(authorKey: String, body: String, createdAt: Int) -> String {
        let seed = "\(authorKey)|\(createdAt)|\(body)"
        return "mock-\(TimelineAuthor.mockPubkey(for: seed).prefix(24))"
    }
}

enum TimelineTimestampFormatter {
    static func relativeText(from createdAt: Int, now: Date = Date()) -> String {
        let nowSeconds = Int(now.timeIntervalSince1970)
        let delta = max(0, nowSeconds - createdAt)
        if delta < 60 {
            return "\(delta)s"
        }
        if delta < 3_600 {
            return "\(delta / 60)m"
        }
        if delta < 86_400 {
            return "\(delta / 3_600)h"
        }
        return "\(delta / 86_400)d"
    }

    static func absoluteText(from createdAt: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "yyyy/MM/dd HH:mm 'JST'"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(createdAt)))
    }

    static func nextRelativeTextChangeDate(from createdAt: Int, after date: Date) -> Date {
        let nowSeconds = Int(floor(date.timeIntervalSince1970))
        let delta = max(0, nowSeconds - createdAt)
        let step: Int
        if delta < 60 {
            step = 1
        } else if delta < 3_600 {
            step = 60
        } else if delta < 86_400 {
            step = 3_600
        } else {
            step = 86_400
        }
        let nextDelta = (delta / step + 1) * step
        return Date(timeIntervalSince1970: TimeInterval(createdAt + nextDelta))
    }
}

enum TimelineMockClock {
    static let referenceNow = Int(Date().timeIntervalSince1970)

    static func createdAt(relative text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != "now",
              let unit = trimmed.last,
              let value = Int(trimmed.dropLast())
        else {
            return referenceNow
        }

        switch unit {
        case "s":
            return referenceNow - value
        case "m":
            return referenceNow - value * 60
        case "h":
            return referenceNow - value * 3_600
        case "d":
            return referenceNow - value * 86_400
        default:
            return referenceNow
        }
    }
}

enum TimelineFeedEntry: Identifiable {
    case post(TimelinePost)
    case gap(TimelineGap)
    case deleted(TimelineDeletedEntry)

    var id: String {
        switch self {
        case .post(let post):
            post.id
        case .gap(let gap):
            gap.id
        case .deleted(let entry):
            entry.id
        }
    }

    var post: TimelinePost? {
        switch self {
        case .post(let post):
            post
        case .gap, .deleted:
            nil
        }
    }
}

struct TimelineDeletedEntry: Identifiable, Equatable {
    let id: String

    init(id: String) {
        self.id = id
    }
}

struct TimelineEmptyState: Equatable {
    let title: String
    let message: String
    let systemName: String
    let primaryActionTitle: String
    let secondaryActionTitle: String?

    static let home = TimelineEmptyState(
        title: "No notes yet",
        message: "Your Home timeline will appear after the follow list and read relays are resolved.",
        systemName: "tray",
        primaryActionTitle: "Check Relays",
        secondaryActionTitle: "Find People"
    )

    static let relays = TimelineEmptyState(
        title: "No relay timeline",
        message: "Pick a relay or wait for NIP-65 discovery to finish before showing relay-scoped notes.",
        systemName: "antenna.radiowaves.left.and.right.slash",
        primaryActionTitle: "Open Relay Status",
        secondaryActionTitle: nil
    )

    static let lists = TimelineEmptyState(
        title: "No list selected",
        message: "NIP-51 lists can become custom timelines once the account has a saved list or bookmark set.",
        systemName: "list.bullet.rectangle",
        primaryActionTitle: "Create List",
        secondaryActionTitle: nil
    )

    static func loadingHome(message: String) -> TimelineEmptyState {
        TimelineEmptyState(
            title: "Loading Home",
            message: message,
            systemName: "arrow.triangle.2.circlepath",
            primaryActionTitle: "Relay Status",
            secondaryActionTitle: nil
        )
    }

    static func liveError(message: String) -> TimelineEmptyState {
        TimelineEmptyState(
            title: "Home unavailable",
            message: message,
            systemName: "exclamationmark.triangle",
            primaryActionTitle: "Retry",
            secondaryActionTitle: nil
        )
    }

    static let noContacts = TimelineEmptyState(
        title: "No follows found",
        message: "NIP-65 relays were resolved, but kind:3 did not return follow pubkeys yet.",
        systemName: "person.2.slash",
        primaryActionTitle: "Retry",
        secondaryActionTitle: nil
    )
}

enum TimelineGapFillDirection: Equatable, Sendable {
    case newer
    case older

    var systemName: String {
        switch self {
        case .newer:
            "chevron.up"
        case .older:
            "chevron.down"
        }
    }

    var label: String {
        switch self {
        case .newer:
            "Backfill newer notes"
        case .older:
            "Backfill older notes"
        }
    }
}

struct TimelineGap: Identifiable, Equatable {
    enum State: Equatable {
        case needsBackfill
        case fetching
        case limited
    }

    let id: String
    let newerPostID: TimelinePost.ID
    let olderPostID: TimelinePost.ID
    let missingEstimate: Int
    let relayCount: Int
    let state: State
    let backfilledPosts: [TimelinePost]

    static func == (lhs: TimelineGap, rhs: TimelineGap) -> Bool {
        lhs.id == rhs.id
            && lhs.newerPostID == rhs.newerPostID
            && lhs.olderPostID == rhs.olderPostID
            && lhs.missingEstimate == rhs.missingEstimate
            && lhs.relayCount == rhs.relayCount
            && lhs.state == rhs.state
            && lhs.backfilledPosts.map(\.id) == rhs.backfilledPosts.map(\.id)
    }

    func replacingState(_ state: State) -> TimelineGap {
        TimelineGap(
            id: id,
            newerPostID: newerPostID,
            olderPostID: olderPostID,
            missingEstimate: missingEstimate,
            relayCount: relayCount,
            state: state,
            backfilledPosts: backfilledPosts
        )
    }

    var title: String {
        switch state {
        case .needsBackfill:
            "Missing notes"
        case .fetching:
            "Fetching gap"
        case .limited:
            "Relay limit reached"
        }
    }

    var detail: String {
        switch state {
        case .needsBackfill:
            "Tap to backfill \(missingEstimate) cached interval from \(relayCount) relays"
        case .fetching:
            "Requesting smaller since/until windows"
        case .limited:
            "Try a narrower relay window later"
        }
    }

    var systemName: String {
        switch state {
        case .needsBackfill:
            "arrow.down.doc"
        case .fetching:
            "arrow.triangle.2.circlepath"
        case .limited:
            "exclamationmark.triangle.fill"
        }
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
    let createdAt: Int
}

struct TimelineReplyContext {
    let author: TimelineAuthor
    let avatar: AvatarStyle
    let createdAt: Int
    let bodyPreview: String
    let richContent: NostrRichContent?
    let isSelfReply: Bool

    init(
        author: TimelineAuthor,
        avatar: AvatarStyle,
        createdAt: Int,
        bodyPreview: String,
        richContent: NostrRichContent? = nil,
        isSelfReply: Bool
    ) {
        self.author = author
        self.avatar = avatar
        self.createdAt = createdAt
        self.bodyPreview = bodyPreview
        self.richContent = richContent
        self.isSelfReply = isSelfReply
    }
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
    case filtered

    var label: String {
        switch self {
        case .longText:
            "Show more"
        case .linkHeavy:
            "Link-heavy post"
        case .lowTrustLinks:
            "Tap to inspect"
        case .filtered:
            "Filtered"
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
        case .filtered:
            "line.3.horizontal.decrease.circle"
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
    let createdAt: Int
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
            createdAt: createdAt,
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
            createdAt: parent.createdAt,
            bodyPreview: parent.body,
            isSelfReply: author.pubkey == parent.author.pubkey
        )
    }
}

struct QuotedTimelinePost {
    let author: TimelineAuthor
    let avatar: AvatarStyle
    let body: String
    let richBody: NostrRichContent?
    let createdAt: Int?
    let isAvailable: Bool

    func timelinePost() -> TimelinePost {
        TimelinePost(
            id: "quoted-\(author.pubkey)-\(createdAt ?? 0)",
            author: author,
            avatar: avatar,
            body: body,
            richBody: richBody,
            createdAt: createdAt ?? 0,
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
    let profileResolutionState: NostrProfileResolutionState
    let isFollowed: Bool

    var isMetadataResolved: Bool {
        profileResolutionState == .resolved
    }

    var primaryText: String {
        guard let displayName, !displayName.isEmpty else {
            return abbreviatedPubkey
        }

        return displayName
    }

    var secondaryText: String {
        switch profileResolutionState {
        case .fetching:
            return "kind:0 pending"
        case .unknown, .unavailable:
            return abbreviatedPubkey
        case .resolved:
            break
        }

        guard let nip05, !nip05.isEmpty else {
            return abbreviatedPubkey
        }

        return displayableNIP05(nip05)
    }

    var secondarySystemName: String {
        if profileResolutionState == .fetching {
            return "clock"
        }

        guard isMetadataResolved else { return "person.crop.circle" }

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
            profileResolutionState: .resolved,
            isFollowed: isFollowed
        )
    }

    static func metadataResolved(
        displayName: String?,
        nip05: String?,
        nip05Status: NIP05Status,
        pubkey: String,
        isFollowed: Bool
    ) -> TimelineAuthor {
        TimelineAuthor(
            displayName: displayName,
            nip05: nip05,
            nip05Status: nip05 == nil ? .absent : nip05Status,
            pubkey: pubkey,
            profileResolutionState: .resolved,
            isFollowed: isFollowed
        )
    }

    static func unresolved(
        pubkey: String,
        state: NostrProfileResolutionState = .unknown
    ) -> TimelineAuthor {
        TimelineAuthor(
            displayName: nil,
            nip05: nil,
            nip05Status: .absent,
            pubkey: pubkey,
            profileResolutionState: state,
            isFollowed: false
        )
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

enum NIP19Display {
    private static let cache = NIP19DisplayCache()
    private static let charset = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
    private static let generator: [Int] = [
        0x3b6a57b2,
        0x26508e6d,
        0x1ea119fa,
        0x3d4233dd,
        0x2a1462b3
    ]

    static func npub(fromHexPubkey hexPubkey: String) -> String? {
        if let cached = cache.value(for: hexPubkey) {
            return cached
        }

        guard let bytes = bytes(fromHex: hexPubkey), bytes.count == 32 else {
            return nil
        }

        let data = convertBits(bytes, fromBits: 8, toBits: 5, pad: true)
        let encoded = bech32Encode(hrp: "npub", data: data)
        cache.setValue(encoded, for: hexPubkey)
        return encoded
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

private final class NIP19DisplayCache: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    func value(for key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    func setValue(_ value: String, for key: String) {
        lock.lock()
        values[key] = value
        lock.unlock()
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
    let imageURL: URL?

    init(
        primary: Color,
        secondary: Color,
        symbolName: String,
        pictureState: AvatarPictureState = .resolved,
        placeholderSeed: String = "",
        imageURL: URL? = nil
    ) {
        self.primary = primary
        self.secondary = secondary
        self.symbolName = symbolName
        self.pictureState = pictureState
        self.placeholderSeed = placeholderSeed
        self.imageURL = imageURL
    }

    func withPlaceholderSeed(_ seed: String) -> AvatarStyle {
        AvatarStyle(
            primary: primary,
            secondary: secondary,
            symbolName: symbolName,
            pictureState: pictureState,
            placeholderSeed: seed,
            imageURL: imageURL
        )
    }
}

enum AvatarPictureState {
    case resolved
    case missing
    case metadataPending
    case failed

    init(_ nostrState: NostrAvatarPictureState) {
        switch nostrState {
        case .resolved:
            self = .resolved
        case .missing:
            self = .missing
        case .metadataPending:
            self = .metadataPending
        }
    }

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

enum TimelineMediaLayoutMetrics {
    static let galleryAspectRatio: CGFloat = 1.9
    static let singleFallbackAspectRatio: CGFloat = 1.35
    static let singleMinimumAspectRatio: CGFloat = 0.62
    static let singleMaximumAspectRatio: CGFloat = 2.2
    static let singleMinimumHeight: CGFloat = 154
    static let singleMaximumHeight: CGFloat = 300
    static let singleLandscapeWidthFraction: CGFloat = 0.92

    static func singleMediaSize(
        aspectRatio rawAspectRatio: CGFloat?,
        availableWidth: CGFloat
    ) -> CGSize {
        let boundedWidth = max(availableWidth, 1)
        let aspectRatio = min(
            max(rawAspectRatio ?? singleFallbackAspectRatio, singleMinimumAspectRatio),
            singleMaximumAspectRatio
        )
        let maxWidth = aspectRatio > galleryAspectRatio ? boundedWidth * singleLandscapeWidthFraction : boundedWidth
        let idealHeight = maxWidth / aspectRatio
        let height = min(max(idealHeight, singleMinimumHeight), singleMaximumHeight)
        let width = min(maxWidth, height * aspectRatio)
        return CGSize(width: width, height: height)
    }

    static func galleryAspectRatio(for tiles: [MediaTile]) -> CGFloat {
        switch tiles.count {
        case 1:
            return min(max(tiles.first?.aspectRatio ?? singleFallbackAspectRatio, singleMinimumAspectRatio), singleMaximumAspectRatio)
        default:
            return galleryAspectRatio
        }
    }
}

struct MediaTile: Identifiable {
    let id: String
    let title: String
    let colors: [Color]
    let symbolName: String
    let url: URL?
    let altText: String?
    let width: Int?
    let height: Int?
    let blurhash: String?
    let remoteLoadMode: NostrRemotePreviewFetchMode

    init(
        title: String,
        colors: [Color],
        symbolName: String,
        url: URL? = nil,
        altText: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        blurhash: String? = nil,
        remoteLoadMode: NostrRemotePreviewFetchMode = .automatic
    ) {
        self.id = url?.absoluteString ?? "\(title)|\(symbolName)|\(altText ?? "")"
        self.title = title
        self.colors = colors
        self.symbolName = symbolName
        self.url = url
        self.altText = altText
        self.width = width
        self.height = height
        self.blurhash = blurhash
        self.remoteLoadMode = remoteLoadMode
    }

    var aspectRatio: CGFloat? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return CGFloat(width) / CGFloat(height)
    }

    var isPortrait: Bool {
        guard let aspectRatio else { return false }
        return aspectRatio < 0.82
    }

    var isVideo: Bool {
        symbolName == "play.rectangle"
    }
}

struct LinkPreview {
    let title: String
    let subtitle: String
    let host: String
    let url: String
    let imageURL: URL?
    let style: LinkPreviewStyle
    let remoteImageLoadMode: NostrRemotePreviewFetchMode

    init(
        title: String,
        subtitle: String,
        host: String,
        url: String,
        imageURL: URL? = nil,
        style: LinkPreviewStyle = .standard,
        remoteImageLoadMode: NostrRemotePreviewFetchMode = .automatic
    ) {
        self.title = title
        self.subtitle = subtitle
        self.host = host
        self.url = url
        self.imageURL = imageURL
        self.style = style
        self.remoteImageLoadMode = remoteImageLoadMode
    }
}

enum LinkPreviewStyle: Equatable {
    case standard
    case youtube
}

struct UnresolvedLinkPreview {
    let host: String
    let url: String
}

extension TimelineMedia {
    var allowsAutomaticRemoteMediaLoading: Bool {
        switch self {
        case .gallery(let tiles):
            tiles.allSatisfy { $0.remoteLoadMode == .automatic }
        case .linkPreview(let preview):
            preview.imageURL == nil || preview.remoteImageLoadMode == .automatic
        case .unresolvedLink:
            true
        }
    }

    var requiresTapToLoadRemoteMedia: Bool {
        !allowsAutomaticRemoteMediaLoading
    }

    func allowingRemoteMediaLoading() -> TimelineMedia {
        switch self {
        case .gallery(let tiles):
            return .gallery(tiles.map { tile in
                MediaTile(
                    title: tile.title,
                    colors: tile.colors,
                    symbolName: tile.symbolName,
                    url: tile.url,
                    altText: tile.altText,
                    width: tile.width,
                    height: tile.height,
                    blurhash: tile.blurhash,
                    remoteLoadMode: .automatic
                )
            })
        case .linkPreview(let preview):
            return .linkPreview(LinkPreview(
                title: preview.title,
                subtitle: preview.subtitle,
                host: preview.host,
                url: preview.url,
                imageURL: preview.imageURL,
                style: preview.style,
                remoteImageLoadMode: .automatic
            ))
        case .unresolvedLink:
            return self
        }
    }

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
