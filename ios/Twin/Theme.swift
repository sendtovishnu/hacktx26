import SwiftUI

// Design tokens from the Figma file "Twin: App Design".
// Paper tones, one ember accent, Fraunces for headlines and DM Sans for everything else.

enum Theme {
    // MARK: Color
    static let paper = Color(hex: 0xFBF6EF)
    static let cream = Color(hex: 0xF3EADF)
    static let linen = Color(hex: 0xEADFD1)
    static let ink = Color(hex: 0x2A211C)
    static let ink2 = Color(hex: 0x6E625A)
    static let ink3 = Color(hex: 0xA2968C)
    static let ember = Color(hex: 0xE2673E)
    static let emberDeep = Color(hex: 0xC24F2A)
    static let peach = Color(hex: 0xF7CBAA)
    static let blush = Color(hex: 0xF6DCD3)
    static let glow = Color(hex: 0xFBEDE3)
    static let sage = Color(hex: 0x7E9C80)
    static let sageLight = Color(hex: 0xDCE7DA)
    static let sageInk = Color(hex: 0x4D6B50)
    static let sun = Color(hex: 0xEDB042)
    static let dusk = Color(hex: 0x7A72B5)
    static let duskLight = Color(hex: 0xE3E0F2)

    static let surpriseGradient = LinearGradient(
        colors: [ember, Color(hex: 0xEE8A5E), Color(hex: 0xF3B48A)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func avatarColors(for name: String) -> [Color] {
        switch name {
        case "Maya": return [ember, peach]
        case "Jay": return [sage, Color(hex: 0xB9CFB6)]
        case "Priya": return [dusk, Color(hex: 0xC6C0E6)]
        default:
            let palettes: [[Color]] = [[ember, peach], [sage, Color(hex: 0xB9CFB6)], [dusk, Color(hex: 0xC6C0E6)]]
            let sum = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
            return palettes[sum % palettes.count]
        }
    }

    // MARK: Type
    enum Typeface {
        static let serif = "Fraunces-SemiBold"
        static let serifItalic = "Fraunces-Italic"
        static let sans = "DMSans9pt-Regular"
        static let sansMedium = "DMSans9pt-Medium"
        static let sansSemiBold = "DMSans9pt-SemiBold"
        static let sansBold = "DMSans9pt-Bold"
    }

    static func display(_ size: CGFloat = 44) -> Font { .custom(Typeface.serif, size: size) }
    static func title(_ size: CGFloat = 34) -> Font { .custom(Typeface.serif, size: size) }
    static func heading(_ size: CGFloat = 22) -> Font { .custom(Typeface.serif, size: size) }
    static func quote(_ size: CGFloat = 22) -> Font { .custom(Typeface.serifItalic, size: size) }
    static func body(_ size: CGFloat = 15) -> Font { .custom(Typeface.sans, size: size) }
    static func bodyStrong(_ size: CGFloat = 16) -> Font { .custom(Typeface.sansBold, size: size) }
    static func small(_ size: CGFloat = 13) -> Font { .custom(Typeface.sans, size: size) }
    static func label(_ size: CGFloat = 12) -> Font { .custom(Typeface.sansBold, size: size) }
    static func button(_ size: CGFloat = 16) -> Font { .custom(Typeface.sansSemiBold, size: size) }
    static func semibold(_ size: CGFloat) -> Font { .custom(Typeface.sansSemiBold, size: size) }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

// MARK: Text helpers

struct Eyebrow: View {
    let text: String
    var color: Color = Theme.ink3

    var body: some View {
        Text(text.uppercased())
            .font(Theme.label())
            .tracking(1.4)
            .foregroundStyle(color)
    }
}

/// Screen header used instead of the system large title, so headlines use Fraunces.
struct ScreenHeader: View {
    let eyebrow: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(text: eyebrow)
            Text(title)
                .font(Theme.title())
                .tracking(-0.6)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }
}

// MARK: Surfaces

struct CardModifier: ViewModifier {
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Theme.ink.opacity(0.06), radius: 12, y: 8)
    }
}

extension View {
    func card(padding: CGFloat = 18) -> some View {
        modifier(CardModifier(padding: padding))
    }

    /// The paper background and spacing every screen shares.
    func screenBackground() -> some View {
        background(Theme.paper.ignoresSafeArea())
    }
}

// MARK: Buttons

struct PrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = 54

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.button())
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Theme.ember, in: Capsule())
            .shadow(color: Theme.ember.opacity(0.35), radius: 10, y: 8)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct SoftButtonStyle: ButtonStyle {
    var height: CGFloat = 54

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.button())
            .foregroundStyle(Theme.emberDeep)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Theme.blush, in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

// MARK: Small components

struct Pill: View {
    enum Tone { case ember, sage, dusk, neutral }

    let text: String
    var tone: Tone = .neutral
    var systemImage: String?

    private var colors: (Color, Color) {
        switch tone {
        case .ember: return (Theme.emberDeep, Theme.blush)
        case .sage: return (Theme.sageInk, Theme.sageLight)
        case .dusk: return (Theme.dusk, Theme.duskLight)
        case .neutral: return (Theme.ink, Theme.cream)
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 11, weight: .semibold))
            } else {
                Circle().frame(width: 7, height: 7)
            }
            Text(text).font(Theme.semibold(13))
        }
        .foregroundStyle(colors.0)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(colors.1, in: Capsule())
    }
}

struct IconBadge: View {
    let systemImage: String
    var size: CGFloat = 40
    var radius: CGFloat = 14
    var background: Color = Theme.blush
    var foreground: Color = Theme.ember

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(background)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.45, weight: .medium))
                    .foregroundStyle(foreground)
            )
    }
}

/// Friend / Close / Closest picker styled like the Figma component.
struct TierPicker: View {
    let selection: Tier
    let onChange: (Tier) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tier.allCases) { tier in
                let on = tier == selection
                Button {
                    withAnimation(.snappy) { onChange(tier) }
                } label: {
                    Text(tier.label)
                        .font(Theme.semibold(13))
                        .foregroundStyle(on ? Theme.ink : Theme.ink2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(Color.white)
                                    .shadow(color: Theme.ink.opacity(0.1), radius: 3, y: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.cream, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// The logo: two overlapping circles, the shared middle in a deeper ember.
struct TwinMark: View {
    var width: CGFloat = 64

    var body: some View {
        Canvas { context, size in
            let s = size.width / 64
            let r = 16 * s
            let left = CGRect(x: (22 - 16) * s, y: (20 - 16) * s, width: 2 * r, height: 2 * r)
            let right = CGRect(x: (42 - 16) * s, y: (20 - 16) * s, width: 2 * r, height: 2 * r)
            context.fill(Path(ellipseIn: left), with: .color(Theme.ember))
            context.fill(Path(ellipseIn: right), with: .color(Theme.peach))
            var lens = Path(ellipseIn: left)
            lens = lens.intersection(Path(ellipseIn: right))
            context.fill(lens, with: .color(Theme.emberDeep))
        }
        .frame(width: width, height: width * 40 / 64)
        .accessibilityLabel("Twin")
    }
}
