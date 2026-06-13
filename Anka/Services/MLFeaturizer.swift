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
    /// size. ⚠️ Tuned for IDR ranges (see CONTEXT "Internationalization concern").
    static func amountBucket(_ amount: Double) -> String {
        switch amount {
        case ..<20_000:    return "micro"
        case ..<100_000:   return "small"
        case ..<500_000:   return "medium"
        case ..<2_000_000: return "large"
        default:           return "xlarge"
        }
    }

    /// The exact training/inference input string: lowercased note + amount tier.
    static func input(note: String, amount: Double) -> String {
        "\(note.lowercased()) \(amountBucket(amount))"
    }
}
