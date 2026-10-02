import Foundation

public enum StoryReadingLength {
    public static let defaultWordsPerMinute = 120

    public static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).filter {
            $0.unicodeScalars.contains { CharacterSet.letters.contains($0) }
        }.count
    }

    public static func minutes(words: Int, wordsPerMinute: Int) -> Double {
        Double(words) / Double(max(1, wordsPerMinute))
    }
}
