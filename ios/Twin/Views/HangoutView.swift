import SwiftUI

// "I just want to hang out": no hard week needed. Both twins compare calendars (only the free
// gaps, never what's on them) and interests, then suggest things to do together and when.

struct HangoutView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.openURL) private var openURL
    let friend: User

    @State private var plan: HangoutPlan?
    @State private var loading = false
    @State private var error: String?
    @State private var shareItem: ShareItem?

    private var firstName: String {
        friend.name.split(separator: " ").first.map(String.init) ?? friend.name
    }

    /// Their number, ready for Messages; nil if they haven't added one.
    private var phone: String? {
        guard let raw = friend.phone else { return nil }
        let dialable = raw.filter { $0.isNumber || $0 == "+" }
        return dialable.filter(\.isNumber).count >= 7 ? dialable : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if loading && plan == nil {
                    VStack(spacing: 14) {
                        TwinMark(width: 72)
                        ProgressView().tint(Theme.accent)
                        Text("Your FirstMates are comparing calendars and what you both love\u{2026}")
                            .font(Theme.small())
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Theme.ink2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
                }

                if let plan {
                    if let note = calendarNote(plan.calendars) {
                        Label(note, systemImage: "calendar.badge.exclamationmark")
                            .font(Theme.small())
                            .foregroundStyle(Theme.ink2)
                            .padding(.horizontal, 4)
                    }
                    if !plan.freeTimes.isEmpty {
                        freeTimes(plan.freeTimes)
                    }
                    ForEach(Array(plan.ideas.enumerated()), id: \.offset) { _, idea in
                        ideaCard(idea)
                    }
                    Button {
                        Task { await load() }
                    } label: {
                        HStack(spacing: 8) {
                            if loading { ProgressView().tint(Theme.onAccent) } else { Image(systemName: "sparkles") }
                            Text(loading ? "Brainstorming\u{2026}" : "Brainstorm more ideas")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle(height: 50))
                    .disabled(loading)
                }

                ErrorText(message: error)

                Label("Only the times you're both free are compared. Neither of you sees what's on the other's calendar.", systemImage: "lock.fill")
                    .font(Theme.small(12))
                    .foregroundStyle(Theme.ink3)
                    .labelStyle(SageIconLabelStyle())
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .task { if plan == nil { await load() } }
        .pullToRefresh { await load() }
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.text])
                .presentationDetents([.medium, .large])
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            // You and them, side by side like the logo.
            ZStack {
                Avatar(user: state.me, size: 46)
                    .overlay(Circle().strokeBorder(Theme.card, lineWidth: 3))
                    .offset(x: -14)
                Avatar(user: friend, size: 46)
                    .overlay(Circle().strokeBorder(Theme.card, lineWidth: 3))
                    .offset(x: 14)
            }
            .frame(width: 76, height: 50)
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: "Just because", color: Theme.accent)
                Text("Hang out with \(firstName)")
                    .font(Theme.title(28))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func freeTimes(_ times: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "You're both free")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(times, id: \.self) { time in
                        Text(time)
                            .font(Theme.semibold(12))
                            .foregroundStyle(Theme.accentDeep)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(Theme.tint, in: Capsule())
                    }
                }
            }
        }
    }

    private func ideaCard(_ idea: HangoutIdea) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if let interest = idea.basedOn {
                    Label(idea.sharedInterest == true ? "You both love \(interest.lowercased())" : "Into \(interest.lowercased())",
                          systemImage: "heart.fill")
                        .font(Theme.semibold(11))
                        .foregroundStyle(Theme.accentDeep)
                }
                Text(idea.title).font(Theme.bodyStrong(17)).foregroundStyle(Theme.ink)
                Label(idea.when, systemImage: "clock")
                    .font(Theme.semibold(13))
                    .foregroundStyle(Theme.ink)
                Text(idea.detail).font(Theme.small()).foregroundStyle(Theme.ink2)
            }
            if let place = idea.place {
                PlaceDetails(place: place)
            }
            Text("\u{201C}\(idea.message)\u{201D}")
                .font(Theme.quote(16))
                .foregroundStyle(Theme.ink2)
            Button {
                text(idea.message)
            } label: {
                Label(phone == nil ? "Send to \(firstName)" : "Text \(firstName)", systemImage: "message.fill")
            }
            .buttonStyle(PrimaryButtonStyle(height: 46))
        }
        .card()
    }

    /// Who hasn't connected a calendar, so it's clear whose times the suggestions fit.
    private func calendarNote(_ calendars: HangoutPlan.Calendars) -> String? {
        switch (calendars.mine, calendars.theirs) {
        case (true, true): return nil
        case (true, false): return "\(firstName) hasn't connected a calendar, so these times only fit yours."
        case (false, true): return "Connect your calendar in Account so these times fit you too."
        case (false, false): return "Neither of you has a calendar connected, so the times are just suggestions."
        }
    }

    /// Messages, already addressed and written; the share sheet if they have no number.
    private func text(_ message: String) {
        if let phone,
           let body = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "sms:\(phone)&body=\(body)") {
            openURL(url)
        } else {
            shareItem = ShareItem(text: message)
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let fresh = try await state.api.planHangout(with: friend.id, avoid: plan?.ideas.map(\.title) ?? [])
            withAnimation(.snappy) { plan = fresh }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
