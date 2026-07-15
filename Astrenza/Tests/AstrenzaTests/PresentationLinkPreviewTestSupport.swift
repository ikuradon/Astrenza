import AstrenzaCore
@testable import Astrenza

struct PresentationLinkPreviewSchedule: Equatable {
    let scopeID: String
    let policy: NostrSyncPolicy
}

enum PresentationLinkPreviewEffectEvent: Equatable {
    case updated
    case failed(String)
}

@MainActor
final class PresentationLinkPreviewSpy: HomeTimelineLinkPreviewScheduling {
    private let result: Bool
    private var didUpdate: (@MainActor () -> Void)?
    private var didFail: (@MainActor (String) -> Void)?
    private(set) var schedules: [PresentationLinkPreviewSchedule] = []

    init(result: Bool = true) {
        self.result = result
    }

    func schedule(
        scopeID: String,
        policy: NostrSyncPolicy,
        didUpdate: @escaping @MainActor () -> Void,
        didFail: @escaping @MainActor (String) -> Void
    ) -> Bool {
        schedules.append(PresentationLinkPreviewSchedule(
            scopeID: scopeID,
            policy: policy
        ))
        self.didUpdate = didUpdate
        self.didFail = didFail
        return result
    }

    func completeUpdate() {
        didUpdate?()
    }

    func fail(_ message: String) {
        didFail?(message)
    }
}

@MainActor
final class PresentationLinkPreviewEffectProbe {
    private(set) var events: [PresentationLinkPreviewEffectEvent] = []

    var effects: HomeTimelineLinkPreviewEffects {
        HomeTimelineLinkPreviewEffects(
            didUpdate: { [self] in events.append(.updated) },
            didFail: { [self] message in events.append(.failed(message)) }
        )
    }
}
