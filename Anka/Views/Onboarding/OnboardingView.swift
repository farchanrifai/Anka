import SwiftUI

/// First-run onboarding: Welcome → Speed → Clarity → Trial.
/// Presented as a full-screen overlay above `AppRouter` until the user
/// finishes (see `AnkaApp.rootView`, gated by `anka.hasCompletedOnboarding`).
///
/// The subscription CTA and demo mode on the last page are **placeholders** —
/// StoreKit 2 wiring is Phase 9 and demo mode (24h auto-reset) doesn't exist
/// yet. Both currently just complete onboarding.
struct OnboardingView: View {
    var onComplete: () -> Void

    @State private var page = 0
    private let lastPage = 3

    var body: some View {
        ZStack {
            DSColor.bgPrimary.ignoresSafeArea()
            glow

            VStack(spacing: 0) {
                topBar

                TabView(selection: $page) {
                    OnboardingWelcomePage(isActive: page == 0, onContinue: advance)
                        .tag(0)
                    OnboardingSpeedPage(isActive: page == 1, onContinue: advance)
                        .tag(1)
                    OnboardingClarityPage(isActive: page == 2, onContinue: advance)
                        .tag(2)
                    OnboardingPaywallView(
                        isActive: page == lastPage,
                        onStartTrial: finish,
                        onExploreDemo: finish
                    )
                    .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                pageDots
                    .padding(.top, DSSpacing.md)
                    .padding(.bottom, DSSpacing.lg)
            }
        }
        .onChange(of: page) { _, _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    // MARK: - Chrome

    /// Soft coral wash that drifts as the user moves through the pages —
    /// gives each page a slightly different mood without new artwork.
    private var glow: some View {
        RadialGradient(
            colors: [DSColor.accent.opacity(0.14), .clear],
            center: glowCenter,
            startRadius: 0,
            endRadius: 420
        )
        .ignoresSafeArea()
        .animation(.spring(response: 1.2, dampingFraction: 0.9), value: page)
    }

    private var glowCenter: UnitPoint {
        switch page {
        case 0:  UnitPoint(x: 0.5, y: 0.28)
        case 1:  UnitPoint(x: 0.18, y: 0.34)
        case 2:  UnitPoint(x: 0.82, y: 0.34)
        default: UnitPoint(x: 0.5, y: 0.12)
        }
    }

    private var topBar: some View {
        HStack {
            Spacer()
            Button {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) {
                    page = lastPage
                }
            } label: {
                Text("Skip")
                    .font(.dsFootnoteMedium)
                    .foregroundStyle(DSColor.textMuted)
                    .padding(.vertical, DSSpacing.sm)
                    .padding(.horizontal, DSSpacing.lg)
            }
            .opacity(page == lastPage ? 0 : 1)
            .disabled(page == lastPage)
            .animation(.easeInOut(duration: 0.2), value: page)
        }
        .padding(.horizontal, DSSpacing.xs)
        .frame(height: 44)
    }

    private var pageDots: some View {
        HStack(spacing: DSSpacing.sm) {
            ForEach(0...lastPage, id: \.self) { index in
                Capsule()
                    .fill(index == page ? DSColor.accent : DSColor.textMuted.opacity(0.35))
                    .frame(width: index == page ? 22 : 7, height: 7)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: page)
    }

    // MARK: - Actions

    private func advance() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) {
            page = min(page + 1, lastPage)
        }
    }

    private func finish() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onComplete()
    }
}

// MARK: - Shared reveal animation

/// Staggered entrance used by all onboarding pages: content fades in with a
/// rise + de-blur the first time its page becomes current. Plays once so
/// swiping back doesn't blank previously-seen pages.
struct OnboardingReveal: ViewModifier {
    let isActive: Bool
    let delay: Double
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 18)
            .blur(radius: shown ? 0 : 6)
            .onChange(of: isActive, initial: true) { _, active in
                guard active, !shown else { return }
                withAnimation(.spring(response: 0.6, dampingFraction: 0.85).delay(delay)) {
                    shown = true
                }
            }
    }
}

extension View {
    /// Staggered onboarding entrance — see `OnboardingReveal`.
    func onboardingReveal(_ isActive: Bool, delay: Double = 0) -> some View {
        modifier(OnboardingReveal(isActive: isActive, delay: delay))
    }
}

/// Primary coral capsule button shared across onboarding pages.
struct OnboardingContinueButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Text(title)
                .font(.dsHeadlineSemi)
                .foregroundStyle(DSColor.textOnAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(DSColor.accent, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    OnboardingView(onComplete: {})
}
