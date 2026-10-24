import SwiftUI

struct NudgesView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        List {
            if !state.surprises.isEmpty {
                Section("Surprises for you") {
                    ForEach(state.surprises) { gesture in
                        Button {
                            state.activeSurprise = gesture
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "gift.fill")
                                    .font(.title2)
                                    .foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("From \(gesture.fromFriend.name)").font(.headline)
                                    Text(gesture.note).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section("Friends who could use you") {
                if state.nudges.isEmpty {
                    Text("Nothing right now. When a close friend could use support, you'll hear about it here.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(state.nudges) { nudge in
                        NavigationLink(value: nudge) {
                            NudgeRow(nudge: nudge)
                        }
                    }
                }
            }
        }
        .navigationTitle("Nudges")
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
        HStack(alignment: .top, spacing: 12) {
            Avatar(name: nudge.fromUser.name)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(nudge.fromUser.name) could use you").font(.headline)
                    Spacer()
                    Text(DateText.ago(nudge.createdAt)).font(.caption).foregroundStyle(.secondary)
                }
                Text(nudge.message).font(.subheadline)
                if nudge.status == "acted" {
                    Label("You helped", systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(.vertical, 4)
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Avatar(name: nudge.fromUser.name, size: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(nudge.fromUser.name) could use you").font(.title3.weight(.bold))
                        Text(nudge.message).foregroundStyle(.secondary)
                    }
                }
                .card()

                if let sent {
                    sentCard(sent)
                }

                Text("Ways to help").font(.headline)

                if loading {
                    ProgressView().frame(maxWidth: .infinity)
                }

                ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                    suggestionCard(suggestion, index: index)
                }

                ErrorText(message: error)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Help \(nudge.fromUser.name)")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func suggestionCard(_ suggestion: Suggestion, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: suggestion.gestureType.symbol)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text(suggestion.title).font(.headline)
                    Text(suggestion.detail).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if let place = suggestion.place {
                PlaceDetails(place: place)
                    .padding(.leading, 44)
            }
            Button {
                Task { await send(index) }
            } label: {
                HStack {
                    if sendingIndex == index {
                        ProgressView()
                    }
                    Text("Do this")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(alreadyActed || sendingIndex != nil)
        }
        .card()
    }

    private func sentCard(_ gesture: Gesture) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Done", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(.green)
            Text("\(nudge.fromUser.name) will get a surprise note:")
                .font(.subheadline)
            Text("\"\(gesture.note)\"")
                .font(.subheadline.italic())
                .foregroundStyle(.secondary)
        }
        .card()
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
            withAnimation { sent = gesture }
            error = nil
            await state.poll()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
