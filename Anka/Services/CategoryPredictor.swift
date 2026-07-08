import Foundation
import Observation
import CoreML
import NaturalLanguage
import SwiftData
import os

// Logger is Sendable; safe to use from the detached training task.
private nonisolated let predictorLogger = Logger(subsystem: "com.nc.Anka", category: "CategoryPredictor")

// MARK: - Prediction types

public enum PredictionSource {
    case keyword, userModel, starterModel
}

public struct Prediction {
    public let category: String
    public let confidence: Double
    public let source: PredictionSource

    /// True only for high-confidence predictions (≥ 0.85). Retained for a
    /// possible future silent-vs-soft distinction; the current UI applies both
    /// bands the same way (see `shouldSuggest`).
    public var shouldAutoAssign: Bool { confidence >= 0.85 }

    /// Confidence floor for surfacing a prediction at all. The 0.60–0.85 band
    /// was originally earmarked for a confirm "chip" that was never built; per
    /// AUDIT.md (Batch 10 chip-band decision) it is **folded into
    /// auto-assign-with-undo** — the predicted category is applied and shown via
    /// the tappable sparkle pill, and deselecting it logs a negative correction.
    /// So one threshold gates whether a prediction is applied.
    public var shouldSuggest: Bool { confidence >= 0.60 }
}

// MARK: - Correction signal

/// A labeled correction signal from user behavior.
/// `actual` is nil when the user dismissed a chip without assigning (negative signal).
public struct CorrectionEntry: Codable {
    public let note: String
    public let amount: Double
    public let predicted: String
    public let actual: String?
}

// MARK: - Predictor

/// Orchestrates the 3-layer prediction pipeline:
///   1. KeywordMatcher     — static dictionary, fires first
///   2. UserCategoryClassifier — trained on user's own transactions
///   3. StarterCategoryClassifier — bundled model, softest fallback
@MainActor
@Observable
public final class CategoryPredictor {
    private let starterModel: NLModel?
    private var userModel: NLModel?

    /// Snapshot of the user's recent expense amounts, used to bucket new
    /// amounts relative to their own spend (currency-agnostic). Updated by
    /// the view layer alongside category/transaction feeds.
    private var recentAmounts: [Double] = []

    public init() {
        starterModel = Self.loadStarterModel()
        loadUserModel()
    }

    /// Feeds the predictor a snapshot of the user's recent expense amounts so
    /// `amountBucket` can scale to their spending instead of fixed IDR ranges.
    public func updateRecentAmounts(_ amounts: [Double]) {
        recentAmounts = amounts
    }

    // MARK: - Predict

    @discardableResult
    public func predict(note: String, amount: Double) -> Prediction? {
        let trimmed = note.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let input = buildInput(note: trimmed, amount: amount)
        var result: Prediction?

        // Layer 1: keyword
        if let match = KeywordMatcher.match(note: trimmed) {
            result = Prediction(category: match.category, confidence: match.confidence, source: .keyword)
        }

        // Layer 2: user model (threshold 0.75)
        if result == nil, let model = userModel {
            result = infer(model: model, input: input, threshold: 0.75, source: .userModel)
        }

        // Layer 3: starter model (threshold 0.60)
        if result == nil, let model = starterModel {
            result = infer(model: model, input: input, threshold: 0.60, source: .starterModel)
        }

        return result
    }

    // MARK: - Correction logging

    /// Max correction entries retained. The log is decoded/appended/re-encoded
    /// on every correction, and entries are doubled at train time — so an
    /// unbounded log means ever-slower saves and stale signals over-weighting
    /// training. Cap to the most recent N (AUDIT.md P6). Entries already baked
    /// into a trained model are additionally pruned by `CategoryMLTrainer`.
    public static let maxCorrections = 500

    public func logCorrection(note: String, amount: Double, predicted: String, actual: String?) {
        let entry = CorrectionEntry(note: note, amount: amount, predicted: predicted, actual: actual)
        let defaults = UserDefaults(suiteName: Self.appGroupID)
        var existing: [CorrectionEntry] = []
        if let data = defaults?.data(forKey: Self.correctionsKey),
           let decoded = try? JSONDecoder().decode([CorrectionEntry].self, from: data) {
            existing = decoded
        }
        existing.append(entry)
        // Keep only the most recent `maxCorrections` (drop oldest).
        if existing.count > Self.maxCorrections {
            existing.removeFirst(existing.count - Self.maxCorrections)
        }
        if let encoded = try? JSONEncoder().encode(existing) {
            defaults?.set(encoded, forKey: Self.correctionsKey)
        }
    }

    /// Kick off background training then reload models on main actor when done.
    public func trainIfReady(transactions: [TrainableTransaction]) {
        Task.detached(priority: .background) {
            do {
                try await CategoryMLTrainer.trainIfNeeded(transactions: transactions)
                await MainActor.run { [weak self] in self?.loadUserModel() }
            } catch {
                predictorLogger.error("ML training failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Private

    private static let correctionsKey = MLStorage.correctionsKey
    private static let appGroupID     = PlatformPaths.appGroupID

    // Bundled asset — loads optionally, doesn't crash if missing.
    private static func loadStarterModel() -> NLModel? {
        guard let url = Bundle.main.url(forResource: "StarterCategoryClassifier", withExtension: "mlmodelc") else {
            predictorLogger.notice("StarterCategoryClassifier.mlmodelc not found in app bundle")
            return nil
        }
        do {
            return try NLModel(mlModel: MLModel(contentsOf: url))
        } catch {
            predictorLogger.error("StarterCategoryClassifier failed to load: \(error)")
            return nil
        }
    }

    // User-trained model lives in the App Group container and may legitimately not exist.
    private func loadUserModel() {
        guard let url = userModelURL(),
              FileManager.default.fileExists(atPath: url.path),
              let mlModel = try? MLModel(contentsOf: url),
              let nlModel = try? NLModel(mlModel: mlModel) else {
            userModel = nil
            return
        }
        userModel = nlModel
    }

    private func infer(model: NLModel, input: String, threshold: Double, source: PredictionSource) -> Prediction? {
        guard let label = model.predictedLabel(for: input) else { return nil }
        let confidence = model.predictedLabelHypotheses(for: input, maximumCount: 1)[label] ?? 0
        guard confidence >= threshold else { return nil }
        return Prediction(category: label, confidence: confidence, source: source)
    }

    private func buildInput(note: String, amount: Double) -> String {
        MLFeaturizer.input(note: note, amount: amount, recentAmounts: recentAmounts)
    }

    private func userModelURL() -> URL? {
        PlatformPaths.appGroupContainerURL
            .appendingPathComponent("UserCategoryClassifier.mlmodelc")
    }
}
