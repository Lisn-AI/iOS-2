import Foundation
@preconcurrency import AVFoundation
import FluidAudio

/// Service for speaker diarization using FluidAudio
@MainActor
class DiarizationService {

    /// Represents a segment of audio spoken by a specific speaker
    struct SpeakerSegment {
        let speaker: Int  // Speaker ID (0, 1, 2, etc.)
        let startTime: TimeInterval
        let endTime: TimeInterval

        var duration: TimeInterval {
            endTime - startTime
        }
    }

    /// Perform speaker diarization on an audio file
    /// - Parameter fileURL: URL to the audio file
    /// - Returns: Array of speaker segments with timing information
    func diarize(fileURL: URL) async throws -> [SpeakerSegment] {
        print("Starting speaker diarization for: \(fileURL.lastPathComponent)")

        // Download models if needed (first time only)
        print("Downloading diarization models if needed...")
        let models = try await DiarizerModels.downloadIfNeeded()

        // Configure for better speaker separation and short utterance detection
        let config = DiarizerConfig(
            clusteringThreshold: 0.55,           // Lower = more sensitive (default 0.7)
            minSpeechDuration: 0.3,              // Capture phrases as short as 300ms (default 1.0)
            minEmbeddingUpdateDuration: 2.0,     // Keep default
            minSilenceGap: 0.2,                  // Detect brief pauses (default 0.5)
            numClusters: -1,                     // Auto-detect number of speakers
            minActiveFramesCount: 10.0,          // Keep default
            debugMode: false,
            chunkDuration: 10.0,                 // Keep default
            chunkOverlap: 0.0                    // Keep default
        )

        // Create and initialize diarization manager
        let diarizer = DiarizerManager(config: config)
        diarizer.initialize(models: models)

        // Load audio file as 16kHz mono samples
        let audioSamples = try await loadAudioFile(fileURL)

        // Process audio to identify speakers
        print("Processing audio for speaker identification...")
        let result = try diarizer.performCompleteDiarization(audioSamples)

        // Convert result to speaker segments
        let segments = convertToSpeakerSegments(result)

        print("Diarization complete: \(segments.count) segments, \(Set(segments.map(\.speaker)).count) speakers")

        return segments
    }

    /// Load audio file and convert to 16kHz mono Float array
    private nonisolated func loadAudioFile(_ url: URL) async throws -> [Float] {
        let file = try AVAudioFile(forReading: url)

        // Step 1: Create intermediate PCM format (at original sample rate)
        guard let pcmFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: file.fileFormat.sampleRate,
            channels: file.fileFormat.channelCount,
            interleaved: false
        ) else {
            throw DiarizationError.audioFormatError
        }

        // Step 2: Read entire file into PCM buffer
        guard let pcmBuffer = AVAudioPCMBuffer(
            pcmFormat: pcmFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ) else {
            throw DiarizationError.bufferCreationFailed
        }

        try file.read(into: pcmBuffer)

        // Step 3: Create target format (16kHz mono Float32)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            throw DiarizationError.audioFormatError
        }

        // Step 4: Calculate target buffer size
        let ratio = 16000.0 / file.fileFormat.sampleRate
        let targetFrameCount = AVAudioFrameCount(Double(pcmBuffer.frameLength) * ratio)

        guard let targetBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: targetFrameCount
        ) else {
            throw DiarizationError.bufferCreationFailed
        }

        // Step 5: Convert to 16kHz mono
        guard let converter = AVAudioConverter(from: pcmFormat, to: targetFormat) else {
            throw DiarizationError.audioFormatError
        }

        // Use a class to wrap mutable state for thread-safe capture
        final class InputState: @unchecked Sendable {
            var offset: AVAudioFramePosition = 0
        }

        let inputState = InputState()
        var error: NSError?

        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            if inputState.offset >= pcmBuffer.frameLength {
                outStatus.pointee = .endOfStream
                return nil
            }

            let framesRemaining = pcmBuffer.frameLength - AVAudioFrameCount(inputState.offset)
            let framesToRead = min(framesRemaining, inNumPackets)

            let tempBuffer = AVAudioPCMBuffer(
                pcmFormat: pcmFormat,
                frameCapacity: framesToRead
            )!

            // Copy data from source buffer
            for channel in 0..<Int(pcmFormat.channelCount) {
                let src = pcmBuffer.floatChannelData![channel].advanced(by: Int(inputState.offset))
                let dst = tempBuffer.floatChannelData![channel]
                memcpy(dst, src, Int(framesToRead) * MemoryLayout<Float>.stride)
            }

            tempBuffer.frameLength = framesToRead
            inputState.offset += AVAudioFramePosition(framesToRead)

            outStatus.pointee = .haveData
            return tempBuffer
        }

        converter.convert(to: targetBuffer, error: &error, withInputFrom: inputBlock)

        if let error = error {
            throw DiarizationError.diarizationFailed("Audio conversion failed: \(error.localizedDescription)")
        }

        // Step 6: Extract float samples
        guard let floatData = targetBuffer.floatChannelData?[0] else {
            throw DiarizationError.audioDataExtractionFailed
        }

        let samples = Array(UnsafeBufferPointer(start: floatData, count: Int(targetBuffer.frameLength)))

        print("Loaded audio: \(samples.count) samples at 16kHz (converted from \(file.fileFormat.sampleRate)Hz)")
        return samples
    }

    /// Convert FluidAudio result to speaker segments
    private nonisolated func convertToSpeakerSegments(_ result: DiarizationResult) -> [SpeakerSegment] {
        var segments: [SpeakerSegment] = []

        // FluidAudio returns segments with speaker IDs and timestamps
        for segment in result.segments {
            // Convert types: speakerId might be String, times are Float
            let speakerId = Int(segment.speakerId) ?? 0
            let startTime = TimeInterval(segment.startTimeSeconds)
            let endTime = TimeInterval(segment.endTimeSeconds)

            let speakerSegment = SpeakerSegment(
                speaker: speakerId,
                startTime: startTime,
                endTime: endTime
            )
            segments.append(speakerSegment)
        }

        return segments
    }
}

// MARK: - Errors
enum DiarizationError: LocalizedError {
    case audioFormatError
    case bufferCreationFailed
    case audioDataExtractionFailed
    case diarizationFailed(String)

    var errorDescription: String? {
        switch self {
        case .audioFormatError:
            return "Failed to create audio format"
        case .bufferCreationFailed:
            return "Failed to create audio buffer"
        case .audioDataExtractionFailed:
            return "Failed to extract audio data"
        case .diarizationFailed(let message):
            return "Speaker diarization failed: \(message)"
        }
    }
}
