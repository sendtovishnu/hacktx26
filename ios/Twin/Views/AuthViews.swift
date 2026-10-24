import SwiftUI

// Welcome, sign-in and first-run setup. Sign-in is a demo: no real accounts yet.

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
                        Task { await signIn() }
                    } label: {
                        HStack(spacing: 10) {
                            Text("G")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.accent)
                            Text("Continue with Google")
                        }
                    }
                    .buttonStyle(AuthButtonStyle(background: Theme.card, foreground: Theme.ink, border: Theme.linen))
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

    private func signIn() async {
        working = true
        defer { working = false }
        await state.signIn(email: email)
    }
}

struct SetupView: View {
    @EnvironmentObject private var state: AppState
    @State private var surpriseOn = true
    @State private var notificationsAsked = false
    @State private var saving = false

    var body: some View {
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
                            Text("Two quick things")
                                .font(Theme.title(30))
                                .foregroundStyle(Theme.ink)
                        }
                    }
                    .padding(.top, 40)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 14) {
                            IconBadge(systemImage: "gift")
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Surprise support").font(Theme.bodyStrong()).foregroundStyle(Theme.ink)
                                Text("When your week gets heavy, your twin can quietly let your closest friends know. You won't be asked each time.")
                                    .font(Theme.small())
                                    .foregroundStyle(Theme.ink2)
                            }
                            Spacer(minLength: 0)
                            Toggle("", isOn: $surpriseOn).labelsHidden().tint(Theme.sage)
                        }
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
                            .buttonStyle(SoftButtonStyle(height: 44))
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
        .onAppear { surpriseOn = state.me?.surpriseOptIn ?? true }
    }

    private func finish() async {
        saving = true
        defer { saving = false }
        if let user = try? await state.api.updateSettings(surpriseOptIn: surpriseOn, paused: nil) {
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
