import SwiftUI

// MARK: - Page 1 · Welcome

struct OnboardingWelcomePage: View {
    let isActive: Bool
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            AnkaSparkMark(size: 132)
                .onboardingReveal(isActive)

            VStack(spacing: DSSpacing.md) {
                Text("Anka")
                    .font(.dsSerifHero)
                    .foregroundStyle(DSColor.textPrimary)
                    .onboardingReveal(isActive, delay: 0.15)

                Text("Track what you spend.\nBeautifully, in seconds.")
                    .font(.dsBody)
                    .foregroundStyle(DSColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .onboardingReveal(isActive, delay: 0.25)
            }
            .padding(.top, DSSpacing.xxl)

            Spacer()
            Spacer()

            OnboardingContinueButton(title: "Get Started", action: onContinue)
                .onboardingReveal(isActive, delay: 0.4)
        }
        .padding(.horizontal, DSSpacing.screenEdge)
        .padding(.bottom, DSSpacing.sm)
    }
}

/// Anka's animated mark — a six-petal coral spark (Anthropic-style asterisk).
/// Petals bloom in with a staggered spring, then the whole mark rotates
/// imperceptibly slowly so it never feels static.
struct AnkaSparkMark: View {
    var size: CGFloat = 120

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var bloomed = false
    @State private var spinning = false

    var body: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { index in
                Capsule()
                    .fill(DSColor.accent)
                    .frame(width: size * 0.21, height: size * 0.46)
                    .offset(y: -size * 0.26)
                    .rotationEffect(.degrees(Double(index) * 60))
                    .scaleEffect(bloomed ? 1 : 0.1)
                    .opacity(bloomed ? 1 : 0)
                    .animation(
                        .spring(response: 0.65, dampingFraction: 0.7).delay(Double(index) * 0.07),
                        value: bloomed
                    )
            }
        }
        .frame(width: size, height: size)
        // The perpetual slow spin is decorative — skip it under Reduce Motion
        // (AC5). The petals still settle into place (no rotation), they just
        // don't bloom-scale or spin.
        .rotationEffect(.degrees(spinning ? 360 : 0))
        .animation(reduceMotion ? nil : .linear(duration: 90).repeatForever(autoreverses: false), value: spinning)
        .onAppear {
            bloomed = true
            spinning = !reduceMotion
        }
    }
}

// MARK: - Page 2 · Speed

struct OnboardingSpeedPage: View {
    let isActive: Bool
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            QuickAddDemo(isActive: isActive)
                .onboardingReveal(isActive)

            VStack(spacing: DSSpacing.md) {
                Text("Five seconds,\ndone.")
                    .font(.dsSerifTitle)
                    .foregroundStyle(DSColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .onboardingReveal(isActive, delay: 0.12)

                Text("Amount, category, save. Logging an expense should never feel like a chore — so it doesn't.")
                    .font(.dsBody)
                    .foregroundStyle(DSColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .onboardingReveal(isActive, delay: 0.22)
            }
            .padding(.top, DSSpacing.xxl)

            Spacer()
            Spacer()

            OnboardingContinueButton(title: "Continue", action: onContinue)
                .onboardingReveal(isActive, delay: 0.35)
        }
        .padding(.horizontal, DSSpacing.screenEdge)
        .padding(.bottom, DSSpacing.sm)
    }
}

/// Looping micro-demo of the Add Transaction flow: the amount ticks up,
/// a category chip appears, then a Save pill confirms — and it loops.
private struct QuickAddDemo: View {
    let isActive: Bool

    @State private var amount: Int = 0
    @State private var showChip = false
    @State private var saved = false
    @State private var loopTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            Text("New expense")
                .font(.dsCaptionMedium)
                .foregroundStyle(DSColor.textMuted)
                .textCase(.uppercase)

            Text("IDR \(amount.formatted())")
                .font(.dsTitle2Bold)
                .foregroundStyle(DSColor.textPrimary)
                .contentTransition(.numericText(value: Double(amount)))
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                if showChip {
                    HStack(spacing: DSSpacing.xs) {
                        Text("☕️")
                            .font(.dsFootnote)
                        Text("Coffee")
                            .font(.dsFootnoteSemi)
                            .foregroundStyle(DSColor.accent)
                    }
                    .padding(.vertical, DSSpacing.sm)
                    .padding(.horizontal, DSSpacing.md)
                    .background(DSColor.accentSoft, in: Capsule())
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }

                Spacer()

