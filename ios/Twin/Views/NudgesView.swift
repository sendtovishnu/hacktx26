import SwiftUI

struct NudgesView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(eyebrow: "Nudges", title: "Friends who could use you")

                if !state.surprises.isEmpty {
                    Eyebrow(text: "Surprises for you")
                    ForEach(state.surprises) { gesture in
                        Button {
                            state.activeSurprise = gesture
                        } label: {
                            HStack(spacing: 14) {
                                IconBadge(systemImage: "gift.fill", size: 46, radius: 16)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("From \(gesture.fromFriend.name)").font(Theme.bodyStrong()).foregroundStyle(Theme.ink)
                                    Text(gesture.note).font(Theme.small()).foregroundStyle(Theme.ink2).lineLimit(2)
                                }
                                Spacer(minLength: 0)
                            }
                            .card()
                        }
                        .buttonStyle(.plain)
                    }
                }

                if state.nudges.isEmpty {
                    VStack(spacing: 14) {
                        TwinMark(width: 72).opacity(0.8)
                        Text("All quiet")
                            .font(Theme.heading())
                            .foregroundStyle(Theme.ink)
                        Text("When someone close to you could use support, their twin will let you know here.")
                            .font(Theme.body())
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Theme.ink2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .padding(.horizontal, 16)
                } else {
                    ForEach(state.nudges) { nudge in
                        NavigationLink(value: nudge) {
                            NudgeRow(nudge: nudge)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .withUserPicker()
        .navigationDestination(for: Nudge.self) { nudge in
            SuggestionsView(nudge: nudge)
        }
        .refreshable { await state.poll() }
    }
}

private struct NudgeRow: View {
    let nudge: Nudge

    var body: some View {
        HStack(spacing: 14) {
            Avatar(name: nudge.fromUser.name, size: 48, glow: nudge.status != "acted")
                .padding(6)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(nudge.fromUser.name) could use you")
                    .font(Theme.bodyStrong())
                    .foregroundStyle(Theme.ink)
                Text(nudge.message)
                    .font(Theme.small())
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text(DateText.ago(nudge.createdAt)).font(Theme.small(12)).foregroundStyle(Theme.ink3)
                    if nudge.status == "acted" {
                        Pill(text: "You helped", tone: .sage, systemImage: "checkmark")
                    }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink3)
        }
        .card(padding: 14)
    }
}

struct SuggestionsView: View {
    @EnvironmentObject private var state: AppState
    let nudge: Nudge

    @State private var suggestions: [Suggestion] = []
    @State private var loading = true
    @State private var sendingIndex: Int?
    @State private var sent: Gesture?
    @State private var error: String?

    private var alreadyActed: Bool {
        nudge.status == "acted" || sent != nil
    }

    private var framing: String {
        if suggestions.contains(where: { $0.gestureType == .hangout }) {
            return "You both have a little free time soon, so a short break together could help."
        }
        if suggestions.contains(where: { $0.gestureType == .dropOff }) {
            return "You two don't have free time together soon, so something small fits best."
        }
        return "A few words from you would mean a lot."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    Avatar(name: nudge.fromUser.name, size: 58, glow: true)
                        .padding(12)
                    VStack(alignment: .leading, spacing: 4) {
                        Eyebrow(text: "A nudge from \(nudge.fromUser.name)'s twin", color: Theme.ember)
                        Text("\(nudge.fromUser.name) could use you")
                            .font(Theme.heading(24))
                            .foregroundStyle(Theme.ink)
                    }
                }

                Text("\(nudge.message) \(loading ? "" : framing)")
                    .font(Theme.body(16))
                    .lineSpacing(2)
                    .foregroundStyle(Theme.ink)

                if let sent {
                    sentCard(sent)
                }

                Eyebrow(text: "Ways to help")

                if loading {
                    ProgressView().tint(Theme.ember).frame(maxWidth: .infinity).padding()
                }

                ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                    suggestionCard(suggestion, index: index)
                }

                ErrorText(message: error)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await load() }
    }

    private func suggestionCard(_ suggestion: Suggestion, index: Int) -> some View {
        let primary = index == 0
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                IconBadge(systemImage: symbol(for: suggestion.gestureType))
                VStack(alignment: .leading, spacing: 3) {
                    Text(suggestion.title).font(Theme.bodyStrong()).foregroundStyle(Theme.ink)
                    Text(suggestion.detail).font(Theme.small()).foregroundStyle(Theme.ink2)
                }
            }
            if let place = suggestion.place {
                PlaceDetails(place: place)
            }
            Button {
                Task { await send(index) }
            } label: {
                HStack(spacing: 8) {
                    if sendingIndex == index {
                        ProgressView().tint(primary ? .white : Theme.emberDeep)
                    }
                    Text(suggestion.gestureType == .message ? "Write it" : "Do this")
                }
            }
            .modifier(SuggestionButtonStyle(primary: primary))
            .disabled(alreadyActed || sendingIndex != nil)
            .opacity(alreadyActed ? 0.5 : 1)
        }
        .card()
    }

    private func sentCard(_ gesture: Gesture) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Done. \(nudge.fromUser.name) gets a surprise.", systemImage: "checkmark.seal.fill")
                .font(Theme.bodyStrong(15))
                .foregroundStyle(Theme.sageInk)
            Text("\u{201C}\(gesture.note)\u{201D}")
                .font(Theme.quote(17))
                .foregroundStyle(Theme.ink2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.sageLight, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .transition(.scale(scale: 0.95).combined(with: .opacity))
    }

    private func symbol(for type: GestureType) -> String {
        switch type {
        case .dropOff: return "cup.and.saucer"
        case .hangout: return "figure.walk"
        case .message: return "bubble.left"
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            suggestions = try await state.api.suggestions(nudgeId: nudge.id)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func send(_ index: Int) async {
        sendingIndex = index
        defer { sendingIndex = nil }
        do {
            let gesture = try await state.api.sendGesture(nudgeId: nudge.id, suggestionIndex: index)
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { sent = gesture }
            error = nil
            await state.poll()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct SuggestionButtonStyle: ViewModifier {
    let primary: Bool

    func body(content: Content) -> some View {
        if primary {
            content.buttonStyle(PrimaryButtonStyle(height: 46))
        } else {
            content.buttonStyle(SoftButtonStyle(height: 46))
        }
    }
}
