import SwiftUI

// Welcome, sign-in and first-run setup. Google signs in with a real account;
// Apple, email and the chips sign in as a seeded demo user.

struct WelcomeView: View {
    let onStart: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 28) {
                ZStack {
                    Circle()
                        .fill(RadialGradient(
                            colors: [Theme.tint, Theme.glow, Theme.paper.opacity(0)],
                            center: .center, startRadius: 0, endRadius: 115
                        ))
                        .frame(width: 230, height: 230)
                        .scaleEffect(appeared ? 1 : 0.85)
                    TwinMark(width: 150)
                        .scaleEffect(appeared ? 1 : 0.7)
                }
                Text("Your friends shouldn't have to ask.")
                    .font(Theme.title(38))
                    .tracking(-0.6)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.ink)
                Text("Twin keeps up with your week and quietly lets your closest people know when you could use them.")
                    .font(Theme.body(17))
                    .lineSpacing(3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.ink2)
            }
            .padding(.horizontal, 28)
            .opacity(appeared ? 1 : 0)
            Spacer()
            VStack(spacing: 14) {
                Button("Get started", action: onStart)
                    .buttonStyle(PrimaryButtonStyle())
                Label("Your calendar and email never leave your twin.", systemImage: "lock.fill")
                    .font(Theme.small())
                    .foregroundStyle(Theme.ink2)
                    .labelStyle(SageIconLabelStyle())
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) { appeared = true }
        }
    }
}

struct SignInView: View {
    @EnvironmentObject private var state: AppState
    @State private var email = ""
    @State private var working = false
    @State private var googleWorking = false
    @State private var googleError: String?
    @FocusState private var emailFocused: Bool

