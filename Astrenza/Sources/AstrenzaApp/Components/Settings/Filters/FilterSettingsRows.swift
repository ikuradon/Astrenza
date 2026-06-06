import AstrenzaCore
import SwiftUI

struct FilterAddButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(Color.astrenzaAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct FilterOverviewRuleRow: View {
    let rule: NostrFilterRuleRecord
    let icon: String
    let isEditing: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onEdit) {
                HStack(spacing: 12) {
                    SettingsIcon(systemName: icon, tint: rule.isEnabled ? .orange : .gray)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayValue)
                            .font(.system(size: 17, weight: .black, design: .rounded))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(rule.kind.displayTitle)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Text(rule.isEnabled ? "Enabled" : "Disabled")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(rule.isEnabled ? Color.astrenzaAccent : .secondary)
                }
            }
            .buttonStyle(.plain)

            if isEditing {
                Button(action: onDelete) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.red)
                        .frame(width: 34, height: 58)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 58)
    }

    private var displayValue: String {
        switch rule.kind {
        case .mutedPubkey:
            rule.value.abbreviatedMiddle
        case .mutedHashtag:
            "#\(rule.value)"
        default:
            rule.value
        }
    }
}

struct FilterCandidateUserRow: View {
    let candidate: FilterCandidateUser

    var body: some View {
        HStack(spacing: 14) {
            AvatarView(style: candidate.avatar, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(candidate.displayName)
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(candidate.nip05)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(candidate.npub)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 74)
        .contentShape(Rectangle())
    }
}

struct FilterSelectedUserRow: View {
    let candidate: FilterCandidateUser

    var body: some View {
        HStack(spacing: 14) {
            AvatarView(style: candidate.avatar, size: 54)
            VStack(alignment: .leading, spacing: 3) {
                Text(candidate.displayName)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                Text(candidate.nip05)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(candidate.npub)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}

struct FilterToggleLine: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 18, weight: .regular, design: .rounded))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.switch)
        .tint(Color.astrenzaAccent)
        .padding(.horizontal, 18)
        .frame(minHeight: subtitle == nil ? 66 : 86)
        .settingsRowTextStyle()
    }
}

struct FilterScopeToggleRow: View {
    let scope: FilterApplicationScope
    @Binding var isOn: Bool

    var body: some View {
        Toggle(scope.rawValue, isOn: $isOn)
            .toggleStyle(.switch)
            .tint(Color.astrenzaAccent)
            .padding(.horizontal, 18)
            .frame(height: 64)
            .settingsRowTextStyle()
    }
}
