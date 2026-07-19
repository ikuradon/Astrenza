import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var step: OnboardingStep = .welcome
    @State private var accessMode: OnboardingAccessMode = .login
    @State private var credential = ""
    @State private var displayName = ""
    @State private var nip05 = ""
    @State private var about = ""
    @State private var isNIP65Enabled = true
    @State private var selectedRecommendations: Set<OnboardingRecommendation.ID> = Set(OnboardingRecommendation.mockValues.map(\.id))

    var body: some View {
        ZStack {
            OnboardingBackground()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(spacing: AstrenzaSpacing.point24) {
                        stepContent
                    }
                    .padding(.horizontal, AstrenzaSpacing.point22)
                    .padding(.top, AstrenzaSpacing.point18)
                    .padding(.bottom, 118)
                }
                .scrollIndicators(.hidden)
            }

            VStack {
                Spacer()
                bottomActionBar
            }
        }
        .foregroundStyle(.white)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    dismiss()
                }
                .font(.astrenza(.point18, weight: .bold, design: .rounded))
                .foregroundStyle(AstrenzaPalette.Onboarding.accent)
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            welcomeStep
        case .chooseAccess:
            chooseAccessStep
        case .enterCredential:
            credentialStep
        case .createProfile:
            createProfileStep
        case .relayDiscovery:
            relayDiscoveryStep
        case .followSuggestions:
            followSuggestionsStep
        }
    }

    private var header: some View {
        VStack(spacing: AstrenzaSpacing.point12) {
            OnboardingStepIndicator(currentStep: step)
                .padding(.top, AstrenzaSpacing.point10)

            Text(step.title)
                .font(.astrenza(.point30, weight: .black, design: .rounded))
                .multilineTextAlignment(.center)

            if let subtitle = step.subtitle {
                Text(subtitle)
                    .font(.astrenza(.point15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.74))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AstrenzaSpacing.point18)
            }
        }
        .padding(.horizontal, AstrenzaSpacing.point20)
        .padding(.top, AstrenzaSpacing.point6)
        .padding(.bottom, AstrenzaSpacing.point10)
    }

    private var welcomeStep: some View {
        VStack(spacing: AstrenzaSpacing.point28) {
            OnboardingHeroMark()
                .padding(.top, AstrenzaSpacing.point24)

            VStack(spacing: AstrenzaSpacing.point10) {
                Text("Welcome to Astrenza")
                    .font(.astrenza(.point34, weight: .black, design: .rounded))
                    .multilineTextAlignment(.center)

                Text("A Nostr client for timelines, relays, and keys that stay understandable.")
                    .font(.astrenza(.point20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
            }

            OnboardingInfoCard(
                icon: "key.horizontal.fill",
                title: "Your account is your key",
                message: "Log in with whatever Nostr identity material you already have, or create a fresh key and profile."
            )
        }
    }

    private var chooseAccessStep: some View {
        VStack(spacing: AstrenzaSpacing.point14) {
            ForEach(OnboardingAccessMode.allCases) { mode in
                Button {
                    withAnimation(.snappy(duration: AstrenzaMotion.emphasized)) {
                        accessMode = mode
                    }
                } label: {
                    OnboardingAccessModeCard(mode: mode, isSelected: mode == accessMode)
                }
                .buttonStyle(.plain)
            }

            OnboardingInfoCard(
                icon: "antenna.radiowaves.left.and.right",
                title: "Relay discovery is part of login",
                message: "When the account is resolved, Astrenza tries NIP-65 first, then falls back to a small bootstrap set so the first timeline has somewhere to load from."
            )
        }
    }

    private var credentialStep: some View {
        VStack(spacing: AstrenzaSpacing.point16) {
            OnboardingInputPanel(
                title: "Nostr login",
                placeholder: "nsec, ncryptsec, recovery words, bunker://, npub, or NIP-05",
                text: $credential,
                isSecure: detectedLoginKind == .privateKey
            )

            VStack(spacing: AstrenzaSpacing.point10) {
                ForEach(detectedLoginKind.detailRows) { row in
                    OnboardingProtocolRow(row: row)
                }
            }
        }
    }

    private var createProfileStep: some View {
        VStack(spacing: AstrenzaSpacing.point18) {
            OnboardingProfileAvatar()

            OnboardingInputPanel(title: "Display name", placeholder: "User Astral", text: $displayName)
            OnboardingInputPanel(title: "NIP-05 (optional)", placeholder: "_@example.com or name@example.com", text: $nip05)
            OnboardingInputPanel(title: "About", placeholder: "What should people know about you?", text: $about, axis: .vertical)

            OnboardingInfoCard(
                icon: "lock.shield.fill",
                title: "Backup before posting",
                message: "The real flow should show NIP-06 recovery words and require a backup confirmation before the first signed event."
            )
        }
    }

    private var relayDiscoveryStep: some View {
        VStack(spacing: AstrenzaSpacing.point16) {
            Toggle(isOn: $isNIP65Enabled.animation(.snappy(duration: AstrenzaMotion.relaxed))) {
                VStack(alignment: .leading, spacing: AstrenzaSpacing.point4) {
                    Text("Fetch NIP-65 relay list automatically")
                        .font(.astrenza(.point17, weight: .black, design: .rounded))
                    Text("Read/write relay hints are internal, but the connection plan should be visible here.")
                        .font(.astrenza(.point13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                }
            }
            .tint(AstrenzaPalette.Onboarding.accent)
            .padding(AstrenzaSpacing.point18)
            .background(AstrenzaPalette.Onboarding.card, in: RoundedRectangle(cornerRadius: AstrenzaRadius.point24))

            VStack(spacing: AstrenzaSpacing.point10) {
                ForEach(OnboardingRelayPlan.mockValues(isNIP65Enabled: isNIP65Enabled)) { relay in
                    OnboardingRelayRow(relay: relay)
                }
            }
        }
    }

    private var followSuggestionsStep: some View {
        VStack(spacing: AstrenzaSpacing.point18) {
            Text("Follow a few Nostr signals?")
                .font(.astrenza(.point26, weight: .black, design: .rounded))
                .multilineTextAlignment(.center)

            VStack(spacing: 0) {
                ForEach(OnboardingRecommendation.mockValues) { recommendation in
                    Button {
                        if selectedRecommendations.contains(recommendation.id) {
                            selectedRecommendations.remove(recommendation.id)
                        } else {
                            selectedRecommendations.insert(recommendation.id)
                        }
                    } label: {
                        OnboardingRecommendationRow(
                            recommendation: recommendation,
                            isSelected: selectedRecommendations.contains(recommendation.id)
                        )
                    }
                    .buttonStyle(.plain)

                    if recommendation.id != OnboardingRecommendation.mockValues.last?.id {
                        Divider().overlay(.white.opacity(0.14))
                    }
                }
            }
            .background(AstrenzaPalette.Onboarding.card, in: RoundedRectangle(cornerRadius: AstrenzaRadius.point26))

            OnboardingInfoCard(
                icon: "checkmark.seal.fill",
                title: "Mock finish",
                message: "This does not persist an account yet. It gives us the UI shell for login, profile setup, relay bootstrap, and first-follow selection."
            )
        }
    }

    private var bottomActionBar: some View {
        HStack(spacing: AstrenzaSpacing.point14) {
            if step != .welcome {
                Button {
                    withAnimation(.snappy(duration: AstrenzaMotion.slow)) {
                        step = step.previous(for: accessMode)
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.astrenza(.point19, weight: .black))
                        .frame(width: 56, height: 56)
                        .background(.white.opacity(0.18), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            }

            Button {
                advance()
            } label: {
                HStack(spacing: AstrenzaSpacing.point10) {
                    Text(step.primaryButtonTitle(for: accessMode))
                    Image(systemName: step == .followSuggestions ? "checkmark" : "arrow.up")
                }
                .font(.astrenza(.point18, weight: .black, design: .rounded))
                .foregroundStyle(.black.opacity(0.82))
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(.white.opacity(0.82), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AstrenzaSpacing.point22)
        .padding(.top, AstrenzaSpacing.point14)
        .padding(.bottom, AstrenzaSpacing.point18)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    LinearGradient(
                        colors: [.clear, AstrenzaPalette.Onboarding.background.opacity(0.85)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .ignoresSafeArea()
        }
    }

    private func advance() {
        if step == .followSuggestions {
            dismiss()
            return
        }

        withAnimation(.snappy(duration: AstrenzaMotion.slow)) {
            step = step.next(for: accessMode)
        }
    }

    private var detectedLoginKind: OnboardingLoginKind {
        OnboardingLoginKind.detect(from: credential)
    }
}

private enum OnboardingStep: Int, CaseIterable {
    case welcome
    case chooseAccess
    case enterCredential
    case createProfile
    case relayDiscovery
    case followSuggestions

    var title: String {
        switch self {
        case .welcome: "Start with Nostr"
        case .chooseAccess: "How do you want to enter?"
        case .enterCredential: "Connect your identity"
        case .createProfile: "Create your profile"
        case .relayDiscovery: "Find your relays"
        case .followSuggestions: "Warm up the timeline"
        }
    }

    var subtitle: String? {
        switch self {
        case .welcome:
            nil
        case .chooseAccess:
            "Nostr login is about signing authority, not a server account."
        case .enterCredential:
            "Private keys can post. Public identifiers can only read."
        case .createProfile:
            "This mock keeps the profile fields simple and leaves key generation to the real auth layer."
        case .relayDiscovery:
            "NIP-65 tells us where to read from and where to publish."
        case .followSuggestions:
            "Optional follows help a fresh account avoid an empty first timeline."
        }
    }

    func next(for mode: OnboardingAccessMode) -> OnboardingStep {
        switch self {
        case .welcome:
            .chooseAccess
        case .chooseAccess:
            mode == .newAccount ? .createProfile : .enterCredential
        case .enterCredential, .createProfile:
            .relayDiscovery
        case .relayDiscovery:
            .followSuggestions
        case .followSuggestions:
            .followSuggestions
        }
    }

    func previous(for mode: OnboardingAccessMode) -> OnboardingStep {
        switch self {
        case .welcome:
            .welcome
        case .chooseAccess:
            .welcome
        case .enterCredential, .createProfile:
            .chooseAccess
        case .relayDiscovery:
            mode == .newAccount ? .createProfile : .enterCredential
        case .followSuggestions:
            .relayDiscovery
        }
    }

    func primaryButtonTitle(for mode: OnboardingAccessMode) -> String {
        switch self {
        case .welcome:
            "Get Started"
        case .chooseAccess:
            mode == .newAccount ? "Create Profile" : "Continue"
        case .enterCredential:
            "Continue"
        case .createProfile:
            "Generate Mock Key"
        case .relayDiscovery:
            "Use These Relays"
        case .followSuggestions:
            "Enter Astrenza"
        }
    }
}

private enum OnboardingAccessMode: String, CaseIterable, Identifiable {
    case login
    case newAccount

    var id: String { rawValue }

    var title: String {
        switch self {
        case .login: "Log in"
        case .newAccount: "Create a new account"
        }
    }

    var subtitle: String {
        switch self {
        case .login: "Paste nsec, ncryptsec, recovery words, bunker://, npub, or NIP-05."
        case .newAccount: "Generate a fresh key, then publish kind:0 and relay list."
        }
    }

    var icon: String {
        switch self {
        case .login: "key.fill"
        case .newAccount: "sparkles"
        }
    }
}

private enum OnboardingLoginKind {
    case unknown
    case privateKey
    case remoteSigner
    case readOnly

    static func detect(from credential: String) -> OnboardingLoginKind {
        let trimmed = credential.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty {
            return .unknown
        }
        if trimmed.hasPrefix("bunker://") || trimmed.hasPrefix("nostrconnect://") {
            return .remoteSigner
        }
        if trimmed.hasPrefix("npub1") || trimmed.contains("@") {
            return .readOnly
        }
        if trimmed.hasPrefix("nsec1") || trimmed.hasPrefix("ncryptsec1") {
            return .privateKey
        }

        let wordCount = trimmed.split(separator: " ").count
        if wordCount >= 12 {
            return .privateKey
        }

        return .unknown
    }

    var detailRows: [OnboardingProtocolRowModel] {
        switch self {
        case .unknown:
            [
                OnboardingProtocolRowModel(label: "Private", value: "nsec, ncryptsec, or NIP-06 recovery words", icon: "key.horizontal.fill"),
                OnboardingProtocolRowModel(label: "Signer", value: "bunker:// or nostrconnect:// via NIP-46", icon: "signature"),
                OnboardingProtocolRowModel(label: "Read-only", value: "npub or NIP-05, no signing permissions", icon: "eye.fill")
            ]
        case .privateKey:
            [
                OnboardingProtocolRowModel(label: "nsec", value: "imports a raw private key", icon: "key.horizontal.fill"),
                OnboardingProtocolRowModel(label: "ncryptsec", value: "NIP-49 encrypted private key", icon: "lock.fill"),
                OnboardingProtocolRowModel(label: "NIP-06", value: "mnemonic based recovery", icon: "text.word.spacing")
            ]
        case .remoteSigner:
            [
                OnboardingProtocolRowModel(label: "nostr bunker", value: "persistent signer connection", icon: "network"),
                OnboardingProtocolRowModel(label: "NIP-46", value: "remote signing requests", icon: "signature"),
                OnboardingProtocolRowModel(label: "Permissions", value: "approve posting, reactions, profile edits", icon: "checkmark.shield.fill")
            ]
        case .readOnly:
            [
                OnboardingProtocolRowModel(label: "npub", value: "public key only", icon: "person.crop.circle.badge.checkmark"),
                OnboardingProtocolRowModel(label: "NIP-05", value: "resolve name@example.com to npub", icon: "at"),
                OnboardingProtocolRowModel(label: "Limit", value: "replies, boosts, reactions, DMs are disabled", icon: "hand.raised.fill")
            ]
        }
    }
}

private struct OnboardingProtocolRowModel: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    let icon: String
}

private struct OnboardingRelayPlan: Identifiable {
    let id = UUID()
    let url: String
    let role: String
    let status: String
    let tint: Color

    static func mockValues(isNIP65Enabled: Bool) -> [OnboardingRelayPlan] {
        if isNIP65Enabled {
            return [
                OnboardingRelayPlan(url: "wss://relay-a.mock", role: "read/write", status: "NIP-65", tint: .green),
                OnboardingRelayPlan(url: "wss://relay-b.mock", role: "read", status: "profile", tint: .cyan),
                OnboardingRelayPlan(url: "wss://relay-c.mock", role: "write", status: "fallback", tint: .orange)
            ]
        }

        return [
            OnboardingRelayPlan(url: "wss://bootstrap-a.mock", role: "discover", status: "fallback", tint: .orange),
            OnboardingRelayPlan(url: "wss://bootstrap-b.mock", role: "read", status: "fallback", tint: .yellow),
            OnboardingRelayPlan(url: "wss://bootstrap-c.mock", role: "write", status: "manual", tint: .purple)
        ]
    }
}

private struct OnboardingRecommendation: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color

    static let mockValues = [
        OnboardingRecommendation(title: "@astrenza", subtitle: "client updates and release notes", icon: "app.badge.fill", tint: .purple),
        OnboardingRecommendation(title: "@relay-status", subtitle: "relay health and outage notices", icon: "antenna.radiowaves.left.and.right", tint: .cyan),
        OnboardingRecommendation(title: "@nostr-guides", subtitle: "NIPs, keys, and migration tips", icon: "book.pages.fill", tint: .green)
    ]
}

private struct OnboardingBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                AstrenzaPalette.Onboarding.background,
                AstrenzaPalette.Onboarding.backgroundMiddle,
                AstrenzaPalette.Onboarding.backgroundDeep
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            RadialGradient(
                colors: [.white.opacity(0.18), .clear],
                center: .topTrailing,
                startRadius: 24,
                endRadius: 360
            )
        }
        .ignoresSafeArea()
    }
}

private struct OnboardingStepIndicator: View {
    let currentStep: OnboardingStep

    var body: some View {
        HStack(spacing: AstrenzaSpacing.point6) {
            ForEach(OnboardingStep.allCases, id: \.self) { step in
                Capsule()
                    .fill(step.rawValue <= currentStep.rawValue ? .white.opacity(0.86) : .white.opacity(0.24))
                    .frame(width: step == currentStep ? 26 : 8, height: 8)
            }
        }
        .animation(.snappy(duration: 0.25), value: currentStep)
    }
}

private struct OnboardingHeroMark: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.12))
                .frame(width: 230, height: 230)
            Circle()
                .stroke(.white.opacity(0.18), lineWidth: 22)
                .frame(width: 196, height: 196)
            AstrenzaLogoMark(
                size: 150,
                backgroundColor: AstrenzaPalette.Logo.darkBackground,
                strokeColor: .white.opacity(0.35),
                shadowColor: .black.opacity(0.2)
            )
        }
        .shadow(color: .black.opacity(0.24), radius: 22, y: 18)
    }
}

