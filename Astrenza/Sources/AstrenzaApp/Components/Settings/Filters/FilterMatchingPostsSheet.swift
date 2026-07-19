import AstrenzaCore
import SwiftUI

struct FilterMatchingPostsSheetModel: Identifiable {
    let id = UUID()
    let title: String
    let posts: [FilterMatchingPostRow]
    let totalCount: Int
}

struct FilterMatchingPostRow: Identifiable {
    let id: String
    let author: String
    let body: String
    let createdAt: Int

    init(event: NostrEvent) {
        id = event.id
        author = event.pubkey.abbreviatedMiddle
        body = event.content
        createdAt = event.createdAt
    }
}

struct FilterMatchingPostsSheet: View {
    let model: FilterMatchingPostsSheetModel
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            SettingsList {
                SettingsSection(title: "POSTS") {
                    if model.posts.isEmpty {
                        NostrListEmptyRow(
                            icon: "line.3.horizontal.decrease.circle",
                            title: "No Matching Posts",
                            subtitle: "Cached Home timeline events do not currently match this filter."
                        )
                    } else {
                        ForEach(model.posts) { post in
                            FilterMatchingPostRowView(post: post)
                            if post.id != model.posts.last?.id {
                                SettingsDivider()
                                    .padding(.leading, AstrenzaSpacing.point18)
                            }
                        }
                    }
                } footer: {
                    "Showing \(model.posts.count) of \(model.totalCount) cached matches from the Home timeline."
                }
            }
            .settingsNavigation(title: model.title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onDone)
                        .font(.astrenza(.point18, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.astrenzaAccent)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }
}

private struct FilterMatchingPostRowView: View {
    let post: FilterMatchingPostRow

    var body: some View {
        VStack(alignment: .leading, spacing: AstrenzaSpacing.point6) {
            HStack(spacing: AstrenzaSpacing.point8) {
                Text(post.author)
                    .font(.astrenza(.point14, weight: .black, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                Text(formattedDate)
                    .font(.astrenza(.point12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
            }

            Text(post.body)
                .font(.astrenza(.point16, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, AstrenzaSpacing.point18)
        .padding(.vertical, AstrenzaSpacing.point12)
    }

    private var formattedDate: String {
        Date(timeIntervalSince1970: TimeInterval(post.createdAt))
            .formatted(date: .abbreviated, time: .shortened)
    }
}
