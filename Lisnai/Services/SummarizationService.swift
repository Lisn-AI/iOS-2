import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Service for summarizing transcriptions using Apple Intelligence Foundation Models
@MainActor
class SummarizationService {

    /// Check if on-device summarization is available
    var isAvailable: Bool {
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        return false
    }

    /// Summarize a transcription using on-device Apple Intelligence
    /// - Parameter text: Transcribed audio text to summarize
    /// - Returns: Summary text
    func summarize(_ text: String) async throws -> String {
        guard #available(iOS 26.0, *) else {
            throw SummarizationError.unsupportedOS
        }

        guard SystemLanguageModel.default.isAvailable else {
            throw SummarizationError.modelNotAvailable
        }

        // Skip very short transcriptions
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 20 else {
            return trimmed
        }

        print("[Summarization] Generating summary for \(text.count) characters...")

        return try await _summarize(text)
    }

    @available(iOS 26.0, *)
    private func _summarize(_ text: String) async throws -> String {
        let session = LanguageModelSession {
            """
            You are a precise summarizer for audio transcriptions captured throughout someone's day. \
            These are real conversations, meetings, lectures, voice notes, and ambient recordings.

            Your job is to extract what actually matters from the transcription. Follow these rules strictly:

            1. CAPTURE ALL KEY INFORMATION: Names of people mentioned, specific numbers, dates, times, \
            places, decisions made, tasks assigned, promises or commitments, and any factual claims.

            2. PRESERVE CONTEXT: If speakers are labeled (Speaker 1, Speaker 2), note who said what \
            when it matters. If only one speaker, treat it as a monologue or voice note.

            3. HANDLE TRANSCRIPTION NOISE: Ignore filler words (um, uh, like, you know), false starts, \
            and repetitions. Focus on the substance.

            4. FORMAT: Write 2-4 clear sentences. Start with what the conversation/recording is about, \
            then cover the key points. No bullet points, no headers — just clean prose.

            5. BE SPECIFIC, NOT GENERIC: Instead of "They discussed work plans", say \
            "Discussed the Q3 product launch timeline, targeting August 15th release."

            6. ACTION ITEMS: If someone commits to doing something, mention it explicitly. \
            Example: "Alex agreed to send the revised proposal by Friday."

            7. SHORT RECORDINGS: If the transcription is very brief (a quick thought or reminder), \
            just restate it clearly in one sentence.
            """
        }

        let prompt = "Summarize this transcription:\n\n\(text)"
        let response = try await session.respond(to: prompt)
        let summary = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

        print("[Summarization] Summary generated: \(summary.count) characters")
        return summary
    }

    /// Generate a daily recap from multiple transcripts
    func generateDailyRecap(transcripts: [String]) async throws -> String {
        guard #available(iOS 26.0, *) else {
            throw SummarizationError.unsupportedOS
        }

        guard SystemLanguageModel.default.isAvailable else {
            throw SummarizationError.modelNotAvailable
        }

        return try await _generateDailyRecap(transcripts: transcripts)
    }

    @available(iOS 26.0, *)
    private func _generateDailyRecap(transcripts: [String]) async throws -> String {
        let fullText = transcripts.enumerated().map { index, text in
            "Recording \(index + 1):\n\(text)"
        }.joined(separator: "\n\n---\n\n")

        let session = LanguageModelSession {
            """
            You create daily recaps from a person's audio recordings captured throughout the day. \
            These recordings are real conversations, meetings, voice notes, and ambient audio.

            Write a cohesive daily summary that:
            - Groups related topics together (don't just go recording by recording)
            - Highlights the most important events, decisions, and conversations
            - Notes any action items, commitments, or follow-ups needed
            - Mentions specific people, places, times, and details
            - Uses clear, readable prose (3-6 sentences)
            - Reads like a personal journal entry for the day
            """
        }

        let prompt = "Here are today's recordings. Create a daily recap:\n\n\(fullText)"
        let response = try await session.respond(to: prompt)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
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
