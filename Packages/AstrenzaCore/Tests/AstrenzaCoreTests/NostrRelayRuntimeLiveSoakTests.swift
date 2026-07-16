import Foundation
import Testing
@testable import AstrenzaCore

@Suite("Nostr relay runtime live soak")
struct NostrRelayRuntimeLiveSoakTests {
    @Test(
        "公開Relayのforward購読はEOSE後のEVENTを取り零さずterminalで停止する",
        .enabled(if: LiveRelaySoakEnvironment.isEnabled),
        .timeLimit(.minutes(3))
    )
    func publicRelaysDeliverEveryPostEOSEEventAndTerminateCleanly() async throws {
        let relayURLs = try LiveRelaySoakEnvironment.relayURLs()
        let runID = UUID().uuidString.lowercased()
        let startedAt = Int(Date().timeIntervalSince1970)
        let plans = try relayURLs.enumerated().map { index, relayURL in
            try LiveRelayProbePlan(
                relayURL: relayURL,
                index: index,
                runID: runID,
                since: startedAt - 5
            )
        }
        let expectedSubscriptions = Set(plans.map(\.subscription))

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        let urlSession = URLSession(configuration: configuration)
        let runtime = NostrRelayRuntime(
            transportFactory: { _ in NostrURLSessionRelayTransport(urlSession: urlSession) },
            autoReceive: true,
            heartbeatPolicy: .disabled,
            backwardPolicy: .disabled
        )
        let recorder = LiveRelaySoakRecorder()
        let stream = await runtime.events()
        let collectTask = Task {
            for await packet in stream {
                await recorder.record(packet)
            }
            await recorder.finish()
        }

        let snapshotBeforeTermination: LiveRelaySoakSnapshot
        do {
            try await runtime.setDefaultRelays(relayURLs)
            _ = try await waitForLiveRelayMilestone(
                .connected(Set(relayURLs)),
                phase: "Relay接続",
                recorder: recorder
            )

            for plan in plans {
                try await runtime.installForward(plan.packet)
            }
            _ = try await waitForLiveRelayMilestone(
                .eose(expectedSubscriptions),
                phase: "forward REQのEOSE",
                recorder: recorder
            )

            #expect(await runtime.activeForwardSubscriptionIDs() == plans.map(\.subscriptionID).sorted())
            for plan in plans {
                #expect(
                    await runtime.activeSubscriptionIDs(relayURL: plan.relayURL) == [plan.subscriptionID],
                    "\(plan.relayURL) のforward購読がEOSE後もactiveである必要があります"
                )
            }

            let probeEvents = try await makeProbeEvents(plans: plans, runID: runID)
            let publications = await publishProbeEvents(
                probeEvents,
                publisher: NostrOutboxRelayPublisher(
                    relayRuntime: runtime,
                    timeoutNanoseconds: 12_000_000_000
                )
            )
            if let rejected = publications.first(where: { !$0.result.accepted }) {
                throw LiveRelaySoakError.publicationRejected(
                    relayURL: rejected.probe.relayURL,
                    eventID: rejected.probe.event.id,
                    message: rejected.result.message ?? "応答なし"
                )
            }

            let expectedEventIDs = Set(probeEvents.map(\.event.id))
            snapshotBeforeTermination = try await waitForLiveRelayMilestone(
                .postEOSEEvents(expectedEventIDs),
                phase: "EOSE後のEVENT受信",
                recorder: recorder
            )

            let expectedObservations = Set(probeEvents.map { probe in
                LiveRelayEventObservation(
                    relayURL: probe.relayURL,
                    subscriptionID: probe.subscriptionID,
                    eventID: probe.event.id,
                    wasReceivedAfterEOSE: true
                )
            })
            #expect(Set(snapshotBeforeTermination.events) == expectedObservations)
            #expect(Set(snapshotBeforeTermination.events.map(\.eventID)) == expectedEventIDs)
            #expect(snapshotBeforeTermination.events.count == expectedEventIDs.count)
            #expect(snapshotBeforeTermination.events.allSatisfy { $0.wasReceivedAfterEOSE })
            #expect(snapshotBeforeTermination.duplicateEventIDs.isEmpty)
        } catch {
            await runtime.terminate()
            await collectTask.value
            urlSession.invalidateAndCancel()
            throw error
        }

