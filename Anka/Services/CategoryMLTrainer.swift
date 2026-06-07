import Foundation
import CoreML
import SwiftData

#if canImport(CreateML) && canImport(TabularData)
import CreateML
import TabularData
#endif

/// A thread-safe representation of a transaction used for ML training.
public struct TrainableTransaction: Sendable {
    public let note: String
    public let amount: Double
    public let categoryName: String

    public init(note: String, amount: Double, categoryName: String) {
        self.note = note
        self.amount = amount
        self.categoryName = categoryName
    }
}

/// On-device training for the user's personal category classifier.
/// Uses CreateML's MLTextClassifier (available on macOS and iOS 16+
/// when the CreateML framework is importable in the build target).
/// On builds where CreateML is unavailable, `trainIfNeeded` is a no-op —
/// inference still works via the bundled StarterCategoryClassifier.
public enum CategoryMLTrainer {
    private static let lastCountKey = "ml_last_train_count"
    private static let appGroupID   = PlatformPaths.appGroupID

    // MARK: - Public

    public static func trainIfNeeded(transactions: [TrainableTransaction]) async throws {
        guard transactions.count >= 20 else { return }

        let defaults  = UserDefaults(suiteName: appGroupID)
        let lastCount = defaults?.integer(forKey: lastCountKey) ?? 0
        guard transactions.count >= lastCount + 10 || lastCount == 0 else { return }

#if canImport(CreateML) && canImport(TabularData)
        try await train(labeled: transactions, defaults: defaults, newCount: transactions.count)
#endif
    }

    // MARK: - Training (CreateML path)

#if canImport(CreateML) && canImport(TabularData)
    private static func train(labeled: [TrainableTransaction], defaults: UserDefaults?, newCount: Int) async throws {
        var texts:  [String] = []
        var labels: [String] = []

        for tx in labeled {
            texts.append("\(tx.note.lowercased()) \(amountBucket(tx.amount))")
            labels.append(tx.categoryName)
        }

        // Include correction examples at 2x weight to prioritize user feedback.
        for entry in loadCorrections() {
            guard let actual = entry.actual,
                  !entry.note.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let text = "\(entry.note.lowercased()) \(amountBucket(entry.amount))"
            texts.append(contentsOf: [text, text])
            labels.append(contentsOf: [actual, actual])
        }

        guard texts.count >= 20 else { return }

        var df = DataFrame()
        df.append(column: Column<String>(name: "text",  contents: texts))
        df.append(column: Column<String>(name: "label", contents: labels))

        // MLTextClassifier.init is a blocking CPU-intensive call.
        // Run it in a detached task so it never executes on the main actor.
        let tempURL = try await Task.detached(priority: .background) {
            let classifier = try MLTextClassifier(
                trainingData: df,
                textColumn: "text",
                labelColumn: "label"
            )
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("UserCategoryClassifier_\(UUID().uuidString).mlmodel")
            try classifier.write(to: url)
            return url
        }.value

        // Compile the written .mlmodel to .mlmodelc.
        let compiledURL = try await MLModel.compileModel(at: tempURL)

        // Move to shared container.
        let destURL = PlatformPaths.appGroupContainerURL
            .appendingPathComponent("UserCategoryClassifier.mlmodelc")

        let fm = FileManager.default
        if fm.fileExists(atPath: destURL.path) {
            try fm.removeItem(at: destURL)
        }
        try fm.copyItem(at: compiledURL, to: destURL)

        try? fm.removeItem(at: tempURL)
        try? fm.removeItem(at: compiledURL)

        defaults?.set(newCount, forKey: lastCountKey)
    }
#endif

    // MARK: - Corrections

    private static func loadCorrections() -> [CorrectionEntry] {
        let defaults = UserDefaults(suiteName: appGroupID)
        guard let data = defaults?.data(forKey: "ml_corrections"),
              let entries = try? JSONDecoder().decode([CorrectionEntry].self, from: data) else {
            return []
        }
        return entries
    }

    // MARK: - Shared helper

    private static func amountBucket(_ amount: Double) -> String {
        switch amount {
        case ..<20_000:    return "micro"
        case ..<100_000:   return "small"
        case ..<500_000:   return "medium"
        case ..<2_000_000: return "large"
        default:           return "xlarge"
        }
    }
}
