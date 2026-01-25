import Foundation

/// Service for speaker diarization and transcription using Deepgram API
@MainActor
class DeepgramService {

    private let apiKey = "31c950afad9d0a55a05fdc3a06069e2067cac65c"
    private let baseURL = "https://api.deepgram.com/v1/listen"

    /// Represents a speaker segment from Deepgram
    struct SpeakerSegment {
        let speaker: Int
        let startTime: TimeInterval
        let endTime: TimeInterval
        let transcript: String
        let confidence: Double?

        var duration: TimeInterval {
            endTime - startTime
        }
    }

    /// Deepgram API response structures
    private struct DeepgramResponse: Codable {
        let results: Results

        struct Results: Codable {
            let channels: [Channel]
            let utterances: [Utterance]?

            struct Channel: Codable {
                let alternatives: [Alternative]

                struct Alternative: Codable {
                    let transcript: String
                    let confidence: Double
                    let words: [Word]

                    struct Word: Codable {
                        let word: String
                        let start: Double
                        let end: Double
                        let confidence: Double
                        let speaker: Int?
                        let speakerConfidence: Double?

                        enum CodingKeys: String, CodingKey {
                            case word, start, end, confidence, speaker
                            case speakerConfidence = "speaker_confidence"
                        }
                    }
                }
            }

            struct Utterance: Codable {
                let speaker: Int
                let start: Double
                let end: Double
                let transcript: String
                let confidence: Double
            }
        }
    }

    /// Perform transcription and speaker diarization using Deepgram
    /// - Parameter fileURL: URL to the audio file
    /// - Returns: Tuple of (full transcript, speaker segments)
    func transcribeAndDiarize(fileURL: URL) async throws -> (transcript: String, segments: [SpeakerSegment]) {
        print("Starting Deepgram transcription and diarization for: \(fileURL.lastPathComponent)")

        // Read audio file
        let audioData = try Data(contentsOf: fileURL)

        // Build request URL with parameters
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "model", value: "nova-3"),           // Nova-3 (nova-2 has known diarization bugs)
            URLQueryItem(name: "diarize", value: "true"),           // Enable speaker diarization
            URLQueryItem(name: "utterances", value: "true"),        // Group by speaker utterances
            URLQueryItem(name: "punctuate", value: "true"),         // Add punctuation
            URLQueryItem(name: "smart_format", value: "true"),      // Better formatting
            URLQueryItem(name: "detect_language", value: "true")    // Auto-detect language
        ]

        guard let url = components.url else {
            throw DeepgramError.invalidURL
        }

        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/m4a", forHTTPHeaderField: "Content-Type")
        request.httpBody = audioData
        request.timeoutInterval = 120 // 2 minutes for long audio

        print("Uploading \(audioData.count) bytes to Deepgram...")

        // Make API request
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DeepgramError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("Deepgram API error (\(httpResponse.statusCode)): \(errorMessage)")
            throw DeepgramError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        // Parse response
        let decoder = JSONDecoder()
        let deepgramResponse = try decoder.decode(DeepgramResponse.self, from: data)

        // Extract full transcript
        let fullTranscript = deepgramResponse.results.channels.first?.alternatives.first?.transcript ?? ""
        print("Transcription complete: \(fullTranscript.count) characters")

        // Extract speaker segments from utterances
        var segments: [SpeakerSegment] = []

        if let utterances = deepgramResponse.results.utterances {
            for utterance in utterances {
                let segment = SpeakerSegment(
                    speaker: utterance.speaker,
                    startTime: utterance.start,
                    endTime: utterance.end,
                    transcript: utterance.transcript,
                    confidence: utterance.confidence
                )
                segments.append(segment)
            }

            let uniqueSpeakers = Set(segments.map(\.speaker)).count
            print("Diarization complete: \(segments.count) segments, \(uniqueSpeakers) speakers detected")
        } else {
            print("Warning: No utterances found in response. Diarization may have failed.")
        }

        return (fullTranscript, segments)
    }
}

// MARK: - Errors
enum DeepgramError: LocalizedError {
    case invalidURL
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case decodingError

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Deepgram API URL"
        case .invalidResponse:
            return "Invalid response from Deepgram API"
        case .apiError(let statusCode, let message):
            return "Deepgram API error (\(statusCode)): \(message)"
        case .decodingError:
            return "Failed to decode Deepgram response"
        }
    }
}
