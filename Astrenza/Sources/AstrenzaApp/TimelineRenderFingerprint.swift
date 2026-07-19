import AstrenzaCore
import Foundation

enum TimelineRenderFingerprint {
    static func entries(_ entries: [TimelineFeedEntry]) -> [Int] {
        entries.map(entry)
    }

    static func entry(_ entry: TimelineFeedEntry) -> Int {
        var hasher = Hasher()
        switch entry {
        case .post(let post):
            hasher.combine("post")
            combine(post, into: &hasher)
        case .gap(let gap):
            hasher.combine("gap")
            hasher.combine(gap.id)
            hasher.combine(gap.newerPostID)
            hasher.combine(gap.olderPostID)
            hasher.combine(gap.missingEstimate)
            hasher.combine(gap.relayCount)
            hasher.combine(String(describing: gap.state))
            for post in gap.backfilledPosts {
                combine(post, into: &hasher)
            }
        case .deleted(let entry):
            hasher.combine("deleted")
            hasher.combine(entry.id)
        }
        return hasher.finalize()
    }

    private static func combine(_ post: TimelinePost, into hasher: inout Hasher) {
        hasher.combine(post.id)
        combine(post.author, into: &hasher)
        combine(post.avatar, into: &hasher)
        hasher.combine(post.body)
        combine(post.richBody, into: &hasher)
        hasher.combine(post.createdAt)
        hasher.combine(post.replyCount)
        hasher.combine(post.boostCount)
        hasher.combine(post.favoriteCount)
        hasher.combine(post.isLocked)
        combine(post.media, into: &hasher)
        hasher.combine(post.context)

        if let repostedBy = post.repostedBy {
            hasher.combine("reposted")
            combine(repostedBy.author, into: &hasher)
            combine(repostedBy.avatar, into: &hasher)
            hasher.combine(repostedBy.createdAt)
        } else {
            hasher.combine("no-repost")
        }

        if let quotedPost = post.quotedPost {
            hasher.combine("quote")
            combine(quotedPost.author, into: &hasher)
            combine(quotedPost.avatar, into: &hasher)
            hasher.combine(quotedPost.body)
            combine(quotedPost.richBody, into: &hasher)
            hasher.combine(quotedPost.createdAt)
            hasher.combine(quotedPost.isAvailable)
        } else {
            hasher.combine("no-quote")
        }

        if let replyContext = post.replyContext {
            hasher.combine("reply-context")
            combine(replyContext.author, into: &hasher)
            combine(replyContext.avatar, into: &hasher)
            hasher.combine(replyContext.createdAt)
            hasher.combine(replyContext.bodyPreview)
            combine(replyContext.richContent, into: &hasher)
            hasher.combine(replyContext.isSelfReply)
        } else {
            hasher.combine("no-reply-context")
        }

        hasher.combine(post.replyMention?.text)
        hasher.combine(post.replyMention?.isExternal)
        hasher.combine(post.contentWarning?.reason)
        switch post.bodyPresentation {
        case .standard:
            hasher.combine("body-standard")
        case .collapsed(let lineLimit, let reason):
            hasher.combine("body-collapsed")
            hasher.combine(lineLimit)
            hasher.combine(String(describing: reason))
        }
        if let linkSummary = post.linkSummary {
            hasher.combine(linkSummary.totalCount)
            hasher.combine(linkSummary.visibleHosts)
            hasher.combine(linkSummary.unresolvedCount)
        } else {
            hasher.combine("no-link-summary")
        }
        hasher.combine(post.actionState.didReply)
        hasher.combine(post.actionState.didRepost)
        hasher.combine(post.actionState.didFavorite)
        hasher.combine(post.actionState.didZap)
    }

    private static func combine(_ author: TimelineAuthor, into hasher: inout Hasher) {
        hasher.combine(author.displayName)
        hasher.combine(author.nip05)
        hasher.combine(String(describing: author.nip05Status))
        hasher.combine(author.pubkey)
        hasher.combine(author.profileResolutionState)
        hasher.combine(author.isFollowed)
    }

    private static func combine(_ avatar: AvatarStyle, into hasher: inout Hasher) {
        hasher.combine(avatar.primary)
        hasher.combine(avatar.secondary)
        hasher.combine(avatar.symbolName)
        hasher.combine(String(describing: avatar.pictureState))
        hasher.combine(avatar.placeholderSeed)
        hasher.combine(avatar.imageURL?.absoluteString)
    }

    private static func combine(_ richContent: NostrRichContent?, into hasher: inout Hasher) {
        guard let richContent else {
            hasher.combine("no-rich-content")
            return
        }
        hasher.combine(richContent.displayText)
        for token in richContent.tokens {
            hasher.combine(String(reflecting: token))
        }
        for reference in richContent.references {
            hasher.combine(String(reflecting: reference))
        }
        for key in richContent.profileDisplayNamesByPubkey.keys.sorted() {
            hasher.combine(key)
            hasher.combine(richContent.profileDisplayNamesByPubkey[key])
        }
        for key in richContent.eventDisplayTextByID.keys.sorted() {
            hasher.combine(key)
            hasher.combine(richContent.eventDisplayTextByID[key])
        }
    }

