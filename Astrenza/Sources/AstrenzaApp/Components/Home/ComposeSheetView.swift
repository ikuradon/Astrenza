import SwiftUI

struct ComposeSheetView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider().overlay(Color.astrenzaSeparator)

            VStack(alignment: .leading, spacing: 18) {
                Text("Nostrに投稿する内容を入力")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("ここはあとで実際の投稿エディタに差し替えます。今は下から出てくる標準モーダルの動きと、投稿タブの分離配置を確認するためのモックです。")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.astrenzaText)
                    .lineSpacing(4)

                actionBar
                    .padding(.top, 8)
            }
            .padding(18)

            Spacer(minLength: 0)
        }
        .background(Color.astrenzaBackground)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 12) {
            AvatarView(style: AvatarStyle(primary: .black, secondary: .cyan, symbolName: "cat.fill"), size: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text("New note")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                Text("Posting as ikuradon")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: dismiss.callAsFunction) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .black))
                    .frame(width: 34, height: 34)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .astrenzaGlass(tint: Color.white.opacity(0.04), in: Circle())
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 16)
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button {
            } label: {
                Image(systemName: "photo")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)
            .astrenzaGlass(tint: Color.white.opacity(0.04), in: Circle())

            Button {
            } label: {
                Image(systemName: "link")
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)
            .astrenzaGlass(tint: Color.white.opacity(0.04), in: Circle())

            Spacer()

            Button(action: dismiss.callAsFunction) {
                Text("Post")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 22)
                    .frame(height: 42)
                    .background(Color.astrenzaAccent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}
