import SwiftUI

struct NostrLoginView: View {
    @ObservedObject var sessionStore: NostrSessionStore

    var body: some View {
        VStack(spacing: AstrenzaSpacing.point28) {
            Spacer(minLength: 40)

            VStack(spacing: AstrenzaSpacing.point14) {
                AstrenzaLogoMark(
                    size: 96,
                    strokeColor: Color.astrenzaAccent.opacity(0.28),
                    shadowColor: Color.astrenzaAccent.opacity(0.16)
                )

                Text("Astrenza")
                    .font(.astrenza(.point42, weight: .black, design: .rounded))
                    .foregroundStyle(Color.astrenzaText)

                Text("Nostr login for resolving NIP-65 relays, kind:3 follows, and your Home timeline.")
                    .font(.astrenza(.point17, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 330)
            }

            VStack(alignment: .leading, spacing: AstrenzaSpacing.point12) {
                Text("Nostr identity")
                    .font(.astrenza(.point13, weight: .heavy, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                TextField("npub1..., nsec1..., or name@example.com", text: $sessionStore.loginInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .onSubmit {
                        guard !sessionStore.isLoggingIn else { return }
                        Task {
                            await sessionStore.login()
                        }
                    }
                    .font(.astrenza(.point18, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.astrenzaText)
                    .padding(.horizontal, AstrenzaSpacing.point16)
                    .frame(height: 54)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: AstrenzaRadius.point14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: AstrenzaRadius.point14, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    }
                    .accessibilityIdentifier("login.nostr_identity")

                if let errorMessage = sessionStore.errorMessage {
                    Text(errorMessage)
                        .font(.astrenza(.point13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: 360)

            Button {
                Task {
                    await sessionStore.login()
                }
            } label: {
                HStack(spacing: AstrenzaSpacing.point10) {
                    if sessionStore.isLoggingIn {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.astrenzaBackground)
                    } else {
                        Image(systemName: "arrow.right")
                            .font(.astrenza(.point17, weight: .black))
                    }

                    Text(sessionStore.isLoggingIn ? "Resolving" : "Continue")
                        .font(.astrenza(.point18, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(Color.astrenzaBackground)
                .frame(maxWidth: 360)
                .frame(height: 54)
                .background(Color.astrenzaAccent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(sessionStore.isLoggingIn)
            .opacity(sessionStore.isLoggingIn ? 0.7 : 1)
            .accessibilityIdentifier("login.continue")

            Spacer(minLength: 60)
        }
        .padding(.horizontal, AstrenzaSpacing.point24)
        .background(Color.astrenzaBackground.ignoresSafeArea())
    }
}
