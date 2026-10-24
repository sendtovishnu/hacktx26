import SwiftUI

struct TwinView: View {
    @EnvironmentObject private var state: AppState
    @State private var checkin = ""
    @State private var signals: Signals?
    @State private var nudgesSent: Int?
    @State private var refreshing = false
    @State private var error: String?

    private var weekday: String {
        Date().formatted(.dateTime.weekday(.wide))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenHeader(eyebrow: weekday, title: "Your week, read gently")

                if let signals {
                    readCard(signals)
                    sharingCard(signals)
                    if nudgesSent != nil {
                        reassurance
                    }
                }

                checkinCard
                ErrorText(message: error)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .withUserPicker()
        .task(id: state.reloadToken) { await load() }
    }

    // MARK: Cards

    private var checkinCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(signals == nil ? "How's your week going?" : "Anything else on your mind?")
                .font(Theme.heading(19))
                .foregroundStyle(Theme.ink)
            TextField("Optional: a sentence for your twin", text: $checkin, axis: .vertical)
                .font(Theme.body())
                .lineLimit(1...3)
                .padding(12)
                .background(Theme.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Button {
                Task { await refresh() }
            } label: {
                HStack(spacing: 8) {
                    if refreshing {
                        ProgressView().tint(.white)
                        Text("Reading your week...")
                    } else {
                        Image(systemName: "sparkles")
                        Text("Refresh my twin")
                    }
                }
            }
            .buttonStyle(PrimaryButtonStyle(height: 50))
            .disabled(refreshing)
        }
        .card()
    }

    private func readCard(_ signals: Signals) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                IconBadge(systemImage: symbol(for: signals.supportLevel), size: 56, radius: 18,
                          background: badgeBackground(for: signals.supportLevel),
                          foreground: color(for: signals.supportLevel))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your twin's read").font(Theme.small()).foregroundStyle(Theme.ink2)
                    Text(signals.supportLevel.label).font(Theme.heading()).foregroundStyle(Theme.ink)
                }
            }
            if !signals.stressors.isEmpty {
                FlowRow(spacing: 8) {
                    ForEach(signals.stressors, id: \.self) { stressor in
                        Pill(text: "\(stressor.what) · \(stressor.when)", tone: .neutral, systemImage: "calendar")
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Busy hours, next 3 days").font(Theme.small()).foregroundStyle(Theme.ink2)
                    Spacer()
                    Text("\(Int(signals.busyHoursNext3Days.rounded())) of 42")
                        .font(Theme.bodyStrong(13))
                        .foregroundStyle(Theme.ink)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.cream)
                        Capsule()
                            .fill(LinearGradient(colors: [Theme.sun, Theme.ember], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * min(signals.busyHoursNext3Days / 42, 1))
                    }
                }
                .frame(height: 10)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(hex: 0xFFF4EC), .white], startPoint: .topLeading, endPoint: .center),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .shadow(color: Theme.ink.opacity(0.06), radius: 12, y: 8)
    }

    private func sharingCard(_ signals: Signals) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow(text: "What friends would see")
            shareRow(tier: "Closest", color: Theme.emberDeep, text: signals.summaryForClosest, textColor: Theme.ink)
            shareRow(tier: "Close", color: Theme.ink2, text: signals.summaryForClose, textColor: Theme.ink)
            shareRow(tier: "Friend", color: Theme.ink3, text: "Nothing", textColor: Theme.ink3)
        }
        .card()
    }

    private func shareRow(tier: String, color: Color, text: String, textColor: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(tier).font(Theme.bodyStrong(13)).foregroundStyle(color).frame(width: 64, alignment: .leading)
            Text(text).font(Theme.body(14)).foregroundStyle(textColor)
        }
    }

    /// Deliberately says nothing about whether anyone was nudged, so the surprise stays a surprise.
    private var reassurance: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(Theme.sageInk)
            Text("Got it. Your twin is keeping you company this week.")
                .font(Theme.semibold(14))
                .foregroundStyle(Theme.sageInk)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.sageLight, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func symbol(for level: SupportLevel) -> String {
        switch level {
        case .doingFine: return "sun.max"
        case .couldUseSupport: return "cloud.sun"
        case .struggling: return "cloud.rain"
        }
    }

    private func color(for level: SupportLevel) -> Color {
        switch level {
        case .doingFine: return Theme.sageInk
        case .couldUseSupport: return Theme.ember
        case .struggling: return Theme.dusk
        }
    }

    private func badgeBackground(for level: SupportLevel) -> Color {
        switch level {
        case .doingFine: return Theme.sageLight
        case .couldUseSupport: return Theme.blush
        case .struggling: return Theme.duskLight
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
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                signals = result.signals
                nudgesSent = result.nudgesSent
            }
            checkin = ""
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Wraps children onto new lines, for pills.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, maxWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