                HStack(spacing: DSSpacing.xs) {
                    if saved {
                        Image(systemName: "checkmark")
                            .font(.dsFootnoteBold)
                            .transition(.scale.combined(with: .opacity))
                    }
                    Text(saved ? "Saved" : "Save")
                        .font(.dsFootnoteSemi)
                }
                .foregroundStyle(saved ? DSColor.textOnAccent : DSColor.textMuted)
                .padding(.vertical, DSSpacing.sm)
                .padding(.horizontal, DSSpacing.lg)
                .background(
                    Capsule().fill(saved ? DSColor.accent : DSColor.bgTertiary)
                )
            }
        }
        .padding(DSSpacing.xl)
        .frame(maxWidth: 320)
        .background(DSColor.bgCard, in: RoundedRectangle(cornerRadius: DSRadius.large))
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.large)
                .stroke(DSColor.separator.opacity(0.5), lineWidth: 1)
        )
        .onChange(of: isActive, initial: true) { _, active in
            loopTask?.cancel()
            if active {
                loopTask = Task { await runLoop() }
            }
        }
        .onDisappear { loopTask?.cancel() }
    }

    @MainActor
    private func runLoop() async {
        while !Task.isCancelled {
            // Type the amount digit by digit.
            for value in [2, 25, 250, 2_500, 25_000] {
                try? await Task.sleep(for: .milliseconds(320))
                guard !Task.isCancelled else { return }
                withAnimation(.snappy(duration: 0.25)) { amount = value }
            }

            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { showChip = true }

            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { saved = true }

            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                amount = 0
                showChip = false
                saved = false
            }

            try? await Task.sleep(for: .milliseconds(700))
        }
    }
}

// MARK: - Page 3 · Clarity

struct OnboardingClarityPage: View {
    let isActive: Bool
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ClarityDonutDemo(isActive: isActive)
                .onboardingReveal(isActive)

            VStack(spacing: DSSpacing.md) {
                Text("Clarity,\nnot clutter.")
                    .font(.dsSerifTitle)
                    .foregroundStyle(DSColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .onboardingReveal(isActive, delay: 0.12)

                Text("One screen for today, one chart for the month. Everything you need — nothing you don't.")
                    .font(.dsBody)
                    .foregroundStyle(DSColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .onboardingReveal(isActive, delay: 0.22)
            }
            .padding(.top, DSSpacing.xxl)

            Spacer()
            Spacer()

            OnboardingContinueButton(title: "Continue", action: onContinue)
                .onboardingReveal(isActive, delay: 0.35)
        }
        .padding(.horizontal, DSSpacing.screenEdge)
        .padding(.bottom, DSSpacing.sm)
    }
}

/// A small donut chart whose segments draw themselves in when the page
/// becomes active — a quiet preview of the Stats screen.
private struct ClarityDonutDemo: View {
    let isActive: Bool

    @State private var progress: Double = 0

    private struct Segment {
        let start: Double
        let end: Double
        let color: Color
    }

    private var segments: [Segment] {
        [
            Segment(start: 0.00, end: 0.42, color: DSColor.accent),
            Segment(start: 0.45, end: 0.68, color: DSColor.accent.opacity(0.45)),
            Segment(start: 0.71, end: 0.97, color: DSColor.textMuted.opacity(0.3)),
        ]
    }

    var body: some View {
        ZStack {
            ForEach(segments.indices, id: \.self) { index in
                let segment = segments[index]
                Circle()
                    .trim(
                        from: segment.start,
                        to: segment.start + (segment.end - segment.start) * progress
                    )
                    .stroke(segment.color, style: StrokeStyle(lineWidth: 20, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }

            VStack(spacing: DSSpacing.xs) {
                Text("June")
                    .font(.dsCaptionMedium)
                    .foregroundStyle(DSColor.textMuted)
                    .textCase(.uppercase)
                Text("12.4M")
                    .font(.dsTitle2Bold)
                    .foregroundStyle(DSColor.textPrimary)
            }
        }
        .frame(width: 176, height: 176)
        .padding(DSSpacing.md)
        .onChange(of: isActive, initial: true) { _, active in
            guard active else { return }
            progress = 0
            withAnimation(.spring(response: 1.1, dampingFraction: 0.9).delay(0.25)) {
                progress = 1
            }
        }
    }
}

#Preview("Welcome") {
    ZStack {
        DSColor.bgPrimary.ignoresSafeArea()
        OnboardingWelcomePage(isActive: true, onContinue: {})
    }
}

#Preview("Speed") {
    ZStack {
        DSColor.bgPrimary.ignoresSafeArea()
        OnboardingSpeedPage(isActive: true, onContinue: {})
    }
}

#Preview("Clarity") {
    ZStack {
        DSColor.bgPrimary.ignoresSafeArea()
        OnboardingClarityPage(isActive: true, onContinue: {})
    }
}