private struct OnboardingAccessModeCard: View {
    let mode: OnboardingAccessMode
    let isSelected: Bool

    var body: some View {
        HStack(spacing: AstrenzaSpacing.point14) {
            Image(systemName: mode.icon)
                .font(.astrenza(.point24, weight: .black))
                .foregroundStyle(isSelected ? .black.opacity(0.82) : AstrenzaPalette.Onboarding.accent)
                .frame(width: 48, height: 48)
                .background(isSelected ? .white.opacity(0.82) : .white.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: AstrenzaSpacing.point4) {
                Text(mode.title)
                    .font(.astrenza(.point18, weight: .black, design: .rounded))
                Text(mode.subtitle)
                    .font(.astrenza(.point13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: AstrenzaSpacing.point8)

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.astrenza(.point24, weight: .bold))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.34))
        }
        .padding(AstrenzaSpacing.point16)
        .background(isSelected ? AstrenzaPalette.Onboarding.selectedCard : AstrenzaPalette.Onboarding.card, in: RoundedRectangle(cornerRadius: AstrenzaRadius.point24))
        .overlay {
            RoundedRectangle(cornerRadius: AstrenzaRadius.point24)
                .stroke(isSelected ? .white.opacity(0.42) : .white.opacity(0.1), lineWidth: 1)
        }
    }
}