    private let demoAccounts = [("Maya", "maya@example.com"), ("Jay", "jay@example.com"), ("Priya", "priya@example.com")]

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 18) {
                    TwinMark(width: 76)
                    VStack(spacing: 8) {
                        Text("Welcome to Twin")
                            .font(Theme.title())
                            .tracking(-0.6)
                            .foregroundStyle(Theme.ink)
                        Text("Sign in to see your people.")
                            .font(Theme.body(16))
                            .foregroundStyle(Theme.ink2)
                    }
                }
                .padding(.top, 56)

                VStack(spacing: 12) {
                    Button {
                        Task { await signIn() }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "apple.logo").font(.system(size: 18, weight: .medium))
                            Text("Continue with Apple")
                        }
                    }
                    .buttonStyle(AuthButtonStyle(background: Theme.ink, foreground: Theme.paper))

                    Button {
                        Task { await signInWithGoogle() }
                    } label: {
                        HStack(spacing: 10) {
                            if googleWorking {
                                ProgressView()
                            } else {
                                Text("G")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundStyle(Theme.accent)
                            }
                            Text("Continue with Google")
                        }
                    }
                    .buttonStyle(AuthButtonStyle(background: Theme.card, foreground: Theme.ink, border: Theme.linen))
                    .disabled(googleWorking)

                    if let googleError {
                        Text(googleError)
                            .font(Theme.small(13))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Theme.accentDeep)
                    }
                }

                HStack(spacing: 12) {
                    Rectangle().fill(Theme.linen).frame(height: 1)
                    Text("or").font(Theme.small()).foregroundStyle(Theme.ink3)
                    Rectangle().fill(Theme.linen).frame(height: 1)
                }

                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "envelope")
                            .foregroundStyle(Theme.ink3)
                        TextField("Email address", text: $email)
                            .font(Theme.body(16))
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($emailFocused)
                            .submitLabel(.continue)
                            .onSubmit { Task { await signIn() } }
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 54)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(emailFocused ? Theme.accent.opacity(0.6) : Theme.linen, lineWidth: 1.5)
                    )

                    Button {
                        Task { await signIn() }
                    } label: {
                        HStack(spacing: 8) {
                            if working { ProgressView().tint(Theme.onAccent) }
                            Text("Continue with email")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(working || email.isEmpty)
                    .opacity(email.isEmpty ? 0.55 : 1)
                }

                VStack(spacing: 10) {
                    Eyebrow(text: "Demo accounts")
                    HStack(spacing: 8) {
                        ForEach(demoAccounts, id: \.1) { name, address in
                            Button {
                                email = address
                            } label: {
                                HStack(spacing: 6) {
                                    Avatar(name: name, id: "u_\(name.lowercased())", size: 22)
                                    Text(name).font(Theme.semibold(13)).foregroundStyle(Theme.ink)
                                }
                                .padding(.leading, 4)
                                .padding(.trailing, 10)
                                .padding(.vertical, 4)
                                .background(Theme.cream, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.top, 4)

                Text("Twin only ever shares what you choose. You can change that anytime in Privacy.")
                    .font(Theme.small(12))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.ink3)
                    .padding(.horizontal, 20)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .screenBackground()
    }

    private func signInWithGoogle() async {
        googleWorking = true
        googleError = nil
        defer { googleWorking = false }
        do {
            try await state.signInWithGoogle()
        } catch where GoogleAuth.isCancel(error) {
        } catch {
            googleError = error.localizedDescription
        }
    }

    private func signIn() async {
        working = true
        defer { working = false }
        await state.signIn(email: email)
    }
}

struct SetupView: View {
    @EnvironmentObject private var state: AppState
    @State private var openToSupport = true
    @State private var surprisesOn = true
    @State private var phone = ""
    @State private var notificationsAsked = false
    @State private var saving = false
    @State private var step = 0
    @State private var locationLabel: String?
    @State private var locating = false
    @State private var interests: [String] = []

    var body: some View {
        ZStack {
            if step == 0 {
                interestsPage
                    .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .leading).combined(with: .opacity)))
            } else {
                settingsPage
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: step)
    }

    /// First thing a new account sees, like Instagram's interest picker.
    private var interestsPage: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow(text: "Hi \(state.me?.name.split(separator: " ").first.map(String.init) ?? "there")")
                        Text("What are you into?")
                            .font(Theme.title(30))
                            .foregroundStyle(Theme.ink)
                        Text("Pick as many as you like. When a friend wants to show up for you, your twin suggests things you'd actually love.")
                            .font(Theme.small())
                            .foregroundStyle(Theme.ink2)
                    }
                    .padding(.top, 40)
                    InterestsPicker(selection: $interests)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)

            Button {
                step = 1
            } label: {
                Text(interests.isEmpty ? "Skip for now" : "Continue with \(interests.count) picked")
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .screenBackground()
        .onAppear {
            if interests.isEmpty { interests = state.me?.interests ?? [] }
        }
    }

    private var settingsPage: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 14) {
                        ProfilePhotoPicker {
                            Avatar(user: state.me, size: 52, glow: true)
                                .padding(12)
                                .overlay(alignment: .bottomTrailing) {
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(Theme.onAccent)
                                        .frame(width: 22, height: 22)
                                        .background(Theme.accent, in: Circle())
                                        .overlay(Circle().strokeBorder(Theme.card, lineWidth: 2))
                                        .offset(x: -8, y: -8)
                                }
                        }
                        .buttonStyle(.plain)
                        VStack(alignment: .leading, spacing: 4) {
                            Eyebrow(text: "Hi \(state.me?.name ?? "there")")
                            Text("A few quick things")
                                .font(Theme.title(30))
                                .foregroundStyle(Theme.ink)
                        }
                    }
                    .padding(.top, 40)

                    VStack(alignment: .leading, spacing: 16) {
                        setting("heart", "Open to support",
                                "When your calendar gets heavy, your twin can quietly let your close friends know. Off means it never tells anyone.",
                                isOn: $openToSupport)
                        Rectangle().fill(Theme.cream).frame(height: 1)
                        setting("gift", "Surprises",
                                "On: when a friend brings you a coffee or plans a hangout, you won't know until it happens. Off: you get a heads-up first.",
                                isOn: $surprisesOn)
                    }
                    .card()

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 14) {
                            IconBadge(systemImage: "location")
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Your location").font(Theme.bodyStrong()).foregroundStyle(Theme.ink)
                                Text("So friends get ideas near you, not across the country. No one sees where you are unless you turn that on in Map.")
                                    .font(Theme.small())
                                    .foregroundStyle(Theme.ink2)
                            }
                        }
                        if let locationLabel {
                            Pill(text: "Near \(locationLabel)", tone: .sage, systemImage: "checkmark")
                        } else {
                            Button {
                                Task {
                                    locating = true
                                    locationLabel = await state.shareLocation(askIfNeeded: true)
                                    locating = false
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    if locating { ProgressView().tint(Theme.onAccent) }
                                    Text("Share my location")
                                }
                            }
                            .buttonStyle(PrimaryButtonStyle(height: 44))
                            .disabled(locating)
                        }
                    }
                    .card()

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 14) {
                            IconBadge(systemImage: "phone")
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Your phone number").font(Theme.bodyStrong()).foregroundStyle(Theme.ink)
                                Text("Optional. Friends who have you in their contacts can find you on Twin.")
                                    .font(Theme.small())
                                    .foregroundStyle(Theme.ink2)
                            }
                        }
                        TextField("(512) 555-0123", text: $phone)
                            .font(Theme.body(16))
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                            .padding(.horizontal, 14)
                            .frame(height: 48)
                            .background(Theme.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.linen, lineWidth: 1))
                    }
                    .card()

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 14) {
                            IconBadge(systemImage: "bell")
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Notifications").font(Theme.bodyStrong()).foregroundStyle(Theme.ink)
                                Text("So you hear when a friend could use you, or when someone shows up for you.")
                                    .font(Theme.small())
                                    .foregroundStyle(Theme.ink2)
                            }
                        }
                        if notificationsAsked {
                            Pill(text: "Notifications set", tone: .sage, systemImage: "checkmark")
                        } else {
                            Button("Turn on notifications") {
                                Notifier.requestPermission()
                                withAnimation { notificationsAsked = true }
                            }
                            .buttonStyle(PrimaryButtonStyle(height: 44))
                        }
                    }
                    .card()

                    Label("Tap your photo to add a picture. You can connect your calendar and email anytime from your account.", systemImage: "person.crop.circle")
                        .font(Theme.small())
                        .foregroundStyle(Theme.ink2)
                        .labelStyle(SageIconLabelStyle())
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 20)
            }

            Button {
                Task { await finish() }
            } label: {
                HStack(spacing: 8) {
                    if saving { ProgressView().tint(Theme.onAccent) }
                    Text("Start")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(saving)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .screenBackground()
        .onAppear {
            openToSupport = state.me?.surpriseOptIn ?? true
            surprisesOn = state.me?.surprisesEnabled ?? true
            phone = state.me?.phone ?? ""
            // Interests were picked on the page before; reloading them here would wipe the picks.
        }
    }

    private func setting(_ icon: String, _ title: String, _ detail: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 14) {
            IconBadge(systemImage: icon)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Theme.bodyStrong()).foregroundStyle(Theme.ink)
                Text(detail).font(Theme.small()).foregroundStyle(Theme.ink2)
            }
            Spacer(minLength: 0)
            Toggle("", isOn: isOn).labelsHidden().tint(Theme.sage)
        }
    }

    private func finish() async {
        saving = true
        defer { saving = false }
        let trimmed = phone.trimmingCharacters(in: .whitespaces)
        let patch = SettingsPatch(openToSupport: openToSupport, surprisesOn: surprisesOn, phone: trimmed.isEmpty ? nil : trimmed, interests: interests)
        if let user = try? await state.api.updateSettings(patch) {
            state.updateMe(user)
        }
        state.hasCompletedSetup = true
    }
}

struct AuthButtonStyle: ButtonStyle {
    var background: Color
    var foreground: Color
    var border: Color?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.button())
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(background, in: Capsule())
            .overlay {
                if let border {
                    Capsule().strokeBorder(border, lineWidth: 1.5)
                }
            }
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct SageIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 7) {
            configuration.icon.foregroundStyle(Theme.sage)
            configuration.title
        }
    }
}
