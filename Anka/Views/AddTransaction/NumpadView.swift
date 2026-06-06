import SwiftUI

struct NumpadView: View {
    @Binding var amountString: String
    let onNoteTap: () -> Void

    private let rows = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]]

    var body: some View {
        VStack(spacing: DSSpacing.sm) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: DSSpacing.sm) {
                    ForEach(row, id: \.self) { digit in
                        key(action: { append(digit) }) {
                            Text(digit)
                                .font(.system(size: 26, weight: .regular))
                                .foregroundStyle(DSColor.textPrimary)
                        }
                    }
                }
            }

            // Note key · 0 · Backspace
            HStack(spacing: DSSpacing.sm) {
                key(action: onNoteTap) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(DSColor.textSecondary)
                }

                key(action: { append("0") }) {
                    Text("0")
                        .font(.system(size: 26, weight: .regular))
                        .foregroundStyle(DSColor.textPrimary)
                }

                key(action: backspace) {
                    Image(systemName: "delete.left")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(DSColor.negative)
                }
            }
        }
        .padding(.horizontal, DSSpacing.lg)
    }

    private func key<Content: View>(
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Content
    ) -> some View {
        Button(action: action) {
            label()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func append(_ digit: String) {
        if amountString == "0" {
            amountString = digit
        } else if amountString.count < 12 {
            amountString.append(digit)
        }
    }

    private func backspace() {
        if amountString.count <= 1 {
            amountString = "0"
        } else {
            amountString.removeLast()
        }
    }
}
