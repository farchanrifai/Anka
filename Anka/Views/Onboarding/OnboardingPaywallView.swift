import SwiftUI

/// Final onboarding page: 14-day trial pitch + plan selection + demo mode.
///
/// ⚠️ **Everything here is a placeholder** (Phase 9 — Subscription, not started):
/// - Prices are hardcoded sample values; real ones come from StoreKit 2
///   `Product` objects once App Store Connect is configured.
/// - "Start Free Trial" does NOT purchase anything — it just completes
///   onboarding.
/// - Demo mode (full access, data auto-resets every 24h) is not built yet;
///   the button also just completes onboarding.
struct OnboardingPaywallView: View {
    let isActive: Bool
    let onStartTrial: () -> Void
    let onExploreDemo: () -> Void

    @State private var selectedPlan: Plan = .yearly

    enum Plan: CaseIterable {
        case monthly, yearly, yearlyInstallment
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: DSSpacing.lg) {
                    header
                    trialTimeline
                        .onboardingReveal(isActive, delay: 0.15)
                    planCards
                        .onboardingReveal(isActive, delay: 0.25)
                }
                .padding(.horizontal, DSSpacing.screenEdge)
                .padding(.bottom, DSSpacing.md)
            }

            footer
                .padding(.horizontal, DSSpacing.screenEdge)
                .onboardingReveal(isActive, delay: 0.35)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: DSSpacing.sm) {
            AnkaSparkMark(size: 40)
                .onboardingReveal(isActive)
                .padding(.bottom, DSSpacing.xs)

            Text("Try Anka free for 14 days")
                .font(.dsSerifTitle)
                .foregroundStyle(DSColor.textPrimary)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
                .onboardingReveal(isActive, delay: 0.08)

            Text("Every feature, no limits. Cancel anytime.")
                .font(.dsFootnote)
                .foregroundStyle(DSColor.textSecondary)
                .onboardingReveal(isActive, delay: 0.12)
        }
    }

    // MARK: - Trial timeline

    private var trialTimeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            timelineRow(
                symbol: "lock.open.fill",
                title: "Today",
                detail: "Full access to everything in Anka.",
                isLast: false
            )
            timelineRow(
                symbol: "bell.fill",
                title: "Day 12",
                detail: "We'll remind you before the trial ends.",
                isLast: false
            )
            timelineRow(
                symbol: "star.fill",
                title: "Day 14",
                detail: "Your plan begins. Cancel anytime before.",
                isLast: true
            )
        }
        .padding(DSSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSColor.bgCard, in: RoundedRectangle(cornerRadius: DSRadius.medium))
    }

    private func timelineRow(symbol: String, title: String, detail: String, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: DSSpacing.md) {
            VStack(spacing: 0) {
                Image(systemName: symbol)
                    .font(.dsBadgeSemi)
                    .foregroundStyle(DSColor.accent)
                    .frame(width: 24, height: 24)
                    .background(DSColor.accentSoft, in: Circle())

                if !isLast {
                    Rectangle()
                        .fill(DSColor.accentSoft)
                        .frame(width: 2)
                        .frame(minHeight: DSSpacing.sm)
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.dsBodySemi)
                    .foregroundStyle(DSColor.textPrimary)
                Text(detail)
                    .font(.dsCaption2)
                    .foregroundStyle(DSColor.textSecondary)
            }
            .padding(.bottom, isLast ? 0 : DSSpacing.sm)
        }
    }

    // MARK: - Plans

    private var planCards: some View {
        VStack(spacing: DSSpacing.sm) {
            // PLACEHOLDER prices — replace with StoreKit 2 Product.displayPrice.
            planCard(
                plan: .yearly,
                title: "Yearly",
                badge: "Best Value",
                price: "Rp 199.000",
                cadence: "/year",
                detail: "Rp 16.600/mo, billed annually"
            )
            planCard(
                plan: .yearlyInstallment,
                title: "Yearly, paid monthly",
                badge: "New",
                price: "Rp 16.600",
                cadence: "/month",
                detail: "Yearly plan split into 12 payments"
            )
            planCard(
                plan: .monthly,
                title: "Monthly",
                badge: nil,
                price: "Rp 29.000",
                cadence: "/month",
                detail: "Billed monthly, switch anytime"
            )
        }
    }

    private func planCard(
        plan: Plan,
        title: String,
        badge: String?,
        price: String,
        cadence: String,
        detail: String
    ) -> some View {
        let isSelected = selectedPlan == plan

        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                selectedPlan = plan
            }
        } label: {
            HStack(spacing: DSSpacing.md) {
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    HStack(spacing: DSSpacing.sm) {
                        Text(title)
                            .font(.dsSubheadSemi)
                            .foregroundStyle(DSColor.textPrimary)

                        if let badge {
                            Text(badge)
                                .font(.dsBadgeSemi)
                                .textCase(.uppercase)
                                .foregroundStyle(DSColor.textOnAccent)
                                .padding(.vertical, 3)
                                .padding(.horizontal, DSSpacing.sm)
                                .background(DSColor.accent, in: Capsule())
                        }
                    }

                    Text(detail)
                        .font(.dsCaption2)
                        .foregroundStyle(DSColor.textSecondary)
                }

                Spacer(minLength: DSSpacing.sm)

                VStack(alignment: .trailing, spacing: 0) {
                    Text(price)
                        .font(.dsSubheadBold)
                        .foregroundStyle(DSColor.textPrimary)
                    Text(cadence)
                        .font(.dsCaption2)
                        .foregroundStyle(DSColor.textMuted)
                }
            }
            .padding(.vertical, DSSpacing.md)
            .padding(.horizontal, DSSpacing.lg)
            .background(DSColor.bgCard, in: RoundedRectangle(cornerRadius: DSRadius.medium))
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.medium)
                    .stroke(
                        isSelected ? DSColor.accent : DSColor.separator.opacity(0.5),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: DSSpacing.sm) {
            // TODO(Phase 9): start the StoreKit 2 purchase for `selectedPlan`.
            OnboardingContinueButton(title: "Start 14-Day Free Trial", action: onStartTrial)

            // TODO: wire real demo mode (full access, data resets every 24h).
            Button(action: onExploreDemo) {
                VStack(spacing: 2) {
                    Text("Explore Demo Mode")
                        .font(.dsSubheadSemi)
                        .foregroundStyle(DSColor.accent)
                    Text("Try everything — your data resets every 24 hours")
                        .font(.dsCaption2)
                        .foregroundStyle(DSColor.textMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DSSpacing.sm)
            }
            .buttonStyle(.plain)

            // Placeholder legal row — link to real Terms/Privacy before launch.
            Text("Restore Purchases · Terms · Privacy")
                .font(.dsCaption2)
                .foregroundStyle(DSColor.textMuted)
        }
    }
}

#Preview {
    ZStack {
        DSColor.bgPrimary.ignoresSafeArea()
        OnboardingPaywallView(isActive: true, onStartTrial: {}, onExploreDemo: {})
    }
}
