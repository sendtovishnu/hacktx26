import SwiftUI

struct TwinView: View {
    @EnvironmentObject private var state: AppState
    @State private var checkin = ""
    @State private var signals: Signals?
    @State private var nudgesSent: Int?
    @State private var refreshing = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                checkinCard
                if let signals {
                    readCard(signals)
                    sharingCard(signals)
                } else if !refreshing {
                    Text("Tap Refresh to let your twin read your week.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                }
                ErrorText(message: error)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Your twin")
        .withUserPicker()
        .task(id: state.reloadToken) { await load() }
    }

    // MARK: Cards

    private var checkinCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How's your week going?")
                .font(.headline)
            TextField("Optional: a sentence for your twin", text: $checkin, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)
            Button {
                Task { await refresh() }
            } label: {
                HStack {
                    if refreshing {
                        ProgressView().tint(.white)
                        Text("Reading your week...")
                    } else {
                        Image(systemName: "sparkles")
                        Text("Refresh my twin")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(refreshing)
        }
        .card()
    }

    private func readCard(_ signals: Signals) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: signals.supportLevel.symbol)
                    .font(.largeTitle)
                    .foregroundStyle(color(for: signals.supportLevel))
                VStack(alignment: .leading) {
                    Text("Your twin's read").font(.caption).foregroundStyle(.secondary)
                    Text(signals.supportLevel.label).font(.title3.weight(.bold))
                }
            }
            if !signals.stressors.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(signals.stressors, id: \.self) { stressor in
                        Label("\(stressor.what), \(stressor.when)", systemImage: "calendar")
                            .font(.subheadline)
                    }
                }
            }
            Text("About \(Int(signals.busyHoursNext3Days.rounded())) busy hours in the next 3 days")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let place = signals.likelyLocation {
                Label("Usually at \(place)", systemImage: "mappin")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let nudgesSent {
                Text(nudgesSent == 0
                     ? "No nudges sent."
                     : "Your twin quietly let \(nudgesSent) \(nudgesSent == 1 ? "friend" : "friends") know.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .card()
    }

    private func sharingCard(_ signals: Signals) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What friends would see").font(.headline)
            shareRow(tier: "Closest", text: signals.summaryForClosest)
            shareRow(tier: "Close", text: signals.summaryForClose)
            shareRow(tier: "Friend", text: "Nothing")
            Text("Your calendar and emails are never shown to anyone.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private func shareRow(tier: String, text: String) -> some View {
        HStack(alignment: .top) {
            Text(tier)
                .font(.caption.weight(.bold))
                .frame(width: 64, alignment: .leading)
                .foregroundStyle(.secondary)
            Text(text).font(.subheadline)
        }
    }

    private func color(for level: SupportLevel) -> Color {
        switch level {
        case .doingFine: return .yellow
        case .couldUseSupport: return .orange
        case .struggling: return .indigo
        }
    }

    // MARK: Actions

    private func load() async {
        nudgesSent = nil
        do {
            signals = try await state.api.twin()
            error = nil
        } catch {
            signals = nil
            self.error = error.localizedDescription
        }
    }

    private func refresh() async {
        refreshing = true
        defer { refreshing = false }
        do {
            let text = checkin.trimmingCharacters(in: .whitespacesAndNewlines)
            let result = try await state.api.refreshTwin(checkin: text.isEmpty ? nil : text)
            withAnimation {
                signals = result.signals
                nudgesSent = result.nudgesSent
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