    private static func combine(_ media: TimelineMedia?, into hasher: inout Hasher) {
        guard let media else {
            hasher.combine("no-media")
            return
        }
        switch media {
        case .gallery(let tiles):
            hasher.combine("gallery")
            for tile in tiles {
                hasher.combine(tile.id)
                hasher.combine(tile.title)
                hasher.combine(tile.symbolName)
                hasher.combine(tile.url?.absoluteString)
                hasher.combine(tile.altText)
                hasher.combine(tile.width)
                hasher.combine(tile.height)
                hasher.combine(tile.blurhash)
                hasher.combine(String(describing: tile.remoteLoadMode))
                for color in tile.colors {
                    hasher.combine(color)
                }
            }
        case .linkPreview(let preview):
            hasher.combine("link")
            hasher.combine(preview.title)
            hasher.combine(preview.subtitle)
            hasher.combine(preview.host)
            hasher.combine(preview.url)
            hasher.combine(preview.imageURL?.absoluteString)
            hasher.combine(String(describing: preview.style))
            hasher.combine(String(describing: preview.remoteImageLoadMode))
        case .unresolvedLink(let preview):
            hasher.combine("unresolved")
            hasher.combine(preview.host)
            hasher.combine(preview.url)
        }
    }
}

/// Rowの高さを変え得る情報だけを追跡する。
/// 描画fingerprintには色や画像状態も含まれるため、layout projectionには使わない。
enum TimelineGeometryFingerprint {
    static func entry(_ entry: TimelineFeedEntry) -> Int {
        var hasher = Hasher()
        switch entry {
        case .post(let post):
            hasher.combine("post")
            combine(post, into: &hasher)
        case .gap:
            // Gap rowは状態や文言によらず固定高。
            hasher.combine("gap")
        case .deleted:
            hasher.combine("deleted")
        }
        return hasher.finalize()
    }

    private static func combine(
        _ post: TimelinePost,
        into hasher: inout Hasher
    ) {
        hasher.combine(post.body)
        combine(post.richBody, into: &hasher)
        hasher.combine(post.repostedBy != nil)

        if let quotedPost = post.quotedPost {
            hasher.combine("quote")
            hasher.combine(quotedPost.body)
            hasher.combine(quotedPost.isAvailable)
            combine(quotedPost.richBody, into: &hasher)
        } else {
            hasher.combine("no-quote")
        }

        if let replyContext = post.replyContext {
            hasher.combine("reply-context")
            hasher.combine(replyContext.bodyPreview)
            hasher.combine(replyContext.isSelfReply)
            combine(replyContext.richContent, into: &hasher)
        } else {
            hasher.combine("no-reply-context")
        }

        hasher.combine(post.replyMention?.text)
        hasher.combine(post.replyMention?.isExternal)
        hasher.combine(post.contentWarning != nil)
        switch post.bodyPresentation {
        case .standard:
            hasher.combine("body-standard")
        case .collapsed(let lineLimit, let reason):
            hasher.combine("body-collapsed")
            hasher.combine(lineLimit)
            hasher.combine(String(describing: reason))
        }

        if let linkSummary = post.linkSummary {
            hasher.combine(linkSummary.totalCount)
            hasher.combine(linkSummary.visibleHosts)
            hasher.combine(linkSummary.unresolvedCount)
        } else {
            hasher.combine("no-link-summary")
        }
        combine(post.media, into: &hasher)
    }

    private static func combine(
        _ richContent: NostrRichContent?,
        into hasher: inout Hasher
    ) {
        guard let richContent else {
            hasher.combine("no-rich-content")
            return
        }
        hasher.combine(richContent.displayText)
        for token in richContent.tokens {
            switch token {
            case .text:
                hasher.combine("text")
            case .url:
                hasher.combine("url")
            case .hashtag:
                hasher.combine("hashtag")
            case .profile:
                hasher.combine("profile")
            case .event:
                hasher.combine("event")
            case .customEmoji:
                hasher.combine("custom-emoji")
            }
        }
    }

    private static func combine(
        _ media: TimelineMedia?,
        into hasher: inout Hasher
    ) {
        guard let media else {
            hasher.combine("no-media")
            return
        }
        switch media {
        case .gallery(let tiles):
            hasher.combine("gallery")
            hasher.combine(tiles.count)
            for tile in tiles {
                hasher.combine(tile.width)
                hasher.combine(tile.height)
            }
        case .linkPreview(let preview):
            hasher.combine("link-preview")
            hasher.combine(String(describing: preview.style))
            hasher.combine(
                preview.imageURL != nil &&
                    preview.remoteImageLoadMode == .automatic
            )
        case .unresolvedLink:
            hasher.combine("unresolved-link")
        }
    }
}