private struct OnboardingInputPanel: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var isSecure = false
    var axis: Axis = .horizontal

    var body: some View {
        VStack(alignment: .leading, spacing: AstrenzaSpacing.point10) {
            Text(title)
                .font(.astrenza(.point14, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.76))

            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text, axis: axis)
                }
            }
            .font(.astrenza(.point17, weight: .bold, design: .rounded))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .foregroundStyle(.white)
            .padding(AstrenzaSpacing.point16)
            .frame(minHeight: axis == .vertical ? 96 : 54, alignment: .topLeading)
            .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: AstrenzaRadius.point18))
            .overlay {
                RoundedRectangle(cornerRadius: AstrenzaRadius.point18)
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            }
        }
        .padding(AstrenzaSpacing.point18)
        .background(AstrenzaPalette.Onboarding.card, in: RoundedRectangle(cornerRadius: AstrenzaRadius.point24))
    }
}

private struct OnboardingInfoCard: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: AstrenzaSpacing.point14) {
            Image(systemName: icon)
                .font(.astrenza(.point22, weight: .black))
                .foregroundStyle(AstrenzaPalette.Onboarding.accent)
                .frame(width: 42, height: 42)
                .background(.white.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: AstrenzaSpacing.point5) {
                Text(title)
                    .font(.astrenza(.point17, weight: .black, design: .rounded))
                Text(message)
                    .font(.astrenza(.point14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AstrenzaSpacing.point18)
        .background(AstrenzaPalette.Onboarding.card, in: RoundedRectangle(cornerRadius: AstrenzaRadius.point24))
    }
}

private struct OnboardingProtocolRow: View {
    let row: OnboardingProtocolRowModel

