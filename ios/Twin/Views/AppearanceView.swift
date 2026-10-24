import SwiftUI

/// Pick a soft accent color and light, dark or system mode. Changes apply instantly.
struct AppearanceView: View {
    @ObservedObject private var theme = ThemeStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    preview

                    VStack(alignment: .leading, spacing: 14) {
                        Eyebrow(text: "Color")
                        HStack(spacing: 0) {
                            ForEach(AccentChoice.allCases) { choice in
                                swatch(choice)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .card()

                    VStack(alignment: .leading, spacing: 14) {
                        Eyebrow(text: "Mode")
                        HStack(spacing: 10) {
                            ForEach(AppearanceMode.allCases) { mode in
                                modeButton(mode)
                            }
                        }
                    }
                    .card()

                    Text("Every color is kept soft on purpose. Twin should feel calm, never loud.")
                        .font(Theme.small(12))
                        .foregroundStyle(Theme.ink3)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .screenBackground()
            .navigationTitle("Appearance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(Theme.semibold(16))
                        .tint(theme.accent.deep)
                }
            }
        }
        // Shared pieces (pills, the logo, icons) read the accent when they draw;
        // rebuilding on change makes every one of them pick up the new color at once.
        .id(theme.accent)
        .tint(theme.accent.accent)
    }

    // A small live sample of the theme.
    private var preview: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [theme.accent.tint, theme.accent.glow, Theme.card.opacity(0)],
                                         center: .center, startRadius: 0, endRadius: 70))
                    .frame(width: 140, height: 140)
                TwinMark(width: 92)
            }
            HStack(spacing: 8) {
                Pill(text: "Could use support", tone: .ember)
                Pill(text: "Doing fine", tone: .sage)
            }
            Text("Do this")
                .font(Theme.button())
                .foregroundStyle(Theme.onAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(theme.accent.accent, in: Capsule())
        }
        .card()
        .animation(.easeInOut(duration: 0.25), value: theme.accent)
    }

    private func swatch(_ choice: AccentChoice) -> some View {
        let selected = theme.accent == choice
        return Button {
            withAnimation(.easeInOut(duration: 0.25)) { theme.accent = choice }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [choice.accent, choice.soft], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 44, height: 44)
                    if selected {
                        Circle().strokeBorder(choice.accent, lineWidth: 2.5).frame(width: 56, height: 56)
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 58, height: 58)
                Text(choice.name)
                    .font(Theme.semibold(12))
                    .foregroundStyle(selected ? Theme.ink : Theme.ink2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(choice.name) color")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func modeButton(_ mode: AppearanceMode) -> some View {
        let selected = theme.appearance == mode
        let icon: String = {
            switch mode {
            case .system: return "circle.lefthalf.filled"
            case .light: return "sun.max"
            case .dark: return "moon"
            }
        }()
        return Button {
            withAnimation(.easeInOut(duration: 0.25)) { theme.appearance = mode }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 20, weight: .medium))
                Text(mode.label).font(Theme.semibold(13))
            }
            .foregroundStyle(selected ? theme.accent.deep : Theme.ink2)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(selected ? theme.accent.tint : Theme.cream, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(selected ? theme.accent.accent.opacity(0.5) : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}
