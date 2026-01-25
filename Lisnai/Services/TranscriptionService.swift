import Foundation
import Speech

/// Service for transcribing audio files using iOS 26 SpeechAnalyzer
@MainActor
class TranscriptionService {

    /// Transcribe an audio file to text using iOS 26 on-device API
    /// - Parameters:
    ///   - fileURL: URL to the audio file
    ///   - locale: Language locale (defaults to device locale)
    /// - Returns: Transcribed text
    func transcribe(fileURL: URL, locale: Locale = .current) async throws -> String {
        // iOS 26+ only - use new SpeechAnalyzer API
        if #available(iOS 26.0, *) {
            return try await transcribeWithSpeechAnalyzer(fileURL: fileURL, locale: locale)
        } else {
            throw TranscriptionError.unsupportedOS
        }
    }

    @available(iOS 26.0, *)
    private func transcribeWithSpeechAnalyzer(fileURL: URL, locale: Locale) async throws -> String {
        print("Starting transcription for: \(fileURL.lastPathComponent)")

        // Create transcriber for offline transcription
        // Using basic init - defaults to on-device transcription
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )

        // Collect transcription results asynchronously
        let transcriptionTask = Task {
            var fullText = ""

            for try await result in transcriber.results {
                // Convert AttributedString to String
                fullText += String(result.text.characters)
                print("Transcribed chunk: \(result.text)")
            }

            return fullText
        }

        // Create analyzer with the transcriber module
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        // Create AVAudioFile from URL
        let audioFile = try AVAudioFile(forReading: fileURL)

        // Analyze the audio file
        if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        }

        // Wait for transcription to complete
        let fullTranscription = try await transcriptionTask.value

        print("Transcription complete: \(fullTranscription.count) characters")
        return fullTranscription
    }
}

// MARK: - Errors
enum TranscriptionError: LocalizedError {
    case unsupportedOS
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedOS:
            return "iOS 26 or later required for on-device transcription"
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        }
    }
}
