import Testing
@testable import Astrenza

@Suite("Home Store runtime coordinator")
@MainActor
struct HomeStoreRuntimeCoordinatorTests {
    @Test("Runtime operations request fresh matching contexts")
    func routesRuntimeOperations() async {
        let fixture = StoreRuntimeCoordinatorFixture()
        let interaction = fixture.interactionFixture

        #expect(fixture.coordinator.startSession() ==
            fixture.runtime.sessionStart)
        #expect(fixture.coordinator.provisionalBootstrapRelayURLs(
            account: interaction.account
        ) == fixture.runtime.provisionalRelayURLs)
        await fixture.coordinator.configure(
            account: interaction.account,
            forceInstall: true
        )
        await fixture.coordinator.handleEvent(
            relayURL: interaction.relayURLs[0],
            subscriptionID: interaction.subscriptionID,
            event: interaction.event
        )

        #expect(fixture.contexts.reads == [
            .runtimeInteraction,
            .runtimeState,
            .runtimeInteraction,
            .runtimeEvent
        ])
        #expect(fixture.runtime.calls == [
            .start(accountID: interaction.account.pubkey),
            .provisional(
                accountID: interaction.account.pubkey,
                stateAccountID: interaction.account.pubkey
            ),
            .configure(
                accountID: interaction.account.pubkey,
                forceInstall: true,
                contextID: interaction.account.pubkey
            ),
            .event(
                relayURL: interaction.relayURLs[0],
                subscriptionID: interaction.subscriptionID,
                eventID: interaction.event.id,
                accountID: interaction.account.pubkey
            )
        ])
    }

    @Test("Dependency, backward, and link preview operations keep their boundaries")
    func routesSupportingOperations() async {
        let fixture = StoreRuntimeCoordinatorFixture()
        let interaction = fixture.interactionFixture

        #expect(await fixture.coordinator.enqueueDependencies(
            for: interaction.event
        ))
        fixture.coordinator.handleBackwardCompletion(interaction.completion)
        #expect(fixture.coordinator.scheduleLinkPreviewResolution())

        #expect(fixture.contexts.reads == [
            .dependencyState,
            .runtimeApplication,
            .backward,
            .linkPreview
        ])
        #expect(fixture.runtime.calls == [
            .dependencies(
                eventID: interaction.event.id,
                accountID: interaction.account.pubkey
            )
        ])
        #expect(fixture.interactionFixture.probe.runtimeApplications == [
            .sourceInstallFailed("coordinator dependency probe")
        ])
        #expect(fixture.backward.calls.count == 1)
        #expect(fixture.backward.calls[0].groupID ==
            interaction.completion.groupID)
        #expect(fixture.backward.calls[0].accountID ==
            interaction.account.pubkey)
        #expect(fixture.linkPreview.accountIDs == [
            interaction.account.pubkey
        ])
        #expect(fixture.contexts.linkPreviewUpdateCount == 1)
    }

    @Test("Setup reset and debug runtime hooks route through the coordinator")
    func routesRuntimeControlHooks() async {
        let fixture = StoreRuntimeCoordinatorFixture()
        let interaction = fixture.interactionFixture

        fixture.coordinator.resetSetup()
        #if DEBUG
        #expect(fixture.coordinator.ensureLifecycle(
            accountID: interaction.account.pubkey
        ) == fixture.runtime.lifecycle)
        await fixture.coordinator.handlePacket(
            interaction.packet,
            isActive: true
        )
        #endif

        #if DEBUG
        #expect(fixture.runtime.calls == [
            .reset,
            .ensureLifecycle(accountID: interaction.account.pubkey),
            .packet(
                isActive: true,
                accountID: interaction.account.pubkey
            )
        ])
        #expect(fixture.contexts.reads == [.runtimeInteraction])
        #else
        #expect(fixture.runtime.calls == [.reset])
        #endif
    }
}
