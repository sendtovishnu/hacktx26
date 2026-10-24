import SwiftUI

// The climax of the demo: shown full screen when a friend acts on a nudge.

struct SurpriseView: View {
    @Environment(\.dismiss) private var dismiss
    let gesture: Gesture
    @State private var appeared = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.accentColor, Color.pink.opacity(0.85), Color.orange.opacity(0.8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: gesture.type == .message ? "heart.text.square.fill" : "gift.fill")
                    .font(.system(size: 88))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, value: appeared)
                    .scaleEffect(appeared ? 1 : 0.4)
                    .opacity(appeared ? 1 : 0)

                VStack(spacing: 8) {
                    Text("Someone's thinking of you")
                        .font(.title2.weight(.bold))
                    Text("From \(gesture.fromFriend.name)")
                        .font(.headline)
                        .opacity(0.85)
                }
                .foregroundStyle(.white)

                Text(gesture.note)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)

                if let place = gesture.place {
                    PlaceDetails(place: place)
                        .padding()
                        .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.horizontal, 32)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text("Thank you, \(gesture.fromFriend.name)")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.white, in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
                appeared = true
            }
        }
    }
}
