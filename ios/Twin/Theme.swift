import SwiftUI

// Design tokens from the Figma file "Twin: App Design", now themeable:
// a soft accent the user picks (Sky by default) and light or dark mode.
// Every color adapts to dark mode through a light/dark pair.

/// Soft accent palettes. Each has light and dark values for every role.
enum AccentChoice: String, CaseIterable, Identifiable {
    case sky, lavender, mint, peach, rose

    var id: String { rawValue }

    var name: String {
        switch self {
        case .sky: return "Sky"
        case .lavender: return "Lavender"
        case .mint: return "Mint"
        case .peach: return "Peach"
        case .rose: return "Rose"
        }
    }

    /// (light, dark) hex pairs for: accent, deep, tint, glow, soft.
    fileprivate var values: (accent: (UInt32, UInt32), deep: (UInt32, UInt32), tint: (UInt32, UInt32), glow: (UInt32, UInt32), soft: (UInt32, UInt32)) {
        switch self {
        case .sky:
            return ((0x3B86E8, 0x6CAAF5), (0x2163BD, 0xA9CCFA), (0xCBE1FB, 0x1E2E44), (0xE1EDFD, 0x18222F), (0x8DBBF5, 0x3E6797))
        case .lavender:
            return ((0x7E74D6, 0xA59DE8), (0x5149A8, 0xCBC6F5), (0xDDD9F6, 0x2A2742), (0xECE9FB, 0x1E1C2E), (0xB7AEEB, 0x5D5690))
        case .mint:
            return ((0x379E82, 0x6CC6AC), (0x226F5A, 0xA8E2D1), (0xCBECE2, 0x1C3530), (0xE2F5EF, 0x152622), (0x92D3BF, 0x3D7A69))
        case .peach:
            return ((0xDB6E47, 0xEE9572), (0xAD4A30, 0xF6C3AD), (0xF7D5C7, 0x3A2620), (0xFBE7DE, 0x2A1D19), (0xF3BB96, 0x8A5A45))
        case .rose:
            return ((0xCD6383, 0xE894AE), (0x9E3F5E, 0xF4C3D3), (0xF5D2DD, 0x3A2230), (0xFAE5EC, 0x2A1922), (0xEDABC0, 0x8A4D63))
        }
    }

    var accent: Color { .dynamic(values.accent) }
    var deep: Color { .dynamic(values.deep) }
    var tint: Color { .dynamic(values.tint) }
    var glow: Color { .dynamic(values.glow) }
    var soft: Color { .dynamic(values.soft) }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Holds the chosen accent and appearance. RootView observes it and redraws the app on change.
final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()

    @Published var accent: AccentChoice {
        didSet { UserDefaults.standard.set(accent.rawValue, forKey: "accent") }
    }
    @Published var appearance: AppearanceMode {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "appearance") }
    }
    /// Lets the Account sheet ask RootView to open Appearance.
    @Published var showAppearance = false

    private init() {
        let d = UserDefaults.standard
        accent = AccentChoice(rawValue: d.string(forKey: "accent") ?? "") ?? .sky
        appearance = AppearanceMode(rawValue: d.string(forKey: "appearance") ?? "") ?? .system
    }
}

enum Theme {
    // MARK: Neutrals (light, dark)
    static let paper = Color.dynamic((0xF7F8FA, 0x111318))
    static let card = Color.dynamic((0xFFFFFF, 0x1B1E25))
    static let cream = Color.dynamic((0xEEF1F5, 0x252932))
    static let linen = Color.dynamic((0xDFE4EB, 0x333844))
    static let ink = Color.dynamic((0x1E2330, 0xEEF0F4))
    static let ink2 = Color.dynamic((0x5E6676, 0xA9B0BC))
    static let ink3 = Color.dynamic((0x9AA2AF, 0x6F7784))
    static let shadow = Color.dynamic((0x1E2330, 0x000000))
    /// Text and icons on an accent fill: white in light mode, near-black on the lighter dark-mode accents.
    static let onAccent = Color.dynamic((0xFFFFFF, 0x0E1420))

    // MARK: Accent (follows the user's pick)
    static var accent: Color { ThemeStore.shared.accent.accent }
    static var accentDeep: Color { ThemeStore.shared.accent.deep }
    static var tint: Color { ThemeStore.shared.accent.tint }
    static var glow: Color { ThemeStore.shared.accent.glow }
    static var accentSoft: Color { ThemeStore.shared.accent.soft }

    // MARK: Meaning (privacy, a hard week)
    static let sage = Color.dynamic((0x7E9C80, 0x8DB490))
    static let sageLight = Color.dynamic((0xDCE7DA, 0x203127))
    static let sageInk = Color.dynamic((0x4D6B50, 0x9CC5A1))
    static let sun = Color.dynamic((0xEDB042, 0xE9B85A))
    static let dusk = Color.dynamic((0x7A72B5, 0xA39CE0))
    static let duskLight = Color.dynamic((0xE3E0F2, 0x2A2840))

    static var surpriseGradient: LinearGradient {
        LinearGradient(colors: [accentDeep.opacity(0.95), accent, accentSoft],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Fixed per person so friends stay recognizable whatever accent you pick.
    static func avatarColors(for name: String) -> [Color] {
        let maya = [Color(hex: 0xE59A7E), Color(hex: 0xF5D0B9)]
        let jay = [Color(hex: 0x7E9C80), Color(hex: 0xB9CFB6)]
        let priya = [Color(hex: 0x8C83D9), Color(hex: 0xC6C0E6)]
        let sky = [Color(hex: 0x5C9FEA), Color(hex: 0xB3D2F8)]
        switch name {
        case "Maya": return maya
        case "Jay": return jay
        case "Priya": return priya
        default:
            let palettes = [maya, jay, priya, sky]
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
    /// A color with separate light and dark mode values.
    static func dynamic(_ pair: (UInt32, UInt32)) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? pair.1 : pair.0)
        })
    }

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

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
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
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Theme.shadow.opacity(0.06), radius: 12, y: 8)
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
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Theme.accent, in: Capsule())
            .shadow(color: Theme.accent.opacity(0.35), radius: 10, y: 8)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct SoftButtonStyle: ButtonStyle {
    var height: CGFloat = 54

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.button())
            .foregroundStyle(Theme.accentDeep)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Theme.tint, in: Capsule())
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
        case .ember: return (Theme.accentDeep, Theme.tint)
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
    var background: Color = Theme.tint
    var foreground: Color = Theme.accent

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
                                    .fill(Theme.card)
                                    .shadow(color: Theme.shadow.opacity(0.1), radius: 3, y: 2)
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

/// The logo: two overlapping circles, the shared middle in the deeper accent.
struct TwinMark: View {
    var width: CGFloat = 64

    var body: some View {
        Canvas { context, size in
            let s = size.width / 64
            let r = 16 * s
            let left = CGRect(x: (22 - 16) * s, y: (20 - 16) * s, width: 2 * r, height: 2 * r)
            let right = CGRect(x: (42 - 16) * s, y: (20 - 16) * s, width: 2 * r, height: 2 * r)
            context.fill(Path(ellipseIn: left), with: .color(Theme.accent))
            context.fill(Path(ellipseIn: right), with: .color(Theme.accentSoft))
            var lens = Path(ellipseIn: left)
            lens = lens.intersection(Path(ellipseIn: right))
            context.fill(lens, with: .color(Theme.accentDeep))
        }
        .frame(width: width, height: width * 40 / 64)
        .accessibilityLabel("Twin")
    }
}
