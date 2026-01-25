import Foundation
import FoundationModels

/// Service for summarizing text using Apple Intelligence Foundation Models
@MainActor
class SummarizationService {

    /// Summarize text using on-device Apple Intelligence
    /// - Parameter text: Text to summarize
    /// - Returns: Summary text
    func summarize(_ text: String) async throws -> String {
        // Check if Apple Intelligence is available (iPhone 15 Pro+ with iOS 26)
        guard #available(iOS 26.0, *) else {
            throw SummarizationError.unsupportedOS
        }

        guard SystemLanguageModel.default.isAvailable else {
            throw SummarizationError.modelNotAvailable
        }

        print("Generating summary for \(text.count) characters...")

        // Create summarization prompt
        let prompt = """
        Summarize the following transcribed conversation in 2-3 concise sentences. Focus on key topics, decisions, and action items:

        \(text)
        """

        // Create session and generate summary using on-device model
        let session = LanguageModelSession()
        let response = try await session.respond(to: prompt)

        // Extract text content from response
        let summary = response.content

        print("Summary generated: \(summary.count) characters")
        return summary
    }

    /// Generate a daily recap from multiple transcripts
    /// - Parameter transcripts: Array of transcript texts from the day
    /// - Returns: Daily recap summary
    func generateDailyRecap(transcripts: [String]) async throws -> String {
        guard #available(iOS 26.0, *) else {
            throw SummarizationError.unsupportedOS
        }

        guard SystemLanguageModel.default.isAvailable else {
            throw SummarizationError.modelNotAvailable
        }

        // Combine all transcripts
        let fullText = transcripts.joined(separator: "\n\n")

        let prompt = """
        Create a daily recap of the following transcribed conversations from today.
        Organize by themes and highlight:
        - Key events and activities
        - Important conversations
        - Decisions made
        - Action items or follow-ups

        Transcripts:
        \(fullText)
        """

        let session = LanguageModelSession()
        let response = try await session.respond(to: prompt)
        // Extract content from response
        let recap = response.content
        return recap
    }
}

// MARK: - Errors
enum SummarizationError: LocalizedError {
    case unsupportedOS
    case modelNotAvailable
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedOS:
            return "iOS 26 or later required for Apple Intelligence"
        case .modelNotAvailable:
            return "Apple Intelligence not available on this device (requires iPhone 15 Pro or newer)"
        case .generationFailed(let message):
            return "Summary generation failed: \(message)"
        }
    }
}