    var body: some View {
        HStack(spacing: AstrenzaSpacing.point12) {
            Image(systemName: row.icon)
                .font(.astrenza(.point18, weight: .black))
                .foregroundStyle(AstrenzaPalette.Onboarding.accent)
                .frame(width: 38, height: 38)
                .background(.white.opacity(0.12), in: Circle())

            Text(row.label)
                .font(.astrenza(.point16, weight: .black, design: .rounded))
                .frame(width: 92, alignment: .leading)

            Text(row.value)
                .font(.astrenza(.point14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.66))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(AstrenzaSpacing.point14)
        .background(.black.opacity(0.17), in: RoundedRectangle(cornerRadius: AstrenzaRadius.point18))
    }
}

private struct OnboardingProfileAvatar: View {
    var body: some View {
        VStack(spacing: AstrenzaSpacing.point10) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.cyan, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "sparkles")
                    .font(.astrenza(.point42, weight: .black))
                    .foregroundStyle(.white)
            }
            .frame(width: 112, height: 112)
            .overlay(Circle().stroke(.white.opacity(0.34), lineWidth: 3))

            Text("Tap later to choose avatar")
                .font(.astrenza(.point13, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))
        }
    }
}

private struct OnboardingRelayRow: View {
    let relay: OnboardingRelayPlan

