import SwiftUI

struct UserSwitchButton: View {
    let isExpanded: Bool

    var body: some View {
        AvatarView(style: AvatarStyle(primary: .black, secondary: .cyan, symbolName: "cat.fill"), size: 34)
            .padding(4)
            .scaleEffect(isExpanded ? 1.06 : 1)
            .astrenzaGlass(tint: Color.white.opacity(isExpanded ? 0.1 : 0.05), in: Circle())
            .animation(.spring(duration: 0.28, bounce: 0.2), value: isExpanded)
            .accessibilityLabel("Switch user")
    }
}

struct UserSwitcherMenu: View {
    let onSettingsTap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            UserSwitcherRow(
                title: "User Alpha",
                npub: "npub1astrenza7q3n9...9h2q",
                nip05: "mock.example",
                avatarStyle: AvatarStyle(primary: .black, secondary: .cyan, symbolName: "cat.fill"),
                isSelected: true
            )

            UserSwitcherRow(
                title: "User Beta",
                npub: "npub1beta4x2ck8...w6mx",
                nip05: "beta.mock.example",
                avatarStyle: AvatarStyle(primary: .purple, secondary: .pink, symbolName: "moon.stars.fill"),
                isSelected: false
            )

            Divider()
                .overlay(Color.astrenzaSeparator)
                .padding(.vertical, 2)

            Button(action: onSettingsTap) {
                HStack(spacing: 10) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 28, height: 28)

                    Text("設定")
                        .font(.system(size: 15, weight: .bold, design: .rounded))

                    Spacer(minLength: 0)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .frame(height: 43)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 7)
        .frame(width: 252)
        .astrenzaGlass(tint: Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.38), radius: 18, y: 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("User switcher")
    }
}

private struct UserSwitcherRow: View {
    let title: String
    let npub: String
    let nip05: String
    let avatarStyle: AvatarStyle
    let isSelected: Bool

    var body: some View {
        Button {
        } label: {
            HStack(spacing: 10) {
                AvatarView(style: avatarStyle, size: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    HStack(spacing: 5) {
                        Text(nip05)
                            .foregroundStyle(.secondary)
                        Text(npub)
                            .foregroundStyle(Color.secondary.opacity(0.72))
                    }
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                }

                Spacer(minLength: 0)

                if isSelected {
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