        await runtime.terminate()
        await collectTask.value
        urlSession.invalidateAndCancel()

        let terminalSnapshot = await recorder.snapshot()
        #expect(terminalSnapshot.isFinished)
        #expect(terminalSnapshot.events == snapshotBeforeTermination.events)
        #expect(terminalSnapshot.duplicateEventIDs.isEmpty)
        #expect(terminalSnapshot.closedSubscriptions.isEmpty)
        #expect(await runtime.defaultRelayURLs().isEmpty)
        #expect(await runtime.activeForwardSubscriptionIDs().isEmpty)
        for relayURL in relayURLs {
            #expect(await runtime.activeSubscriptionIDs(relayURL: relayURL).isEmpty)
        }
    }
}

private enum LiveRelaySoakEnvironment {
    static let enableVariable = "ASTRENZA_LIVE_NOSTR_SOAK_TEST"
    static let relayVariable = "ASTRENZA_LIVE_NOSTR_RELAYS"

    static var isEnabled: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment[enableVariable] == "1" ||
            environment["TEST_RUNNER_\(enableVariable)"] == "1"
    }

    static func relayURLs() throws -> [String] {
        let value = ProcessInfo.processInfo.environment[relayVariable]
            ?? "wss://nos.lol,wss://relay.damus.io"
        var seen: Set<String> = []
        let relayURLs = value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { seen.insert($0).inserted }

        guard (2...4).contains(relayURLs.count) else {
            throw LiveRelaySoakError.invalidConfiguration(
                "\(relayVariable) には2〜4個の公開Relayをカンマ区切りで指定してください"
            )
        }
        guard relayURLs.allSatisfy({ URL(string: $0)?.scheme == "wss" }) else {
            throw LiveRelaySoakError.invalidConfiguration(
                "\(relayVariable) にはwss URLだけを指定してください"
            )
        }
        return relayURLs
    }
}

private struct LiveRelayProbePlan: Sendable {
    let relayURL: String
    let subscriptionID: String
    let signer: NostrPrivateKeySigner
    let packet: NostrREQPacket

    init(relayURL: String, index: Int, runID: String, since: Int) throws {
        self.relayURL = relayURL
        let compactRunID = runID.replacingOccurrences(of: "-", with: "")
        subscriptionID = "astrenza-soak-\(compactRunID.prefix(12))-\(index)"
        let randomKeyMaterial = UUID().uuidString
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
        signer = try NostrPrivateKeySigner(privateKeyHex: randomKeyMaterial + randomKeyMaterial)
        packet = NostrREQPacket.forward(
            subscriptionID: subscriptionID,
            filters: [[
                "authors": .strings([signer.pubkey]),
                "kinds": .ints([20_000]),
                "since": .int(since)
            ]],
            relayURLs: [relayURL]
        )
    }

    var subscription: LiveRelaySubscription {
        LiveRelaySubscription(relayURL: relayURL, subscriptionID: subscriptionID)
    }
}

private struct LiveRelayProbeEvent: Sendable {
    let relayURL: String
    let subscriptionID: String
    let event: NostrEvent
}

private func makeProbeEvents(
    plans: [LiveRelayProbePlan],
    runID: String
) async throws -> [LiveRelayProbeEvent] {
    let createdAt = Int(Date().timeIntervalSince1970)
    var probes: [LiveRelayProbeEvent] = []
    for plan in plans {
        for sequence in 0..<2 {
            let event = try await plan.signer.sign(NostrUnsignedEvent(
                pubkey: plan.signer.pubkey,
                createdAt: createdAt,
                kind: 20_000,
                tags: [
                    ["client", "astrenza-live-soak"],
                    ["nonce", "\(runID)-\(sequence)"]
                ],
                content: "Astrenza live relay soak \(runID) #\(sequence)"
            ))
            probes.append(LiveRelayProbeEvent(
                relayURL: plan.relayURL,
                subscriptionID: plan.subscriptionID,
                event: event
            ))
        }
    }
    return probes
}

private struct LiveRelayPublication: Sendable {
    let probe: LiveRelayProbeEvent
    let result: NostrOutboxRelayPublishResult
}