    var body: some View {
        HStack(spacing: AstrenzaSpacing.point12) {
            Circle()
                .fill(relay.tint)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: AstrenzaSpacing.point3) {
                Text(relay.url)
                    .font(.astrenza(.point15, weight: .black, design: .rounded))
                Text(relay.role)
                    .font(.astrenza(.point13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
            }

            Spacer()

            Text(relay.status)
                .font(.astrenza(.point12, weight: .black, design: .rounded))
                .foregroundStyle(relay.tint)
                .padding(.horizontal, AstrenzaSpacing.point10)
                .padding(.vertical, AstrenzaSpacing.point6)
                .background(relay.tint.opacity(0.18), in: Capsule())
        }
        .padding(AstrenzaSpacing.point16)
        .background(AstrenzaPalette.Onboarding.card, in: RoundedRectangle(cornerRadius: AstrenzaRadius.point20))
    }
}

private struct OnboardingRecommendationRow: View {
    let recommendation: OnboardingRecommendation
    let isSelected: Bool

    var body: some View {
        HStack(spacing: AstrenzaSpacing.point14) {
            Image(systemName: recommendation.icon)
                .font(.astrenza(.point22, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(recommendation.tint, in: Circle())

            VStack(alignment: .leading, spacing: AstrenzaSpacing.point4) {
                Text(recommendation.title)
                    .font(.astrenza(.point18, weight: .black, design: .rounded))
                Text(recommendation.subtitle)
                    .font(.astrenza(.point13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
            }

            Spacer()

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.astrenza(.point27, weight: .bold))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.34))
        }
        .padding(AstrenzaSpacing.point16)
    }
}

#Preview {
    NavigationStack {
        OnboardingView()
    }
}
