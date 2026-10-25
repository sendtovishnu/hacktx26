import SwiftUI

struct TwinView: View {
    @EnvironmentObject private var state: AppState
    @State private var entryDraft = ""
    @State private var entries: [TwinEntry] = []
    @State private var adding = false
    @State private var signals: Signals?
    @State private var nudgesSent: Int?
    @State private var nothingNew = false
    @State private var showTold = false

    /// Added since the last refresh; the twin hasn't read these yet.
    private var waiting: [TwinEntry] { entries.filter { $0.readAt == nil } }
    /// Already part of the twin's read of the week.
    private var told: [TwinEntry] { entries.filter { $0.readAt != nil } }
    @State private var refreshing = false
    @State private var error: String?
    @State private var editingShare = false
    @State private var closestDraft = ""
    @State private var closeDraft = ""
    @State private var friendDraft = ""
    @State private var savingShare = false
    @FocusState private var focusedField: ShareField?

    private enum ShareField { case closest, close, friend }
    private let shareLimit = 90

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
        .withAccountButton()
        .task(id: state.reloadToken) { await load() }
        .pullToRefresh { await load() }
    }

    // MARK: Cards

    private var trimmedEntry: String { entryDraft.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Things you tell your twin stay until you delete them, and are read on every refresh.
    private var checkinCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(signals == nil ? "How's your week going?" : "Anything else on your mind?")
                .font(Theme.heading(19))
                .foregroundStyle(Theme.ink)
            Text("Tell your twin what your calendar can't: a hard conversation, a deadline, feeling off. Friends only ever hear the short line above.")
                .font(Theme.small())
                .foregroundStyle(Theme.ink2)
            TextField("Something your twin doesn\u{2019}t know yet", text: $entryDraft, axis: .vertical)
                .font(Theme.body())
                .lineLimit(1...4)
                .padding(12)
                .background(Theme.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Button {
                Task { await addEntry() }
            } label: {
                HStack(spacing: 8) {
                    if adding || refreshing { ProgressView().tint(Theme.onAccent) } else { Image(systemName: "plus") }
                    Text(adding ? "Adding\u{2026}" : refreshing ? "Updating your twin\u{2026}" : "Add to my twin")
                }
            }
            .buttonStyle(PrimaryButtonStyle(height: 46))
            .disabled(trimmedEntry.isEmpty || adding || refreshing)
            .opacity(trimmedEntry.isEmpty ? 0.5 : 1)

            if !waiting.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: "Waiting for your next refresh")
                    ForEach(waiting) { entry in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "text.bubble")
                                .foregroundStyle(Theme.ink3)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.text).font(Theme.body()).foregroundStyle(Theme.ink)
                                Text(DateText.ago(entry.createdAt)).font(Theme.small(11)).foregroundStyle(Theme.ink3)
                            }
                            Spacer(minLength: 0)
                            Button {
                                Task { await deleteEntry(entry) }
                            } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.ink3)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove")
                        }
                        .padding(10)
                        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .padding(.top, 4)
            }

            Rectangle().fill(Theme.cream).frame(height: 1).padding(.vertical, 2)

            Button {
                Task { await refresh() }
            } label: {
                HStack(spacing: 8) {
                    if refreshing {
                        ProgressView().tint(Theme.onAccent)
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
            // Calendar, email and what you told your twin, read together into one week.
            if !signals.stressors.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: "This week")
                    ForEach(signals.stressors, id: \.self) { stressor in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Circle().fill(Theme.accent).frame(width: 6, height: 6)
                            Text(stressor.what)
                                .font(Theme.body(15))
                                .foregroundStyle(Theme.ink)
                            Spacer(minLength: 8)
                            Text(DateText.day(stressor.when))
                                .font(Theme.small(12))
                                .foregroundStyle(Theme.ink2)
                        }
                    }
                }
            }
            if !told.isEmpty {
                DisclosureGroup(isExpanded: $showTold) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(told) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Text(entry.text).font(Theme.small()).foregroundStyle(Theme.ink2)
                                Spacer(minLength: 0)
                                Button {
                                    Task { await deleteEntry(entry) }
                                } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.ink3)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove")
                            }
                        }
                        Text("Remove anything that's over. Your twin stops counting it on the next refresh.")
                            .font(Theme.small(11))
                            .foregroundStyle(Theme.ink3)
                    }
                    .padding(.top, 6)
                } label: {
                    Text("What you told your twin (\(told.count))")
                        .font(Theme.semibold(13))
                        .foregroundStyle(Theme.ink2)
                }
                .tint(Theme.ink2)
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
                            .fill(LinearGradient(colors: [Theme.sun, Theme.accent], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * min(signals.busyHoursNext3Days / 42, 1))
                    }
                }
                .frame(height: 10)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Theme.glow, Theme.card], startPoint: .topLeading, endPoint: .center),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .shadow(color: Theme.shadow.opacity(0.06), radius: 12, y: 8)
    }

    private func sharingCard(_ signals: Signals) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Eyebrow(text: "What friends would see")
                Spacer()
                if !editingShare {
                    Button {
                        closestDraft = signals.summaryForClosest
                        closeDraft = signals.summaryForClose
                        friendDraft = signals.summaryForFriend ?? ""
                        withAnimation(.snappy) { editingShare = true }
                        focusedField = .closest
                    } label: {
                        Label("Edit", systemImage: "pencil")
                            .font(Theme.semibold(13))
                            .foregroundStyle(Theme.accentDeep)
                    }
                    .buttonStyle(.plain)
                }
            }

            if editingShare {
                shareEditor(tier: .closest, text: $closestDraft, field: .closest, hint: "A short line about your week")
                shareEditor(tier: .close, text: $closeDraft, field: .close, hint: "Something general, no details")
                shareEditor(tier: .friend, text: $friendDraft, field: .friend, hint: "Optional. Leave empty and they hear nothing")
                Text("Your twin writes these from your week, and keeps your words once you edit them. Friends never see your calendar or email.")
                    .font(Theme.small(12))
                    .foregroundStyle(Theme.ink3)
                Button {
                    Task { await resetShare() }
                } label: {
                    Label("Use my twin\u{2019}s wording", systemImage: "sparkles")
                        .font(Theme.semibold(13))
                        .foregroundStyle(Theme.accentDeep)
                }
                .buttonStyle(.plain)
                .disabled(savingShare)
                HStack(spacing: 10) {
                    Button("Cancel") {
                        withAnimation(.snappy) { editingShare = false }
                        focusedField = nil
                    }
                    .buttonStyle(SoftButtonStyle(height: 44))
                    Button {
                        Task { await saveShare() }
                    } label: {
                        HStack(spacing: 6) {
                            if savingShare { ProgressView().tint(Theme.onAccent) }
                            Text("Save")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle(height: 44))
                    .disabled(savingShare || !draftsValid)
                    .opacity(draftsValid ? 1 : 0.5)
                }
            } else {
                shareRow(tier: .closest, text: signals.summaryForClosest, signals: signals)
                shareRow(tier: .close, text: signals.summaryForClose, signals: signals)
                if let line = signals.summaryForFriend, !line.isEmpty {
                    shareRow(tier: .friend, text: line, signals: signals)
                } else {
                    friendNothingRow
                }
            }
        }
        .card()
    }

    private func tierColor(_ tier: Tier) -> Color {
        switch tier {
        case .closest: return Theme.accentDeep
        case .close: return Theme.ink2
        case .friend: return Theme.ink3
        }
    }

    /// The exact message that circle's nudge would carry.
    private func preview(_ tier: Tier, line: String) -> String {
        let name = state.me?.name ?? "You"
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = text.prefix(1).lowercased() + text.dropFirst()
        switch tier {
        case .closest: return "\(name) could use you right now: \(lower)."
        case .close: return "\(name) could use a lift this week: \(lower)."
        case .friend: return "\(name)\u{2019}s week: \(lower). A kind word might be nice."
        }
    }

    private func shareRow(tier: Tier, text: String, signals: Signals) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(tier.label).font(Theme.bodyStrong(13)).foregroundStyle(tierColor(tier)).frame(width: 104, alignment: .leading)
                Text(text).font(Theme.body(14)).foregroundStyle(Theme.ink)
            }
        }
    }

    /// With no line of your own, the Friends circle is never nudged, so say so.
    private var friendNothingRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(Tier.friend.label).font(Theme.bodyStrong(13)).foregroundStyle(tierColor(.friend)).frame(width: 104, alignment: .leading)
            Text("Hears nothing about your week").font(Theme.body(14)).italic().foregroundStyle(Theme.ink3)
        }
    }

    private var draftsValid: Bool {
        // Closest and close need a line; the Friends one is optional (empty means they hear nothing).
        let required = [closestDraft, closeDraft].allSatisfy { draft in
            let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            return !t.isEmpty && t.count <= shareLimit
        }
        return required && friendDraft.trimmingCharacters(in: .whitespacesAndNewlines).count <= shareLimit
    }

    private func shareEditor(tier: Tier, text: Binding<String>, field: ShareField, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(tier.label).font(Theme.bodyStrong(13)).foregroundStyle(tierColor(tier))
                Spacer()
                Text("\(text.wrappedValue.count)/\(shareLimit)")
                    .font(Theme.small(11))
                    .foregroundStyle(text.wrappedValue.count > shareLimit ? Theme.accentDeep : Theme.ink3)
            }
            TextField(hint, text: text, axis: .vertical)
                .font(Theme.body(15))
                .lineLimit(1...3)
                .focused($focusedField, equals: field)
                .padding(12)
                .background(Theme.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(focusedField == field ? Theme.accent.opacity(0.6) : Theme.linen, lineWidth: 1.2)
                )
            if !text.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("They\u{2019}d get: \u{201C}\(preview(tier, line: text.wrappedValue))\u{201D}")
                    .font(Theme.small(12))
                    .italic()
                    .foregroundStyle(Theme.ink2)
            }
        }
    }

    private func saveShare() async {
        savingShare = true
        defer { savingShare = false }
        do {
            let updated = try await state.api.updateSummaries(
                closest: closestDraft.trimmingCharacters(in: .whitespacesAndNewlines),
                close: closeDraft.trimmingCharacters(in: .whitespacesAndNewlines),
                friend: friendDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            withAnimation(.snappy) {
                signals = updated
                editingShare = false
            }
            focusedField = nil
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func resetShare() async {
        savingShare = true
        defer { savingShare = false }
        do {
            let updated = try await state.api.resetSummaries()
            withAnimation(.snappy) {
                signals = updated
                closestDraft = updated.summaryForClosest
                closeDraft = updated.summaryForClose
                friendDraft = updated.friendLine
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Deliberately says nothing about whether anyone was nudged, so the surprise stays a surprise.
    private var reassurance: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(Theme.sageInk)
            Text(nothingNew
                 ? "Nothing new since your friends last heard, so no one was nudged again. Add something above if there's more going on."
                 : "Got it. Your twin is keeping you company this week.")
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
        case .couldUseSupport: return Theme.accent
        case .struggling: return Theme.dusk
        }
    }

    private func badgeBackground(for level: SupportLevel) -> Color {
        switch level {
        case .doingFine: return Theme.sageLight
        case .couldUseSupport: return Theme.tint
        case .struggling: return Theme.duskLight
        }
    }

    // MARK: Actions

    private func load() async {
        nudgesSent = nil
        do {
            signals = try await state.api.twin()
            entries = try await state.api.twinEntries()
            error = nil
        } catch {
            signals = nil
            self.error = error.localizedDescription
        }
    }

    private func addEntry() async {
        adding = true
        defer { adding = false }
        do {
            let entry = try await state.api.addTwinEntry(trimmedEntry)
            withAnimation(.snappy) { entries.insert(entry, at: 0) }
            entryDraft = ""
            error = nil
        } catch {
            self.error = error.localizedDescription
            return
        }
        adding = false
        // One tap: adding also refreshes, so the entry lands in "This week" right away.
        await refresh()
    }

    private func deleteEntry(_ entry: TwinEntry) async {
        do {
            try await state.api.deleteTwinEntry(entry.id)
            withAnimation(.snappy) { entries.removeAll { $0.id == entry.id } }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func refresh() async {
        refreshing = true
        defer { refreshing = false }
        do {
            // Saved entries are read on the server; nothing extra rides along with the refresh.
            let result = try await state.api.refreshTwin(checkin: nil)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                signals = result.signals
                nudgesSent = result.nudgesSent
                nothingNew = result.nothingNew ?? false
            }
            // Read entries move up into "This week".
            let fresh = try await state.api.twinEntries()
            withAnimation(.snappy) { entries = fresh }
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
