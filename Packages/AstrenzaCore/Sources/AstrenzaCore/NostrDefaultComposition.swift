import Foundation
import NostrCryptoSecp256k1
import NostrHomeFeature
import NostrProtocol
import NostrReconciliationNegentropy
import NostrRelay
import NostrSync

public extension NostrRelaySession {
    init(
        relayURL: String,
        transport: any NostrRelayTransport
    ) {
        self.init(
            relayURL: relayURL,
            transport: transport,
            eventValidator: NostrEventValidator()
        )
    }
}

public extension NostrRelayRuntime {
    init(
        transportFactory: @escaping TransportFactory,
        autoReceive: Bool = true,
        retryPolicy: NostrRelayRuntimeRetryPolicy = NostrRelayRuntimeRetryPolicy(),
        retryJitterSource: @escaping RetryJitterSource = {
            Double.random(in: 0...1)
        },
        reconnectOverlapSeconds: Int = 10,
        heartbeatPolicy: NostrRelayRuntimeHeartbeatPolicy = NostrRelayRuntimeHeartbeatPolicy(),
        backwardPolicy: NostrRelayRuntimeBackwardPolicy = NostrRelayRuntimeBackwardPolicy(),
        relayInformationFetcher: (any NostrRelayInformationFetching)? = nil,
        workSchedulerPolicy: NostrRelayWorkSchedulerPolicy = NostrRelayWorkSchedulerPolicy()
    ) {
        self.init(
            transportFactory: transportFactory,
            eventValidator: NostrEventValidator(),
            autoReceive: autoReceive,
            retryPolicy: retryPolicy,
            retryJitterSource: retryJitterSource,
            reconnectOverlapSeconds: reconnectOverlapSeconds,
            heartbeatPolicy: heartbeatPolicy,
            backwardPolicy: backwardPolicy,
            relayInformationFetcher: relayInformationFetcher,
            workSchedulerPolicy: workSchedulerPolicy
        )
    }
}

public extension NostrRelayClient {
    init(
        urlSession: URLSession = .shared,
        timeoutNanoseconds: UInt64 = 7_000_000_000
    ) {
        self.init(
            eventValidator: NostrEventValidator(),
            reconciliationFactory: NegentropySwiftReconciliationSessionFactory(),
            urlSession: urlSession,
            timeoutNanoseconds: timeoutNanoseconds
        )
    }
}

public extension NIP77SyncSession {
    convenience init(
        localEvents: [NostrEvent],
        frameSizeLimit: Int = 60_000
    ) throws {
        try self.init(
            localEvents: localEvents,
            frameSizeLimit: frameSizeLimit,
            reconciliationFactory: NegentropySwiftReconciliationSessionFactory()
        )
    }
}

public extension NostrRelayRuntimeClient {
    init(runtime: NostrRelayRuntime) {
        self.init(
            runtime: runtime,
            fallback: NostrRelayClient()
        )
    }
}

public extension NostrHomeTimelineLoader {
    init(
        nip05Resolver: any NostrNIP05Resolving = NostrNIP05Resolver(),
        bootstrapRelays: [String] = NostrHomeTimelineLoader.defaultBootstrapRelays,
        pageLimit: Int = 100
    ) {
        self.init(
            relayClient: NostrRelayClient(),
            nip05Resolver: nip05Resolver,
            bootstrapRelays: bootstrapRelays,
            pageLimit: pageLimit
        )
    }
}
