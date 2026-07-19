import AstrenzaCore
import SwiftUI

struct FilterAddButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.astrenza(.point18, weight: .black, design: .rounded))
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
        HStack(spacing: AstrenzaSpacing.point8) {
            Button(action: onEdit) {
                HStack(spacing: AstrenzaSpacing.point12) {
                    SettingsIcon(systemName: icon, tint: rule.isEnabled ? .orange : .gray)
                    VStack(alignment: .leading, spacing: AstrenzaSpacing.point2) {
                        Text(displayValue)
                            .font(.astrenza(.point17, weight: .black, design: .rounded))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(rule.kind.displayTitle)
                            .font(.astrenza(.point12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Text(rule.isEnabled ? "Enabled" : "Disabled")
                        .font(.astrenza(.point15, weight: .bold, design: .rounded))
                        .foregroundStyle(rule.isEnabled ? Color.astrenzaAccent : .secondary)
                }
            }
            .buttonStyle(.plain)

            if isEditing {
                Button(action: onDelete) {
                    Image(systemName: "minus.circle.fill")
                        .font(.astrenza(.point24, weight: .bold))
                        .foregroundStyle(.red)
                        .frame(width: 34, height: 58)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, AstrenzaSpacing.point16)
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
        HStack(spacing: AstrenzaSpacing.point14) {
            AvatarView(style: candidate.avatar, size: 48)
            VStack(alignment: .leading, spacing: AstrenzaSpacing.point3) {
                HStack(spacing: AstrenzaSpacing.point7) {
                    Text(candidate.displayName)
                        .font(.astrenza(.point18, weight: .black, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(candidate.nip05)
                        .font(.astrenza(.point15, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(candidate.npub)
                    .font(.astrenza(.point15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
        .padding(.horizontal, AstrenzaSpacing.point16)
        .frame(minHeight: 74)
        .contentShape(Rectangle())
    }
}

struct FilterSelectedUserRow: View {
    let candidate: FilterCandidateUser

    var body: some View {
        HStack(spacing: AstrenzaSpacing.point14) {
            AvatarView(style: candidate.avatar, size: 54)
            VStack(alignment: .leading, spacing: AstrenzaSpacing.point3) {
                Text(candidate.displayName)
                    .font(.astrenza(.point18, weight: .black, design: .rounded))
                Text(candidate.nip05)
                    .font(.astrenza(.point16, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(candidate.npub)
                    .font(.astrenza(.point13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
        .padding(.horizontal, AstrenzaSpacing.point18)
        .padding(.vertical, AstrenzaSpacing.point12)
    }
}

struct FilterToggleLine: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: AstrenzaSpacing.point4) {
                Text(title)
                    .font(.astrenza(.point18, weight: .regular, design: .rounded))
                if let subtitle {
                    Text(subtitle)
                        .font(.astrenza(.point15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.switch)
        .tint(Color.astrenzaAccent)
        .padding(.horizontal, AstrenzaSpacing.point18)
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
            .padding(.horizontal, AstrenzaSpacing.point18)
            .frame(height: 64)
            .settingsRowTextStyle()
    }
}
