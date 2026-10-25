import SwiftUI

// The climax of the demo: shown full screen when a friend acts on a nudge.

struct SurpriseView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var state: AppState
    let gesture: Gesture
    @State private var appeared = false
    @State private var pulse = false
    @State private var reacted: String?
    @State private var showFullNote = false

    /// Long enough that it won't fit above the buttons, so it gets a "More".
    private var noteIsLong: Bool { gesture.note.count > 140 }

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
                    Text(AppState.headline(for: gesture))
                        .font(Theme.title(34))
                        .tracking(-0.6)
                        .multilineTextAlignment(.center)
                    Text("From \(gesture.fromFriend.name)")
                        .font(Theme.bodyStrong())
                        .opacity(0.85)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)

                VStack(spacing: 8) {
                    Text("\u{201C}\(gesture.note)\u{201D}")
                        .font(Theme.quote())
                        .lineSpacing(2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .lineLimit(noteIsLong ? 4 : nil)
                        .fixedSize(horizontal: false, vertical: !noteIsLong)
                    if noteIsLong {
                        Button("More") { showFullNote = true }
                            .font(Theme.semibold(14))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .overlay(Capsule().stroke(.white.opacity(0.6), lineWidth: 1))
                    }
                }
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

                // Your answer teaches your twin: "needed space" means a note, not a visit, next time.
                VStack(spacing: 10) {
                    if let reacted {
                        Label(reacted == "space"
                              ? "Got it. Next time your twin will ask for a note instead of a visit."
                              : "Got it. Your twin will remember this helped.",
                              systemImage: "sparkles")
                            .font(Theme.small(13))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity)
                    } else {
                        Text("How did this land? Only your twin sees your answer.")
                            .font(Theme.small(13))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    Button {
                        Task { await react("helped") }
                    } label: {
                        Text("This helped \u{2764}\u{FE0F}")
                            .font(Theme.button())
                            .foregroundStyle(Theme.accentDeep)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(.white, in: Capsule())
                    }
                    Button {
                        Task { await react("space") }
                    } label: {
                        Text("I needed space")
                            .font(Theme.bodyStrong(15))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .overlay(Capsule().stroke(.white.opacity(0.6), lineWidth: 1))
                    }
                }
                .disabled(reacted != nil)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
        .environment(\.colorScheme, .light)
        .sheet(isPresented: $showFullNote) {
            FullNoteView(gesture: gesture)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.65)) { appeared = true }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    private func react(_ reaction: String) async {
        // Close the surprise even if the server is unreachable; the reaction is a bonus.
        try? await state.api.react(toSurprise: gesture.id, reaction: reaction)
        withAnimation { reacted = reaction }
        try? await Task.sleep(for: .seconds(1.6))
        dismiss()
    }
}

/// The whole note, for when it's longer than the surprise screen can show.
struct FullNoteView: View {
    let gesture: Gesture

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Avatar(user: gesture.fromFriend, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("From \(gesture.fromFriend.name)").font(Theme.bodyStrong()).foregroundStyle(Theme.ink)
                        Text(DateText.ago(gesture.deliveredAt)).font(Theme.small(12)).foregroundStyle(Theme.ink3)
                    }
                }
                Text(gesture.note)
                    .font(Theme.quote(22))
                    .foregroundStyle(Theme.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(24)
        }
        .screenBackground()
    }
}
