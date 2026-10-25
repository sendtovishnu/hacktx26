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
                                    MarqueeText(text: AppState.headline(for: gesture), font: Theme.bodyStrong())
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
        .pullToRefresh { await state.poll() }
    }
}

private struct NudgeRow: View {
    let nudge: Nudge

    var body: some View {
        HStack(spacing: 14) {
            Avatar(user: nudge.fromUser, size: 48, glow: nudge.status != "acted")
                .padding(6)
            VStack(alignment: .leading, spacing: 3) {
                MarqueeText(text: "\(nudge.fromUser.name) could use you", font: Theme.bodyStrong())
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
    @State private var composing: ComposeChoice?
    @State private var marking = false

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

                if alreadyActed {
                    sentCard
                } else {
                    momentCard
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
        .pullToRefresh {
            await state.poll()
            await load()
        }
        .sheet(item: $composing) { choice in
            ComposeNoteSheet(nudge: live, suggestion: choice.suggestion) { note in
                try await send(choice.index, note: note)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
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

    private func suggestionCard(_ suggestion: Suggestion, index: Int) -> some View {
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                IconBadge(systemImage: symbol(for: suggestion.gestureType))
                VStack(alignment: .leading, spacing: 3) {
                    if let interest = suggestion.basedOn {
                        Label(suggestion.sharedInterest == true ? "You both love \(interest.lowercased())" : "\(firstName) loves \(interest.lowercased())",
                              systemImage: "heart.fill")
                            .font(Theme.semibold(11))
                            .foregroundStyle(Theme.accentDeep)
                    }
                    Text(suggestion.title).font(Theme.bodyStrong()).foregroundStyle(Theme.ink)
                    Text(suggestion.detail).font(Theme.small()).foregroundStyle(Theme.ink2)
                }
            }
            if let place = suggestion.place {
                PlaceDetails(place: place)
            }
            Button {
                composing = ComposeChoice(index: index, suggestion: suggestion)
            } label: {
                HStack(spacing: 8) {
                    if sendingIndex == index {
                        ProgressView().tint(Theme.onAccent)
                    }
                    Text(suggestion.gestureType == .message ? "Write it" : "Do this")
                }
            }
            .buttonStyle(PrimaryButtonStyle(height: 46))
            .disabled(alreadyActed || sendingIndex != nil)
            .opacity(alreadyActed ? 0.5 : 1)
        }
        .card()
    }

    /// After you act: a surprise waits for you to say it happened; anything else is already on its way.
    private var sentCard: some View {
        let gesture = live.gesture ?? sent.map { NudgeGesture(id: $0.id, surprise: $0.surprise ?? false, revealed: !($0.surprise ?? false)) }
        let waiting = gesture.map { $0.surprise && !$0.revealed } ?? false
        return VStack(alignment: .leading, spacing: 10) {
            if waiting {
                Label("It's a surprise. \(firstName) doesn't know.", systemImage: "gift.fill")
                    .font(Theme.bodyStrong(15))
                    .foregroundStyle(Theme.sageInk)
                Text("Once you've done it, tap below and \(firstName) gets your note.")
                    .font(Theme.small())
                    .foregroundStyle(Theme.ink2)
                Button {
                    Task { await markDelivered() }
                } label: {
                    HStack(spacing: 8) {
                        if marking { ProgressView().tint(Theme.onAccent) }
                        Text("Mark as delivered")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(height: 46))
                .disabled(marking || gesture == nil)
            } else {
                Label(gesture?.surprise == true
                      ? "Delivered. \(firstName) has your note."
                      : "Done. \(firstName) got your note.",
                      systemImage: "checkmark.seal.fill")
                    .font(Theme.bodyStrong(15))
                    .foregroundStyle(Theme.sageInk)
            }
            if let note = sent?.note {
                Text("\u{201C}\(note)\u{201D}")
                    .font(Theme.quote(17))
                    .foregroundStyle(Theme.ink2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.sageLight, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .transition(.scale(scale: 0.95).combined(with: .opacity))
    }

    private func symbol(for type: GestureType) -> String {
        switch type {
        case .dropOff: return "cup.and.saucer.fill"
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

    private func send(_ index: Int, note: String) async throws {
        sendingIndex = index
        defer { sendingIndex = nil }
        let gesture = try await state.api.sendGesture(nudgeId: nudge.id, suggestionIndex: index, note: note)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { sent = gesture }
        error = nil
        await state.poll()
    }

    private func markDelivered() async {
        guard let id = live.gesture?.id ?? sent?.id else { return }
        marking = true
        defer { marking = false }
        do {
            try await state.api.markDelivered(gestureId: id)
            await state.poll()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct ComposeChoice: Identifiable {
    let index: Int
    let suggestion: Suggestion
    var id: Int { index }
}

/// You write the note. The twin's draft is only a starting point you can clear.
struct ComposeNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    let nudge: Nudge
    let suggestion: Suggestion
    var onSend: (String) async throws -> Void

    @State private var note = ""
    @State private var sending = false
    @State private var error: String?
    @FocusState private var focused: Bool

    private var firstName: String {
        nudge.fromUser.name.split(separator: " ").first.map(String.init) ?? nudge.fromUser.name
    }

    private var isSurprise: Bool {
        suggestion.gestureType != .message && nudge.fromUser.surprisesEnabled
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow(text: "Your note to \(firstName)", color: Theme.accent)
                        Text(suggestion.title)
                            .font(Theme.heading(22))
                            .foregroundStyle(Theme.ink)
                    }
                    .padding(.top, 24)

                    Label(
                        isSurprise
                            ? "It's a surprise. \(firstName) won't know until you mark it delivered, then they get this note."
                            : suggestion.gestureType == .message
                                ? "\(firstName) gets this note right away."
                                : "\(firstName) has surprises off, so they'll get a heads-up with this note now.",
                        systemImage: isSurprise ? "gift" : "bell"
                    )
                    .font(Theme.small())
                    .foregroundStyle(Theme.ink2)

                    TextEditor(text: $note)
                        .font(Theme.quote(19))
                        .foregroundStyle(Theme.ink)
                        .scrollContentBackground(.hidden)
                        .focused($focused)
                        .frame(minHeight: 180)
                        .padding(12)
                        .background(Theme.cream, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(alignment: .topLeading) {
                            if note.isEmpty {
                                Text("Write it in your own words")
                                    .font(Theme.quote(19))
                                    .foregroundStyle(Theme.ink3)
                                    .padding(.horizontal, 17)
                                    .padding(.vertical, 20)
                                    .allowsHitTesting(false)
                            }
                        }

                    HStack {
                        if !note.isEmpty {
                            Button("Clear") { note = "" }
                                .font(Theme.semibold(13))
                                .foregroundStyle(Theme.ink2)
                        }
                        Spacer()
                        Text("\(note.count)/500")
                            .font(Theme.small(12))
                            .foregroundStyle(note.count > 500 ? Theme.accentDeep : Theme.ink3)
                    }

                    Label("Started by \(firstName)'s twin. It's sent from you, so make it yours.", systemImage: "sparkles")
                        .font(Theme.small(12))
                        .foregroundStyle(Theme.ink3)

                    ErrorText(message: error)
                }
                .padding(.horizontal, 20)
            }
            .scrollDismissesKeyboard(.interactively)

            Button {
                Task { await send() }
            } label: {
                HStack(spacing: 8) {
                    if sending { ProgressView().tint(Theme.onAccent) }
                    Text(isSurprise ? "Plan the surprise" : "Send")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(trimmed.isEmpty || note.count > 500 || sending)
            .opacity(trimmed.isEmpty ? 0.5 : 1)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .screenBackground()
        .onAppear {
            // The note written for this option; the twin's general draft only fits a plain note.
            if note.isEmpty {
                note = suggestion.note ?? (suggestion.gestureType == .message ? nudge.draftNote ?? "" : "")
            }
            focused = true
        }
    }

    private var trimmed: String { note.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func send() async {
        sending = true
        defer { sending = false }
        do {
            try await onSend(trimmed)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