private func publishProbeEvents(
    _ probes: [LiveRelayProbeEvent],
    publisher: NostrOutboxRelayPublisher
) async -> [LiveRelayPublication] {
    await withTaskGroup(of: LiveRelayPublication.self) { group in
        for probe in probes {
            group.addTask {
                LiveRelayPublication(
                    probe: probe,
                    result: await publisher.publish(event: probe.event, relayURL: probe.relayURL)
                )
            }
        }

        var publications: [LiveRelayPublication] = []
        for await publication in group {
            publications.append(publication)
        }
        return publications.sorted { lhs, rhs in
            if lhs.probe.relayURL == rhs.probe.relayURL {
                return lhs.probe.event.id < rhs.probe.event.id
            }
            return lhs.probe.relayURL < rhs.probe.relayURL
        }
    }
}

private struct LiveRelaySubscription: Hashable, Sendable {
    let relayURL: String
    let subscriptionID: String
}

private struct LiveRelayEventObservation: Hashable, Sendable {
    let relayURL: String
    let subscriptionID: String
    let eventID: String
    let wasReceivedAfterEOSE: Bool
}

private struct LiveRelayClosedObservation: Sendable {
    let relayURL: String
    let subscriptionID: String
    let message: String
}

private struct LiveRelaySoakSnapshot: Sendable {
    let connectionStates: [String: NostrRelayConnectionState]
    let eoseSubscriptions: Set<LiveRelaySubscription>
    let events: [LiveRelayEventObservation]
    let duplicateEventIDs: Set<String>
    let closedSubscriptions: [LiveRelayClosedObservation]
    let notices: [String]
    let packetCount: Int
    let isFinished: Bool

    var diagnostics: String {
        let states = connectionStates
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.rawValue)" }
            .joined(separator: ",")
        return "states=[\(states)] eose=\(eoseSubscriptions.count) " +
            "events=\(events.count) duplicates=\(duplicateEventIDs.sorted()) " +
            "notices=\(Array(notices.suffix(3)))"
    }
}

private actor LiveRelaySoakRecorder {
    private var connectionStates: [String: NostrRelayConnectionState] = [:]
    private var eoseSubscriptions: Set<LiveRelaySubscription> = []
    private var events: [LiveRelayEventObservation] = []
    private var receivedEventIDs: Set<String> = []
    private var duplicateEventIDs: Set<String> = []
    private var closedSubscriptions: [LiveRelayClosedObservation] = []
    private var notices: [String] = []
    private var packetCount = 0
    private var isFinished = false
    private var continuations: [UUID: AsyncStream<LiveRelaySoakSnapshot>.Continuation] = [:]

    func record(_ packet: NostrRelayRuntimePacket) {
        packetCount += 1
        switch packet {
        case .stateChanged(let relayURL, let state):
            connectionStates[relayURL] = state
        case .eose(let relayURL, let subscriptionID):
            eoseSubscriptions.insert(LiveRelaySubscription(
                relayURL: relayURL,
                subscriptionID: subscriptionID
            ))
        case .event(let relayURL, let subscriptionID, let event):
            let subscription = LiveRelaySubscription(
                relayURL: relayURL,
                subscriptionID: subscriptionID
            )
            if !receivedEventIDs.insert(event.id).inserted {
                duplicateEventIDs.insert(event.id)
            }
            events.append(LiveRelayEventObservation(
                relayURL: relayURL,
                subscriptionID: subscriptionID,
                eventID: event.id,
                wasReceivedAfterEOSE: eoseSubscriptions.contains(subscription)
            ))
        case .closed(let relayURL, let subscriptionID, let message):
            closedSubscriptions.append(LiveRelayClosedObservation(
                relayURL: relayURL,
                subscriptionID: subscriptionID,
                message: message
            ))
        case .notice(let relayURL, let message):
            notices.append("\(relayURL): \(message)")
        case .auth(let relayURL, let challenge):
            notices.append("\(relayURL): AUTH \(challenge)")
        case .traffic, .requestStarted, .requestInstalled, .requestEnded,
             .timeout, .backwardCompleted:
            break
        }
        emitSnapshot()
    }

    func finish() {
        isFinished = true
        emitSnapshot()
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations = [:]
    }

    func snapshot() -> LiveRelaySoakSnapshot {
        LiveRelaySoakSnapshot(
            connectionStates: connectionStates,
            eoseSubscriptions: eoseSubscriptions,
            events: events,
            duplicateEventIDs: duplicateEventIDs,
            closedSubscriptions: closedSubscriptions,
            notices: notices,
            packetCount: packetCount,
            isFinished: isFinished
        )
    }

    func snapshots() -> AsyncStream<LiveRelaySoakSnapshot> {
        let observerID = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            continuations[observerID] = continuation
            continuation.yield(snapshot())
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeContinuation(observerID)
                }
            }
        }
    }

    private func emitSnapshot() {
        let current = snapshot()
        for continuation in continuations.values {
            continuation.yield(current)
        }
    }

    private func removeContinuation(_ observerID: UUID) {
        continuations[observerID] = nil
    }
}

