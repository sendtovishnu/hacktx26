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
        .withAccountButton()
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
            Avatar(user: nudge.fromUser, size: 48, glow: nudge.status != "acted")
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
    @State private var noteDraft = ""
    @State private var noteEdited = false

    /// The latest copy from polling, so the moment from this friend's twin appears when it's ready.
    private var live: Nudge {
        state.nudges.first { $0.id == nudge.id } ?? nudge
    }

    private var alreadyActed: Bool {
        live.status == "acted" || sent != nil
    }

    private var firstName: String {
        nudge.fromUser.name.split(separator: " ").first.map(String.init) ?? nudge.fromUser.name
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    Avatar(user: nudge.fromUser, size: 58, glow: true)
                        .padding(12)
                    VStack(alignment: .leading, spacing: 4) {
                        Eyebrow(text: "A nudge from \(nudge.fromUser.name)'s twin", color: Theme.accent)
                        Text("\(nudge.fromUser.name) could use you")
                            .font(Theme.heading(24))
                            .foregroundStyle(Theme.ink)
                    }
                }

                // The twin's message already explains the free-time situation.
                Text(nudge.message)
                    .font(Theme.body(16))
                    .lineSpacing(2)
                    .foregroundStyle(Theme.ink)

                if let sent {
                    sentCard(sent)
                } else if !alreadyActed {
                    momentCard
                    noteCard
                }

                Eyebrow(text: "Ways to help")

                if loading {
                    ProgressView().tint(Theme.accent).frame(maxWidth: .infinity).padding()
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
        .onAppear { if !noteEdited { noteDraft = live.draftNote ?? "" } }
        .onChange(of: live.draftNote) { _, draft in
            if !noteEdited { noteDraft = draft ?? "" }
        }
    }

    /// Twin to twin: your own twin read your calendar and found when you can show up.
    private var momentCard: some View {
        HStack(alignment: .top, spacing: 12) {
            IconBadge(systemImage: "clock.badge.checkmark")
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: "Your twin found a moment", color: Theme.accent)
                if let moment = live.moment {
                    Text(moment).font(Theme.body(15)).foregroundStyle(Theme.ink)
                        .transition(.opacity)
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small).tint(Theme.accent)
                        Text("Checking your calendar against \(firstName)'s free time\u{2026}")
                            .font(Theme.small()).foregroundStyle(Theme.ink2)
                    }
                }
                Text("Your twin sees your calendar. It only knows when \(firstName) is busy, never why.")
                    .font(Theme.small(11)).foregroundStyle(Theme.ink3)
            }
        }
        .card()
        .animation(.easeInOut, value: live.moment)
    }

    /// The note goes out in your words: the twin only drafts it.
    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "Your note to \(firstName)")
            TextField("Write something in your own words", text: $noteDraft, axis: .vertical)
                .lineLimit(2...5)
                .font(Theme.body(15))
                .padding(12)
                .background(Theme.cream, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onChange(of: noteDraft) { _, text in
                    if text != (live.draftNote ?? "") { noteEdited = true }
                }
            Label("Suggested by \(firstName)'s twin. Make it yours: it's sent from you.", systemImage: "sparkles")
                .font(Theme.small(12)).foregroundStyle(Theme.ink3)
        }
        .card()
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
                        ProgressView().tint(primary ? Theme.onAccent : Theme.accentDeep)
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
            let note = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            let gesture = try await state.api.sendGesture(nudgeId: nudge.id, suggestionIndex: index, note: note.isEmpty ? nil : note)
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
