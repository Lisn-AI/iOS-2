import SwiftUI

struct TranscriptionCard: View {
    let transcription: String
    let duration: String

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: LisnSpacing.sm) {
            // Header
            HStack(spacing: LisnSpacing.xs) {
                Image(systemName: "waveform.and.mic")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(LisnColors.accent)

                Text("Transcription")
                    .font(LisnFont.labelLarge())
                    .foregroundColor(LisnColors.textPrimary)

                Spacer()

                Button {
                    UIPasteboard.general.string = transcription
                    copied = true
                    LisnHaptics.light()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            copied = false
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12, weight: .medium))
                        if copied {
                            Text("Copied")
                                .font(LisnFont.labelSmall())
                        }
                    }
                    .foregroundColor(copied ? LisnColors.success : LisnColors.textTertiary)
                    .padding(.horizontal, LisnSpacing.xs)
                    .padding(.vertical, LisnSpacing.xxs)
                    .background(copied ? LisnColors.success.opacity(0.1) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: LisnRadius.sm, style: .continuous))
                    .contentTransition(.symbolEffect(.replace))
                }
            }

            Rectangle()
                .fill(LisnColors.borderSubtle)
                .frame(height: 1)

            // Formatted transcription
            FormattedTranscriptionView(text: transcription)

            // Footer
            HStack(spacing: LisnSpacing.md) {
                HStack(spacing: LisnSpacing.xxs) {
                    Image(systemName: "clock")
                        .font(.system(size: 11, weight: .medium))
                    Text(duration)
                        .font(LisnFont.caption())
                }
                .foregroundColor(LisnColors.textTertiary)

                HStack(spacing: LisnSpacing.xxs) {
                    Image(systemName: "text.word.spacing")
                        .font(.system(size: 11, weight: .medium))
                    Text("\(wordCount) words")
                        .font(LisnFont.caption())
                }
                .foregroundColor(LisnColors.textTertiary)

                if speakerCount > 1 {
                    HStack(spacing: LisnSpacing.xxs) {
                        Image(systemName: "person.2")
                            .font(.system(size: 11, weight: .medium))
                        Text("\(speakerCount) speakers")
                            .font(LisnFont.caption())
                    }
                    .foregroundColor(LisnColors.textTertiary)
                }
            }
            .padding(.top, LisnSpacing.xxs)
        }
        .padding(LisnSpacing.md)
        .background(LisnColors.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: LisnRadius.lg, style: .continuous))
        .shadow(
            color: LisnShadow.sm.color,
            radius: LisnShadow.sm.radius,
            x: LisnShadow.sm.x,
            y: LisnShadow.sm.y
        )
    }

    private var wordCount: Int {
        transcription.split(separator: " ").count
    }

    private var speakerCount: Int {
        let segments = TranscriptionParser.parse(transcription)
        let speakers = Set(segments.compactMap { $0.speaker })
        return speakers.count
    }
}

// MARK: - Transcription Parser

enum TranscriptionParser {

    struct Segment {
        let speaker: String?
        let text: String
    }

    /// Parse raw transcription text into speaker-labeled segments.
    /// Supports formats like "Speaker 1: text", "Speaker 2: text" etc.
    static func parse(_ raw: String) -> [Segment] {
        let lines = raw.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        // Regex: matches "Speaker N:" or "Speaker N :" at the start of a line
        let pattern = #"^(Speaker\s*\d+)\s*:\s*(.+)$"#

        var segments: [Segment] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let match = trimmed.range(of: pattern, options: .regularExpression) {
                let matched = String(trimmed[match])
                // Split on first colon
                if let colonRange = matched.range(of: ":") {
                    let speaker = String(matched[matched.startIndex..<colonRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                    let text = String(matched[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                    segments.append(Segment(speaker: speaker, text: text))
                } else {
                    segments.append(Segment(speaker: nil, text: trimmed))
                }
            } else {
                // No speaker label — plain text
                segments.append(Segment(speaker: nil, text: trimmed))
            }
        }

        return segments
    }
}

// MARK: - Formatted Transcription View

/// Renders transcription with styled speaker labels and clean typography.
struct FormattedTranscriptionView: View {
    let text: String

    /// Consistent colors for each speaker
    private static let speakerColors: [Color] = [
        Color(red: 0.769, green: 0.506, blue: 0.239), // Amber (accent)
        Color(red: 0.40, green: 0.56, blue: 0.78),    // Steel blue
        Color(red: 0.60, green: 0.42, blue: 0.70),    // Muted purple
        Color(red: 0.30, green: 0.62, blue: 0.52),    // Teal
        Color(red: 0.78, green: 0.44, blue: 0.36),    // Terra cotta
    ]

    private var segments: [TranscriptionParser.Segment] {
        TranscriptionParser.parse(text)
    }

    /// Map speaker name → consistent color index
    private var speakerColorMap: [String: Color] {
        var map: [String: Color] = [:]
        var idx = 0
        for segment in segments {
            if let speaker = segment.speaker, map[speaker] == nil {
                map[speaker] = Self.speakerColors[idx % Self.speakerColors.count]
                idx += 1
            }
        }
        return map
    }

    private var hasSpeakers: Bool {
        segments.contains { $0.speaker != nil }
    }

    var body: some View {
        if hasSpeakers {
            speakerView
        } else {
            // Plain text — no speaker labels
            Text(text)
                .font(LisnFont.bodyMedium())
                .foregroundColor(LisnColors.textPrimary)
                .lineSpacing(5)
        }
    }

    private var speakerView: some View {
        VStack(alignment: .leading, spacing: LisnSpacing.sm) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                if let speaker = segment.speaker {
                    VStack(alignment: .leading, spacing: 4) {
                        // Speaker label
                        HStack(spacing: 6) {
                            Circle()
                                .fill(speakerColorMap[speaker] ?? LisnColors.accent)
                                .frame(width: 8, height: 8)

                            Text(speaker)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(speakerColorMap[speaker] ?? LisnColors.accent)
                        }

                        // Speaker text
                        Text(segment.text)
                            .font(LisnFont.bodyMedium())
                            .foregroundColor(LisnColors.textPrimary)
                            .lineSpacing(4)
                            .padding(.leading, 14)
                    }
                } else {
                    // Plain text segment (no speaker)
                    Text(segment.text)
                        .font(LisnFont.bodyMedium())
                        .foregroundColor(LisnColors.textPrimary)
                        .lineSpacing(4)
                }
            }
        }
    }
}
