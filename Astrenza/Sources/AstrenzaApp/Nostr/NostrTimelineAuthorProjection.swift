import Foundation
import SwiftUI
import AstrenzaCore

struct NostrTimelineAuthorProjection {
    static func author(for item: NostrHomeTimelineItem) -> TimelineAuthor {
        guard let displayName = item.displayName else {
            return .unresolved(pubkey: item.pubkey)
        }
        return .resolved(
            displayName: displayName,
            nip05: item.nip05,
            nip05Status: NIP05Status(item.nip05Status),
            pubkey: item.pubkey,
            isFollowed: item.isFollowed
        )
    }

    static func avatar(for item: NostrHomeTimelineItem) -> AvatarStyle {
        let palette = avatarPalette(for: item.pubkey)
        return AvatarStyle(
            primary: palette.primary,
            secondary: palette.secondary,
            symbolName: "person.fill",
            pictureState: AvatarPictureState(item.avatarPictureState),
            placeholderSeed: item.pubkey,
            imageURL: item.avatarImageURL
        )
    }

    static func avatar(for event: NostrEvent) -> AvatarStyle {
        avatar(
            for: NostrHomeTimelineItem(
                id: event.id,
                pubkey: event.pubkey,
                displayName: nil,
                nip05: nil,
                nip05Status: .absent,
                isFollowed: true,
                body: event.content,
                createdAt: event.createdAt,
                avatarPictureState: .metadataPending,
                avatarImageURL: nil
            )
        )
    }

    static func avatarPalette(for pubkey: String) -> (primary: Color, secondary: Color) {
        let colors: [Color] = [.purple, .cyan, .mint, .orange, .pink, .blue, .green, .indigo]
        let seed = pubkey.utf8.reduce(0) { Int($0) + Int($1) }
        return (colors[seed % colors.count], colors[(seed / 3 + 2) % colors.count])
    }

    static func relativeTimestamp(from createdAt: Int, now: Int = Int(Date().timeIntervalSince1970)) -> String {
        let delta = max(0, now - createdAt)
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

    static func contentWarning(from event: NostrEvent) -> TimelineContentWarning? {
        guard let tag = event.tags.first(where: { $0.first == "content-warning" }) else { return nil }
        return TimelineContentWarning(reason: tag.dropFirst().first)
    }
}