private enum LiveRelaySoakMilestone: Sendable {
    case connected(Set<String>)
    case eose(Set<LiveRelaySubscription>)
    case postEOSEEvents(Set<String>)

    func isSatisfied(by snapshot: LiveRelaySoakSnapshot) -> Bool {
        switch self {
        case .connected(let relayURLs):
            return relayURLs.allSatisfy { snapshot.connectionStates[$0] == .connected }
        case .eose(let subscriptions):
            return subscriptions.isSubset(of: snapshot.eoseSubscriptions)
        case .postEOSEEvents(let eventIDs):
            let receivedEventIDs = Set(snapshot.events.lazy
                .filter(\.wasReceivedAfterEOSE)
                .map(\.eventID))
            return eventIDs.isSubset(of: receivedEventIDs)
        }
    }
}

private func waitForLiveRelayMilestone(
    _ milestone: LiveRelaySoakMilestone,
    phase: String,
    recorder: LiveRelaySoakRecorder,
    timeout: Duration = .seconds(45)
) async throws -> LiveRelaySoakSnapshot {
    let updates = await recorder.snapshots()
    return try await withThrowingTaskGroup(of: LiveRelaySoakSnapshot.self) { group in
        group.addTask {
            for await snapshot in updates {
                if let closed = snapshot.closedSubscriptions.first {
                    throw LiveRelaySoakError.subscriptionClosed(
                        relayURL: closed.relayURL,
                        subscriptionID: closed.subscriptionID,
                        message: closed.message
                    )
                }
                if milestone.isSatisfied(by: snapshot) {
                    return snapshot
                }
                if snapshot.isFinished {
                    throw LiveRelaySoakError.streamFinished(phase: phase)
                }
            }
            throw LiveRelaySoakError.streamFinished(phase: phase)
        }
        group.addTask {
            try await Task.sleep(for: timeout)
            let snapshot = await recorder.snapshot()
            throw LiveRelaySoakError.timedOut(phase: phase, diagnostics: snapshot.diagnostics)
        }
        defer { group.cancelAll() }
        guard let snapshot = try await group.next() else {
            throw LiveRelaySoakError.streamFinished(phase: phase)
        }
        return snapshot
    }
}

private enum LiveRelaySoakError: Error, CustomStringConvertible, Sendable {
    case invalidConfiguration(String)
    case publicationRejected(relayURL: String, eventID: String, message: String)
    case subscriptionClosed(relayURL: String, subscriptionID: String, message: String)
    case streamFinished(phase: String)
    case timedOut(phase: String, diagnostics: String)

    var description: String {
        switch self {
        case .invalidConfiguration(let message):
            message
        case .publicationRejected(let relayURL, let eventID, let message):
            "\(relayURL) がprobe EVENT \(eventID)を拒否しました: \(message)"
        case .subscriptionClosed(let relayURL, let subscriptionID, let message):
            "\(relayURL) が購読 \(subscriptionID) を終了しました: \(message)"
        case .streamFinished(let phase):
            "\(phase)の完了前にruntime event streamが終了しました"
        case .timedOut(let phase, let diagnostics):
            "\(phase)が45秒以内に完了しませんでした: \(diagnostics)"
        }
    }
}
