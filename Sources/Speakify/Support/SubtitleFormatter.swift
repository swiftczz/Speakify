import Foundation

enum SubtitleFormatter {
    private static let lineCharacterLimit = 48

    static func srt(from alignment: SpeechAlignment) throws -> String {
        guard alignment.isValid else {
            throw TTSProviderError.invalidResponse
        }

        let cues = makeCues(from: alignment)
        guard cues.isEmpty == false else {
            throw TTSProviderError.invalidResponse
        }

        return cues.enumerated().map { index, cue in
            "\(index + 1)\n\(timestamp(cue.start)) --> \(timestamp(cue.end))\n\(wrapped(cue.text))"
        }.joined(separator: "\n\n") + "\n"
    }

    static func estimatedSRT(text: String, duration: TimeInterval) throws -> String {
        let characters = Array(text).map(String.init)
        guard characters.isEmpty == false, duration > 0 else {
            throw TTSProviderError.invalidResponse
        }

        let characterDuration = duration / Double(characters.count)
        let alignment = SpeechAlignment(
            characters: characters,
            characterStartTimesSeconds: characters.indices.map {
                Double($0) * characterDuration
            },
            characterEndTimesSeconds: characters.indices.map {
                Double($0 + 1) * characterDuration
            }
        )
        return try srt(from: alignment)
    }

    private static func makeCues(from alignment: SpeechAlignment) -> [Cue] {
        let characters = alignment.characters
        var cues: [Cue] = []
        var cueStart: Int?
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if cueStart == nil {
                if isWhitespace(character) {
                    index += 1
                    continue
                }
                cueStart = index
            }

            guard let start = cueStart else { continue }
            let isLineBreak = character.contains(where: \.isNewline)
            let sentenceEnd = sentenceEndIndex(at: index, in: characters)

            if isLineBreak || sentenceEnd != nil {
                let end = sentenceEnd ?? index
                appendCue(start: start, end: end, alignment: alignment, to: &cues)
                cueStart = nil
                index = end + 1
                continue
            }

            index += 1
        }

        if let start = cueStart {
            appendCue(start: start, end: characters.count - 1, alignment: alignment, to: &cues)
        }

        return cues
    }

    private static func appendCue(
        start: Int,
        end: Int,
        alignment: SpeechAlignment,
        to cues: inout [Cue]
    ) {
        guard start <= end else { return }

        var trimmedStart = start
        var trimmedEnd = end
        while trimmedStart <= trimmedEnd, isWhitespace(alignment.characters[trimmedStart]) {
            trimmedStart += 1
        }
        while trimmedEnd >= trimmedStart, isWhitespace(alignment.characters[trimmedEnd]) {
            trimmedEnd -= 1
        }
        guard trimmedStart <= trimmedEnd else { return }

        let text = alignment.characters[trimmedStart...trimmedEnd]
            .joined()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else { return }

        cues.append(Cue(
            start: alignment.characterStartTimesSeconds[trimmedStart],
            end: alignment.characterEndTimesSeconds[trimmedEnd],
            text: text
        ))
    }

    private static func wrapped(_ text: String) -> String {
        guard text.count > lineCharacterLimit else { return text }
        let words = text.split(separator: " ")
        guard words.count > 1 else {
            return stride(from: 0, to: text.count, by: lineCharacterLimit)
                .map { offset in
                    let start = text.index(text.startIndex, offsetBy: offset)
                    let end = text.index(
                        start,
                        offsetBy: min(lineCharacterLimit, text.distance(from: start, to: text.endIndex))
                    )
                    return String(text[start..<end])
                }
                .joined(separator: "\n")
        }

        var lines: [String] = []
        var currentLine = ""
        for word in words {
            let candidate = currentLine.isEmpty ? String(word) : "\(currentLine) \(word)"
            if candidate.count <= lineCharacterLimit || currentLine.isEmpty {
                currentLine = candidate
            } else {
                lines.append(currentLine)
                currentLine = String(word)
            }
        }
        if currentLine.isEmpty == false {
            lines.append(currentLine)
        }
        return lines.joined(separator: "\n")
    }

    private static func timestamp(_ time: TimeInterval) -> String {
        let totalMilliseconds = max(Int((time * 1_000).rounded()), 0)
        let milliseconds = totalMilliseconds % 1_000
        let totalSeconds = totalMilliseconds / 1_000
        let seconds = totalSeconds % 60
        let totalMinutes = totalSeconds / 60
        let minutes = totalMinutes % 60
        let hours = totalMinutes / 60
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, milliseconds)
    }

    private static func isWhitespace(_ character: String) -> Bool {
        character.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    private static func sentenceEndIndex(at index: Int, in characters: [String]) -> Int? {
        let character = characters[index]
        guard character.rangeOfCharacter(from: CharacterSet(charactersIn: ".!?。！？")) != nil else {
            return nil
        }
        guard isKnownAbbreviation(endingAt: index, in: characters) == false else {
            return nil
        }

        let closingPunctuation = CharacterSet(charactersIn: "\"'”’)]}»")
        var end = index
        var next = index + 1
        while next < characters.count,
              characters[next].unicodeScalars.allSatisfy({ closingPunctuation.contains($0) }) {
            end = next
            next += 1
        }

        if character.rangeOfCharacter(from: CharacterSet(charactersIn: "。！？")) != nil {
            return end
        }
        return next == characters.count || isWhitespace(characters[next]) ? end : nil
    }

    private static func isKnownAbbreviation(endingAt index: Int, in characters: [String]) -> Bool {
        guard characters[index] == "." else { return false }
        var start = index
        while start > 0, isWhitespace(characters[start - 1]) == false {
            start -= 1
        }
        let token = characters[start...index].joined().lowercased()
        return ["mr.", "mrs.", "ms.", "dr.", "prof.", "sr.", "jr.", "st.", "vs.", "etc.", "e.g.", "i.e.", "no.", "fig."].contains(token)
    }

    private struct Cue {
        let start: TimeInterval
        let end: TimeInterval
        let text: String
    }
}
