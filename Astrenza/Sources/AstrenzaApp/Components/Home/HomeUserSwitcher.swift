import SwiftUI

struct UserSwitchButton: View {
    let isExpanded: Bool
    let account: NostrAccountSummary?

    init(isExpanded: Bool, account: NostrAccountSummary? = nil) {
        self.isExpanded = isExpanded
        self.account = account
    }

    var body: some View {
        AvatarView(style: account?.avatarStyle ?? Self.fallbackAvatar, size: 34)
            .padding(4)
            .scaleEffect(isExpanded ? 1.06 : 1)
            .astrenzaGlass(tint: Color.white.opacity(isExpanded ? 0.1 : 0.05), in: Circle())
            .animation(.spring(duration: 0.28, bounce: 0.2), value: isExpanded)
            .accessibilityLabel("Switch user")
    }

    private static let fallbackAvatar = AvatarStyle(primary: .black, secondary: .cyan, symbolName: "cat.fill")
}

struct UserSwitcherMenu: View {
    let accounts: [NostrAccountSummary]
    let onSelectAccount: (String) -> Void
    let onAddAccount: () -> Void
    let onSettingsTap: () -> Void

    init(
        accounts: [NostrAccountSummary] = [],
        onSelectAccount: @escaping (String) -> Void = { _ in },
        onAddAccount: @escaping () -> Void = {},
        onSettingsTap: @escaping () -> Void
    ) {
        self.accounts = accounts
        self.onSelectAccount = onSelectAccount
        self.onAddAccount = onAddAccount
        self.onSettingsTap = onSettingsTap
    }

    var body: some View {
        VStack(spacing: 0) {
            if accounts.isEmpty {
                UserSwitcherPlaceholderRow()
            } else {
                ForEach(accounts) { account in
                    UserSwitcherRow(account: account) {
                        onSelectAccount(account.id)
                    }
                }
            }

            Divider()
                .overlay(Color.astrenzaSeparator)
                .padding(.vertical, 2)

            UserSwitcherActionRow(
                title: "アカウント追加",
                icon: "plus.circle.fill",
                tint: Color.astrenzaAccent,
                action: onAddAccount
            )

            UserSwitcherActionRow(
                title: "設定",
                icon: "gearshape",
                tint: .primary,
                action: onSettingsTap
            )
        }
        .padding(.vertical, 7)
        .frame(width: 268)
        .astrenzaGlass(tint: Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.38), radius: 18, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("User switcher")
    }
}

private struct UserSwitcherRow: View {
    let account: NostrAccountSummary
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                AvatarView(style: account.avatarStyle, size: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(account.title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        Text(account.subtitle)
                            .foregroundStyle(.secondary)
                        Text(account.npub)
                            .foregroundStyle(Color.secondary.opacity(0.72))
                    }
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                }

                Spacer(minLength: 0)

                if account.isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(Color.astrenzaAccent)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct UserSwitcherActionRow: View {
    let title: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 28, height: 28)

                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))

                Spacer(minLength: 0)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .frame(height: 43)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct UserSwitcherPlaceholderRow: View {
    var body: some View {
        HStack(spacing: 10) {
            AvatarView(style: AvatarStyle(primary: .black, secondary: .cyan, symbolName: "cat.fill"), size: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text("No account")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text("Login from Settings")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 50)
    }
}
