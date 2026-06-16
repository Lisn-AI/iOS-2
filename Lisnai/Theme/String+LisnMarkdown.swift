import Foundation

extension String {
    /// Normalizes LLM-generated markdown that may have headings or bullets glued
    /// onto the same line. Inserts line breaks so `MarkdownUI` parses them correctly.
    ///
    /// Handles three observed patterns from the summary agent:
    ///   1. `<sentence>.### Heading` → heading missing leading blank line
    ///   2. `### Title- bullet`     → bullet glued to heading on same line
    ///   3. `.- Next bullet`         → bullet glued to previous sentence
    ///
    /// The bullet-split step requires a capital letter after the dash to avoid
    /// false positives on compound words ("well-known", "co-author").
    var lisnNormalizedMarkdown: String {
        var result = self

        // 1. Ensure every heading marker (# … ######) starts on its own line.
        result = result.replacingOccurrences(
            of: #"([^\n])(#{1,6}[ \t])"#,
            with: "$1\n\n$2",
            options: .regularExpression
        )

        // 2. Split bullets glued to non-whitespace. Capital letter required after
        //    the dash to skip hyphens in compound words.
        result = result.replacingOccurrences(
            of: #"([^\n\s])[ \t]*-[ \t]+([A-Z])"#,
            with: "$1\n- $2",
            options: .regularExpression
        )

        // 3. Collapse runs of 3+ blank lines.
        result = result.replacingOccurrences(
            of: #"\n{3,}"#,
            with: "\n\n",
            options: .regularExpression
        )

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
