import Foundation

/// Single source of truth for how a transaction is turned into the text feature
/// the category classifier consumes. `CategoryPredictor` (inference) and
/// `CategoryMLTrainer` (training) MUST produce byte-identical strings — any
/// drift between them silently breaks the model contract, so the formatting
/// lived in two copies before (AUDIT.md "shared amountBucket").
///
/// Plain `enum` with `static` funcs → nonisolated, callable from the trainer's
/// detached background task and the main-actor predictor alike.
enum MLFeaturizer {
    /// Coarse amount tier appended to the note so the model can lean on spend
    /// size, relative to the user's own recent spending — currency-agnostic.
    /// Cold-start (no history) returns "medium" (neutral, no signal).
    static func amountBucket(_ amount: Double, relativeTo recentAmounts: [Double]) -> String {
        let sorted = recentAmounts.sorted()
        guard !sorted.isEmpty else { return "medium" }
        let mid = sorted.count / 2
        let median = sorted.count.isMultiple(of: 2)
            ? (sorted[mid - 1] + sorted[mid]) / 2
            : sorted[mid]
        guard median > 0 else { return "medium" }

        let ratio = amount / median
        switch ratio {
        case ..<0.25: return "micro"
        case ..<0.75: return "small"
        case ..<1.5:  return "medium"
        case ..<4:    return "large"
        default:      return "xlarge"
        }
    }

    /// The exact training/inference input string: lowercased note + amount tier.
    static func input(note: String, amount: Double, recentAmounts: [Double]) -> String {
        "\(note.lowercased()) \(amountBucket(amount, relativeTo: recentAmounts))"
    }
}

/// Single source of truth for the App-Group `UserDefaults` keys the ML pipeline
/// reads/writes — previously the `"ml_corrections"` literal was re-typed in both
/// `CategoryPredictor` and `CategoryMLTrainer` (AUDIT.md A4).
enum MLStorage {
    static let correctionsKey   = "ml_corrections"
    static let lastTrainCountKey = "ml_last_train_count"
}
