import SwiftUI

// The climax of the demo: shown full screen when a friend acts on a nudge.

struct SurpriseView: View {
    @Environment(\.dismiss) private var dismiss
    let gesture: Gesture
    @State private var appeared = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            Theme.surpriseGradient.ignoresSafeArea()

            VStack(spacing: 26) {
                Spacer()

                ZStack {
                    Circle().fill(.white.opacity(0.05)).frame(width: 230, height: 230)
                        .scaleEffect(pulse ? 1.06 : 0.94)
                    Circle().fill(.white.opacity(0.08)).frame(width: 186, height: 186)
                    Circle().fill(.white.opacity(0.18)).frame(width: 150, height: 150)
                    Image(systemName: gesture.type == .message ? "heart.text.square" : "gift")
                        .font(.system(size: 62, weight: .light))
                        .foregroundStyle(.white)
                        .symbolEffect(.bounce, value: appeared)
                }
                .scaleEffect(appeared ? 1 : 0.5)
                .opacity(appeared ? 1 : 0)

                VStack(spacing: 8) {
                    Text("Someone's thinking of you")
                        .font(Theme.title(36))
                        .tracking(-0.6)
                        .multilineTextAlignment(.center)
                    Text("From \(gesture.fromFriend.name)")
                        .font(Theme.bodyStrong())
                        .opacity(0.85)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)

                Text("\u{201C}\(gesture.note)\u{201D}")
                    .font(Theme.quote())
                    .lineSpacing(4)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 36)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)

                if let place = gesture.place {
                    HStack(spacing: 8) {
                        Image(systemName: "mappin.and.ellipse").foregroundStyle(Theme.accent)
                        Text(place.name).font(Theme.bodyStrong(14)).foregroundStyle(Theme.ink)
                        Text("· on its way").font(Theme.small()).foregroundStyle(Theme.ink2)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.white.opacity(0.95), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .opacity(appeared ? 1 : 0)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text("Thank you, \(gesture.fromFriend.name)")
                        .font(Theme.button())
                        .foregroundStyle(Theme.accentDeep)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(.white, in: Capsule())
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
        .environment(\.colorScheme, .light)
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.65)) { appeared = true }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}
