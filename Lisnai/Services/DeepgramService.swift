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

    /// Content type for audio files based on extension
    private func contentType(for fileURL: URL) -> String {
        switch fileURL.pathExtension.lowercased() {
        case "m4a": return "audio/m4a"
        case "caf": return "audio/x-caf"
        case "wav": return "audio/wav"
        case "mp3": return "audio/mpeg"
        default: return "audio/m4a"
        }
    }

    /// Perform transcription and speaker diarization using Deepgram
    /// Includes retry logic for transient upload failures (408, 502, 503)
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
            URLQueryItem(name: "language", value: "multi")           // Multilingual code-switching (EN/HI/ES/FR/DE/RU/PT/JA/IT/NL)
        ]

        guard let url = components.url else {
            throw DeepgramError.invalidURL
        }

        let mimeType = contentType(for: fileURL)
        print("Uploading \(audioData.count) bytes (\(mimeType)) to Deepgram...")

        // URLSession with upload-optimized configuration
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 180   // 3 minutes for the request
        config.timeoutIntervalForResource = 300  // 5 minutes total
        let session = URLSession(configuration: config)

        // Retry logic for transient failures (408 SLOW_UPLOAD, 502, 503)
        let maxRetries = 3
        var lastError: Error?

        for attempt in 1...maxRetries {
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
                request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
                request.httpBody = audioData

                if attempt > 1 {
                    print("Deepgram: Retry attempt \(attempt)/\(maxRetries)...")
                }

                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw DeepgramError.invalidResponse
                }

                // Retryable status codes
                if [408, 502, 503, 504].contains(httpResponse.statusCode) {
                    let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                    print("Deepgram: Retryable error (\(httpResponse.statusCode)): \(errorMessage)")
                    lastError = DeepgramError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
                    if attempt < maxRetries {
                        let delay = UInt64(attempt) * 2_000_000_000 // 2s, 4s exponential backoff
                        try? await Task.sleep(nanoseconds: delay)
                        continue
                    }
                    throw lastError!
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

                session.invalidateAndCancel()
                return (fullTranscript, segments)

            } catch let error as DeepgramError {
                lastError = error
                // Don't retry non-retryable DeepgramErrors (except the ones handled above)
                if attempt == maxRetries { throw error }
            } catch {
                lastError = error
                if attempt == maxRetries { throw error }
                print("Deepgram: Network error on attempt \(attempt): \(error.localizedDescription)")
                let delay = UInt64(attempt) * 2_000_000_000
                try? await Task.sleep(nanoseconds: delay)
            }
        }

        session.invalidateAndCancel()
        throw lastError ?? DeepgramError.invalidResponse
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
