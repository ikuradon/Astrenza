import Foundation
import Testing
@testable import AstrenzaCore

@Suite("Nostr relay runtime concurrency")
struct NostrRelayRuntimeConcurrencyTests {
    @Test("Session accepts an EVENT that arrives before REQ send returns")
    func sessionStagesSubscriptionBeforeSendReturns() async throws {
        let signer = try NostrPrivateKeySigner(privateKeyHex: String(repeating: "51", count: 32))
        let event = try await signer.sign(
            NostrPublishInput.post(content: "arrived during send")
                .unsignedEvent(pubkey: signer.pubkey, createdAt: 300)
        )
        let connection = RelayConcurrencyTestConnection(
            inboundFrames: [try eventFrame(subscriptionID: "home-forward", event: event)],
            gateFirstSend: true
        )
        let session = NostrRelaySession(
            relayURL: "wss://relay.example",
            transport: RelayConcurrencyTestTransport(connection: connection)
        )
        let collector = RelayConcurrencyPacketCollector()
        let collectTask = Task {
            for await packet in await session.events() {
                await collector.append(packet)
            }
        }
        defer { collectTask.cancel() }
        let packet = NostrREQPacket.forward(
            subscriptionID: "home-forward",
            filters: [["kinds": .ints([1]), "authors": .strings([signer.pubkey])]]
        )

        let installTask = Task {
            try await session.install(packet)
        }
        await connection.waitUntilFirstSendStarts()
        try await session.receiveNext()
        await connection.releaseFirstSend()
        try await installTask.value
        try await Task.sleep(nanoseconds: 10_000_000)

        #expect(await collector.packets().contains { packet in
            if case .event("wss://relay.example", "home-forward", event) = packet {
                return true
            }
            return false
        })
        #expect(await session.activeSubscriptionIDs() == ["home-forward"])
    }

    @Test("A failed replacement does not roll back over a newer close")
    func failedInstallRollbackRespectsSubscriptionGeneration() async throws {
        let connection = RelayConcurrencyTestConnection()
        let session = NostrRelaySession(
            relayURL: "wss://relay.example",
            transport: RelayConcurrencyTestTransport(connection: connection)
        )
        let originalPacket = NostrREQPacket.forward(
            subscriptionID: "home-forward",
            filters: [["kinds": .ints([1])]]
        )
        let replacementPacket = NostrREQPacket.forward(
            subscriptionID: "home-forward",
            filters: [["kinds": .ints([1]), "since": .int(500)]]
        )

        try await session.install(originalPacket)
        await connection.gateNextSend(failOnRelease: true)
        let replacementTask = Task {
            try await session.install(replacementPacket)
        }
        await connection.waitUntilFirstSendStarts()
        try await session.close(subscriptionID: "home-forward")
        await connection.releaseFirstSend()

        var replacementFailed = false
        do {
            try await replacementTask.value
        } catch {
            replacementFailed = true
        }

        #expect(replacementFailed)
        #expect(await session.activeSubscriptionIDs().isEmpty)
        #expect(await connection.sentFrames().last == #"["CLOSE","home-forward"]"#)
    }

    @Test("An install waiting for connect cannot send after a newer close")
    func installRechecksGenerationAfterConnect() async throws {
        let connection = RelayConcurrencyTestConnection()
        let transport = RelayGatedConnectTransport(connection: connection)
        let session = NostrRelaySession(relayURL: "wss://relay.example", transport: transport)
        let packet = NostrREQPacket.forward(
            subscriptionID: "home-forward",
            filters: [["kinds": .ints([1]), "since": .int(100)]]
        )

        let installTask = Task {
            try await session.install(packet)
        }
        await transport.waitUntilConnectStarts()
        try await session.close(subscriptionID: "home-forward")
        await transport.releaseConnect()
        try await installTask.value

        let requestFrames = await connection.sentFrames().filter { $0.contains(#""REQ""#) }
        #expect(requestFrames.isEmpty)
        #expect(await session.activeSubscriptionIDs().isEmpty)
    }

    @Test("Session invalidates its state before awaiting connection close")
    func sessionTerminationInvalidatesBeforeConnectionCloseReturns() async throws {
        let connection = RelayConcurrencyTestConnection(gateClose: true)
        let session = NostrRelaySession(
            relayURL: "wss://relay.example",
            transport: RelayConcurrencyTestTransport(connection: connection)
        )
        let initialPacket = NostrREQPacket.forward(
            subscriptionID: "home-forward",
            filters: [["kinds": .ints([1])]]
        )
        let latePacket = NostrREQPacket.forward(
            subscriptionID: "late-forward",
            filters: [["kinds": .ints([1]), "since": .int(500)]]
        )

        try await session.install(initialPacket)
        let terminateTask = Task {
            await session.terminate()
        }
        await connection.waitUntilCloseStarts()

        var installError: NostrRelayRuntimeError?
        do {
            try await session.install(latePacket)
        } catch let error as NostrRelayRuntimeError {
            installError = error
        } catch {
            Issue.record("想定外のerror: \(error)")
        }

        #expect(await session.state() == .terminated)
        #expect(await session.activeSubscriptionIDs().isEmpty)
        #expect(installError == .connectionUnavailable(relayURL: "wss://relay.example"))
        #expect(await connection.sentFrames().filter { $0.contains(#""REQ""#) }.count == 1)

        await connection.releaseClose()
        await terminateTask.value
    }

    @Test("Runtime clears relay state before awaiting session termination")
    func runtimeTerminationClearsStateBeforeSessionTerminationReturns() async throws {
        let connection = RelayConcurrencyTestConnection(gateClose: true)
        let runtime = NostrRelayRuntime(
            transportFactory: { _ in RelayConcurrencyTestTransport(connection: connection) },
            autoReceive: false,
            heartbeatPolicy: .disabled
        )
        let packet = NostrREQPacket.forward(
            subscriptionID: "home-forward",
            filters: [["kinds": .ints([1])]]
        )

        try await runtime.setDefaultRelays(["wss://relay.example"])
        try await runtime.installForward(packet)
        let terminateTask = Task {
            await runtime.terminate()
        }
        await connection.waitUntilCloseStarts()

        #expect(await runtime.defaultRelayURLs().isEmpty)
        #expect(await runtime.activeForwardSubscriptionIDs().isEmpty)
        #expect(await runtime.activeSubscriptionIDs(relayURL: "wss://relay.example").isEmpty)

        await connection.releaseClose()
        await terminateTask.value
    }

    @Test("Backward EOSE can complete before REQ send returns")
    func backwardProgressIsRegisteredBeforeSendReturns() async throws {
        let firstConnection = RelayConcurrencyTestConnection(
            inboundFrames: [#"["EOSE","profile-backward"]"#],
            gateFirstSend: true
        )
        let secondConnection = RelayConcurrencyTestConnection(
            inboundFrames: [#"["EOSE","profile-backward"]"#]
        )
        let connections = [
            "wss://one.example": firstConnection,
            "wss://two.example": secondConnection
        ]
        let runtime = NostrRelayRuntime(
            transportFactory: { relayURL in
                RelayConcurrencyTestTransport(connection: connections[relayURL] ?? firstConnection)
            },
            autoReceive: false,
            heartbeatPolicy: .disabled,
            backwardPolicy: NostrRelayRuntimeBackwardPolicy(idleTimeoutMilliseconds: 20)
        )
        let collector = RelayConcurrencyPacketCollector()
        let stream = await runtime.events()
        let collectTask = Task {
            for await packet in stream {
                await collector.append(packet)
            }
        }
        defer { collectTask.cancel() }
        let packet = NostrREQPacket.backward(
            purpose: "profile",
            filters: [["kinds": .ints([0])]],
            relayURLs: ["wss://one.example", "wss://two.example"],
            groupID: "profile-group",
            subscriptionID: "profile-backward"
        )

        try await runtime.setDefaultRelays(["wss://one.example", "wss://two.example"])
        let installTask = Task {
            try await runtime.installBackward([packet], mergeField: .authors)
        }
        await firstConnection.waitUntilFirstSendStarts()
        try await runtime.receiveNext(relayURL: "wss://one.example")
        try await Task.sleep(nanoseconds: 10_000_000)
        #expect(await collector.packets().contains { packet in
            if case .backwardCompleted = packet { return true }
            return false
        } == false)

        await firstConnection.releaseFirstSend()
        try await installTask.value
        try await runtime.receiveNext(relayURL: "wss://two.example")
        try await Task.sleep(nanoseconds: 50_000_000)

        let completions = await collector.packets().compactMap { packet -> NostrBackwardREQCompletion? in
            guard case .backwardCompleted(let completion) = packet else { return nil }
            return completion
        }
        #expect(completions.count == 1)
        #expect(completions.first?.groupID == "profile-group")
        #expect(completions.first?.relayURLs == ["wss://one.example", "wss://two.example"])
        #expect(completions.first?.eoseCount == 2)
        #expect(completions.first?.timeoutCount == 0)
        #expect(await runtime.activeSubscriptionIDs(relayURL: "wss://one.example").isEmpty)
        #expect(await runtime.activeSubscriptionIDs(relayURL: "wss://two.example").isEmpty)
    }

    @Test("One failed relay does not roll back a backward request installed on another relay")
    func backwardInstallIsolatesPerRelayFailure() async throws {
        let healthyConnection = RelayConcurrencyTestConnection(blockReceiveWhenEmpty: true)
        let failedConnection = RelayConcurrencyTestConnection(
            failSendImmediately: true,
            blockReceiveWhenEmpty: true
        )
        let connections = [
            "wss://healthy.example": healthyConnection,
            "wss://failed.example": failedConnection
        ]
        let runtime = NostrRelayRuntime(
            transportFactory: { relayURL in
                RelayConcurrencyTestTransport(connection: connections[relayURL] ?? healthyConnection)
            },
            autoReceive: true,
            retryPolicy: NostrRelayRuntimeRetryPolicy(
                maxAttempts: 0,
                initialDelayMilliseconds: 0,
                delayStepMilliseconds: 0
            ),
            heartbeatPolicy: .disabled,
            backwardPolicy: .disabled
        )
        let packet = NostrREQPacket.backward(
            purpose: "profile",
            filters: [["kinds": .ints([0]), "authors": .strings([String(repeating: "a", count: 64)])]],
            relayURLs: ["wss://healthy.example", "wss://failed.example"],
            groupID: "profile-partial-install",
            subscriptionID: "profile-partial-install-req"
        )

        try await runtime.setDefaultRelays(packet.relayURLs)
        try await runtime.installBackward([packet], mergeField: .authors)

        #expect(await healthyConnection.sentFrames().contains { $0.contains(#""REQ""#) })
        #expect(await failedConnection.sentFrames().contains { $0.contains(#""REQ""#) })
        #expect(
            await runtime.activeSubscriptionIDs(relayURL: "wss://healthy.example")
            == [packet.subscriptionID]
        )
        #expect(await runtime.activeSubscriptionIDs(relayURL: "wss://failed.example").isEmpty)

        await runtime.terminate()
    }

    @Test("Batched backward requests complete every logical group after all relays finish")
    func batchedBackwardRequestsFanOutLogicalCompletions() async throws {
        let firstConnection = RelayConcurrencyTestConnection(
            inboundFrames: [#"["EOSE","profile-one-sub"]"#]
        )
        let secondConnection = RelayConcurrencyTestConnection(
            inboundFrames: [#"["EOSE","profile-one-sub"]"#]
        )
        let connections = [
            "wss://one.example": firstConnection,
            "wss://two.example": secondConnection
        ]
        let runtime = NostrRelayRuntime(
            transportFactory: { relayURL in
                RelayConcurrencyTestTransport(connection: connections[relayURL] ?? firstConnection)
            },
            autoReceive: false,
            heartbeatPolicy: .disabled,
            backwardPolicy: .disabled
        )
        let collector = RelayConcurrencyPacketCollector()
        let stream = await runtime.events()
        let collectTask = Task {
            for await packet in stream {
                await collector.append(packet)
            }
        }
        defer { collectTask.cancel() }
        let relayURLs = ["wss://one.example", "wss://two.example"]
        let first = NostrREQPacket.backward(
            purpose: "profile",
            filters: [["kinds": .ints([0]), "authors": .strings([String(repeating: "a", count: 64)])]],
            relayURLs: relayURLs,
            groupID: "profile-one",
            subscriptionID: "profile-one-sub"
        )
        let second = NostrREQPacket.backward(
            purpose: "profile",
            filters: [["kinds": .ints([0]), "authors": .strings([String(repeating: "b", count: 64)])]],
            relayURLs: relayURLs,
            groupID: "profile-two",
            subscriptionID: "profile-two-sub"
        )

        try await runtime.setDefaultRelays(relayURLs)
        try await runtime.installBackward([first, second], mergeField: .authors)
        try await runtime.receiveNext(relayURL: "wss://one.example")
        try await Task.sleep(nanoseconds: 10_000_000)
        #expect(await collector.packets().contains { packet in
            if case .backwardCompleted = packet { return true }
            return false
        } == false)

        try await runtime.receiveNext(relayURL: "wss://two.example")
        try await Task.sleep(nanoseconds: 30_000_000)

        let completions = await collector.packets().compactMap { packet -> NostrBackwardREQCompletion? in
            guard case .backwardCompleted(let completion) = packet else { return nil }
            return completion
        }
        #expect(completions.map(\.groupID).sorted() == ["profile-one", "profile-two"])
        #expect(completions.allSatisfy { $0.relayURLs == relayURLs })
        #expect(completions.allSatisfy { $0.subscriptionIDs == ["profile-one-sub"] })
        #expect(completions.allSatisfy { $0.eoseCount == 2 })
    }

    @Test("Removing a relay keeps backward group aggregation and completes it once")
    func removingRelayCompletesBackwardProgressIdempotently() async throws {
        let removedConnection = RelayConcurrencyTestConnection()
        let remainingConnection = RelayConcurrencyTestConnection(
            inboundFrames: [#"["EOSE","profile-backward"]"#]
        )
        let connections = [
            "wss://removed.example": removedConnection,
            "wss://remaining.example": remainingConnection
        ]
        let runtime = NostrRelayRuntime(
            transportFactory: { relayURL in
                RelayConcurrencyTestTransport(connection: connections[relayURL] ?? removedConnection)
            },
            autoReceive: false,
            heartbeatPolicy: .disabled,
            backwardPolicy: .disabled
        )
        let collector = RelayConcurrencyPacketCollector()
        let stream = await runtime.events()
        let collectTask = Task {
            for await packet in stream {
                await collector.append(packet)
            }
        }
        defer { collectTask.cancel() }
        let packet = NostrREQPacket.backward(
            purpose: "profile",
            filters: [["kinds": .ints([0])]],
            relayURLs: Array(connections.keys).sorted(),
            groupID: "profile-group",
            subscriptionID: "profile-backward"
        )

        try await runtime.setDefaultRelays(packet.relayURLs)
        try await runtime.installBackward([packet], mergeField: .authors)
        try await runtime.setDefaultRelays(["wss://remaining.example"])
        try await runtime.setDefaultRelays(["wss://remaining.example"])
        await collector.waitForRequestEnds(1)

        let earlyCompletions = await collector.packets().compactMap { packet -> NostrBackwardREQCompletion? in
            guard case .backwardCompleted(let completion) = packet else { return nil }
            return completion
        }
        #expect(earlyCompletions.isEmpty)
        #expect(await collector.requestEnds().contains {
            $0.relayURL == "wss://removed.example" && $0.reason == .cancelled
        })

        try await runtime.receiveNext(relayURL: "wss://remaining.example")
        try await Task.sleep(nanoseconds: 30_000_000)

        let completions = await collector.packets().compactMap { packet -> NostrBackwardREQCompletion? in
            guard case .backwardCompleted(let completion) = packet else { return nil }
            return completion
        }
        #expect(completions.count == 1)
        #expect(completions.first?.groupID == "profile-group")
        #expect(completions.first?.status == .partial)
        #expect(completions.first?.eoseCount == 1)
        #expect(completions.first?.closedCount == 1)
    }

    @Test("Backward install fails before registration when scoped relays are unavailable")
    func backwardInstallRejectsMissingEligibleRelays() async throws {
        let connection = RelayConcurrencyTestConnection()
        let runtime = NostrRelayRuntime(
            transportFactory: { _ in RelayConcurrencyTestTransport(connection: connection) },
            autoReceive: false,
            heartbeatPolicy: .disabled,
            backwardPolicy: .disabled
        )
        let packet = NostrREQPacket.backward(
            purpose: "profile",
            filters: [["kinds": .ints([0])]],
            relayURLs: ["wss://scoped.example"],
            groupID: "profile-scoped-group",
            subscriptionID: "profile-scoped-subscription"
        )

        try await runtime.setDefaultRelays(["wss://default.example"])
        var receivedError: NostrRelayRuntimeError?
        do {
            try await runtime.installBackward([packet], mergeField: .authors)
        } catch let error as NostrRelayRuntimeError {
            receivedError = error
        } catch {
            Issue.record("想定外のerror: \(error)")
        }

        #expect(receivedError == .noEligibleRelays(groupIDs: ["profile-scoped-group"]))
        #expect(await runtime.activeSubscriptionIDs(relayURL: "wss://default.example").isEmpty)
        #expect(await connection.sentFrames().isEmpty)
    }

    @Test("A multi-relay backward install rolls back successful relays when a later relay fails")
    func backwardInstallFailureRollsBackWholeCall() async throws {
        let firstConnection = RelayConcurrencyTestConnection()
        let secondConnection = RelayConcurrencyTestConnection(failSendImmediately: true)
        let connections = [
            "wss://one.example": firstConnection,
            "wss://two.example": secondConnection
        ]
        let runtime = NostrRelayRuntime(
            transportFactory: { relayURL in
                RelayConcurrencyTestTransport(connection: connections[relayURL] ?? firstConnection)
            },
            autoReceive: false,
            heartbeatPolicy: .disabled
        )
        let packet = NostrREQPacket.backward(
            purpose: "older",
            filters: [["kinds": .ints([1])]],
            relayURLs: ["wss://one.example", "wss://two.example"],
            groupID: "older-group",
            subscriptionID: "older-backward"
        )

        try await runtime.setDefaultRelays(["wss://one.example", "wss://two.example"])
        var didFail = false
        do {
            try await runtime.installBackward([packet], mergeField: .authors)
        } catch {
            didFail = true
        }

        #expect(didFail)
        #expect(await runtime.activeSubscriptionIDs(relayURL: "wss://one.example").isEmpty)
        #expect(await runtime.activeSubscriptionIDs(relayURL: "wss://two.example").isEmpty)
        #expect(await firstConnection.sentFrames().last == #"["CLOSE","older-backward"]"#)
    }

    @Test("Session event streams multicast without replacing earlier observers")
    func sessionEventStreamsSupportMultipleObservers() async throws {
        let connection = RelayConcurrencyTestConnection()
        let session = NostrRelaySession(
            relayURL: "wss://relay.example",
            transport: RelayConcurrencyTestTransport(connection: connection)
        )
        let firstCollector = RelayConcurrencyPacketCollector()
        let secondCollector = RelayConcurrencyPacketCollector()
        let firstStream = await session.events()
        let secondStream = await session.events()
        let firstTask = Task {
            for await packet in firstStream {
                await firstCollector.append(packet)
            }
        }
        let secondTask = Task {
            for await packet in secondStream {
                await secondCollector.append(packet)
            }
        }
        defer {
            firstTask.cancel()
            secondTask.cancel()
        }

        try await session.connect()
        try await Task.sleep(nanoseconds: 10_000_000)

        #expect(await firstCollector.states() == [.connecting, .connected])
        #expect(await secondCollector.states() == [.connecting, .connected])
    }

    @Test("Runtime event streams multicast without replacing earlier observers")
    func runtimeEventStreamsSupportMultipleObservers() async throws {
        let connection = RelayConcurrencyTestConnection()
        let runtime = NostrRelayRuntime(
            transportFactory: { _ in RelayConcurrencyTestTransport(connection: connection) },
            autoReceive: false,
            heartbeatPolicy: .disabled
        )
        let firstCollector = RelayConcurrencyPacketCollector()
        let secondCollector = RelayConcurrencyPacketCollector()
        let firstStream = await runtime.events()
        let secondStream = await runtime.events()
        let firstTask = Task {
            for await packet in firstStream {
                await firstCollector.append(packet)
            }
        }
        let secondTask = Task {
            for await packet in secondStream {
                await secondCollector.append(packet)
            }
        }
        defer {
            firstTask.cancel()
            secondTask.cancel()
        }

        try await runtime.setDefaultRelays(["wss://relay.example"])
        try await Task.sleep(nanoseconds: 10_000_000)

        #expect(await firstCollector.states().contains(.connected))
        #expect(await secondCollector.states().contains(.connected))
    }

    @Test("Transient CLOSED retries a desired forward subscription")
    func transientClosedRetriesForwardSubscription() async throws {
        let connection = RelayConcurrencyTestConnection(
            inboundFrames: [#"["CLOSED","home-forward","error: temporary database failure"]"#]
        )
        let runtime = NostrRelayRuntime(
            transportFactory: { _ in RelayConcurrencyTestTransport(connection: connection) },
            autoReceive: false,
            retryPolicy: NostrRelayRuntimeRetryPolicy(
                maxAttempts: 1,
                initialDelayMilliseconds: 0,
                delayStepMilliseconds: 0
            ),
            heartbeatPolicy: .disabled
        )
        let packet = NostrREQPacket.forward(
            subscriptionID: "home-forward",
            filters: [["kinds": .ints([1])]]
        )

        try await runtime.setDefaultRelays(["wss://relay.example"])
        try await runtime.installForward(packet)
        try await runtime.receiveNext(relayURL: "wss://relay.example")
        try await Task.sleep(nanoseconds: 50_000_000)

        let requestFrames = await connection.sentFrames().filter { $0.contains(#""REQ""#) }
        #expect(requestFrames.count == 2)
        #expect(requestFrames[0] == requestFrames[1])
        #expect(await runtime.activeSubscriptionIDs(relayURL: "wss://relay.example") == ["home-forward"])
    }

    @Test("A newly added relay does not receive forward subscriptions scoped to another relay")
    func newRelayHonorsForwardPacketRelayScope() async throws {
        let firstConnection = RelayConcurrencyTestConnection()
        let secondConnection = RelayConcurrencyTestConnection()
        let connections = [
            "wss://one.example": firstConnection,
            "wss://two.example": secondConnection
        ]
        let runtime = NostrRelayRuntime(
            transportFactory: { relayURL in
                RelayConcurrencyTestTransport(connection: connections[relayURL] ?? firstConnection)
            },
            autoReceive: false,
            heartbeatPolicy: .disabled
        )
        let packet = NostrREQPacket.forward(
            subscriptionID: "home-forward-one",
            filters: [["kinds": .ints([1])]],
            relayURLs: ["wss://one.example"]
        )

        try await runtime.setDefaultRelays(["wss://one.example"])
        try await runtime.installForward(packet)
        try await runtime.setDefaultRelays(["wss://one.example", "wss://two.example"])

        #expect(await runtime.activeSubscriptionIDs(relayURL: "wss://one.example") == ["home-forward-one"])
        #expect(await runtime.activeSubscriptionIDs(relayURL: "wss://two.example").isEmpty)
        #expect(await secondConnection.sentFrames().isEmpty)
    }

    @Test("The production receive loop recovers after the first connection attempt fails")
    func initialConnectionFailureKeepsReceiveLoopAlive() async throws {
        let connection = RelayConcurrencyTestConnection(blockReceiveWhenEmpty: true)
        let transport = RelayFailFirstConnectTransport(connection: connection)
        let runtime = NostrRelayRuntime(
            transportFactory: { _ in transport },
            autoReceive: true,
            retryPolicy: NostrRelayRuntimeRetryPolicy(
                maxAttempts: 2,
                initialDelayMilliseconds: 0,
                delayStepMilliseconds: 0
            ),
            heartbeatPolicy: .disabled
        )

        try await runtime.setDefaultRelays(["wss://relay.example"])
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(await transport.connectCallCount() >= 2)
        #expect(await runtime.connectionState(relayURL: "wss://relay.example") == .connected)
        await runtime.terminate()
    }

    @Test("Receive without a connection reports an error instead of spinning")
    func receiveWithoutConnectionThrows() async {
        let session = NostrRelaySession(
            relayURL: "wss://relay.example",
            transport: RelayConcurrencyTestTransport(connection: RelayConcurrencyTestConnection())
        )
        var receivedError: NostrRelayRuntimeError?

        do {
            try await session.receiveNext()
        } catch let error as NostrRelayRuntimeError {
            receivedError = error
        } catch {
            Issue.record("想定外のerror: \(error)")
        }

        #expect(receivedError == .connectionUnavailable(relayURL: "wss://relay.example"))
    }

    @Test("Cancelling the receive loop does not reconnect")
    func receiveLoopCancellationStopsReconnect() async throws {
        let connection = RelayConcurrencyTestConnection(blockReceiveWhenEmpty: true)
        let transport = RelayConcurrencyTestTransport(connection: connection)
        let runtime = NostrRelayRuntime(
            transportFactory: { _ in transport },
            autoReceive: true,
            retryPolicy: NostrRelayRuntimeRetryPolicy(
                maxAttempts: 0,
                initialDelayMilliseconds: 0,
                delayStepMilliseconds: 0
            ),
            heartbeatPolicy: .disabled
        )

        try await runtime.setDefaultRelays(["wss://relay.example"])
        await connection.waitUntilReceiveStarts()
        await runtime.terminate()
        try await Task.sleep(nanoseconds: 20_000_000)

        #expect(await transport.connectCallCount() == 1)
    }

    @Test("requestStarted reports each actual relay and author chunk")
    func requestStartedReportsActualChunksPerRelay() async throws {
        let firstConnection = RelayConcurrencyTestConnection()
        let secondConnection = RelayConcurrencyTestConnection()
        let connections = [
            "wss://one.example": firstConnection,
            "wss://two.example": secondConnection
        ]
        let runtime = NostrRelayRuntime(
            transportFactory: { relayURL in
                RelayConcurrencyTestTransport(connection: connections[relayURL] ?? firstConnection)
            },
            autoReceive: false,
            heartbeatPolicy: .disabled
        )
        let collector = RelayConcurrencyPacketCollector()
        let stream = await runtime.events()
        let collectTask = Task {
            for await packet in stream {
                await collector.append(packet)
            }
        }
        defer { collectTask.cancel() }
        let authors = (0..<251).map { String(format: "%064x", $0) }
        let packet = NostrREQPacket.forward(
            subscriptionID: "home-forward",
            filters: [["kinds": .ints([1]), "authors": .strings(authors)]]
        )

        try await runtime.setDefaultRelays(["wss://one.example", "wss://two.example"])
        try await runtime.installForward(packet)
        await collector.waitForRequestStarts(4)

        let starts = await collector.requestStarts()
        #expect(starts.count == 4)
        #expect(Set(starts.map(\.requestID)).count == 4)
        #expect(Set(starts.map(\.relayURL)) == Set(["wss://one.example", "wss://two.example"]))
        for relayURL in ["wss://one.example", "wss://two.example"] {
            let relayStarts = starts.filter { $0.relayURL == relayURL }
            #expect(Set(relayStarts.map(\.packet.subscriptionID)) == Set(["home-forward", "home-forward-chunk2"]))
            let chunks = relayStarts.compactMap { attempt -> [String]? in
                guard attempt.packet.filters.count == 1,
                      case .strings(let chunk)? = attempt.packet.filters.first?["authors"]
                else { return nil }
                return chunk
            }
            #expect(chunks.map(\.count).sorted() == [1, 250])
            #expect(Set(chunks.flatMap { $0 }) == Set(authors))
        }
    }

    @Test("A failed send ends the same request attempt as installFailed")
    func failedSendEndsRequestAsInstallFailed() async throws {
        let connection = RelayConcurrencyTestConnection(failSendImmediately: true)
        let runtime = NostrRelayRuntime(
            transportFactory: { _ in RelayConcurrencyTestTransport(connection: connection) },
            autoReceive: false,
            heartbeatPolicy: .disabled
        )
        let collector = RelayConcurrencyPacketCollector()
        let stream = await runtime.events()
        let collectTask = Task {
            for await packet in stream {
                await collector.append(packet)
            }
        }
        defer { collectTask.cancel() }
        let packet = NostrREQPacket.forward(
            subscriptionID: "home-forward",
            filters: [["kinds": .ints([1])]]
        )

        try await runtime.setDefaultRelays(["wss://relay.example"])
        var didFail = false
        do {
            try await runtime.installForward(packet)
        } catch {
            didFail = true
        }
        await collector.waitForRequestEnds(1)

        let starts = await collector.requestStarts()
        let ends = await collector.requestEnds()
        #expect(didFail)
        #expect(starts.count == 1)
        #expect(ends.count == 1)
        #expect(ends.first?.requestID == starts.first?.requestID)
        #expect(ends.first?.relayURL == "wss://relay.example")
        #expect(ends.first?.subscriptionID == "home-forward")
        #expect(ends.first?.reason == .installFailed)
        #expect(ends.first?.message != nil)
        #expect(await collector.installedRequestIDs().isEmpty)
    }

    @Test("Reconnect creates a new request attempt for the restored subscription")
    func reconnectCreatesNewRequestAttempt() async throws {
        let connection = RelayConcurrencyTestConnection()
        let session = NostrRelaySession(
            relayURL: "wss://relay.example",
            transport: RelayConcurrencyTestTransport(connection: connection)
        )
        let collector = RelayConcurrencyPacketCollector()
        let stream = await session.events()
        let collectTask = Task {
            for await packet in stream {
                await collector.append(packet)
            }
        }
        defer { collectTask.cancel() }
        let packet = NostrREQPacket.forward(
            subscriptionID: "home-forward",
            filters: [["kinds": .ints([1]), "since": .int(100)]]
        )

        try await session.install(packet)
        try await session.reconnectRestoringSubscriptions()
        await collector.waitForRequestStarts(2)
        await collector.waitForRequestEnds(1)
        await collector.waitForInstalledRequests(2)

        let starts = await collector.requestStarts()
        let ends = await collector.requestEnds()
        let installedRequestIDs = await collector.installedRequestIDs()
        #expect(starts.count == 2)
        #expect(starts[0].requestID != starts[1].requestID)
        #expect(starts.allSatisfy { $0.relayURL == "wss://relay.example" && $0.packet == packet })
        #expect(ends.count == 1)
        #expect(ends.first?.requestID == starts.first?.requestID)
        #expect(ends.first?.reason == .superseded)
        #expect(installedRequestIDs == starts.map(\.requestID))
    }

    private func eventFrame(subscriptionID: String, event: NostrEvent) throws -> String {
        let eventData = try JSONEncoder().encode(event)
        let eventObject = try JSONSerialization.jsonObject(with: eventData)
        let frameData = try JSONSerialization.data(
            withJSONObject: ["EVENT", subscriptionID, eventObject],
            options: [.sortedKeys]
        )
        return String(data: frameData, encoding: .utf8) ?? "[]"
    }
}

private actor RelayConcurrencyPacketCollector {
    private var collected: [NostrRelayRuntimePacket] = []

    func append(_ packet: NostrRelayRuntimePacket) {
        collected.append(packet)
    }

    func packets() -> [NostrRelayRuntimePacket] {
        collected
    }

    func states() -> [NostrRelayConnectionState] {
        collected.compactMap { packet in
            guard case .stateChanged(_, let state) = packet else { return nil }
            return state
        }
    }

    func requestStarts() -> [NostrRelayRequestAttempt] {
        collected.compactMap { packet in
            guard case .requestStarted(let attempt) = packet else { return nil }
            return attempt
        }
    }

    func requestEnds() -> [NostrRelayRequestAttemptEnd] {
        collected.compactMap { packet in
            guard case .requestEnded(let attemptEnd) = packet else { return nil }
            return attemptEnd
        }
    }

    func installedRequestIDs() -> [String] {
        collected.compactMap { packet in
            guard case .requestInstalled(let requestID, _, _, _) = packet else { return nil }
            return requestID
        }
    }

    func waitForRequestStarts(_ expectedCount: Int) async {
        for _ in 0..<1_000 {
            guard requestStarts().count < expectedCount else { return }
            await Task.yield()
        }
    }

    func waitForRequestEnds(_ expectedCount: Int) async {
        for _ in 0..<1_000 {
            guard requestEnds().count < expectedCount else { return }
            await Task.yield()
        }
    }

    func waitForInstalledRequests(_ expectedCount: Int) async {
        for _ in 0..<1_000 {
            guard installedRequestIDs().count < expectedCount else { return }
            await Task.yield()
        }
    }
}

private actor RelayConcurrencyTestTransport: NostrRelayTransport {
    private let connection: RelayConcurrencyTestConnection
    private var callCount = 0

    init(connection: RelayConcurrencyTestConnection) {
        self.connection = connection
    }

    func connect(relayURL: String) async throws -> any NostrRelayTransportConnection {
        callCount += 1
        return connection
    }

    func connectCallCount() -> Int {
        callCount
    }
}

private actor RelayFailFirstConnectTransport: NostrRelayTransport {
    private let connection: RelayConcurrencyTestConnection
    private var callCount = 0

    init(connection: RelayConcurrencyTestConnection) {
        self.connection = connection
    }

    func connect(relayURL: String) async throws -> any NostrRelayTransportConnection {
        callCount += 1
        if callCount == 1 {
            throw NostrRelayClientError.timeout
        }
        return connection
    }

    func connectCallCount() -> Int {
        callCount
    }
}

private actor RelayGatedConnectTransport: NostrRelayTransport {
    private let connection: RelayConcurrencyTestConnection
    private var connectStarted = false
    private var connectStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var connectRelease: CheckedContinuation<Void, Never>?

    init(connection: RelayConcurrencyTestConnection) {
        self.connection = connection
    }

    func connect(relayURL: String) async throws -> any NostrRelayTransportConnection {
        connectStarted = true
        for waiter in connectStartWaiters {
            waiter.resume()
        }
        connectStartWaiters = []
        await withCheckedContinuation { continuation in
            connectRelease = continuation
        }
        return connection
    }

    func waitUntilConnectStarts() async {
        guard !connectStarted else { return }
        await withCheckedContinuation { continuation in
            connectStartWaiters.append(continuation)
        }
    }

    func releaseConnect() {
        connectRelease?.resume()
        connectRelease = nil
    }
}

private actor RelayConcurrencyTestConnection: NostrRelayTransportConnection {
    private var inboundFrames: [String]
    private var outboundFrames: [String] = []
    private var shouldGateFirstSend: Bool
    private let failSendImmediately: Bool
    private let blockReceiveWhenEmpty: Bool
    private let shouldGateClose: Bool
    private var failGatedSendOnRelease = false
    private var firstSendStarted = false
    private var firstSendStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstSendRelease: CheckedContinuation<Void, Never>?
    private var receiveStarted = false
    private var receiveStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var blockedReceive: CheckedContinuation<String, Error>?
    private var closeStarted = false
    private var closeStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var closeRelease: CheckedContinuation<Void, Never>?

    init(
        inboundFrames: [String] = [],
        gateFirstSend: Bool = false,
        failSendImmediately: Bool = false,
        blockReceiveWhenEmpty: Bool = false,
        gateClose: Bool = false
    ) {
        self.inboundFrames = inboundFrames
        self.shouldGateFirstSend = gateFirstSend
        self.failSendImmediately = failSendImmediately
        self.blockReceiveWhenEmpty = blockReceiveWhenEmpty
        self.shouldGateClose = gateClose
    }

    func send(_ textFrame: String) async throws {
        outboundFrames.append(textFrame)
        if failSendImmediately {
            throw NostrRelayClientError.timeout
        }
        guard shouldGateFirstSend else { return }
        shouldGateFirstSend = false
        let shouldFail = failGatedSendOnRelease
        failGatedSendOnRelease = false
        firstSendStarted = true
        for waiter in firstSendStartWaiters {
            waiter.resume()
        }
        firstSendStartWaiters = []
        await withCheckedContinuation { continuation in
            firstSendRelease = continuation
        }
        if shouldFail {
            throw NostrRelayClientError.timeout
        }
    }

    func receive() async throws -> String {
        if !inboundFrames.isEmpty {
            return inboundFrames.removeFirst()
        }
        guard blockReceiveWhenEmpty else {
            throw NostrRelayClientError.timeout
        }
        receiveStarted = true
        for waiter in receiveStartWaiters {
            waiter.resume()
        }
        receiveStartWaiters = []
        return try await withCheckedThrowingContinuation { continuation in
            blockedReceive = continuation
        }
    }

    func close() async {
        blockedReceive?.resume(throwing: CancellationError())
        blockedReceive = nil
        guard shouldGateClose else { return }
        closeStarted = true
        for waiter in closeStartWaiters {
            waiter.resume()
        }
        closeStartWaiters = []
        await withCheckedContinuation { continuation in
            closeRelease = continuation
        }
    }

    func waitUntilFirstSendStarts() async {
        guard !firstSendStarted else { return }
        await withCheckedContinuation { continuation in
            firstSendStartWaiters.append(continuation)
        }
    }

    func gateNextSend(failOnRelease: Bool = false) {
        shouldGateFirstSend = true
        failGatedSendOnRelease = failOnRelease
        firstSendStarted = false
    }

    func releaseFirstSend() {
        firstSendRelease?.resume()
        firstSendRelease = nil
    }

    func waitUntilReceiveStarts() async {
        guard !receiveStarted else { return }
        await withCheckedContinuation { continuation in
            receiveStartWaiters.append(continuation)
        }
    }

    func waitUntilCloseStarts() async {
        guard !closeStarted else { return }
        await withCheckedContinuation { continuation in
            closeStartWaiters.append(continuation)
        }
    }

    func releaseClose() {
        closeRelease?.resume()
        closeRelease = nil
    }

    func sentFrames() -> [String] {
        outboundFrames
    }
}
