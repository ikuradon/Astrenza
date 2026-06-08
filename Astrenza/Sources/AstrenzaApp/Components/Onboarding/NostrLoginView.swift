import SwiftUI

struct NostrLoginView: View {
    @ObservedObject var sessionStore: NostrSessionStore

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 40)

            VStack(spacing: 14) {
                AstrenzaLogoMark(
                    size: 96,
                    strokeColor: Color.astrenzaAccent.opacity(0.28),
                    shadowColor: Color.astrenzaAccent.opacity(0.16)
                )

                Text("Astrenza")
                    .font(.system(size: 42, weight: .black, design: .rounded))
                    .foregroundStyle(Color.astrenzaText)

                Text("Read-only Nostr login for resolving NIP-65 relays, kind:3 follows, and your Home timeline.")
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 330)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Nostr identity")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                TextField("npub1... or name@example.com", text: $sessionStore.loginInput)
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
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.astrenzaText)
                    .padding(.horizontal, 16)
                    .frame(height: 54)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    }
                    .accessibilityIdentifier("login.nostr_identity")

                if let errorMessage = sessionStore.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: 360)

            Button {
                Task {
                    await sessionStore.login()
                }
            } label: {
                HStack(spacing: 10) {
                    if sessionStore.isLoggingIn {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.astrenzaBackground)
                    } else {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 17, weight: .black))
                    }

                    Text(sessionStore.isLoggingIn ? "Resolving" : "Continue")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
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
        .padding(.horizontal, 24)
        .background(Color.astrenzaBackground.ignoresSafeArea())
    }
}
