import AstrenzaCore

enum ComposeContextFactory {
    static func reply(
        to post: TimelinePost,
        eventStore: NostrEventStore?
    ) -> ComposeContext {
        let event = try? eventStore?.event(id: post.id)
        let parent = reference(
            eventID: post.id,
            fallbackPubkey: post.author.pubkey,
            event: event,
            eventStore: eventStore
        )
        let root = rootReference(
            from: event,
            fallback: parent
        )
        var recipients = Set(event?.tags.compactMap(pubkeyTag) ?? [])
        if let parentPubkey = parent.pubkey {
            recipients.insert(parentPubkey)
        }

        return .reply(ComposeReplyContext(
            root: root,
            parent: parent,
            recipientPubkeys: recipients.sorted()
        ))
    }

    static func quote(
        _ post: TimelinePost,
        eventStore: NostrEventStore?
    ) -> ComposeContext {
        let event = try? eventStore?.event(id: post.id)
        return .quote(ComposeQuoteContext(target: reference(
            eventID: post.id,
            fallbackPubkey: post.author.pubkey,
            event: event,
            eventStore: eventStore
        )))
    }

    private static func reference(
        eventID: String,
        fallbackPubkey: String,
        event: NostrEvent?,
        eventStore: NostrEventStore?
    ) -> ComposeEventReference {
        let relayHint = (try? eventStore?.eventSources(eventID: eventID))?
            .first?.relayURL
        return ComposeEventReference(
            eventID: eventID,
            relayHint: relayHint,
            pubkey: event?.pubkey ?? fallbackPubkey
        )
    }

    private static func rootReference(
        from event: NostrEvent?,
        fallback: ComposeEventReference
    ) -> ComposeEventReference {
        guard let event else { return fallback }
        let eventTags = event.tags.filter { $0.count >= 2 && $0[0] == "e" }
        let rootTag = eventTags.first(where: { $0.count >= 4 && $0[3] == "root" })
            ?? eventTags.first
        guard let rootTag else { return fallback }
        return ComposeEventReference(
            eventID: rootTag[1],
            relayHint: nonEmpty(rootTag[safe: 2]),
            pubkey: nonEmpty(rootTag[safe: 4])
        )
    }

    private static func pubkeyTag(_ tag: [String]) -> String? {
        guard tag.count >= 2, tag[0] == "p" else { return nil }
        return nonEmpty(tag[1])
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

private extension Collection where Index == Int {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
