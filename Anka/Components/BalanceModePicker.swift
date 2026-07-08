import SwiftUI

/// Shared balance-mode switcher used by Today (V1), Stats, and Main Page V2.
/// Two variants: expanding capsule pills (icon + title when active) and V2's
/// icon-only 40pt circles (`iconOnly: true`).
struct BalanceModePicker: View {
    @Binding var mode: BalanceMode
    var iconOnly = false

    var body: some View {
        HStack(spacing: DSSpacing.sm) {
            ForEach(BalanceMode.allCases, id: \.self) { candidate in
                let isActive = mode == candidate

                Button {
                    withAnimation(.dsSpring) { mode = candidate }
                } label: {
                    if iconOnly {
                        Image(systemName: candidate.icon)
                            .font(.dsFootnoteMedium)
                            .frame(width: 40, height: 40)
                            .foregroundStyle(isActive ? DSColor.bgPrimary : .primary)
                            .background(isActive ? Color.primary : DSColor.bgSecondary, in: Circle())
                    } else {
                        HStack(spacing: isActive ? 6 : 0) {
                            Image(systemName: candidate.icon)
                                .font(.dsFootnoteMedium)
                            if isActive {
                                Text(candidate.title)
                                    .font(.dsFootnoteMedium)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, DSSpacing.md)
                        .padding(.vertical, DSSpacing.sm)
                        .foregroundStyle(isActive ? DSColor.bgPrimary : .primary)
                        .background(isActive ? Color.primary : DSColor.bgSecondary, in: Capsule())
                        // Animate the pill's width as the title shows/hides, even
                        // when the mode change originates outside a withAnimation.
                        .animation(.dsSpring, value: isActive)
                    }
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(candidate.title)
            }
        }
    }
}
